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

    func testOfficialAppleSummaryMultipliesPerUnitProceeds() throws {
        let text = """
        Provider\tSKU\tTitle\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tBegin Date\tCurrency of Proceeds
        APPLE\tTEST-SKU\tTest Product\t1F\t4\t0.70\t08/01/2026\tUSD
        APPLE\tTEST-SKU\tTest Product\t1F\t-1\t0.70\t08/01/2026\tUSD
        """
        var state = WorkspaceState()

        let summary = try ImportExportService.importDelimitedText(
            text,
            sourceName: "AppStoreConnect-Daily-2026-08-01.tsv",
            into: &state
        )

        XCTAssertEqual(summary.observationsAdded, 1)
        XCTAssertEqual(state.apps.first?.latestObservation?.units, 3)
        XCTAssertEqual(state.apps.first?.latestObservation?.proceeds, Decimal(string: "2.10"))
        XCTAssertEqual(state.ledger.first?.amount, Decimal(string: "2.10"))
    }

    func testOfficialAppleSummaryPreservesCurrenciesWithoutCombiningThem() throws {
        var state = WorkspaceState()
        let text = """
        Provider\tSKU\tTitle\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tBegin Date\tCurrency of Proceeds
        APPLE\tMIXED\tMixed App\t1F\t2\t1.00\t08/01/2026\tUSD
        APPLE\tMIXED\tMixed App\t1F\t3\t0.80\t08/01/2026\tEUR
        """

        let summary = try ImportExportService.importDelimitedText(
            text,
            sourceName: "mixed.tsv",
            into: &state
        )

        XCTAssertEqual(summary.observationsAdded, 2)
        XCTAssertEqual(Set(state.apps[0].observations.map(\.currency)), ["USD", "EUR"])
        XCTAssertEqual(Set(state.ledger.map(\.currency)), ["USD", "EUR"])
        XCTAssertEqual(state.ledger.first(where: { $0.currency == "USD" })?.amount, 2)
        XCTAssertEqual(
            state.ledger.first(where: { $0.currency == "EUR" })?.amount,
            Decimal(string: "2.4")
        )
    }
}
