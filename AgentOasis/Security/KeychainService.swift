import CryptoKit
import Foundation
import LocalAuthentication
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

    /// True when the data protection keychain is usable for WRITES by this build.
    ///
    /// It needs the `keychain-access-groups` entitlement; without it calls return -34018
    /// (errSecMissingEntitlement) and the app cannot open its own workspace. Losing access
    /// to the ledger is a far worse outcome than storing its key in the older keychain, so
    /// this falls back rather than failing to start.
    ///
    /// THE PROBE WRITES, because reads do not need the entitlement. A first attempt at this
    /// used SecItemCopyMatching and reported the keychain available on a build that could
    /// not write to it - the read succeeded, the real SecItemAdd then failed with -34018,
    /// and the app showed that error instead of a workspace. A probe has to exercise the
    /// operation it is vouching for.
    private static let dataProtectionAvailable: Bool = {
        let probeService = "com.realbobcorbin.AgentOasis.probe"
        var add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: probeService,
            kSecAttrAccount: "availability",
            kSecUseDataProtectionKeychain: true,
            kSecValueData: Data([0x01])
        ]
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem { status = errSecSuccess }

        if status == errSecSuccess {
            let cleanup: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: probeService,
                kSecAttrAccount: "availability",
                kSecUseDataProtectionKeychain: true
            ]
            _ = SecItemDelete(cleanup as CFDictionary)
        }
        add.removeAll()
        return status == errSecSuccess
    }()

    /// Access control requiring the device owner to be present.
    ///
    /// Only meaningful on the data protection keychain; the legacy keychain ignores it, which
    /// is why `dataProtectionAvailable` gates its use. `.userPresence` accepts Touch ID or the
    /// Mac password, so a Mac without Touch ID is not locked out of its own workspace.
    private static func ownerPresenceAccess() -> SecAccessControl? {
        SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            nil
        )
    }

    static func loadOrCreateKey(context: LAContext? = nil) throws -> SymmetricKey {
        guard dataProtectionAvailable else {
            // Legacy keychain only. Same behaviour as before this type was hardened.
            if let data = try loadKeyData(dataProtection: false) {
                guard data.count == 32 else { throw WorkspaceSecurityError.invalidKey }
                return SymmetricKey(data: data)
            }
            let key = SymmetricKey(size: .bits256)
            var query = baseQuery(dataProtection: false)
            query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            query[kSecValueData] = key.withUnsafeBytes { Data($0) }
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw WorkspaceSecurityError.keychain(status)
            }
            return key
        }

        if let data = try loadKeyData(
            dataProtection: dataProtectionAvailable, context: context) {
            guard data.count == 32 else { throw WorkspaceSecurityError.invalidKey }
            return SymmetricKey(data: data)
        }

        // Legacy keychain. Anything found here predates the migration and is the real key.
        if let legacy = try? loadKeyData(dataProtection: false), legacy.count == 32 {
            try storeKeyData(legacy, context: context)
            // Only remove the old copy once the new one is provably readable. A failed
            // delete leaves a duplicate, which is recoverable; deleting first and failing
            // to write loses the workspace forever.
            if let confirmed = try? loadKeyData(dataProtection: dataProtectionAvailable),
               confirmed == legacy {
                let query = baseQuery(dataProtection: false)
                _ = SecItemDelete(query as CFDictionary)
            }
            return SymmetricKey(data: legacy)
        }

        let key = SymmetricKey(size: .bits256)
        try storeKeyData(key.withUnsafeBytes { Data($0) }, context: context)
        return key
    }

    static func replaceKey(with data: Data) throws -> SymmetricKey {
        guard data.count == 32 else { throw WorkspaceSecurityError.invalidKey }
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(
            baseQuery(dataProtection: dataProtectionAvailable) as CFDictionary,
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
        let modern = SecItemDelete(
            baseQuery(dataProtection: dataProtectionAvailable) as CFDictionary)
        _ = SecItemDelete(baseQuery(dataProtection: false) as CFDictionary)
        guard modern == errSecSuccess || modern == errSecItemNotFound else {
            throw WorkspaceSecurityError.keychain(modern)
        }
    }

    private static func loadKeyData(
        dataProtection: Bool,
        context: LAContext? = nil
    ) throws -> Data? {
        var query = baseQuery(dataProtection: dataProtection)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        // Reuse the proof from the unlock prompt rather than raising a second one.
        if let context { query[kSecUseAuthenticationContext] = context }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw WorkspaceSecurityError.keychain(status)
        }
        return data
    }

    private static func storeKeyData(_ data: Data, context: LAContext? = nil) throws {
        var query = baseQuery(dataProtection: dataProtectionAvailable)
        query[kSecValueData] = data
        if let context { query[kSecUseAuthenticationContext] = context }
        // Bind the key to owner presence where the keychain honours it; fall back to the
        // plain accessibility class where it does not.
        if dataProtectionAvailable, let access = ownerPresenceAccess() {
            query[kSecAttrAccessControl] = access
        } else {
            query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [CFString: Any] = [kSecValueData: data]
            let updated = SecItemUpdate(
                baseQuery(dataProtection: dataProtectionAvailable) as CFDictionary,
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
