import Foundation

// MARK: - Agent economics

/// An agent's economics, with cash and modelled value kept permanently apart.
///
/// WHY THERE ARE TWO OF EVERYTHING. The previous version computed one `netValue` and one
/// `roi` from four terms, three of which a human typed in:
///
///     net = (equivalentHumanHours × loadedHourlyRate) + directRevenueInfluenced
///           + avoidedVendorSpend − cost
///
/// The result was rendered beside real App Store proceeds at the same precision. A single
/// number that blends a measured dollar with an imagined one is not a summary, it is a
/// laundering step: the estimate arrives wearing the measurement's authority. The ledger
/// already made this distinction - `LedgerEntryType.capacityValue` is deliberately not
/// `.revenue` - and the analytics layer then dissolved it. These two are never summed.
struct AgentEconomics: Identifiable {
    let id: UUID
    let name: String

    /// Money that actually moved. Costs are always real; revenue counts only when measured.
    let directCost: Decimal
    let cashRevenue: Decimal
    let cashNetValue: Decimal
    let cashROI: Double?

    /// Judgements. Useful for planning, never presented as earnings.
    let modeledCapacityValue: Decimal
    let modeledAvoidedSpend: Decimal
    let modeledRevenue: Decimal
    let modeledNetValue: Decimal
    let modeledROI: Double?

    /// Delivery quality. These are counts, so they are always measured.
    let acceptanceRate: Double
    let reworkRate: Double
    let costPerAcceptedTask: Decimal?

    /// How much of the value picture is observed rather than asserted.
    let measuredInputs: Int
    let totalValueInputs: Int
    let confidence: Double
    let confidenceReason: String

    var isFullyEstimated: Bool { measuredInputs == 0 }
}

struct WorkspaceSummary {
    let cashRevenue: Decimal
    let cashExpenses: Decimal
    let netCash: Decimal
    let cashSavings: Decimal
    /// Modelled. Never added to `netCash`.
    let capacityValue: Decimal
    /// Sum of per-agent CASH net value only.
    let agentCashNetValue: Decimal
    /// Sum of per-agent MODELLED net value only.
    let agentModeledNetValue: Decimal
    let activeExperiments: Int
    let averageAppHealth: Double
    let staleConnections: Int
    /// Share of agent value inputs that are measured, across the fleet. 0 when nothing is.
    let fleetEvidenceRatio: Double
    /// Cash rows preserved in another currency and therefore excluded from workspace totals.
    let excludedCurrencyEntryCount: Int
    let excludedCurrencies: [String]
}

struct MonthlyPoint: Identifiable {
    let id = UUID()
    let date: Date
    let revenue: Decimal
    let expenses: Decimal
    var net: Decimal { revenue - expenses }
}

// MARK: - Experiments

/// The result of asking "did this experiment move anything?"
///
/// A bare percentage cannot answer that. The old `experimentLift` returned
/// `(observed − baseline) / baseline` and ignored the `confounders` field entirely, while
/// the demo data itself recorded "A point release landed during the measurement window".
/// A lift computed across a known confounder is not a weak measurement, it is a different
/// measurement wearing this one's label, so it is refused rather than discounted.
enum ExperimentAttribution: Equatable {
    case attributable(lift: Double)
    case notAttributable(reason: String)
    case insufficientData(reason: String)

    var lift: Double? {
        if case .attributable(let value) = self { return value }
        return nil
    }

    var isAttributable: Bool { lift != nil }
}

// MARK: - Engine

enum AnalyticsEngine {
    static func agentEconomics(for agent: AgentProfile) -> AgentEconomics {
        let basis = agent.basis
        let cost = agent.externalCost + agent.computeCost

        // Cash. Costs are invoices, so they are real regardless of provenance. Revenue is
        // only cash when someone measured it; asserted revenue is modelled by definition.
        let cashRevenue = basis.directRevenueInfluenced == .measured
            ? agent.directRevenueInfluenced
            : .zero
        let cashNet = cashRevenue - cost
        let cashROI = decimalDouble(cost) > 0 ? decimalDouble(cashNet) / decimalDouble(cost) : nil

        // Modelled. Capacity is a product of two inputs, so it is only ever as good as the
        // weaker one; it stays on the modelled side unless BOTH were measured.
        let capacityIsMeasured = basis.equivalentHumanHours == .measured
            && basis.loadedHourlyRate == .measured
        let capacity = Decimal(agent.equivalentHumanHours) * agent.loadedHourlyRate
        let modeledCapacity = capacityIsMeasured ? .zero : capacity
        let measuredCapacity = capacityIsMeasured ? capacity : .zero
        let modeledAvoided = basis.avoidedVendorSpend == .measured ? .zero : agent.avoidedVendorSpend
        let measuredAvoided = basis.avoidedVendorSpend == .measured ? agent.avoidedVendorSpend : .zero
        let modeledRevenue = basis.directRevenueInfluenced == .measured
            ? .zero
            : agent.directRevenueInfluenced

        let modeledNet = modeledCapacity + modeledAvoided + modeledRevenue
        let modeledROI = decimalDouble(cost) > 0
            ? decimalDouble(modeledNet) / decimalDouble(cost)
            : nil

        let attempted = max(1, agent.acceptedTasks + agent.failedTasks)
        let acceptance = Double(agent.acceptedTasks) / Double(attempted)
        let rework = Double(agent.reworkedTasks) / Double(max(1, agent.acceptedTasks))
        let costPerTask = agent.acceptedTasks > 0 ? cost / Decimal(agent.acceptedTasks) : nil

        let (confidence, reason) = evidenceConfidence(for: agent)

        return AgentEconomics(
            id: agent.id,
            name: agent.name,
            directCost: cost,
            cashRevenue: cashRevenue + measuredCapacity + measuredAvoided,
            cashNetValue: cashNet + measuredCapacity + measuredAvoided,
            cashROI: cashROI,
            modeledCapacityValue: modeledCapacity,
            modeledAvoidedSpend: modeledAvoided,
            modeledRevenue: modeledRevenue,
            modeledNetValue: modeledNet,
            modeledROI: modeledROI,
            acceptanceRate: acceptance,
            reworkRate: rework,
            costPerAcceptedTask: costPerTask,
            measuredInputs: basis.measuredCount,
            totalValueInputs: basis.total,
            confidence: confidence,
            confidenceReason: reason
        )
    }

    /// Confidence in an agent's VALUE figures, driven by evidence rather than by activity.
    ///
    /// The old score was `0.35 + (acceptedTasks/100)*0.4 + recency*0.2`. It never looked at
    /// where a single value input came from, so a busy, recently-seen agent scored ~0.95 on
    /// a net-value figure whose hourly rate had been invented thirty seconds earlier. It
    /// measured how busy the agent was and printed the answer next to how much it was worth.
    ///
    /// Provenance is now the whole numerator. Staleness can only pull the number DOWN, never
    /// prop it up: an agent with four measured inputs that has not run in two months is
    /// well-evidenced but out of date, while an agent with four typed inputs scores zero no
    /// matter how hard it worked today. Zero is the honest answer there - nothing about that
    /// value figure has been observed.
    static func evidenceConfidence(for agent: AgentProfile) -> (Double, String) {
        let basis = agent.basis
        let measured = basis.measuredCount
        guard measured > 0 else {
            return (0, "No value input is measured. Every figure here was entered by hand.")
        }
        let evidence = Double(measured) / Double(basis.total)

        let staleness: Double
        let note: String
        if let lastSeen = agent.lastSeen {
            let days = Date().timeIntervalSince(lastSeen) / 86_400
            staleness = max(0.4, min(1, 1 - days / 60))
            note = days > 14
                ? " Last seen \(Int(days)) days ago, so the figures may have moved."
                : ""
        } else {
            staleness = 0.4
            note = " This agent has never reported in, so even the measured inputs are old."
        }

        let score = evidence * staleness
        return (
            min(0.99, score),
            "\(measured) of \(basis.total) value inputs are measured.\(note)"
        )
    }

    static func summary(for state: WorkspaceState) -> WorkspaceSummary {
        let baseCurrency = state.settings.baseCurrency.uppercased()
        let baseCurrencyLedger = state.ledger.filter {
            $0.currency.uppercased() == baseCurrency
        }
        let revenue = baseCurrencyLedger
            .filter { $0.type == .revenue }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let expenses = baseCurrencyLedger
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let cashSavings = baseCurrencyLedger
            .filter { $0.type == .cashSavings }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let excludedCashEntries = state.ledger.filter {
            $0.currency.uppercased() != baseCurrency
                && ($0.type == .revenue || $0.type == .expense || $0.type == .cashSavings)
        }
        let excludedCurrencies = Array(Set(excludedCashEntries.map {
            $0.currency.uppercased()
        })).sorted()

        let economics = state.agents.map(agentEconomics)
        let capacity = economics.reduce(Decimal.zero) { $0 + $1.modeledCapacityValue }
        let agentCash = economics.reduce(Decimal.zero) { $0 + $1.cashNetValue }
        let agentModeled = economics.reduce(Decimal.zero) { $0 + $1.modeledNetValue }

        let averageHealth = state.apps.isEmpty
            ? 0
            : state.apps.reduce(0) { $0 + $1.healthScore } / Double(state.apps.count)
        let stale = state.connections.filter {
            $0.status == .stale || $0.status == .error || $0.status == .needsSetup
        }.count

        let inputsTotal = economics.reduce(0) { $0 + $1.totalValueInputs }
        let inputsMeasured = economics.reduce(0) { $0 + $1.measuredInputs }
        let ratio = inputsTotal > 0 ? Double(inputsMeasured) / Double(inputsTotal) : 0

        return WorkspaceSummary(
            cashRevenue: revenue,
            cashExpenses: expenses,
            netCash: revenue - expenses,
            cashSavings: cashSavings,
            capacityValue: capacity,
            agentCashNetValue: agentCash,
            agentModeledNetValue: agentModeled,
            activeExperiments: state.experiments.filter { $0.status == .running }.count,
            averageAppHealth: averageHealth,
            staleConnections: stale,
            fleetEvidenceRatio: ratio,
            excludedCurrencyEntryCount: excludedCashEntries.count,
            excludedCurrencies: excludedCurrencies
        )
    }

    static func monthlyCashFlow(for state: WorkspaceState, months: Int = 6) -> [MonthlyPoint] {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let baseCurrency = state.settings.baseCurrency.uppercased()
        return (0..<months).reversed().map { offset in
            let date = calendar.date(byAdding: .month, value: -offset, to: now) ?? now
            let matching = state.ledger.filter {
                calendar.isDate($0.date, equalTo: date, toGranularity: .month)
                    && $0.currency.uppercased() == baseCurrency
            }
            let revenue = matching.filter { $0.type == .revenue }
                .reduce(Decimal.zero) { $0 + $1.amount }
            let expenses = matching.filter { $0.type == .expense }
                .reduce(Decimal.zero) { $0 + $1.amount }
            return MonthlyPoint(date: date, revenue: revenue, expenses: expenses)
        }
    }

    static func appTrend(_ app: PortfolioApp) -> Double? {
        guard
            let latest = app.latestObservation,
            let prior = app.priorObservation,
            prior.proceeds != 0
        else { return nil }
        return (decimalDouble(latest.proceeds) - decimalDouble(prior.proceeds))
            / abs(decimalDouble(prior.proceeds))
    }

    /// Whether an experiment's change can be attributed to the experiment.
    ///
    /// Refuses rather than discounts when a confounder is recorded. A number labelled "lift"
    /// that a reader cannot distinguish from seasonality is worse than no number: it will be
    /// repeated without its caveat, and the caveat is the entire finding.
    static func attribution(for experiment: Experiment) -> ExperimentAttribution {
        let confounders = experiment.confounders.trimmingCharacters(in: .whitespacesAndNewlines)
        if !confounders.isEmpty {
            return .notAttributable(reason: confounders)
        }
        guard experiment.baselineProceeds != 0 else {
            return .insufficientData(reason: "No baseline was recorded for this experiment.")
        }
        if experiment.status == .running {
            let elapsed = Date().timeIntervalSince(experiment.startedAt) / 86_400
            if elapsed < Double(experiment.observationWindowDays) {
                return .insufficientData(
                    reason: "The \(experiment.observationWindowDays)-day observation window "
                        + "has not closed yet."
                )
            }
        }
        let lift = (decimalDouble(experiment.observedProceeds)
            - decimalDouble(experiment.baselineProceeds))
            / abs(decimalDouble(experiment.baselineProceeds))
        return .attributable(lift: lift)
    }

    /// Raw arithmetic difference, with no claim of attribution. Use `attribution(for:)` for
    /// anything a person will read as a result.
    static func rawChange(_ experiment: Experiment) -> Double? {
        guard experiment.baselineProceeds != 0 else { return nil }
        return (decimalDouble(experiment.observedProceeds)
            - decimalDouble(experiment.baselineProceeds))
            / abs(decimalDouble(experiment.baselineProceeds))
    }

    static func decimalDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

private func decimalDouble(_ value: Decimal) -> Double {
    AnalyticsEngine.decimalDouble(value)
}
