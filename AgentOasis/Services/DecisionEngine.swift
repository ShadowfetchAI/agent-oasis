import Foundation

enum DecisionDisposition: String, CaseIterable, Identifiable {
    case scale
    case hold
    case investigate
    case refresh
    case instrument

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scale: "Scale"
        case .hold: "Hold and measure"
        case .investigate: "Investigate"
        case .refresh: "Refresh data"
        case .instrument: "Add evidence"
        }
    }

    var systemImage: String {
        switch self {
        case .scale: "arrow.up.right"
        case .hold: "equal"
        case .investigate: "magnifyingglass"
        case .refresh: "arrow.clockwise"
        case .instrument: "waveform.path.ecg"
        }
    }
}

struct PortfolioDecision: Identifiable {
    let id: UUID
    let appName: String
    let currentProceeds: Decimal
    let priorProceeds: Decimal
    let currentUnits: Int
    let currency: String
    let trend: Double?
    let daysSinceLatestObservation: Int?
    let evidenceRatio: Double
    let decisionScore: Int
    let disposition: DecisionDisposition
    let rationale: String
}

struct AgentDecision: Identifiable {
    let id: UUID
    let agentName: String
    let cashNetValue: Decimal
    let modeledNetValue: Decimal
    let acceptanceRate: Double
    let reworkRate: Double
    let evidenceRatio: Double
    let disposition: DecisionDisposition
    let rationale: String
}

struct DecisionScenarioInput: Equatable {
    var customerPrice: Decimal
    var monthlyUnits: Int
    /// The share of customer price the operator expects to receive, after store fees/tax.
    var proceedsRate: Double
    var refundRate: Double
    var variableCostPerUnit: Decimal
    var monthlyOperatingCost: Decimal
    var humanHoursAvoided: Double
    var loadedHourlyRate: Decimal
}

struct DecisionScenarioResult: Equatable {
    let customerSales: Decimal
    let cashProceeds: Decimal
    let variableCosts: Decimal
    let operatingCosts: Decimal
    let netCash: Decimal
    let modeledCapacityValue: Decimal
    let breakEvenUnits: Int?
}

struct ScenarioSensitivityPoint: Identifiable, Equatable {
    let id: String
    let label: String
    let units: Int
    let netCash: Decimal
}

struct SnapshotDelta: Equatable {
    let netCash: Decimal
    let recentPortfolioProceeds: Decimal
    let agentCashNetValue: Decimal
    let agentModeledNetValue: Decimal
    let fleetEvidenceRatio: Double
}

enum DecisionEngine {
    static let defaultWindowDays = 30

    static func portfolioDecisions(
        for state: WorkspaceState,
        now: Date = Date(),
        windowDays: Int = defaultWindowDays
    ) -> [PortfolioDecision] {
        state.apps.map { app in
            portfolioDecision(for: app, now: now, windowDays: windowDays)
        }
        .sorted {
            if $0.decisionScore != $1.decisionScore {
                return $0.decisionScore < $1.decisionScore
            }
            return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
    }

    static func agentDecisions(for state: WorkspaceState) -> [AgentDecision] {
        state.agents.map { agent in
            let economics = AnalyticsEngine.agentEconomics(for: agent)
            let disposition: DecisionDisposition
            let rationale: String

            if economics.measuredInputs == 0 {
                disposition = .instrument
                rationale = "No value input is measured. Add a source before treating modelled value as a result."
            } else if economics.reworkRate >= 0.25 {
                disposition = .investigate
                rationale = "Rework is \(percent(economics.reworkRate)); inspect task definitions and review loops."
            } else if economics.acceptanceRate < 0.70 {
                disposition = .investigate
                rationale = "Acceptance is \(percent(economics.acceptanceRate)); improve reliability before adding volume."
            } else if economics.cashNetValue > 0 && economics.confidence >= 0.50 {
                disposition = .scale
                rationale = "Positive measured cash value with \(percent(economics.confidence)) evidence coverage."
            } else {
                disposition = .hold
                rationale = "The evidence is usable, but there is not yet a strong measured case to expand."
            }

            return AgentDecision(
                id: agent.id,
                agentName: agent.name,
                cashNetValue: economics.cashNetValue,
                modeledNetValue: economics.modeledNetValue,
                acceptanceRate: economics.acceptanceRate,
                reworkRate: economics.reworkRate,
                evidenceRatio: economics.confidence,
                disposition: disposition,
                rationale: rationale
            )
        }
        .sorted {
            if dispositionRank($0.disposition) != dispositionRank($1.disposition) {
                return dispositionRank($0.disposition) < dispositionRank($1.disposition)
            }
            return $0.cashNetValue > $1.cashNetValue
        }
    }

    static func scenario(_ input: DecisionScenarioInput) -> DecisionScenarioResult {
        let safeUnits = max(0, input.monthlyUnits)
        let safeProceedsRate = min(1, max(0, input.proceedsRate))
        let safeRefundRate = min(1, max(0, input.refundRate))
        let paidUnits = Decimal(safeUnits) * Decimal(1 - safeRefundRate)
        let sales = input.customerPrice * paidUnits
        let proceeds = sales * Decimal(safeProceedsRate)
        let variableCosts = input.variableCostPerUnit * Decimal(safeUnits)
        let netCash = proceeds - variableCosts - input.monthlyOperatingCost
        let modeledCapacity = Decimal(max(0, input.humanHoursAvoided)) * input.loadedHourlyRate

        let cashPerUnit = input.customerPrice * Decimal(safeProceedsRate)
            * Decimal(1 - safeRefundRate) - input.variableCostPerUnit
        let breakEven: Int?
        if cashPerUnit > 0, input.monthlyOperatingCost > 0 {
            let raw = AnalyticsEngine.decimalDouble(input.monthlyOperatingCost / cashPerUnit)
            breakEven = Int(ceil(raw))
        } else if input.monthlyOperatingCost <= 0 {
            breakEven = 0
        } else {
            breakEven = nil
        }

        return DecisionScenarioResult(
            customerSales: sales,
            cashProceeds: proceeds,
            variableCosts: variableCosts,
            operatingCosts: input.monthlyOperatingCost,
            netCash: netCash,
            modeledCapacityValue: modeledCapacity,
            breakEvenUnits: breakEven
        )
    }

    static func sensitivity(for input: DecisionScenarioInput) -> [ScenarioSensitivityPoint] {
        let factors: [(String, Double)] = [
            ("50%", 0.5), ("75%", 0.75), ("Plan", 1), ("125%", 1.25), ("150%", 1.5)
        ]
        return factors.map { label, factor in
            var candidate = input
            candidate.monthlyUnits = Int((Double(max(0, input.monthlyUnits)) * factor).rounded())
            return ScenarioSensitivityPoint(
                id: label,
                label: label,
                units: candidate.monthlyUnits,
                netCash: scenario(candidate).netCash
            )
        }
    }

    static func makeSnapshot(
        label: String,
        state: WorkspaceState,
        now: Date = Date()
    ) -> BusinessSnapshot {
        let summary = AnalyticsEngine.summary(for: state)
        return BusinessSnapshot(
            capturedAt: now,
            label: label,
            currency: state.settings.baseCurrency,
            cashRevenue: summary.cashRevenue,
            cashExpenses: summary.cashExpenses,
            netCash: summary.netCash,
            recentPortfolioProceeds: recentPortfolioProceeds(for: state, now: now),
            agentCashNetValue: summary.agentCashNetValue,
            agentModeledNetValue: summary.agentModeledNetValue,
            trackedApps: state.apps.count,
            activeAgents: state.agents.filter { $0.status == .active }.count,
            fleetEvidenceRatio: summary.fleetEvidenceRatio
        )
    }

    static func delta(current: BusinessSnapshot, baseline: BusinessSnapshot) -> SnapshotDelta {
        SnapshotDelta(
            netCash: current.netCash - baseline.netCash,
            recentPortfolioProceeds: current.recentPortfolioProceeds - baseline.recentPortfolioProceeds,
            agentCashNetValue: current.agentCashNetValue - baseline.agentCashNetValue,
            agentModeledNetValue: current.agentModeledNetValue - baseline.agentModeledNetValue,
            fleetEvidenceRatio: current.fleetEvidenceRatio - baseline.fleetEvidenceRatio
        )
    }

    static func recentPortfolioProceeds(
        for state: WorkspaceState,
        now: Date = Date(),
        days: Int = defaultWindowDays
    ) -> Decimal {
        let start = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: -max(1, days),
            to: now
        ) ?? now
        return state.apps.flatMap(\.observations)
            .filter {
                $0.date >= start
                    && $0.date <= now
                    && $0.confidence == .confirmed
                    && $0.currency.caseInsensitiveCompare(state.settings.baseCurrency) == .orderedSame
            }
            .reduce(.zero) { $0 + $1.proceeds }
    }

    // MARK: - Private

    private static func portfolioDecision(
        for app: PortfolioApp,
        now: Date,
        windowDays: Int
    ) -> PortfolioDecision {
        let observations = app.observations
            .filter { $0.currency.caseInsensitiveCompare(app.currency) == .orderedSame }
            .sorted { $0.date < $1.date }
        guard let latest = observations.last else {
            return PortfolioDecision(
                id: app.id,
                appName: app.name,
                currentProceeds: 0,
                priorProceeds: 0,
                currentUnits: 0,
                currency: app.currency,
                trend: nil,
                daysSinceLatestObservation: nil,
                evidenceRatio: 0,
                decisionScore: 0,
                disposition: .instrument,
                rationale: "No sales observation exists. Import or sync data before changing price or marketing."
            )
        }

        let calendar = Calendar(identifier: .gregorian)
        let anchor = min(latest.date, now)
        let currentStart = calendar.date(byAdding: .day, value: -max(1, windowDays), to: anchor) ?? anchor
        let priorStart = calendar.date(byAdding: .day, value: -(max(1, windowDays) * 2), to: anchor) ?? anchor
        let current = observations.filter { $0.date > currentStart && $0.date <= anchor }
        let prior = observations.filter { $0.date > priorStart && $0.date <= currentStart }
        let currentProceeds = current.reduce(Decimal.zero) { $0 + $1.proceeds }
        let priorProceeds = prior.reduce(Decimal.zero) { $0 + $1.proceeds }
        let currentUnits = current.reduce(0) { $0 + $1.units }
        let trend: Double? = priorProceeds != 0
            ? (AnalyticsEngine.decimalDouble(currentProceeds - priorProceeds)
                / abs(AnalyticsEngine.decimalDouble(priorProceeds)))
            : nil
        let age = max(0, Int(now.timeIntervalSince(latest.date) / 86_400))
        let evidence = observations.isEmpty ? 0 : Double(
            observations.filter { $0.confidence == .confirmed }.count
        ) / Double(observations.count)

        var score = Int((app.healthScore * 35).rounded())
        score += Int((evidence * 20).rounded())
        score += max(0, 20 - min(20, age))
        if let trend {
            score += Int((min(1, max(-1, trend)) + 1) * 12.5)
        }
        score = min(100, max(0, score))

        let disposition: DecisionDisposition
        let rationale: String
        if age >= 21 {
            disposition = .refresh
            rationale = "Latest evidence is \(age) days old. Refresh it before acting on the trend."
        } else if currentProceeds == 0, priorProceeds > 0 {
            disposition = .investigate
            rationale = "The current window has no proceeds after a non-zero prior window. Check availability, price, and discoverability."
        } else if let trend, trend <= -0.20 {
            disposition = .investigate
            rationale = "Proceeds fell \(percent(abs(trend))) against the prior comparable window. Diagnose before adding spend."
        } else if let trend, trend >= 0.20, evidence >= 0.50 {
            disposition = .scale
            rationale = "Proceeds rose \(percent(trend)) with \(percent(evidence)) confirmed observations."
        } else if prior.isEmpty {
            disposition = .instrument
            rationale = "There is current evidence but no comparable prior window yet. Keep measuring."
        } else {
            disposition = .hold
            rationale = "Movement is inside the decision band. Hold the variable steady and collect another window."
        }

        return PortfolioDecision(
            id: app.id,
            appName: app.name,
            currentProceeds: currentProceeds,
            priorProceeds: priorProceeds,
            currentUnits: currentUnits,
            currency: app.currency,
            trend: trend,
            daysSinceLatestObservation: age,
            evidenceRatio: evidence,
            decisionScore: score,
            disposition: disposition,
            rationale: rationale
        )
    }

    private static func dispositionRank(_ disposition: DecisionDisposition) -> Int {
        switch disposition {
        case .investigate: 0
        case .refresh: 1
        case .instrument: 2
        case .scale: 3
        case .hold: 4
        }
    }

    private static func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0%"
    }
}
