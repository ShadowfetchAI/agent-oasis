import Foundation
import XCTest

/// Importing the same sales report twice must not double the money.
///
/// `importAppStoreRows` appended an observation and a revenue LedgerEntry unconditionally, and
/// `AnalyticsEngine.summary` sums `state.ledger` directly - so a re-download, a retry after a
/// mis-click, or the same file kept in two folders permanently doubled reported revenue with
/// no warning and no way to tell from the UI which entries were duplicates.
final class ImportIdempotencyTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ao-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    /// The importer derives its source name from the FILE NAME, so idempotency is scoped to
    /// the file a user actually re-imports.
    private func write(_ text: String, as name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func fixture() -> String {
        [
            "SKU\tTitle\tBundle ID\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tBegin Date",
            "SKU-1\tGlowmere\tcom.example.glowmere\t10\t42.50\tUSD\t07/01/2026",
            "SKU-1\tGlowmere\tcom.example.glowmere\t5\t20.00\tUSD\t07/02/2026",
        ].joined(separator: "\n")
    }

    func testImportingTheSameReportTwiceDoesNotDoubleRevenue() throws {
        var state = WorkspaceState()

        let first = try ImportExportService.importDelimitedFile(
            at: write(fixture(), as: "SalesJuly.tsv"), into: &state)
        let revenueAfterFirst = AnalyticsEngine.summary(for: state).cashRevenue
        let ledgerAfterFirst = state.ledger.count
        let observationsAfterFirst = state.apps.first?.observations.count ?? 0
        XCTAssertGreaterThan(revenueAfterFirst, 0, "Precondition: the import recorded revenue")
        XCTAssertEqual(first.appsCreated, 1)

        _ = try ImportExportService.importDelimitedFile(
            at: write(fixture(), as: "SalesJuly.tsv"), into: &state)

        XCTAssertEqual(state.ledger.count, ledgerAfterFirst,
                       "Re-importing the same report must not add ledger entries.")
        XCTAssertEqual(state.apps.first?.observations.count, observationsAfterFirst,
                       "Re-importing the same report must not add observations.")
        XCTAssertEqual(AnalyticsEngine.summary(for: state).cashRevenue, revenueAfterFirst,
                       "Headline revenue must be identical after a duplicate import.")
        XCTAssertEqual(state.apps.count, 1, "No duplicate app should be created.")
    }

    /// A corrected re-export of the same day should replace, not accumulate.
    func testCorrectedReExportReplacesRatherThanAdds() throws {
        var state = WorkspaceState()
        _ = try ImportExportService.importDelimitedFile(
            at: write(fixture(), as: "SalesJuly.tsv"), into: &state)
        let ledgerCount = state.ledger.count

        let corrected = [
            "SKU\tTitle\tBundle ID\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tBegin Date",
            "SKU-1\tGlowmere\tcom.example.glowmere\t10\t99.99\tUSD\t07/01/2026",
            "SKU-1\tGlowmere\tcom.example.glowmere\t5\t20.00\tUSD\t07/02/2026",
        ].joined(separator: "\n")
        _ = try ImportExportService.importDelimitedFile(
            at: write(corrected, as: "SalesJuly.tsv"), into: &state)

        XCTAssertEqual(state.ledger.count, ledgerCount, "A correction must not append.")
        let july1 = state.ledger.first {
            Calendar(identifier: .gregorian).component(.day, from: $0.date) == 1
        }
        XCTAssertEqual(july1?.amount, Decimal(string: "99.99"),
                       "The corrected figure must win, not sit beside the old one.")
    }

    /// Two genuinely different reports must both count.
    func testDifferentSourcesBothCount() throws {
        var state = WorkspaceState()
        _ = try ImportExportService.importDelimitedFile(
            at: write(fixture(), as: "SalesJuly.tsv"), into: &state)
        let after = state.ledger.count
        _ = try ImportExportService.importDelimitedFile(
            at: write(fixture(), as: "SalesAugust.tsv"), into: &state)
        XCTAssertGreaterThan(state.ledger.count, after,
                             "Idempotency must be scoped to the source, not global.")
    }
}
