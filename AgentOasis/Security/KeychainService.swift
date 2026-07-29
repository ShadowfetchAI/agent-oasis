import CryptoKit
import Foundation
import Security

/// Storage for the 256-bit workspace key.
///
/// USES THE DATA PROTECTION KEYCHAIN, DELIBERATELY. Until 2026-07-29 these queries set
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` but never set
/// `kSecUseDataProtectionKeychain`. On macOS that means the item went to the LEGACY
/// file-based keychain, where the accessibility attribute is not enforced the way it is in
/// the data protection keychain - so the protection the README advertised was not actually
/// in force. The attribute was present, readable, and doing nothing, which is the most
/// expensive kind of wrong: it answers the question "is this protected?" with a yes.
///
/// MIGRATION IS NOT OPTIONAL. Turning the flag on changes WHERE the item lives, so a naive
/// switch would leave the existing key behind in the legacy keychain and the app would
/// generate a fresh one - and every existing workspace would be permanently undecryptable.
/// `loadOrCreateKey` therefore looks in the new keychain, then the old one, and migrates
/// before it ever considers minting a new key.
enum KeychainService {
    private static let service = "com.realbobcorbin.AgentOasis.workspace"
    private static let account = "primary-encryption-key"

    private static func baseQuery(dataProtection: Bool) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain] = true }
        return query
    }

    static func loadOrCreateKey() throws -> SymmetricKey {
        if let data = try loadKeyData(dataProtection: true) {
            guard data.count == 32 else { throw WorkspaceSecurityError.invalidKey }
            return SymmetricKey(data: data)
        }

        // Legacy keychain. Anything found here predates the migration and is the real key.
        if let legacy = try? loadKeyData(dataProtection: false), legacy.count == 32 {
            try storeKeyData(legacy)
            // Only remove the old copy once the new one is provably readable. A failed
            // delete leaves a duplicate, which is recoverable; deleting first and failing
            // to write loses the workspace forever.
            if let confirmed = try? loadKeyData(dataProtection: true), confirmed == legacy {
                let query = baseQuery(dataProtection: false)
                _ = SecItemDelete(query as CFDictionary)
            }
            return SymmetricKey(data: legacy)
        }

        let key = SymmetricKey(size: .bits256)
        try storeKeyData(key.withUnsafeBytes { Data($0) })
        return key
    }

    static func replaceKey(with data: Data) throws -> SymmetricKey {
        guard data.count == 32 else { throw WorkspaceSecurityError.invalidKey }
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(
            baseQuery(dataProtection: true) as CFDictionary,
            attributes as CFDictionary
        )
        if status == errSecItemNotFound {
            try storeKeyData(data)
        } else if status != errSecSuccess {
            throw WorkspaceSecurityError.keychain(status)
        }
        return SymmetricKey(data: data)
    }

    static func deleteKey() throws {
        // Both keychains: a stale legacy copy of a deleted key is exactly the residue this
        // whole type exists to stop leaving behind.
        let modern = SecItemDelete(baseQuery(dataProtection: true) as CFDictionary)
        _ = SecItemDelete(baseQuery(dataProtection: false) as CFDictionary)
        guard modern == errSecSuccess || modern == errSecItemNotFound else {
            throw WorkspaceSecurityError.keychain(modern)
        }
    }

    private static func loadKeyData(dataProtection: Bool) throws -> Data? {
        var query = baseQuery(dataProtection: dataProtection)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw WorkspaceSecurityError.keychain(status)
        }
        return data
    }

    private static func storeKeyData(_ data: Data) throws {
        var query = baseQuery(dataProtection: true)
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecValueData] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [CFString: Any] = [kSecValueData: data]
            let updated = SecItemUpdate(
                baseQuery(dataProtection: true) as CFDictionary,
                update as CFDictionary
            )
            guard updated == errSecSuccess else {
                throw WorkspaceSecurityError.keychain(updated)
            }
            return
        }
        guard status == errSecSuccess else {
            throw WorkspaceSecurityError.keychain(status)
        }
    }
}
