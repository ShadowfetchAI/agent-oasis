import CryptoKit
import Foundation
import XCTest

/// Regression tests for defects that only show up on someone else's Mac.
///
/// Each of these shipped in a build that compiled cleanly and passed every existing test.
/// They were found by auditing the crash and data-loss paths specifically, which is a
/// different question from "does the feature work".
final class CrashAndDataLossTests: XCTestCase {

    // MARK: - The parser used to kill the process

    /// A header line ending in two delimiters must not trap.
    ///
    /// `Dictionary(uniqueKeysWithValues:)` traps on duplicate keys - SIGTRAP, not a thrown
    /// error, so the do/catch around the import could not save it. Trailing empty columns are
    /// exactly what Excel, Numbers and Sheets emit, and both file pickers accept any file, so
    /// picking the wrong document killed the app outright.
    func testTrailingEmptyHeaderColumnsDoNotTrap() {
        let rows = DelimitedTextParser.parse("Date,Units,,\n2026-01-01,5,,\n")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["Date"], "2026-01-01")
        XCTAssertEqual(rows[0]["Units"], "5")
        XCTAssertNil(rows[0][""], "Blank headers must be dropped, not collide.")
    }

    /// Two identical named headers must not trap either; first column wins.
    func testDuplicateNamedHeadersDoNotTrap() {
        let rows = DelimitedTextParser.parse("Units,Units\n7,9\n")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["Units"], "7", "First column wins, matching value(in:keys:).")
    }

    /// Whitespace-only headers collapse to the same key and must not trap.
    func testWhitespaceOnlyHeadersDoNotTrap() {
        let rows = DelimitedTextParser.parse("Date, , \n2026-01-01,a,b\n")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["Date"], "2026-01-01")
    }

    // MARK: - Restoring must not destroy what it replaces

    /// The workspace that a restore replaces has to survive somewhere.
    ///
    /// `replaceItemAt` without `backupItemName:` unlinks the outgoing file permanently, so
    /// restoring last month's backup silently destroyed every entry recorded since - while
    /// Settings described the operation as validated and safe.
    func testRestoreRetainsTheReplacedWorkspace() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ao-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = try EncryptedWorkspaceRepository(baseDirectory: directory)
        let key = SymmetricKey(size: .bits256)

        var current = WorkspaceState()
        current.name = "Current work"
        try repository.save(current, using: key)

        var older = WorkspaceState()
        older.name = "Older backup"
        let backupBytes = try WorkspaceCipher.encrypt(older, using: key)

        _ = try repository.restoreEncryptedBackup(backupBytes, using: key)
        XCTAssertEqual(try repository.load(using: key)?.name, "Older backup")

        let retained = repository.workspaceURL
            .deletingLastPathComponent()
            .appendingPathComponent("workspace-previous.aovault")
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path),
                      "The replaced workspace must be retained, not unlinked.")
        let recovered = try WorkspaceCipher.decrypt(
            WorkspaceState.self, from: Data(contentsOf: retained), using: key)
        XCTAssertEqual(recovered.name, "Current work",
                       "The retained copy must be the work the restore replaced.")
    }
}

/// The audit trail's evidence hash has to be something a person can actually check.
@MainActor
final class AuditChainTests: XCTestCase {

    private func makeStore() throws -> (OasisStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ao-audit-\(UUID().uuidString)", isDirectory: true)
        let repository = try EncryptedWorkspaceRepository(baseDirectory: directory)
        let store = OasisStore(
            repository: repository,
            keyProvider: { _ in SymmetricKey(size: .bits256) },
            ownerAuthenticator: { _ in nil }
        )
        return (store, directory)
    }

    /// Every stored entry's hash must be reproducible from its own stored fields.
    ///
    /// It was not: `Date()` was called twice, so the digest covered a timestamp microseconds
    /// away from the one saved. The value was rendered in monospace beside financial records,
    /// where it reads as tamper-evidence, and could never be verified by anyone.
    func testEveryAuditHashRecomputesFromItsStoredFields() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.unlock()

        XCTAssertFalse(store.workspace.audit.isEmpty, "Unlocking should record an event")
        XCTAssertNil(OasisStore.firstBrokenAuditIndex(in: store.workspace.audit),
                     "A freshly written trail must verify against its own stored fields.")
    }

    /// The chain must survive being encrypted, written and read back.
    func testAuditChainSurvivesAWorkspaceRoundTrip() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ao-audit-rt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try EncryptedWorkspaceRepository(baseDirectory: directory)
        let key = SymmetricKey(size: .bits256)

        let first = OasisStore(repository: repository, keyProvider: { _ in key },
                               ownerAuthenticator: { _ in nil })
        await first.unlock()
        first.lock(reason: "test")

        let second = OasisStore(repository: repository, keyProvider: { _ in key },
                                ownerAuthenticator: { _ in nil })
        await second.unlock()
        XCTAssertNil(OasisStore.firstBrokenAuditIndex(in: second.workspace.audit),
                     "ISO-8601 is what gets persisted, so it is what must be hashed.")
    }

    /// Editing any recorded field must break that entry's hash.
    func testRewritingAnEntryBreaksItsHash() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.unlock()

        var audit = store.workspace.audit
        try XCTSkipIf(audit.isEmpty)
        audit[0].summary = "Something that did not happen"
        XCTAssertEqual(OasisStore.firstBrokenAuditIndex(in: audit), 0)
    }

    /// Deleting an entry must break every entry after it — that is what chaining buys.
    ///
    /// Without a chain, a per-row hash detects a rewritten row and nothing else: any row could
    /// be removed or reordered and the survivors all still checked out.
    func testDeletingAnEntryBreaksTheChain() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ao-chain-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try EncryptedWorkspaceRepository(baseDirectory: directory)
        let key = SymmetricKey(size: .bits256)

        // unlock -> lock -> unlock accumulates a real multi-entry trail across two sessions.
        // eraseWorkspace() cannot be used here: it replaces the workspace, so the audit array
        // is emptied and the record OF the erasure ends up as the only entry.
        let first = OasisStore(repository: repository, keyProvider: { _ in key },
                               ownerAuthenticator: { _ in nil })
        await first.unlock()
        first.lock(reason: "test")
        let second = OasisStore(repository: repository, keyProvider: { _ in key },
                                ownerAuthenticator: { _ in nil })
        await second.unlock()

        var audit = second.workspace.audit
        XCTAssertGreaterThanOrEqual(audit.count, 2,
                                    "Two sessions must leave at least two audit entries.")
        XCTAssertNil(OasisStore.firstBrokenAuditIndex(in: audit), "Precondition: intact chain")

        audit.remove(at: 0)
        XCTAssertNotNil(OasisStore.firstBrokenAuditIndex(in: audit),
                        "Removing an entry must invalidate the entries that followed it.")
    }
}
