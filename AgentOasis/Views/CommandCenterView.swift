import SwiftUI

struct CommandCenterView: View {
    @EnvironmentObject private var store: OasisStore

    private var summary: WorkspaceSummary {
        AnalyticsEngine.summary(for: store.workspace)
    }

    private var monthly: [MonthlyPoint] {
        AnalyticsEngine.monthlyCashFlow(for: store.workspace)
    }

    private var sortedAgents: [AgentEconomics] {
        store.workspace.agents
            .map(AnalyticsEngine.agentEconomics)
            .sorted { $0.netValue > $1.netValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    "Command Center",
                    subtitle: "Cash, portfolio movement, experiments, and agent economics in one view."
                ) {
                    StatusIndicator(
                        text: "Local encrypted workspace",
                        systemImage: "lock.fill",
                        color: OasisPalette.green
                    )
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 12)],
                    spacing: 12
                ) {
                    MetricTile(
                        title: "Net cash",
                        value: OasisFormat.currency(summary.netCash),
                        detail: "Revenue minus recorded cash expenses",
                        systemImage: "banknote",
                        color: summary.netCash >= 0 ? OasisPalette.green : OasisPalette.coral
                    )
                    MetricTile(
                        title: "Agent net value",
                        value: OasisFormat.currency(summary.agentNetValue),
                        detail: "Capacity + revenue + avoided spend - cost",
                        systemImage: "cpu",
                        color: OasisPalette.indigo
                    )
                    MetricTile(
                        title: "Portfolio health",
                        value: OasisFormat.percent(summary.averageAppHealth),
                        detail: "\(store.workspace.apps.count) tracked products",
                        systemImage: "heart.text.square",
                        color: OasisPalette.teal
                    )
                    MetricTile(
                        title: "Active experiments",
                        value: String(summary.activeExperiments),
                        detail: "\(summary.staleConnections) connections need attention",
                        systemImage: "flask",
                        color: OasisPalette.gold
                    )
                }

                HStack(alignment: .top, spacing: 14) {
                    OasisPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                SectionTitle(
                                    "Cash movement",
                                    subtitle: "Revenue and actual expenses by month"
                                )
                                Spacer()
                                HStack(spacing: 12) {
                                    Label("Revenue", systemImage: "square.fill")
                                        .foregroundStyle(OasisPalette.green)
                                    Label("Expense", systemImage: "square.fill")
                                        .foregroundStyle(OasisPalette.coral)
                                }
                                .font(.caption)
                            }
                            CashFlowChart(points: monthly)
                                .frame(minHeight: 230)
                        }
                    }
                    .frame(minWidth: 440)

                    OasisPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionTitle(
                                "Priority signals",
                                subtitle: "The items most likely to change the next decision"
                            )
                            ForEach(prioritySignals) { signal in
                                SignalRow(signal: signal)
                            }
                            if prioritySignals.isEmpty {
                                Text("No priority signals.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(minWidth: 300, maxWidth: 380)
                }

                HStack(alignment: .top, spacing: 14) {
                    OasisPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(
                                "Portfolio pulse",
                                subtitle: "Latest proceeds and month-over-month movement"
                            )
                            Divider()
                            ForEach(store.workspace.apps.sorted(by: {
                                ($0.latestObservation?.proceeds ?? 0) > ($1.latestObservation?.proceeds ?? 0)
                            }).prefix(6)) { app in
                                Button {
                                    store.selection = .portfolio
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: app.platform == .macOS ? "macbook" : "app")
                                            .foregroundStyle(app.status.color)
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(app.name)
                                                .fontWeight(.medium)
                                            Text(app.platform.rawValue)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(OasisFormat.currency(
                                                app.latestObservation?.proceeds ?? 0,
                                                code: app.currency
                                            ))
                                            if let trend = AnalyticsEngine.appTrend(app) {
                                                Text(OasisFormat.percent(trend, signed: true))
                                                    .font(.caption)
                                                    .foregroundStyle(trend >= 0 ? OasisPalette.green : OasisPalette.coral)
                                            } else {
                                                Text("No baseline")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    OasisPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(
                                "Agent returns",
                                subtitle: "Modeled value with confidence kept visible"
                            )
                            Divider()
                            ForEach(sortedAgents.prefix(6)) { economics in
                                Button {
                                    store.selection = .agents
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(economics.name)
                                                .fontWeight(.medium)
                                            Text("Confidence \(OasisFormat.percent(economics.confidence))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(OasisFormat.currency(economics.netValue))
                                            Text(economics.roi.map {
                                                "\(OasisFormat.percent($0)) ROI"
                                            } ?? "Cost not entered")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.28))
    }

    private var prioritySignals: [PrioritySignal] {
        var signals: [PrioritySignal] = []
        let running = store.workspace.experiments.filter { $0.status == .running }
        for experiment in running.prefix(2) {
            let lift = AnalyticsEngine.experimentLift(experiment)
            signals.append(
                PrioritySignal(
                    title: experiment.title,
                    detail: lift.map {
                        "Preliminary lift \(OasisFormat.percent($0, signed: true)); \(experiment.observationWindowDays)-day window."
                    } ?? "Waiting for a usable baseline.",
                    systemImage: "flask.fill",
                    color: OasisPalette.gold
                )
            )
        }

        let blocked = store.workspace.agents.filter { $0.status == .blocked }
        if !blocked.isEmpty {
            signals.append(
                PrioritySignal(
                    title: "\(blocked.count) blocked agent\(blocked.count == 1 ? "" : "s")",
                    detail: "Review assignment dependencies before adding more agent capacity.",
                    systemImage: "exclamationmark.octagon.fill",
                    color: OasisPalette.coral
                )
            )
        }

        let connections = store.workspace.connections.filter {
            $0.status == .needsSetup || $0.status == .error || $0.status == .stale
        }
        if !connections.isEmpty {
            signals.append(
                PrioritySignal(
                    title: "\(connections.count) data source\(connections.count == 1 ? "" : "s") need attention",
                    detail: "Fresh source data raises the confidence of every downstream result.",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    color: OasisPalette.teal
                )
            )
        }

        if store.workspace.ledger.contains(where: { $0.confidence == .inferred }) {
            signals.append(
                PrioritySignal(
                    title: "Modeled values are present",
                    detail: "Capacity and risk values remain separate from realized cash.",
                    systemImage: "equal.circle.fill",
                    color: OasisPalette.indigo
                )
            )
        }
        return Array(signals.prefix(4))
    }
}

private struct PrioritySignal: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
}

private struct SignalRow: View {
    let signal: PrioritySignal

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: signal.systemImage)
                .foregroundStyle(signal.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(signal.title)
                    .font(.subheadline.weight(.medium))
                Text(signal.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
