import XCTest

final class DecisionEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_785_542_400) // 2026-08-01 UTC

    func testPortfolioWithoutObservationsRequiresEvidence() {
        let app = makeApp(observations: [])
        let result = DecisionEngine.portfolioDecisions(
            for: WorkspaceState(apps: [app]),
            now: now
        )

        XCTAssertEqual(result.first?.disposition, .instrument)
        XCTAssertEqual(result.first?.decisionScore, 0)
    }

    func testConfirmedGrowthBecomesScaleCandidate() {
        let app = makeApp(observations: [
            observation(daysAgo: 45, proceeds: 50, units: 20),
            observation(daysAgo: 10, proceeds: 90, units: 36)
        ])
        let result = DecisionEngine.portfolioDecisions(
            for: WorkspaceState(apps: [app]),
            now: now
        ).first

        XCTAssertEqual(result?.disposition, .scale)
        XCTAssertEqual(result?.trend ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(result?.evidenceRatio, 1)
        XCTAssertTrue(result?.rationale.contains("rose") == true)
        XCTAssertTrue(result?.rationale.contains("%") == true)
        XCTAssertFalse(result?.rationale.contains("percent(") == true)
    }

    func testStaleEvidenceIsRefreshedBeforeTrendIsTrusted() {
        let app = makeApp(observations: [
            observation(daysAgo: 80, proceeds: 40, units: 10),
            observation(daysAgo: 50, proceeds: 80, units: 20)
        ])
        let result = DecisionEngine.portfolioDecisions(
            for: WorkspaceState(apps: [app]),
            now: now
        ).first

        XCTAssertEqual(result?.disposition, .refresh)
        XCTAssertEqual(result?.daysSinceLatestObservation, 50)
        XCTAssertTrue(result?.rationale.contains("50 days old") == true)
        XCTAssertFalse(result?.rationale.contains("(age)") == true)
    }

    func testScenarioNeverAddsModeledCapacityToCash() {
        let input = DecisionScenarioInput(
            customerPrice: 10,
            monthlyUnits: 100,
            proceedsRate: 0.80,
            refundRate: 0.10,
            variableCostPerUnit: 1,
            monthlyOperatingCost: 200,
            humanHoursAvoided: 50,
            loadedHourlyRate: 40
        )
        let result = DecisionEngine.scenario(input)

        XCTAssertEqual(result.cashProceeds, 720)
        XCTAssertEqual(result.netCash, 420)
        XCTAssertEqual(result.modeledCapacityValue, 2_000)
        XCTAssertNotEqual(result.netCash, 2_420)
    }

    func testScenarioCalculatesBreakEvenUnits() {
        let input = DecisionScenarioInput(
            customerPrice: 5,
            monthlyUnits: 10,
            proceedsRate: 0.80,
            refundRate: 0,
            variableCostPerUnit: 1,
            monthlyOperatingCost: 10,
            humanHoursAvoided: 0,
            loadedHourlyRate: 0
        )

        XCTAssertEqual(DecisionEngine.scenario(input).breakEvenUnits, 4)
    }

    func testSensitivityKeepsPlanInTheMiddle() {
        let input = DecisionScenarioInput(
            customerPrice: 2,
            monthlyUnits: 100,
            proceedsRate: 1,
            refundRate: 0,
            variableCostPerUnit: 0,
            monthlyOperatingCost: 0,
            humanHoursAvoided: 0,
            loadedHourlyRate: 0
        )
        let points = DecisionEngine.sensitivity(for: input)

        XCTAssertEqual(points.map(\.units), [50, 75, 100, 125, 150])
        XCTAssertEqual(points[2].label, "Plan")
    }

    func testRecentPortfolioProceedsExcludeEstimatedObservations() {
        var confirmed = observation(daysAgo: 2, proceeds: 40, units: 10)
        confirmed.confidence = .confirmed
        var estimated = observation(daysAgo: 1, proceeds: 900, units: 100)
        estimated.confidence = .estimated
        let state = WorkspaceState(apps: [makeApp(observations: [confirmed, estimated])])

        XCTAssertEqual(
            DecisionEngine.recentPortfolioProceeds(for: state, now: now),
            40
        )
    }

    func testSnapshotDeltaKeepsCashAndModeledValueSeparate() {
        let before = BusinessSnapshot(
            capturedAt: now,
            label: "Before",
            currency: "USD",
            cashRevenue: 100,
            cashExpenses: 50,
            netCash: 50,
            recentPortfolioProceeds: 40,
            agentCashNetValue: 10,
            agentModeledNetValue: 500,
            trackedApps: 1,
            activeAgents: 1,
            fleetEvidenceRatio: 0.25
        )
        var after = before
        after.netCash = 80
        after.agentCashNetValue = 25
        after.agentModeledNetValue = 900
        after.fleetEvidenceRatio = 0.75

        let delta = DecisionEngine.delta(current: after, baseline: before)
        XCTAssertEqual(delta.netCash, 30)
        XCTAssertEqual(delta.agentCashNetValue, 15)
        XCTAssertEqual(delta.agentModeledNetValue, 400)
        XCTAssertEqual(delta.fleetEvidenceRatio, 0.5)
    }

    func testExecutiveBriefNeverIncludesVaultSecrets() {
        var state = WorkspaceState(name: "Private Company")
        state.vaultItems = [
            VaultItem(
                label: "Apple key",
                service: "App Store Connect",
                account: "owner",
                kind: .privateKey,
                secret: "TOP-SECRET-PRIVATE-KEY",
                createdAt: now,
                updatedAt: now,
                notes: "Do not export"
            )
        ]

        let report = ExecutiveBriefingService.html(for: state, now: now)

        XCTAssertFalse(report.contains("TOP-SECRET-PRIVATE-KEY"))
        XCTAssertFalse(report.contains("Apple key"))
        XCTAssertTrue(report.contains("Measured cash"))
        XCTAssertTrue(report.contains("Modelled value"))
        XCTAssertTrue(report.contains("<ul>"))
        XCTAssertTrue(report.contains("</ul>"))
    }

    func testLegacyWorkspaceWithoutSnapshotsStillDecodes() throws {
        var state = WorkspaceState(name: "Legacy")
        state.businessSnapshots = nil
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
        )
        object.removeValue(forKey: "businessSnapshots")
        object["schemaVersion"] = 1
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        XCTAssertEqual(decoded.name, "Legacy")
        XCTAssertTrue(decoded.snapshots.isEmpty)
    }

    private func makeApp(observations: [AppObservation]) -> PortfolioApp {
        PortfolioApp(
            name: "Test App",
            bundleID: "com.example.test",
            sku: "TEST",
            platform: .iOS,
            category: "Utilities",
            status: .healthy,
            price: 1.99,
            currency: "USD",
            healthScore: 0.9,
            notes: "",
            observations: observations
        )
    }

    private func observation(daysAgo: Int, proceeds: Decimal, units: Int) -> AppObservation {
        AppObservation(
            date: calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now,
            units: units,
            proceeds: proceeds,
            currency: "USD",
            source: "Measured fixture",
            confidence: .confirmed
        )
    }
}
