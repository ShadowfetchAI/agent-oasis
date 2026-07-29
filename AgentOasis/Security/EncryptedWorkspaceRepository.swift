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
        try writePrivately(encrypted)
    }

    /// Write so the file is never briefly readable by anyone else.
    ///
    /// `Data.write(options: .atomic)` creates its temporary file at the process umask -
    /// typically 0644 - and the chmod that followed only narrowed it afterwards. Between
    /// those two calls an encrypted workspace sat world-readable. The contents are encrypted,
    /// so this was never a disclosure of plaintext, but "0600" was documented as a property
    /// of the file and it was not continuously true. Creating the file private and renaming
    /// it into place closes the window instead of shortening it.
    private func writePrivately(_ data: Data) throws {
        let directory = workspaceURL.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            ".workspace-\(UUID().uuidString).tmp"
        )
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            defer { try? handle.close() }
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        _ = try FileManager.default.replaceItemAt(workspaceURL, withItemAt: temporary)
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
        try writePrivately(data)
        return state
    }

    func deleteWorkspace() throws {
        guard FileManager.default.fileExists(atPath: workspaceURL.path) else { return }
        try FileManager.default.removeItem(at: workspaceURL)
    }
}
