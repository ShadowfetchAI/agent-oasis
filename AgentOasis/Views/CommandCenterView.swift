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
            .sorted { $0.cashNetValue > $1.cashNetValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if store.workspace.apps.isEmpty && store.workspace.agents.isEmpty

                    && store.workspace.ledger.isEmpty {

                    GettingStartedPanel()

                }

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
                        title: "Agent cash value",
                        value: OasisFormat.currency(summary.agentCashNetValue),
                        detail: "Measured revenue minus real cost. Modeled value is excluded.",
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
                            HStack(alignment: .firstTextBaseline) {
                                SectionTitle(
                                    "Attention Inbox",
                                    subtitle: "Actionable gaps only — empty means nothing needs you"
                                )
                                Spacer()
                                if !attentionItems.isEmpty {
                                    Text("\(attentionItems.count)")
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(OasisPalette.coral.opacity(0.18), in: Capsule())
                                        .foregroundStyle(OasisPalette.coral)
                                }
                            }
                            ForEach(attentionItems.prefix(6)) { item in
                                AttentionRow(item: item) {
                                    store.openAttentionItem(item)
                                }
                            }
                            if attentionItems.isEmpty {
                                Label(
                                    "Nothing needs attention right now.",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .foregroundStyle(OasisPalette.green)
                                .font(.subheadline)
                            } else if attentionItems.count > 6 {
                                Text("\(attentionItems.count - 6) more in Agents, Experiments, or Connections.")
                                    .font(.caption)
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
                                            Text(economics.confidence < 0.01 ? "No evidence" : "Evidence \(OasisFormat.percent(economics.confidence))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(OasisFormat.currency(economics.cashNetValue))
                                            Text(economics.cashROI.map {
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

    private var attentionItems: [AttentionItem] {
        AttentionEngine.items(for: store.workspace)
    }
}

private struct AttentionRow: View {
    let item: AttentionItem
    let action: () -> Void

    private var color: Color {
        switch item.severity {
        case .critical: OasisPalette.coral
        case .warning: OasisPalette.gold
        case .info: OasisPalette.teal
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.systemImage)
                    .symbolEffect(
                        .pulse,
                        options: .repeating,
                        isActive: item.severity == .critical
                    )
                    .foregroundStyle(color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(item.section.title)")
    }
}

struct GettingStartedPanel: View {
    @EnvironmentObject private var store: OasisStore

    /// Shown until the workspace has real content in it.
    ///
    /// A new workspace is deliberately empty - the app no longer invents a portfolio to fill
    /// the screen - so it owes the user an explanation of what to do instead of a blank grid.
    /// Every step here is optional and local; none of them require an account.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(OasisNeon.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your workspace is empty")
                        .font(.title3.weight(.semibold))
                    Text("Nothing here is made up. Add your own data and every figure stays "
                         + "yours, on this Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                step("1", "square.and.arrow.down",
                     "Import a Sales and Trends report",
                     "⌘I or drop a CSV/TSV here. You will preview counts before anything is "
                         + "written. Re-importing the same file will not double-count it.")
                step("2", "key.horizontal",
                     "Connect App Store Connect (optional)",
                     "Vault → add your .p8 key, then Connections. Read-only; it syncs app "
                         + "records, never money.")
                step("3", "person.2",
                     "Add the agents you actually run",
                     "⌘3 then ⌘N, or Agents → add. Mark each value input as measured or "
                         + "estimated — cash and modelled value stay apart.")
                step("4", "arrow.down.doc",
                     "Export a backup and keep the recovery key",
                     "Settings → Export encrypted backup. Without it, losing this Mac loses "
                         + "the workspace.")
            }

            HStack(spacing: 10) {
                Button {
                    store.requestImportPicker()
                } label: {
                    Label("Import report…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    store.selection = .agents
                    store.pendingNewItem = true
                } label: {
                    Label("Add first agent", systemImage: "plus")
                }

                Button {
                    store.showingCommandPalette = true
                } label: {
                    Label("Command palette", systemImage: "command")
                }
                .help("⌘K")

                Spacer(minLength: 0)
            }
        }
        .padding(OasisMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oasisSurface()
    }

    private func step(_ number: String, _ symbol: String,
                      _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(OasisNeon.cyan)
                .frame(width: 20, height: 20)
                .background(OasisNeon.cyan.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
