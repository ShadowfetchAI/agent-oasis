import CryptoKit
import Foundation

struct EncryptedWorkspaceEnvelope: Codable, Equatable {
    var formatVersion: Int
    var nonce: Data
    var ciphertext: Data
    var tag: Data
}

enum WorkspaceCipher {
    static func encrypt<T: Encodable>(_ value: T, using key: SymmetricKey) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let plaintext = try encoder.encode(value)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        let envelope = EncryptedWorkspaceEnvelope(
            formatVersion: 1,
            nonce: Data(sealed.nonce),
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
        return try encoder.encode(envelope)
    }

    static func decrypt<T: Decodable>(
        _ type: T.Type,
        from encryptedData: Data,
        using key: SymmetricKey
    ) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(EncryptedWorkspaceEnvelope.self, from: encryptedData)
        guard envelope.formatVersion == 1 else {
            throw WorkspaceSecurityError.unsupportedFormat
        }
        let nonce = try AES.GCM.Nonce(data: envelope.nonce)
        let box = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: envelope.ciphertext,
            tag: envelope.tag
        )
        let plaintext = try AES.GCM.open(box, using: key)
        return try decoder.decode(type, from: plaintext)
    }
}

enum WorkspaceSecurityError: LocalizedError {
    case authenticationUnavailable
    case authenticationFailed
    case keychain(OSStatus)
    case invalidKey
    case unsupportedFormat
    case workspaceLocked
    case invalidBackup
    case storageUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .authenticationUnavailable:
            "This Mac cannot currently perform owner authentication."
        case .authenticationFailed:
            "Agent Oasis could not verify the device owner."
        case .keychain(let status):
            "Keychain operation failed with status \(status)."
        case .invalidKey:
            "The workspace encryption key is invalid."
        case .unsupportedFormat:
            "This Agent Oasis workspace format is not supported."
        case .workspaceLocked:
            "Unlock Agent Oasis before performing this operation."
        case .invalidBackup:
            "The selected backup or recovery key is not valid."
        case .storageUnavailable(let reason):
            reason
        }
    }
}
