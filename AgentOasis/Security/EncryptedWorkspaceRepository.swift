import CryptoKit
import Foundation

struct EncryptedWorkspaceRepository {
    let workspaceURL: URL

    init(baseDirectory: URL? = nil) throws {
        let root: URL
        if let baseDirectory {
            root = baseDirectory
        } else {
            root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Agent Oasis", isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        workspaceURL = root.appendingPathComponent("workspace.aovault")
    }

    func load(using key: SymmetricKey) throws -> WorkspaceState? {
        guard FileManager.default.fileExists(atPath: workspaceURL.path) else { return nil }
        let data = try Data(contentsOf: workspaceURL)
        return try WorkspaceCipher.decrypt(WorkspaceState.self, from: data, using: key)
    }

    func save(_ state: WorkspaceState, using key: SymmetricKey) throws {
        let encrypted = try WorkspaceCipher.encrypt(state, using: key)
        try encrypted.write(to: workspaceURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: workspaceURL.path
        )
    }

    func encryptedBackupData() throws -> Data {
        try Data(contentsOf: workspaceURL)
    }

    func restoreEncryptedBackup(_ data: Data, using key: SymmetricKey) throws -> WorkspaceState {
        let state = try WorkspaceCipher.decrypt(WorkspaceState.self, from: data, using: key)
        try data.write(to: workspaceURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: workspaceURL.path
        )
        return state
    }

    func deleteWorkspace() throws {
        guard FileManager.default.fileExists(atPath: workspaceURL.path) else { return }
        try FileManager.default.removeItem(at: workspaceURL)
    }
}
