import Foundation
import Security

/// Persists a single set of ``KalshiCredentials`` in the macOS Keychain as one
/// generic-password item, keyed by `service`. The API Key ID is stored as the
/// item's account and the PEM private key as its secret data.
///
/// ## Code-signing requirement
/// Keychain access on macOS requires the calling process to be code-signed.
/// This works in a signed `.app`, but an unsigned CLI or test binary may be
/// prompted for authorization or fail with an access error. Treat this type as
/// app-facing storage, not something to exercise from unsigned unit tests.
///
/// ## Storage choices
/// - `kSecUseDataProtectionKeychain: true` — required on macOS so that access
///   control is honored (without it, accessibility is ignored and prompts can
///   appear). This opts into the modern data-protection keychain.
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — the signing key stays on
///   this device and never enters iCloud Keychain or backups.
/// - `kSecAttrSynchronizable` is deliberately *not* set, keeping the item local.
public struct KeychainCredentialStore: Sendable {
    /// The keychain service identifier used to group this SDK's items.
    private let service: String

    public init(service: String = "com.kalshikit.credentials") {
        self.service = service
    }

    /// Base query attributes shared by every operation.
    private func baseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecUseDataProtectionKeychain: true,
        ]
    }

    /// Saves credentials, replacing any existing item for this service.
    ///
    /// - Throws: ``KalshiError/signing(reason:)`` if the keychain write fails.
    public func save(_ credentials: KalshiCredentials) throws {
        // Replace any existing item so the store always holds at most one.
        try clear()

        guard let pemData = credentials.privateKeyPEM.data(using: .utf8) else {
            throw KalshiError.signing(reason: "Could not UTF-8 encode private key for keychain storage.")
        }

        var attributes = baseQuery()
        attributes[kSecAttrAccount] = credentials.apiKeyID
        attributes[kSecValueData] = pemData
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KalshiError.signing(reason: "Keychain save failed: \(Self.message(for: status))")
        }
    }

    /// Loads the stored credentials, or `nil` if none are present.
    ///
    /// - Throws: ``KalshiError/signing(reason:)`` if the keychain read fails for
    ///   a reason other than "item not found".
    public func load() throws -> KalshiCredentials? {
        var query = baseQuery()
        query[kSecReturnData] = true
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KalshiError.signing(reason: "Keychain load failed: \(Self.message(for: status))")
        }

        guard
            let item = result as? [CFString: Any],
            let account = item[kSecAttrAccount] as? String,
            let pemData = item[kSecValueData] as? Data,
            let pem = String(data: pemData, encoding: .utf8)
        else {
            throw KalshiError.signing(reason: "Keychain item is missing or malformed.")
        }

        return KalshiCredentials(apiKeyID: account, privateKeyPEM: pem)
    }

    /// Removes the stored credentials, if any. A missing item is treated as success.
    ///
    /// - Throws: ``KalshiError/signing(reason:)`` if the keychain delete fails.
    public func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KalshiError.signing(reason: "Keychain clear failed: \(Self.message(for: status))")
        }
    }

    /// Maps an `OSStatus` to a human-readable string for error messages.
    private static func message(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (OSStatus \(status))"
        }
        return "OSStatus \(status)"
    }
}
