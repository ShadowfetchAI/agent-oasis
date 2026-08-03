import SwiftUI

/// The flagship Hermes integration: a first-class dashboard for a live Hermes agent fleet,
/// built entirely from what `HermesFleetService` actually measures. No number here is invented -
/// where Hermes has no aggregate (there is no fleet-wide "duty success rate" anywhere on a real
/// install), this view says so instead of approximating one.
struct HermesFleetView: View {
    @EnvironmentObject private var store: OasisStore

    private var snapshot: HermesFleetSnapshot? { store.workspace.hermesFleetSnapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    "Hermes Fleet",
                    subtitle: "The agentic workforce behind this workspace, read live and read-only."
                ) {
                    HStack(spacing: 10) {
                        if let snapshot {
                            StatusIndicator(
                                text: "Synced \(OasisFormat.relative(snapshot.fetchedAt))",
                                systemImage: "checkmark.circle.fill",
                                color: OasisPalette.green
                            )
                        }
                        Button {
                            Task { await store.syncHermesFleet() }
                        } label: {
                            Label(
                                store.isSyncingHermes ? "Syncing..." : "Sync Fleet",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .disabled(store.isSyncingHermes)
                    }
                }

                if let snapshot {
                    summaryGrid(snapshot)
                    kanbanPanel(snapshot)
                    decisionQueuePanel(snapshot)
                    rosterAndGatewayPanel(snapshot)
                    telemetryPanel(snapshot)
                } else {
                    EmptyStateView(
                        title: "No Fleet Synced Yet",
                        message: "Point Settings at a Hermes host, then press Sync Fleet. "
                            + "Nothing here is estimated - an empty tab means nothing has been read.",
                        systemImage: "point.3.filled.connected.trianglepath.dotted"
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                }

                if let error = store.errorMessage, store.selection == .hermesFleet {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(OasisPalette.coral)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func summaryGrid(_ snapshot: HermesFleetSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            MetricTile(
                title: "Roster",
                value: "\(snapshot.roster?.count ?? snapshot.profileCount)",
                detail: "Agent profiles on \(snapshot.version)",
                systemImage: "person.3",
                color: OasisPalette.indigo
            )
            MetricTile(
                title: "Active gateways",
                value: "\(snapshot.activeGateways)/\(snapshot.profileCount)",
                detail: "Discord/Telegram-connected agent processes",
                systemImage: "antenna.radiowaves.left.and.right",
                color: OasisPalette.teal
            )
            if let health = snapshot.kanbanHealth {
                MetricTile(
                    title: "Kanban shape",
                    value: "\(health.total)",
                    detail: kanbanShapeDetail(health),
                    systemImage: "square.stack.3d.up",
                    color: OasisPalette.gold
                )
            }
            if let integrity = snapshot.integrity {
                MetricTile(
                    title: "Fleet integrity",
                    value: (integrity.clean ?? false) ? "Clean" : "\(integrity.issues.count) issue(s)",
                    detail: integrity.checkedAt.map { "Checked \(OasisFormat.relative($0))" } ?? "Structural check",
                    systemImage: (integrity.clean ?? false) ? "checkmark.seal" : "exclamationmark.triangle",
                    color: (integrity.clean ?? false) ? OasisPalette.green : OasisPalette.coral
                )
            }
        }
    }

    private func kanbanShapeDetail(_ health: HermesKanbanHealth) -> String {
        health.byStatus
            .sorted { $0.key < $1.key }
            .map { "\($0.value) \($0.key)" }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private func kanbanPanel(_ snapshot: HermesFleetSnapshot) -> some View {
        if let health = snapshot.kanbanHealth {
            OasisPanel {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(
                        "Kanban health",
                        subtitle: "Work is tracked as cards, not claims - shape and the oldest blockers, never card contents"
                    )
                    KanbanStatusBar(byStatus: health.byStatus)
                        .frame(height: 22)
                    if !health.oldestBlocked.isEmpty {
                        Divider()
                        Text("Oldest blocked")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(health.oldestBlocked.prefix(6)) { card in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "hourglass")
                                        .font(.caption)
                                        .foregroundStyle(OasisPalette.coral)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(card.title)
                                            .font(.callout)
                                            .lineLimit(1)
                                        HStack(spacing: 6) {
                                            if let assignee = card.assignee {
                                                Text(assignee)
                                            }
                                            if let createdAt = card.createdAt {
                                                Text("· open \(OasisFormat.relative(createdAt))")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func decisionQueuePanel(_ snapshot: HermesFleetSnapshot) -> some View {
        if let queue = snapshot.decisionQueue {
            OasisPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionTitle(
                            "Decision queue",
                            subtitle: "Open items awaiting acknowledgement, by authority - titles only, never the underlying case"
                        )
                        Spacer()
                        if !queue.isEmpty {
                            Text("\(queue.count) open")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(OasisPalette.gold.opacity(0.16), in: Capsule())
                                .foregroundStyle(OasisPalette.gold)
                        }
                    }
                    if queue.isEmpty {
                        Text("Nothing open.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(queue.sorted { ($0.ackDeadline ?? .distantFuture) < ($1.ackDeadline ?? .distantFuture) }.prefix(8)) { item in
                                DecisionQueueRow(item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rosterAndGatewayPanel(_ snapshot: HermesFleetSnapshot) -> some View {
        if let roster = snapshot.roster, !roster.isEmpty {
            OasisPanel {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("Roster", subtitle: "\(roster.count) profiles read from the fleet")
                    let gatewaysByName = Dictionary(uniqueKeysWithValues: (snapshot.gateways ?? []).map { ($0.name, $0) })
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(roster) { entry in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(dotColor(for: entry, gateways: gatewaysByName))
                                    .frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.name)
                                        .font(.callout.weight(.medium))
                                    Text(entry.model)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: OasisMetrics.tightCorner))
                        }
                    }
                }
            }
        }
    }

    private func dotColor(for entry: HermesRosterEntry, gateways: [String: HermesGatewayStatus]) -> Color {
        if let gateway = gateways[entry.name] {
            return gateway.running ? OasisPalette.green : OasisPalette.coral
        }
        return entry.gatewayState.lowercased() == "running" ? OasisPalette.green : .secondary
    }

    @ViewBuilder
    private func telemetryPanel(_ snapshot: HermesFleetSnapshot) -> some View {
        if !snapshot.agents.isEmpty {
            OasisPanel {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(
                        "Per-agent telemetry",
                        subtitle: "Sessions, messages, and tokens over the last 30 days"
                    )
                    VStack(spacing: 0) {
                        ForEach(snapshot.agents, id: \.name) { agent in
                            HStack {
                                Circle()
                                    .fill(agent.isGatewayActive ? OasisPalette.green : Color.secondary)
                                    .frame(width: 6, height: 6)
                                Text(agent.name)
                                    .font(.callout)
                                Spacer()
                                Text("\(agent.sessions) sessions")
                                Text("\(agent.messages) msgs")
                                Text(OasisFormat.integer(agent.totalTokensReported) + " tok")
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct KanbanStatusBar: View {
    let byStatus: [String: Int]

    private static let order = ["done", "todo", "scheduled", "triage", "blocked"]
    private static let colors: [String: Color] = [
        "done": OasisPalette.green,
        "todo": OasisPalette.teal,
        "scheduled": OasisPalette.indigo,
        "triage": OasisPalette.gold,
        "blocked": OasisPalette.coral,
    ]

    private var total: Int { max(byStatus.values.reduce(0, +), 1) }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(Self.order.filter { (byStatus[$0] ?? 0) > 0 }, id: \.self) { status in
                    let count = byStatus[status] ?? 0
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Self.colors[status] ?? .secondary)
                        .frame(width: geometry.size.width * CGFloat(count) / CGFloat(total))
                        .overlay(alignment: .center) {
                            if geometry.size.width * CGFloat(count) / CGFloat(total) > 34 {
                                Text("\(count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
            }
        }
    }
}

private struct DecisionQueueRow: View {
    let item: HermesDecisionQueueItem

    private var urgencyColor: Color {
        guard let deadline = item.ackDeadline else { return .secondary }
        let remaining = deadline.timeIntervalSinceNow
        if remaining < 0 { return OasisPalette.coral }
        if remaining < 3600 { return OasisPalette.gold }
        return OasisPalette.green
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.authority?.capitalized ?? "Unspecified")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.4), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let raisedBy = item.raisedBy {
                        Text("Raised by \(raisedBy)")
                    }
                    if item.ackCount > 0 {
                        Text("· \(item.ackCount) ack(s)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let deadlineRaw = item.ackDeadlineRaw {
                Circle()
                    .fill(urgencyColor)
                    .frame(width: 7, height: 7)
                    .help("Ack deadline: \(deadlineRaw)")
            }
        }
    }
}
