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
