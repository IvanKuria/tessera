import Foundation
import Security

/// Persists a single set of ``KalshiCredentials`` in the macOS Keychain as one
/// generic-password item, keyed by `service`. The API Key ID is stored as the
/// item's account and the PEM private key as its secret data.
///
/// ## Data-protection vs legacy keychain
/// The modern **data-protection keychain** (`kSecUseDataProtectionKeychain: true`)
/// honors access-control attributes but requires a `keychain-access-groups`
/// entitlement — which an ad-hoc / unsigned build doesn't have, producing
/// `errSecMissingEntitlement` (-34018). Each operation therefore tries the
/// data-protection keychain first and, if the entitlement is missing, falls back
/// to the legacy file keychain (which works for unsigned/dev builds). A properly
/// signed `.app` with the entitlement transparently uses the secure path.
///
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` keeps the signing key on this
/// device (never iCloud Keychain / backups); `kSecAttrSynchronizable` is not set.
public struct KeychainCredentialStore: Sendable {
    /// The keychain service identifier used to group this SDK's items.
    private let service: String

    /// `errSecMissingEntitlement` — the data-protection keychain isn't available
    /// to this (unsigned/un-entitled) process.
    private static let missingEntitlement: OSStatus = -34018

    public init(service: String = "com.kalshikit.credentials") {
        self.service = service
    }

    /// Base query attributes shared by every operation.
    private func baseQuery(dataProtection: Bool) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain] = true
        }
        return query
    }

    /// Saves credentials, replacing any existing item for this service.
    public func save(_ credentials: KalshiCredentials) throws {
        guard let pemData = credentials.privateKeyPEM.data(using: .utf8) else {
            throw KalshiError.signing(reason: "Could not UTF-8 encode private key for keychain storage.")
        }

        var lastStatus: OSStatus = errSecSuccess
        for dataProtection in [true, false] {
            // Remove any existing item in this keychain domain first.
            let deleteStatus = SecItemDelete(baseQuery(dataProtection: dataProtection) as CFDictionary)
            if deleteStatus == Self.missingEntitlement { lastStatus = deleteStatus; continue }

            var attributes = baseQuery(dataProtection: dataProtection)
            attributes[kSecAttrAccount] = credentials.apiKeyID
            attributes[kSecValueData] = pemData
            if dataProtection {
                attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }

            let status = SecItemAdd(attributes as CFDictionary, nil)
            if status == Self.missingEntitlement { lastStatus = status; continue }
            guard status == errSecSuccess else {
                throw KalshiError.signing(reason: "Keychain save failed: \(Self.message(for: status))")
            }
            return
        }
        throw KalshiError.signing(reason: "Keychain save failed: \(Self.message(for: lastStatus))")
    }

    /// Loads the stored credentials, or `nil` if none are present.
    public func load() throws -> KalshiCredentials? {
        var lastStatus: OSStatus = errSecItemNotFound
        for dataProtection in [true, false] {
            var query = baseQuery(dataProtection: dataProtection)
            query[kSecReturnData] = true
            query[kSecReturnAttributes] = true
            query[kSecMatchLimit] = kSecMatchLimitOne

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            if status == errSecItemNotFound { return nil }
            if status == Self.missingEntitlement { lastStatus = status; continue }
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
        // Couldn't reach a keychain we're entitled to — treat as "no stored creds".
        _ = lastStatus
        return nil
    }

    /// Removes the stored credentials, if any. A missing item is treated as success.
    public func clear() throws {
        for dataProtection in [true, false] {
            let status = SecItemDelete(baseQuery(dataProtection: dataProtection) as CFDictionary)
            if status == Self.missingEntitlement { continue }
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KalshiError.signing(reason: "Keychain clear failed: \(Self.message(for: status))")
            }
            return
        }
        // No entitled keychain available — nothing we could have stored anyway.
    }

    /// Maps an `OSStatus` to a human-readable string for error messages.
    private static func message(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (OSStatus \(status))"
        }
        return "OSStatus \(status)"
    }
}
