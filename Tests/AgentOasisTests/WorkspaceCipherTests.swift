import CryptoKit
import XCTest

final class WorkspaceCipherTests: XCTestCase {
    func testEncryptedWorkspaceRoundTrip() throws {
        let original = DemoWorkspace.make(now: Date(timeIntervalSince1970: 1_700_000_000))
        let key = SymmetricKey(size: .bits256)

        let encrypted = try WorkspaceCipher.encrypt(original, using: key)
        let decrypted = try WorkspaceCipher.decrypt(
            WorkspaceState.self,
            from: encrypted,
            using: key
        )

        XCTAssertEqual(decrypted, original)
        XCTAssertFalse(encrypted.contains(Data("Chirphound".utf8)))
    }

    func testTamperedWorkspaceFailsAuthentication() throws {
        let state = DemoWorkspace.make()
        let key = SymmetricKey(size: .bits256)
        let encrypted = try WorkspaceCipher.encrypt(state, using: key)
        let decoder = JSONDecoder()
        var envelope = try decoder.decode(EncryptedWorkspaceEnvelope.self, from: encrypted)
        envelope.ciphertext[0] ^= 0x01
        let tampered = try JSONEncoder().encode(envelope)

        XCTAssertThrowsError(
            try WorkspaceCipher.decrypt(WorkspaceState.self, from: tampered, using: key)
        )
    }

    func testWrongKeyCannotDecryptWorkspace() throws {
        let encrypted = try WorkspaceCipher.encrypt(
            DemoWorkspace.make(),
            using: SymmetricKey(size: .bits256)
        )
        XCTAssertThrowsError(
            try WorkspaceCipher.decrypt(
                WorkspaceState.self,
                from: encrypted,
                using: SymmetricKey(size: .bits256)
            )
        )
    }

    func testEncryptedBackupRestoreReplacesWorkspaceAndKeepsMode600() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = try EncryptedWorkspaceRepository(baseDirectory: root)
        let key = SymmetricKey(size: .bits256)
        let original = DemoWorkspace.make(now: Date(timeIntervalSince1970: 1_700_000_000))
        try repository.save(original, using: key)
        let backup = try repository.encryptedBackupData()

        var replacement = DemoWorkspace.make()
        replacement.name = "Replacement"
        try repository.save(replacement, using: key)

        let restored = try repository.restoreEncryptedBackup(backup, using: key)
        let reloaded = try XCTUnwrap(repository.load(using: key))
        let attributes = try FileManager.default.attributesOfItem(
            atPath: repository.workspaceURL.path
        )
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)

        XCTAssertEqual(restored, original)
        XCTAssertEqual(reloaded, original)
        XCTAssertEqual(permissions.intValue, 0o600)
    }
}
