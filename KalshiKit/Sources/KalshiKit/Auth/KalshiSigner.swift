import Foundation
import Security

/// A concrete ``RequestSigning`` implementation backed by Apple's Security
/// framework. It imports the user's RSA private key once at construction time
/// and signs each request with RSA-PSS / SHA-256, exactly as Kalshi's API
/// requires.
///
/// CryptoKit has no RSA support, so this type uses `SecKey` directly. The
/// imported key is retained for the lifetime of the signer and reused for
/// every signature, avoiding repeated PEM parsing.
///
/// ## Concurrency
/// `SecKey` is a CoreFoundation type and is not automatically `Sendable`.
/// However, `SecKeyCreateSignature` is documented as thread-safe to call
/// concurrently on the same key, and the imported key is immutable after
/// construction. The signer is therefore safe to share across threads, which
/// is why it is declared `@unchecked Sendable`.
public struct KalshiSigner: RequestSigning, @unchecked Sendable {
    /// The imported RSA private key (PKCS#1, class private). Immutable after init.
    private let privateKey: SecKey

    /// The API Key ID, sent verbatim in the `KALSHI-ACCESS-KEY` header.
    private let apiKeyID: String

    /// The PSS algorithm Kalshi expects: RSA-PSS, SHA-256 digest, MGF1(SHA-256),
    /// salt length == digest length (32). The *message* variant hashes the input
    /// internally, matching Kalshi's "sign the raw message" scheme.
    private static let algorithm: SecKeyAlgorithm = .rsaSignatureMessagePSSSHA256

    /// Parses the credentials' PEM private key (PKCS#1 or PKCS#8) and imports it.
    ///
    /// - Throws: ``KalshiError/signing(reason:)`` if the PEM cannot be decoded,
    ///   normalized to PKCS#1, or imported by the Security framework.
    public init(credentials: KalshiCredentials) throws {
        self.apiKeyID = credentials.apiKeyID

        let der = try Self.pkcs1DER(fromPEM: credentials.privateKeyPEM)

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "unknown error"
            throw KalshiError.signing(reason: "Could not import RSA private key: \(reason)")
        }
        self.privateKey = key
    }

    // MARK: - RequestSigning

    public func authHeaders(method: String, path: String, timestampMs: Int64) throws -> [String: String] {
        // Kalshi signing string: timestamp + METHOD + path, no separators.
        let message = "\(timestampMs)\(method)\(path)"
        guard let messageData = message.data(using: .utf8) else {
            throw KalshiError.signing(reason: "Could not UTF-8 encode signing string.")
        }

        guard SecKeyIsAlgorithmSupported(privateKey, .sign, Self.algorithm) else {
            throw KalshiError.signing(reason: "RSA-PSS/SHA-256 is not supported for this key.")
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            Self.algorithm,
            messageData as CFData,
            &error
        ) else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "unknown error"
            throw KalshiError.signing(reason: "RSA-PSS signing failed: \(reason)")
        }

        let signatureBase64 = (signature as Data).base64EncodedString()

        return [
            "KALSHI-ACCESS-KEY": apiKeyID,
            "KALSHI-ACCESS-TIMESTAMP": "\(timestampMs)",
            "KALSHI-ACCESS-SIGNATURE": signatureBase64,
        ]
    }

    /// The current Unix time in milliseconds, suitable for `timestampMs`.
    public static func currentTimestampMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - PEM / ASN.1 handling

    /// Decodes a PEM private key and returns the PKCS#1 `RSAPrivateKey` DER bytes.
    ///
    /// Accepts both `-----BEGIN RSA PRIVATE KEY-----` (PKCS#1, returned as-is) and
    /// `-----BEGIN PRIVATE KEY-----` (PKCS#8, unwrapped to its inner PKCS#1 key,
    /// because `SecKeyCreateWithData` expects PKCS#1 for `kSecAttrKeyTypeRSA`).
    private static func pkcs1DER(fromPEM pem: String) throws -> Data {
        let isPKCS8: Bool
        if pem.contains("BEGIN RSA PRIVATE KEY") {
            isPKCS8 = false
        } else if pem.contains("BEGIN PRIVATE KEY") {
            isPKCS8 = true
        } else {
            throw KalshiError.signing(reason: "Unrecognized PEM header; expected an RSA private key.")
        }

        let der = try base64DER(fromPEM: pem)
        return isPKCS8 ? try unwrapPKCS8(der) : der
    }

    /// Strips PEM armor and whitespace, then base64-decodes the body to DER.
    private static func base64DER(fromPEM pem: String) throws -> Data {
        let body = pem
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .filter { !$0.isWhitespace }

        guard let der = Data(base64Encoded: body) else {
            throw KalshiError.signing(reason: "PEM body is not valid base64.")
        }
        return der
    }

    /// Unwraps a PKCS#8 `PrivateKeyInfo` to its inner PKCS#1 `RSAPrivateKey`.
    ///
    /// PKCS#8 structure:
    /// ```
    /// SEQUENCE {
    ///   INTEGER            version
    ///   SEQUENCE           privateKeyAlgorithm (AlgorithmIdentifier)
    ///   OCTET STRING       privateKey  -- the raw PKCS#1 RSAPrivateKey
    /// }
    /// ```
    /// We parse the outer SEQUENCE, skip the version INTEGER and the algorithm
    /// SEQUENCE, then return the contents of the OCTET STRING.
    private static func unwrapPKCS8(_ der: Data) throws -> Data {
        let bytes = [UInt8](der)
        var parser = ASN1Parser(bytes: bytes)

        // Outer SEQUENCE
        let outer = try parser.expectTLV(tag: 0x30)
        var inner = ASN1Parser(bytes: outer)

        // version INTEGER
        _ = try inner.expectTLV(tag: 0x02)
        // privateKeyAlgorithm SEQUENCE
        _ = try inner.expectTLV(tag: 0x30)
        // privateKey OCTET STRING -> its contents are the PKCS#1 key
        let pkcs1 = try inner.expectTLV(tag: 0x04)

        return Data(pkcs1)
    }
}

/// A minimal, length-aware ASN.1 DER parser sufficient to walk PKCS#8 wrappers.
///
/// It understands single-byte tags and both short-form and long-form (definite)
/// lengths. It does not handle indefinite lengths (not used in DER).
private struct ASN1Parser {
    private let bytes: [UInt8]
    private var index: Int

    init(bytes: [UInt8]) {
        self.bytes = bytes
        self.index = 0
    }

    /// Reads one TLV element, requiring the given tag, and returns its value bytes.
    /// Advances the cursor past the element.
    mutating func expectTLV(tag expectedTag: UInt8) throws -> [UInt8] {
        guard index < bytes.count else {
            throw KalshiError.signing(reason: "ASN.1 parse error: unexpected end of data.")
        }
        let tag = bytes[index]
        guard tag == expectedTag else {
            throw KalshiError.signing(
                reason: "ASN.1 parse error: expected tag 0x\(String(expectedTag, radix: 16)), "
                    + "found 0x\(String(tag, radix: 16))."
            )
        }
        index += 1

        let length = try readLength()
        guard index + length <= bytes.count else {
            throw KalshiError.signing(reason: "ASN.1 parse error: length exceeds available data.")
        }
        let value = Array(bytes[index ..< index + length])
        index += length
        return value
    }

    /// Reads a DER definite-form length (short or long form).
    private mutating func readLength() throws -> Int {
        guard index < bytes.count else {
            throw KalshiError.signing(reason: "ASN.1 parse error: missing length byte.")
        }
        let first = bytes[index]
        index += 1

        // Short form: bit 7 clear, length is the low 7 bits.
        if first & 0x80 == 0 {
            return Int(first)
        }

        // Long form: low 7 bits give the number of subsequent length bytes.
        let byteCount = Int(first & 0x7F)
        guard byteCount > 0 else {
            throw KalshiError.signing(reason: "ASN.1 parse error: indefinite lengths are not allowed in DER.")
        }
        guard byteCount <= 8, index + byteCount <= bytes.count else {
            throw KalshiError.signing(reason: "ASN.1 parse error: malformed long-form length.")
        }

        var length = 0
        for _ in 0 ..< byteCount {
            length = (length << 8) | Int(bytes[index])
            index += 1
        }
        return length
    }
}
