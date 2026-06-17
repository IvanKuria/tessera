import Foundation

/// A user's Kalshi API credentials: the Key ID and the RSA private key (PEM)
/// generated at kalshi.com → Account → API Keys. The private key is shown once
/// by Kalshi and is never transmitted anywhere except, signed, to Kalshi itself.
public struct KalshiCredentials: Sendable, Equatable {
    /// The API Key ID (a UUID), sent in the `KALSHI-ACCESS-KEY` header.
    public let apiKeyID: String
    /// The RSA private key in PEM form (PKCS#1 `BEGIN RSA PRIVATE KEY` or
    /// PKCS#8 `BEGIN PRIVATE KEY`; the signer normalizes to PKCS#1).
    public let privateKeyPEM: String

    public init(apiKeyID: String, privateKeyPEM: String) {
        self.apiKeyID = apiKeyID
        self.privateKeyPEM = privateKeyPEM
    }
}

/// Produces the per-request authentication headers Kalshi requires for
/// authenticated (portfolio/order) endpoints.
///
/// Implementations sign the string `"\(timestampMs)\(method)\(path)"` with
/// RSA-PSS / SHA-256 and return the three `KALSHI-ACCESS-*` headers. The
/// networking client depends only on this protocol, so the concrete
/// Security-framework signer stays an isolated, separately-testable unit.
public protocol RequestSigning: Sendable {
    /// - Parameters:
    ///   - method: Uppercase HTTP method, e.g. `"GET"`, `"POST"`.
    ///   - path: Request path **including** `/trade-api/v2` and **excluding** any query string.
    ///   - timestampMs: Unix time in milliseconds; reused verbatim in the timestamp header.
    /// - Returns: `KALSHI-ACCESS-KEY`, `KALSHI-ACCESS-TIMESTAMP`, `KALSHI-ACCESS-SIGNATURE`.
    func authHeaders(method: String, path: String, timestampMs: Int64) throws -> [String: String]
}
