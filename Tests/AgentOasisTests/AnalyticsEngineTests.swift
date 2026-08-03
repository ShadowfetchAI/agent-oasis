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
        // Every input on this fixture is estimated (the default basis), so none of it is cash.
        XCTAssertEqual(result.modeledCapacityValue, 500)
        XCTAssertEqual(result.modeledRevenue, 200)
        XCTAssertEqual(result.modeledAvoidedSpend, 75)
        XCTAssertEqual(result.modeledNetValue, 775)
        XCTAssertEqual(result.cashRevenue, 0)
        XCTAssertEqual(result.acceptanceRate, 0.8, accuracy: 0.0001)
        XCTAssertEqual(result.reworkRate, 0.1, accuracy: 0.0001)
        XCTAssertEqual(result.costPerAcceptedTask, Decimal(string: "6.25"))
        XCTAssertEqual(result.modeledROI ?? 0, 6.2, accuracy: 0.0001)
        XCTAssertNotNil(result.cashROI)
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

    func testWorkspaceCashDoesNotMixCurrenciesWithoutAnExchangeRate() {
        var state = WorkspaceState()
        state.settings.baseCurrency = "USD"
        state.ledger = [
            LedgerEntry(
                date: Date(), type: .revenue, category: "Sales",
                entityKind: .business, entityName: "Business", description: "USD sale",
                amount: 100, currency: "USD", source: "Test", confidence: .confirmed, notes: ""
            ),
            LedgerEntry(
                date: Date(), type: .revenue, category: "Sales",
                entityKind: .business, entityName: "Business", description: "EUR sale",
                amount: 500, currency: "EUR", source: "Test", confidence: .confirmed, notes: ""
            )
        ]

        let summary = AnalyticsEngine.summary(for: state)

        XCTAssertEqual(summary.cashRevenue, 100)
        XCTAssertEqual(summary.excludedCurrencyEntryCount, 1)
        XCTAssertEqual(summary.excludedCurrencies, ["EUR"])
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

        XCTAssertEqual(AnalyticsEngine.attribution(for: experiment).lift ?? 0, 0.25, accuracy: 0.0001)
    }

    // MARK: - Provenance and evidence
    //
    // These are the audit findings turned into failing-if-regressed assertions. The bug they
    // guard against is not a crash: it is a number that looks right and is not, which no
    // amount of manual testing reliably catches.

    /// Cash and modelled value must never be summed into one figure.
    func testCashAndModeledValueNeverMerge() {
        var agent = Self.sampleAgent()
        agent.valueBasis = AgentValueBasis(
            equivalentHumanHours: .estimated,
            loadedHourlyRate: .estimated,
            directRevenueInfluenced: .measured,
            avoidedVendorSpend: .estimated
        )
        let e = AnalyticsEngine.agentEconomics(for: agent)
        XCTAssertEqual(e.cashRevenue, agent.directRevenueInfluenced,
                       "Measured revenue belongs to cash.")
        XCTAssertEqual(e.modeledRevenue, 0,
                       "Revenue counted as cash must not also be counted as modelled.")
        XCTAssertNotEqual(e.cashNetValue, e.cashNetValue + e.modeledNetValue,
                          "Cash net value must not absorb modelled value.")
    }

    /// An agent with nothing measured has zero evidence, no matter how busy it is.
    func testFullyEstimatedAgentHasNoEvidenceRegardlessOfActivity() {
        var agent = Self.sampleAgent()
        agent.acceptedTasks = 5_000
        agent.failedTasks = 0
        agent.lastSeen = Date()
        agent.valueBasis = AgentValueBasis()   // all estimated

        let e = AnalyticsEngine.agentEconomics(for: agent)
        XCTAssertEqual(e.confidence, 0, accuracy: 0.0001,
                       "Volume and recency must not manufacture confidence in a typed number.")
        XCTAssertTrue(e.isFullyEstimated)
        XCTAssertTrue(e.confidenceReason.contains("No value input is measured"))
    }

    /// Measuring inputs is the only thing that raises evidence.
    func testMeasuredInputsRaiseEvidence() {
        var agent = Self.sampleAgent()
        agent.lastSeen = Date()
        agent.acceptedTasks = 1          // deliberately low volume
        agent.valueBasis = AgentValueBasis(
            equivalentHumanHours: .measured,
            loadedHourlyRate: .measured,
            directRevenueInfluenced: .measured,
            avoidedVendorSpend: .measured
        )
        let e = AnalyticsEngine.agentEconomics(for: agent)
        XCTAssertGreaterThan(e.confidence, 0.9,
                             "Four measured inputs and a recent sighting is strong evidence.")
        XCTAssertEqual(e.measuredInputs, 4)
    }

    /// Staleness may only reduce evidence, never inflate it.
    func testStalenessOnlyReducesEvidence() {
        var fresh = Self.sampleAgent()
        fresh.lastSeen = Date()
        fresh.valueBasis = AgentValueBasis(
            equivalentHumanHours: .measured, loadedHourlyRate: .measured,
            directRevenueInfluenced: .measured, avoidedVendorSpend: .measured)

        var stale = fresh
        stale.lastSeen = Date().addingTimeInterval(-90 * 86_400)

        XCTAssertGreaterThan(
            AnalyticsEngine.agentEconomics(for: fresh).confidence,
            AnalyticsEngine.agentEconomics(for: stale).confidence
        )
    }

    /// A recorded confounder refuses attribution rather than reporting a discounted lift.
    func testConfounderRefusesAttribution() {
        var experiment = Self.sampleExperiment()
        experiment.confounders = "A point release landed during the measurement window."
        let result = AnalyticsEngine.attribution(for: experiment)
        XCTAssertNil(result.lift, "A lift across a known confounder is not attributable.")
        guard case .notAttributable(let reason) = result else {
            return XCTFail("Expected .notAttributable, got \(result)")
        }
        XCTAssertTrue(reason.contains("point release"))
        // The arithmetic is still available for anyone who asks for it explicitly.
        XCTAssertNotNil(AnalyticsEngine.rawChange(experiment))
    }

    /// A still-running experiment inside its own window is not a result yet.
    func testOpenObservationWindowIsInsufficientData() {
        var experiment = Self.sampleExperiment()
        experiment.status = .running
        experiment.startedAt = Date().addingTimeInterval(-2 * 86_400)
        experiment.observationWindowDays = 30
        guard case .insufficientData = AnalyticsEngine.attribution(for: experiment) else {
            return XCTFail("An open window must not report a lift.")
        }
    }

    /// Fleet evidence ratio reports how much of the value picture is observed.
    func testFleetEvidenceRatioReflectsProvenance() {
        var measured = Self.sampleAgent()
        measured.valueBasis = AgentValueBasis(
            equivalentHumanHours: .measured, loadedHourlyRate: .measured,
            directRevenueInfluenced: .measured, avoidedVendorSpend: .measured)
        var state = WorkspaceState()
        state.agents = [measured, Self.sampleAgent()]   // 4 of 8 measured
        XCTAssertEqual(AnalyticsEngine.summary(for: state).fleetEvidenceRatio,
                       0.5, accuracy: 0.0001)
    }

    /// Workspaces written before provenance existed must still decode, as all-estimated.
    func testLegacyAgentWithoutProvenanceDecodesAsEstimated() throws {
        let agent = Self.sampleAgent()
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(agent)) as! [String: Any]
        json.removeValue(forKey: "valueBasis")
        let decoded = try JSONDecoder().decode(
            AgentProfile.self,
            from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.basis, .allEstimated,
                       "A pre-provenance workspace must not silently claim measured inputs.")
    }

    // MARK: - Fixtures

    static func sampleAgent() -> AgentProfile {
        AgentProfile(
            name: "Sample", role: "Ops", provider: "Test", model: "test-1",
            status: .active, sessions: 10, messages: 100,
            acceptedTasks: 20, failedTasks: 2, reworkedTasks: 1,
            inputTokens: 1_000, outputTokens: 1_000, totalTokensReported: 2_000,
            toolCalls: 10, externalCost: 100, computeCost: 25,
            supervisionMinutes: 30, equivalentHumanHours: 10, loadedHourlyRate: 50,
            directRevenueInfluenced: 200, avoidedVendorSpend: 75,
            lastSeen: Date(), source: "Test", tags: []
        )
    }

    static func sampleExperiment() -> Experiment {
        Experiment(
            appName: "Sample", title: "Test", kind: .metadata, status: .completed,
            startedAt: Date().addingTimeInterval(-40 * 86_400),
            endedAt: Date().addingTimeInterval(-10 * 86_400),
            hypothesis: "", beforeValue: "", afterValue: "",
            observationWindowDays: 14, baselineProceeds: 400, observedProceeds: 500,
            confounders: "", notes: ""
        )
    }
}
