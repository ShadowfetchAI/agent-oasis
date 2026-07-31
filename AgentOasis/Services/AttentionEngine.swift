import Foundation

/// Something in the workspace that deserves a human decision — not a vanity metric.
///
/// The Command Center used to invent "priority signals" from whatever was convenient to
/// display. An Attention Inbox is the opposite: every item names a concrete gap (blocked
/// agent, refused attribution, stale source, zero evidence behind a large modelled figure)
/// and offers a destination. Empty means nothing needs you, not that the dashboard is bored.
struct AttentionItem: Identifiable, Hashable {
    enum Severity: String, Hashable {
        case critical
        case warning
        case info
    }

    enum Destination: Hashable {
        case section(AppSection)
        case agent(UUID)
        case experiment(UUID)
        case connection(UUID)
    }

    let id: String
    let severity: Severity
    let title: String
    let detail: String
    let systemImage: String
    let destination: Destination

    var section: AppSection {
        switch destination {
        case .section(let section): section
        case .agent: .agents
        case .experiment: .experiments
        case .connection: .connections
        }
    }
}

enum AttentionEngine {
    /// Days without a measured touch before an agent with measured inputs is called stale.
    static let staleMeasuredDays = 21
    /// Days without any backup audit event before we ask for one.
    static let backupReminderDays = 14
    /// Modelled net value above which zero-evidence agents are worth flagging.
    static let modeledValueAttentionFloor: Decimal = 250

    static func items(
        for state: WorkspaceState,
        now: Date = Date()
    ) -> [AttentionItem] {
        var items: [AttentionItem] = []

        items.append(contentsOf: blockedAgents(in: state))
        items.append(contentsOf: attributionRefused(in: state))
        items.append(contentsOf: sourceProblems(in: state))
        items.append(contentsOf: zeroEvidenceHighModel(in: state))
        items.append(contentsOf: staleMeasuredAgents(in: state, now: now))
        items.append(contentsOf: runningWithoutBaseline(in: state))
        items.append(contentsOf: backupReminder(in: state, now: now))

        return items.sorted { lhs, rhs in
            if severityRank(lhs.severity) != severityRank(rhs.severity) {
                return severityRank(lhs.severity) < severityRank(rhs.severity)
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    // MARK: - Rules

    private static func blockedAgents(in state: WorkspaceState) -> [AttentionItem] {
        state.agents
            .filter { $0.status == .blocked }
            .map { agent in
                AttentionItem(
                    id: "blocked-\(agent.id.uuidString)",
                    severity: .critical,
                    title: "\(agent.name) is blocked",
                    detail: "Clear the dependency before treating this agent's capacity as available.",
                    systemImage: "exclamationmark.octagon.fill",
                    destination: .agent(agent.id)
                )
            }
    }

    private static func attributionRefused(in state: WorkspaceState) -> [AttentionItem] {
        state.experiments.compactMap { experiment in
            guard case .notAttributable(let reason) = AnalyticsEngine.attribution(for: experiment)
            else { return nil }
            return AttentionItem(
                id: "confounder-\(experiment.id.uuidString)",
                severity: .warning,
                title: "\(experiment.title): attribution refused",
                detail: reason,
                systemImage: "flask.fill",
                destination: .experiment(experiment.id)
            )
        }
    }

    private static func sourceProblems(in state: WorkspaceState) -> [AttentionItem] {
        state.connections
            .filter {
                $0.status == .needsSetup || $0.status == .error || $0.status == .stale
            }
            .map { connection in
                let severity: AttentionItem.Severity =
                    connection.status == .error ? .critical : .warning
                return AttentionItem(
                    id: "connection-\(connection.id.uuidString)",
                    severity: severity,
                    title: "\(connection.name): \(connection.status.title.lowercased())",
                    detail: connection.notes.isEmpty
                        ? "Fresh source data raises the confidence of every downstream figure."
                        : connection.notes,
                    systemImage: "point.3.connected.trianglepath.dotted",
                    destination: .connection(connection.id)
                )
            }
    }

    private static func zeroEvidenceHighModel(in state: WorkspaceState) -> [AttentionItem] {
        state.agents.compactMap { agent in
            let economics = AnalyticsEngine.agentEconomics(for: agent)
            guard economics.isFullyEstimated,
                  economics.modeledNetValue >= modeledValueAttentionFloor
            else { return nil }
            return AttentionItem(
                id: "zero-evidence-\(agent.id.uuidString)",
                severity: .warning,
                title: "\(agent.name) has no measured value inputs",
                detail: "Modeled net \(formatCurrency(economics.modeledNetValue)) rests entirely on typed figures. Mark measured inputs or lower the claim.",
                systemImage: "pencil.and.outline",
                destination: .agent(agent.id)
            )
        }
    }

    private static func staleMeasuredAgents(in state: WorkspaceState, now: Date) -> [AttentionItem] {
        state.agents.compactMap { agent in
            guard agent.basis.measuredCount > 0 else { return nil }
            guard let lastSeen = agent.lastSeen else {
                return AttentionItem(
                    id: "never-seen-\(agent.id.uuidString)",
                    severity: .warning,
                    title: "\(agent.name) never reported in",
                    detail: "Measured inputs exist, but there is no last-seen timestamp to trust their age.",
                    systemImage: "clock.badge.exclamationmark",
                    destination: .agent(agent.id)
                )
            }
            let days = now.timeIntervalSince(lastSeen) / 86_400
            guard days >= Double(staleMeasuredDays) else { return nil }
            return AttentionItem(
                id: "stale-\(agent.id.uuidString)",
                severity: .info,
                title: "\(agent.name) last seen \(Int(days)) days ago",
                detail: "Measured economics may have moved. Sync the fleet or update the profile.",
                systemImage: "clock.arrow.circlepath",
                destination: .agent(agent.id)
            )
        }
    }

    private static func runningWithoutBaseline(in state: WorkspaceState) -> [AttentionItem] {
        state.experiments.compactMap { experiment in
            guard experiment.status == .running,
                  case .insufficientData(let reason) = AnalyticsEngine.attribution(for: experiment)
            else { return nil }
            return AttentionItem(
                id: "baseline-\(experiment.id.uuidString)",
                severity: .info,
                title: "\(experiment.title) needs more data",
                detail: reason,
                    systemImage: "hourglass",
                destination: .experiment(experiment.id)
            )
        }
    }

    private static func backupReminder(in state: WorkspaceState, now: Date) -> [AttentionItem] {
        let hasContent = !(state.apps.isEmpty && state.agents.isEmpty && state.ledger.isEmpty)
        guard hasContent else { return [] }

        let lastBackup = state.audit
            .filter { $0.category == "Backup" && $0.action.localizedCaseInsensitiveContains("export") }
            .map(\.timestamp)
            .max()

        if let lastBackup {
            let days = now.timeIntervalSince(lastBackup) / 86_400
            guard days >= Double(backupReminderDays) else { return [] }
            return [
                AttentionItem(
                    id: "backup-stale",
                    severity: .info,
                    title: "Encrypted backup is \(Int(days)) days old",
                    detail: "Export a fresh .oasisbackup and keep the recovery key somewhere that is not this Mac.",
                    systemImage: "externaldrive.badge.exclamationmark",
                    destination: .section(.settings)
                )
            ]
        }

        return [
            AttentionItem(
                id: "backup-missing",
                severity: .warning,
                title: "No encrypted backup on record",
                detail: "This workspace only lives on this Mac until you export one. Settings → Export Encrypted Backup.",
                systemImage: "externaldrive.badge.plus",
                destination: .section(.settings)
            )
        ]
    }

    private static func severityRank(_ severity: AttentionItem.Severity) -> Int {
        switch severity {
        case .critical: 0
        case .warning: 1
        case .info: 2
        }
    }

    private static func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}
