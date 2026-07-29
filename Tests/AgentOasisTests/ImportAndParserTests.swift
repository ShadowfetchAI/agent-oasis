import XCTest

final class ImportAndParserTests: XCTestCase {
    func testCSVParserHandlesQuotedCommasAndEscapedQuotes() {
        let text = #"""
        name,notes,amount
        "Agent, One","Said ""ready""",12.50
        """#

        let rows = DelimitedTextParser.parse(text)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["name"], "Agent, One")
        XCTAssertEqual(rows[0]["notes"], "Said \"ready\"")
        XCTAssertEqual(rows[0]["amount"], "12.50")
    }

    func testTSVParserIsInferred() {
        let text = "name\tvalue\nHermes\t35\n"
        let rows = DelimitedTextParser.parse(text)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["name"], "Hermes")
        XCTAssertEqual(rows[0]["value"], "35")
    }

    func testAppStoreImportCreatesAppObservationAndLedgerEvidence() throws {
        let text = """
        Title,SKU,Units,Developer Proceeds,Begin Date,Currency of Proceeds,Customer Price
        Test Product,TEST-SKU,4,3.20,07/01/2026,USD,0.99
        Test Product,TEST-SKU,2,1.60,07/01/2026,USD,0.99
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-oasis-sales-\(UUID().uuidString).csv")
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var state = WorkspaceState()

        let summary = try ImportExportService.importDelimitedFile(at: url, into: &state)

        XCTAssertEqual(summary.appsCreated, 1)
        XCTAssertEqual(summary.observationsAdded, 1)
        XCTAssertEqual(summary.ledgerEntriesAdded, 1)
        XCTAssertEqual(state.apps.first?.latestObservation?.units, 6)
        XCTAssertEqual(state.apps.first?.latestObservation?.proceeds, Decimal(string: "4.80"))
        XCTAssertEqual(state.ledger.first?.confidence, .confirmed)
        XCTAssertEqual(state.ledger.first?.source, url.lastPathComponent)
    }
}
