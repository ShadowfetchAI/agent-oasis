import Foundation

struct AgentEconomics: Identifiable {
    let id: UUID
    let name: String
    let directCost: Decimal
    let capacityValue: Decimal
    let directRevenue: Decimal
    let avoidedSpend: Decimal
    let netValue: Decimal
    let roi: Double?
    let acceptanceRate: Double
    let reworkRate: Double
    let costPerAcceptedTask: Decimal?
    let confidence: Double
}

struct WorkspaceSummary {
    let cashRevenue: Decimal
    let cashExpenses: Decimal
    let netCash: Decimal
    let cashSavings: Decimal
    let capacityValue: Decimal
    let agentNetValue: Decimal
    let activeExperiments: Int
    let averageAppHealth: Double
    let staleConnections: Int
}

struct MonthlyPoint: Identifiable {
    let id = UUID()
    let date: Date
    let revenue: Decimal
    let expenses: Decimal
    var net: Decimal { revenue - expenses }
}

enum AnalyticsEngine {
    static func agentEconomics(for agent: AgentProfile) -> AgentEconomics {
        let cost = agent.externalCost + agent.computeCost
        let capacity = Decimal(agent.equivalentHumanHours) * agent.loadedHourlyRate
        let net = capacity + agent.directRevenueInfluenced + agent.avoidedVendorSpend - cost
        let roi = decimalDouble(cost) > 0
            ? decimalDouble(net) / decimalDouble(cost)
            : nil
        let attempted = max(1, agent.acceptedTasks + agent.failedTasks)
        let acceptance = Double(agent.acceptedTasks) / Double(attempted)
        let rework = Double(agent.reworkedTasks) / Double(max(1, agent.acceptedTasks))
        let costPerTask = agent.acceptedTasks > 0
            ? cost / Decimal(agent.acceptedTasks)
            : nil
        let volumeFactor = min(1, Double(agent.acceptedTasks) / 100)
        let recencyFactor: Double
        if let lastSeen = agent.lastSeen {
            recencyFactor = max(0.35, 1 - Date().timeIntervalSince(lastSeen) / (86400 * 30))
        } else {
            recencyFactor = 0.35
        }
        let confidence = min(0.98, max(0.25, 0.35 + volumeFactor * 0.4 + recencyFactor * 0.2))

        return AgentEconomics(
            id: agent.id,
            name: agent.name,
            directCost: cost,
            capacityValue: capacity,
            directRevenue: agent.directRevenueInfluenced,
            avoidedSpend: agent.avoidedVendorSpend,
            netValue: net,
            roi: roi,
            acceptanceRate: acceptance,
            reworkRate: rework,
            costPerAcceptedTask: costPerTask,
            confidence: confidence
        )
    }

    static func summary(for state: WorkspaceState) -> WorkspaceSummary {
        let revenue = state.ledger
            .filter { $0.type == .revenue }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let expenses = state.ledger
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let cashSavings = state.ledger
            .filter { $0.type == .cashSavings }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let agentEconomics = state.agents.map(agentEconomics)
        let capacity = agentEconomics.reduce(Decimal.zero) { $0 + $1.capacityValue }
        let agentNet = agentEconomics.reduce(Decimal.zero) { $0 + $1.netValue }
        let averageHealth = state.apps.isEmpty
            ? 0
            : state.apps.reduce(0) { $0 + $1.healthScore } / Double(state.apps.count)
        let stale = state.connections.filter {
            $0.status == .stale || $0.status == .error || $0.status == .needsSetup
        }.count

        return WorkspaceSummary(
            cashRevenue: revenue,
            cashExpenses: expenses,
            netCash: revenue - expenses,
            cashSavings: cashSavings,
            capacityValue: capacity,
            agentNetValue: agentNet,
            activeExperiments: state.experiments.filter { $0.status == .running }.count,
            averageAppHealth: averageHealth,
            staleConnections: stale
        )
    }

    static func monthlyCashFlow(for state: WorkspaceState, months: Int = 6) -> [MonthlyPoint] {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        return (0..<months).reversed().map { offset in
            let date = calendar.date(byAdding: .month, value: -offset, to: now) ?? now
            let matching = state.ledger.filter {
                calendar.isDate($0.date, equalTo: date, toGranularity: .month)
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

    static func experimentLift(_ experiment: Experiment) -> Double? {
        guard experiment.baselineProceeds != 0 else { return nil }
        return (decimalDouble(experiment.observedProceeds) - decimalDouble(experiment.baselineProceeds))
            / abs(decimalDouble(experiment.baselineProceeds))
    }

    static func decimalDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

private func decimalDouble(_ value: Decimal) -> Double {
    AnalyticsEngine.decimalDouble(value)
}
