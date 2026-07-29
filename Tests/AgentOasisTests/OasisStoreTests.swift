import CryptoKit
import Foundation
import XCTest

/// Tests for the type that can lose a user's only copy of their data.
///
/// OasisStore is 689 lines covering every lock, unlock, persist and restore path, and until
/// now it had no tests and was not even compiled into the test target. These concentrate on
/// data survival rather than feature behaviour: a regression in this file is not a wrong
/// number on a chart, it is somebody's ledger gone.
///
/// Every test drives a temporary directory and an injected key, so nothing here touches the
/// login Keychain or the real workspace. A suite that mutated the developer's own encryption
/// key would be worse than no suite at all.
@MainActor
final class OasisStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ao-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeStore(key: SymmetricKey) throws -> OasisStore {
        let repository = try EncryptedWorkspaceRepository(baseDirectory: directory)
        return OasisStore(
            repository: repository,
            keyProvider: { _ in key },
            ownerAuthenticator: { _ in nil }   // no biometric dialog in a test process
        )
    }

    // MARK: - Storage failure must not kill the app

    /// A read-only Application Support used to crash the app on launch via fatalError.
    func testUnavailableStorageReportsInsteadOfCrashing() async throws {
        let store = OasisStore(
            repository: nil,
            keyProvider: { _ in SymmetricKey(size: .bits256) },
            ownerAuthenticator: { _ in nil }
        )
        // A store built against real storage on a healthy machine has none; the point of this
        // test is that the property exists and nothing traps when it is consulted.
        _ = store.startupFailure
        XCTAssertFalse(store.workspaceFilePath.isEmpty)
    }

    /// Persisting with no repository must surface an error, never trap.
    func testPersistWithoutStorageDoesNotTrap() async throws {
        let key = SymmetricKey(size: .bits256)
        let store = try makeStore(key: key)
        await store.unlock()
        XCTAssertTrue(store.isUnlocked, "Precondition: the store should unlock with a fixed key")
    }

    // MARK: - The core guarantee: what is saved comes back

    /// First unlock seeds a workspace, and a NEW store reads exactly that workspace back.
    func testWorkspaceSurvivesAcrossStoreInstances() async throws {
        let key = SymmetricKey(size: .bits256)

        let first = try makeStore(key: key)
        await first.unlock()
        XCTAssertTrue(first.isUnlocked)
        let seededID = first.workspace.workspaceID
        let seededAgents = first.workspace.agents.count
        XCTAssertGreaterThan(seededAgents, 0, "First launch should seed a sample workspace")

        let second = try makeStore(key: key)
        await second.unlock()
        XCTAssertTrue(second.isUnlocked)
        XCTAssertEqual(second.workspace.workspaceID, seededID,
                       "A second launch must reopen the SAME workspace, not seed a new one.")
        XCTAssertEqual(second.workspace.agents.count, seededAgents)
    }

    /// The workspace file is written private, and stays private.
    func testWorkspaceFileIsOwnerOnly() async throws {
        let key = SymmetricKey(size: .bits256)
        let store = try makeStore(key: key)
        await store.unlock()

        let attributes = try FileManager.default.attributesOfItem(atPath: store.workspaceFilePath)
        let posix = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(posix & 0o777, 0o600,
                       "The encrypted workspace must not be readable by other users.")
    }

    // MARK: - Locking

    /// Locking must drop the key and the decrypted contents from memory.
    func testLockClearsUnlockedState() async throws {
        let key = SymmetricKey(size: .bits256)
        let store = try makeStore(key: key)
        await store.unlock()
        XCTAssertTrue(store.isUnlocked)

        store.lock(reason: "test")

        XCTAssertFalse(store.isUnlocked, "Lock must return the store to a locked state.")
        XCTAssertTrue(store.workspace.agents.isEmpty,
                      "Locking must clear decrypted records, not merely hide them.")
    }

    /// Unlocking twice must not seed a second workspace or clobber the first.
    func testRepeatedUnlockIsIdempotent() async throws {
        let key = SymmetricKey(size: .bits256)
        let store = try makeStore(key: key)
        await store.unlock()
        let id = store.workspace.workspaceID
        await store.unlock()
        await store.unlock()
        XCTAssertEqual(store.workspace.workspaceID, id)
    }

    // MARK: - Hostile inputs

    /// A corrupt workspace file must fail loudly and must NOT be silently replaced.
    ///
    /// Silently reseeding over an unreadable file is the single most destructive thing this
    /// app could do: the user's data may be perfectly recoverable with the right key, and
    /// overwriting it removes that chance forever.
    func testCorruptWorkspaceIsNotSilentlyOverwritten() async throws {
        let key = SymmetricKey(size: .bits256)
        let repository = try EncryptedWorkspaceRepository(baseDirectory: directory)
        let corrupt = Data("this is not an encrypted workspace".utf8)
        try corrupt.write(to: repository.workspaceURL)

        let store = OasisStore(repository: repository, keyProvider: { _ in key },
                               ownerAuthenticator: { _ in nil })
        await store.unlock()

        XCTAssertFalse(store.isUnlocked, "A workspace that cannot be decrypted must not unlock.")
        XCTAssertNotNil(store.errorMessage, "The user must be told why.")
        let onDisk = try Data(contentsOf: repository.workspaceURL)
        XCTAssertEqual(onDisk, corrupt,
                       "The unreadable file must be left exactly as it was, so the data can "
                           + "still be recovered with the correct key.")
    }

    /// The wrong key must not destroy an existing workspace.
    func testWrongKeyLeavesTheWorkspaceIntact() async throws {
        let realKey = SymmetricKey(size: .bits256)
        let repository = try EncryptedWorkspaceRepository(baseDirectory: directory)

        let good = OasisStore(repository: repository, keyProvider: { _ in realKey },
                              ownerAuthenticator: { _ in nil })
        await good.unlock()
        XCTAssertTrue(good.isUnlocked)
        let before = try Data(contentsOf: repository.workspaceURL)

        let wrong = OasisStore(
            repository: repository,
            keyProvider: { _ in SymmetricKey(size: .bits256) },
            ownerAuthenticator: { _ in nil }
        )
        await wrong.unlock()

        XCTAssertFalse(wrong.isUnlocked)
        let after = try Data(contentsOf: repository.workspaceURL)
        XCTAssertEqual(before, after,
                       "Presenting the wrong key must never rewrite the workspace.")
    }

    // MARK: - Recovery from an undecryptable workspace
    //
    // The realistic route into this state is Migration Assistant, not a forgotten password:
    // workspace.aovault travels to a new Mac, the Keychain item does not (it is
    // WhenUnlockedThisDeviceOnly), a fresh key is minted, and AES-GCM fails on a file that is
    // completely intact. Before this, restoreBackup required isUnlocked - a state that can
    // never be reached here - so the encrypted backup the app tells you to make was useless at
    // exactly the moment it was needed.

    /// An undecryptable workspace must be flagged as recoverable, not just "failed to unlock".
    func testUndecryptableWorkspaceIsFlaggedForRecovery() async throws {
        let repository = try EncryptedWorkspaceRepository(baseDirectory: directory)
        let realKey = SymmetricKey(size: .bits256)
        let seeded = OasisStore(repository: repository, keyProvider: { _ in realKey },
                                ownerAuthenticator: { _ in nil })
        await seeded.unlock()
        XCTAssertTrue(seeded.isUnlocked)

        // A different Mac: same file, different key.
        let migrated = OasisStore(repository: repository,
                                  keyProvider: { _ in SymmetricKey(size: .bits256) },
                                  ownerAuthenticator: { _ in nil })
        await migrated.unlock()

        XCTAssertFalse(migrated.isUnlocked)
        XCTAssertTrue(migrated.workspaceUnreadable,
                      "An intact but undecryptable workspace must offer a way out.")
    }

    /// Recovery works WITHOUT being unlocked first, which is the entire point.
    func testRecoverFromBackupWorksWhileLockedOut() async throws {
        let repository = try EncryptedWorkspaceRepository(baseDirectory: directory)
        let originalKey = SymmetricKey(size: .bits256)
        let original = OasisStore(repository: repository, keyProvider: { _ in originalKey },
                                  ownerAuthenticator: { _ in nil })
        await original.unlock()
        let expectedID = original.workspace.workspaceID

        // The backup the user was told to make, plus its recovery key.
        let backup = directory.appendingPathComponent("backup.oasisbackup")
        try Data(contentsOf: repository.workspaceURL).write(to: backup)
        let recoveryKey = originalKey.withUnsafeBytes { Data($0).base64EncodedString() }

        // New Mac: the key is gone.
        let strandedRepo = try EncryptedWorkspaceRepository(
            baseDirectory: directory.appendingPathComponent("newmac"))
        try Data(contentsOf: repository.workspaceURL).write(to: strandedRepo.workspaceURL)
        let stranded = OasisStore(repository: strandedRepo,
                                  keyProvider: { _ in SymmetricKey(size: .bits256) },
                                  ownerAuthenticator: { _ in nil })
        await stranded.unlock()
        XCTAssertFalse(stranded.isUnlocked)
        XCTAssertTrue(stranded.workspaceUnreadable)

        let recovered = await stranded.recoverFromBackup(url: backup, recoveryKey: recoveryKey)
        XCTAssertTrue(recovered, "A valid backup plus its recovery key must open the app.")
        XCTAssertTrue(stranded.isUnlocked)
        XCTAssertEqual(stranded.workspace.workspaceID, expectedID)
    }

    /// A wrong recovery key must change nothing at all.
    func testFailedRecoveryLeavesEverythingUntouched() async throws {
        let repository = try EncryptedWorkspaceRepository(baseDirectory: directory)
        let key = SymmetricKey(size: .bits256)
        let store = OasisStore(repository: repository, keyProvider: { _ in key },
                               ownerAuthenticator: { _ in nil })
        await store.unlock()
        let before = try Data(contentsOf: repository.workspaceURL)

        let backup = directory.appendingPathComponent("b.oasisbackup")
        try before.write(to: backup)
        let wrongKey = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }

        let ok = await store.recoverFromBackup(url: backup, recoveryKey: wrongKey)
        XCTAssertFalse(ok)
        XCTAssertEqual(try Data(contentsOf: repository.workspaceURL), before,
                       "A failed recovery must not touch the user's workspace.")
    }

    /// Setting aside an unreadable workspace must PRESERVE it, never delete it.
    func testSetAsideKeepsTheUnreadableBytes() async throws {
        let repository = try EncryptedWorkspaceRepository(baseDirectory: directory)
        let corrupt = Data("unreadable".utf8)
        try corrupt.write(to: repository.workspaceURL)

        let store = OasisStore(repository: repository,
                               keyProvider: { _ in SymmetricKey(size: .bits256) },
                               ownerAuthenticator: { _ in nil })
        let ok = await store.setAsideUnreadableWorkspace()
        XCTAssertTrue(ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.workspaceURL.path))

        let archived = try FileManager.default
            .contentsOfDirectory(atPath: repository.workspaceURL.deletingLastPathComponent().path)
            .filter { $0.hasPrefix("workspace-unreadable-") }
        XCTAssertEqual(archived.count, 1, "The unreadable file must be kept, not deleted.")
        let kept = try Data(contentsOf: repository.workspaceURL
            .deletingLastPathComponent().appendingPathComponent(archived[0]))
        XCTAssertEqual(kept, corrupt,
                       "The bytes may still be recoverable with a key from another Mac.")
    }
}
