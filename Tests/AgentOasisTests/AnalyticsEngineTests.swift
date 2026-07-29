import XCTest

final class AnalyticsEngineTests: XCTestCase {
    func testAgentNetValueKeepsAllComponentsVisible() {
        let agent = AgentProfile(
            name: "Test Agent",
            role: "Validation",
            provider: "Provider",
            model: "Model",
            status: .active,
            sessions: 10,
            messages: 100,
            acceptedTasks: 20,
            failedTasks: 5,
            reworkedTasks: 2,
            inputTokens: 100_000,
            outputTokens: 10_000,
            totalTokensReported: 250_000,
            toolCalls: 50,
            externalCost: 100,
            computeCost: 25,
            supervisionMinutes: 60,
            equivalentHumanHours: 10,
            loadedHourlyRate: 50,
            directRevenueInfluenced: 200,
            avoidedVendorSpend: 75,
            lastSeen: Date(),
            source: "Test",
            tags: []
        )

        let result = AnalyticsEngine.agentEconomics(for: agent)

        XCTAssertEqual(result.directCost, 125)
        XCTAssertEqual(result.capacityValue, 500)
        XCTAssertEqual(result.directRevenue, 200)
        XCTAssertEqual(result.avoidedSpend, 75)
        XCTAssertEqual(result.netValue, 650)
        XCTAssertEqual(result.acceptanceRate, 0.8, accuracy: 0.0001)
        XCTAssertEqual(result.reworkRate, 0.1, accuracy: 0.0001)
        XCTAssertEqual(result.costPerAcceptedTask, Decimal(string: "6.25"))
        XCTAssertEqual(result.roi ?? 0, 5.2, accuracy: 0.0001)
    }

    func testWorkspaceHeadlineCashExcludesModeledCapacity() {
        var state = WorkspaceState()
        state.ledger = [
            LedgerEntry(
                date: Date(),
                type: .revenue,
                category: "Sales",
                entityKind: .business,
                entityName: "Business",
                description: "Revenue",
                amount: 500,
                currency: "USD",
                source: "Test",
                confidence: .confirmed,
                notes: ""
            ),
            LedgerEntry(
                date: Date(),
                type: .expense,
                category: "Cost",
                entityKind: .business,
                entityName: "Business",
                description: "Expense",
                amount: 120,
                currency: "USD",
                source: "Test",
                confidence: .confirmed,
                notes: ""
            ),
            LedgerEntry(
                date: Date(),
                type: .capacityValue,
                category: "Capacity",
                entityKind: .agent,
                entityName: "Agent",
                description: "Modeled",
                amount: 9_000,
                currency: "USD",
                source: "Test",
                confidence: .inferred,
                notes: ""
            )
        ]

        let summary = AnalyticsEngine.summary(for: state)

        XCTAssertEqual(summary.cashRevenue, 500)
        XCTAssertEqual(summary.cashExpenses, 120)
        XCTAssertEqual(summary.netCash, 380)
    }

    func testExperimentLift() {
        let experiment = Experiment(
            appName: "App",
            title: "Price",
            kind: .price,
            status: .completed,
            startedAt: Date(),
            hypothesis: "",
            beforeValue: "$2.99",
            afterValue: "$0.99",
            observationWindowDays: 30,
            baselineProceeds: 100,
            observedProceeds: 125,
            confounders: "",
            notes: ""
        )

        XCTAssertEqual(AnalyticsEngine.experimentLift(experiment) ?? 0, 0.25, accuracy: 0.0001)
    }
}
