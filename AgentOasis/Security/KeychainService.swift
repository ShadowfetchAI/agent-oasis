import CryptoKit
import Foundation
import Security

enum KeychainService {
    private static let service = "com.realbobcorbin.AgentOasis.workspace"
    private static let account = "primary-encryption-key"

    static func loadOrCreateKey() throws -> SymmetricKey {
        if let data = try loadKeyData() {
            guard data.count == 32 else { throw WorkspaceSecurityError.invalidKey }
            return SymmetricKey(data: data)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try storeKeyData(data)
        return key
    }

    static func replaceKey(with data: Data) throws -> SymmetricKey {
        guard data.count == 32 else { throw WorkspaceSecurityError.invalidKey }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            try storeKeyData(data)
        } else if status != errSecSuccess {
            throw WorkspaceSecurityError.keychain(status)
        }
        return SymmetricKey(data: data)
    }

    static func deleteKey() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WorkspaceSecurityError.keychain(status)
        }
    }

    private static func loadKeyData() throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw WorkspaceSecurityError.keychain(status)
        }
        return data
    }

    private static func storeKeyData(_ data: Data) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WorkspaceSecurityError.keychain(status)
        }
    }
}
