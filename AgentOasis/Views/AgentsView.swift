import SwiftUI

struct AgentsView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var selectedAgentID: UUID?
    @State private var search = ""
    @State private var showingAddAgent = false

    private var agents: [AgentProfile] {
        store.workspace.agents
            .filter {
                search.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(search)
                    || $0.role.localizedCaseInsensitiveContains(search)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selected: AgentProfile? {
        let id = selectedAgentID ?? agents.first?.id
        return store.workspace.agents.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                "Agents",
                subtitle: "Measure cost, accepted work, supervision, attributable value, and confidence."
            ) {
                HStack {
                    Button {
                        Task { await store.syncHermesFleet() }
                    } label: {
                        Label(
                            store.isSyncingHermes ? "Syncing..." : "Sync Hermes",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(store.isSyncingHermes)
                    Button {
                        showingAddAgent = true
                    } label: {
                        Label("Add Agent", systemImage: "plus")
                    }
                }
            }
            .padding(24)

            Divider()

            HSplitView {
                List(agents, selection: $selectedAgentID) { agent in
                    AgentRow(agent: agent)
                        .tag(agent.id)
                }
                .listStyle(.inset)
                .searchable(text: $search, placement: .sidebar)
                .frame(minWidth: 270, idealWidth: 310, maxWidth: 370)

                if let selected {
                    AgentDetailView(agent: selected)
                        .id(selected.id)
                } else {
                    EmptyStateView(
                        title: "No Agent Selected",
                        message: "Add an agent profile or synchronize the Hermes fleet.",
                        systemImage: "cpu"
                    )
                }
            }
        }
        .sheet(isPresented: $showingAddAgent) {
            AddAgentSheet()
                .environmentObject(store)
        }
        .onAppear {
            if selectedAgentID == nil { selectedAgentID = agents.first?.id }
        }
    }
}

private struct AgentRow: View {
    let agent: AgentProfile

    private var economics: AgentEconomics {
        AnalyticsEngine.agentEconomics(for: agent)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: agent.status.systemImage)
                .foregroundStyle(agent.status.color)
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(agent.name)
                    .font(.subheadline.weight(.medium))
                Text(agent.role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(OasisFormat.currency(economics.netValue))
                    .font(.caption.weight(.medium))
                Text("\(agent.sessions) sessions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AgentDetailView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var draft: AgentProfile

    init(agent: AgentProfile) {
        _draft = State(initialValue: agent)
    }

    private var economics: AgentEconomics {
        AnalyticsEngine.agentEconomics(for: draft)
    }

    private var inputOutputTotal: Int64 {
        draft.inputTokens + draft.outputTokens
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(draft.name)
                            .font(.system(size: 24, weight: .semibold))
                        Text(draft.role)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusIndicator(
                        text: draft.status.rawValue.capitalized,
                        systemImage: draft.status.systemImage,
                        color: draft.status.color
                    )
                    Button("Save Assumptions") {
                        store.updateAgent(draft)
                    }
                    .buttonStyle(.borderedProminent)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                    spacing: 12
                ) {
                    MetricTile(
                        title: "Direct cost",
                        value: OasisFormat.currency(economics.directCost),
                        detail: "Model, API, and compute cost",
                        systemImage: "creditcard",
                        color: OasisPalette.coral
                    )
                    MetricTile(
                        title: "Capacity value",
                        value: OasisFormat.currency(economics.capacityValue),
                        detail: "Equivalent hours x loaded rate",
                        systemImage: "hourglass",
                        color: OasisPalette.indigo
                    )
                    MetricTile(
                        title: "Net agent value",
                        value: OasisFormat.currency(economics.netValue),
                        detail: economics.roi.map { "\(OasisFormat.percent($0)) modeled ROI" }
                            ?? "Enter cost to calculate ROI",
                        systemImage: "chart.line.uptrend.xyaxis",
                        color: OasisPalette.green
                    )
                    MetricTile(
                        title: "Acceptance",
                        value: OasisFormat.percent(economics.acceptanceRate),
                        detail: "\(draft.reworkedTasks) accepted tasks needed rework",
                        systemImage: "checkmark.seal",
                        color: OasisPalette.teal
                    )
                }

                HStack(alignment: .top, spacing: 14) {
                    OasisPanel {
                        VStack(alignment: .leading, spacing: 13) {
                            SectionTitle(
                                "Value decomposition",
                                subtitle: "Each kind of value remains independently visible"
                            )
                            ValueLine("Capacity value", value: economics.capacityValue, color: OasisPalette.indigo)
                            ValueLine("Direct revenue influence", value: economics.directRevenue, color: OasisPalette.green)
                            ValueLine("Avoided vendor spend", value: economics.avoidedSpend, color: OasisPalette.teal)
                            Divider()
                            ValueLine("Direct operating cost", value: -economics.directCost, color: OasisPalette.coral)
                            Divider()
                            ValueLine("Modeled net value", value: economics.netValue, color: OasisPalette.gold, bold: true)
                            Text("Capacity value describes productive capacity. It is not automatically cash saved.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    OasisPanel {
                        VStack(alignment: .leading, spacing: 13) {
                            SectionTitle(
                                "Reliability",
                                subtitle: "Outcome quality and supervision burden"
                            )
                            ReliabilityLine(label: "Accepted tasks", value: String(draft.acceptedTasks))
                            ReliabilityLine(label: "Failed tasks", value: String(draft.failedTasks))
                            ReliabilityLine(label: "Reworked", value: String(draft.reworkedTasks))
                            ReliabilityLine(label: "Supervision", value: "\(draft.supervisionMinutes) min")
                            ReliabilityLine(
                                label: "Cost / accepted task",
                                value: economics.costPerAcceptedTask.map {
                                    OasisFormat.currency($0)
                                } ?? "Unknown"
                            )
                            ReliabilityLine(
                                label: "Model confidence",
                                value: OasisFormat.percent(economics.confidence)
                            )
                        }
                    }
                }

                OasisPanel {
                    VStack(alignment: .leading, spacing: 15) {
                        SectionTitle(
                            "Hermes activity",
                            subtitle: "\(draft.source) - last seen \(OasisFormat.relative(draft.lastSeen))"
                        )
                        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                            GridRow {
                                TokenMetric(label: "Sessions", value: OasisFormat.integer(Int64(draft.sessions)))
                                TokenMetric(label: "Messages", value: OasisFormat.integer(Int64(draft.messages)))
                                TokenMetric(label: "Tool calls", value: OasisFormat.integer(Int64(draft.toolCalls)))
                            }
                            GridRow {
                                TokenMetric(label: "Input tokens", value: OasisFormat.integer(draft.inputTokens))
                                TokenMetric(label: "Output tokens", value: OasisFormat.integer(draft.outputTokens))
                                TokenMetric(label: "Reported total", value: OasisFormat.integer(draft.totalTokensReported))
                            }
                        }
                        if draft.totalTokensReported > 0 && draft.totalTokensReported != inputOutputTotal {
                            Label(
                                "Reported total differs from input + output. Cached, system, or tool accounting may be included; assign cost only after provider normalization.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(OasisPalette.gold)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                OasisPanel {
                    VStack(alignment: .leading, spacing: 15) {
                        SectionTitle(
                            "Economics assumptions",
                            subtitle: "Use loaded labor rates and attributable values you can defend"
                        )
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            GridRow {
                                Text("Provider").foregroundStyle(.secondary)
                                TextField("Provider", text: $draft.provider)
                                Text("Model").foregroundStyle(.secondary)
                                TextField("Model", text: $draft.model)
                            }
                            GridRow {
                                Text("Model/API cost").foregroundStyle(.secondary)
                                TextField(
                                    "External cost",
                                    value: $draft.externalCost,
                                    format: .number.precision(.fractionLength(0...2))
                                )
                                Text("Compute cost").foregroundStyle(.secondary)
                                TextField(
                                    "Compute cost",
                                    value: $draft.computeCost,
                                    format: .number.precision(.fractionLength(0...2))
                                )
                            }
                            GridRow {
                                Text("Equivalent hours").foregroundStyle(.secondary)
                                TextField(
                                    "Hours",
                                    value: $draft.equivalentHumanHours,
                                    format: .number.precision(.fractionLength(0...1))
                                )
                                Text("Loaded hourly rate").foregroundStyle(.secondary)
                                TextField(
                                    "Rate",
                                    value: $draft.loadedHourlyRate,
                                    format: .number.precision(.fractionLength(0...2))
                                )
                            }
                            GridRow {
                                Text("Revenue influenced").foregroundStyle(.secondary)
                                TextField(
                                    "Revenue",
                                    value: $draft.directRevenueInfluenced,
                                    format: .number.precision(.fractionLength(0...2))
                                )
                                Text("Avoided vendor spend").foregroundStyle(.secondary)
                                TextField(
                                    "Avoided spend",
                                    value: $draft.avoidedVendorSpend,
                                    format: .number.precision(.fractionLength(0...2))
                                )
                            }
                            GridRow {
                                Text("Accepted / failed").foregroundStyle(.secondary)
                                HStack {
                                    TextField("Accepted", value: $draft.acceptedTasks, format: .number)
                                    TextField("Failed", value: $draft.failedTasks, format: .number)
                                }
                                Text("Rework / supervision").foregroundStyle(.secondary)
                                HStack {
                                    TextField("Reworked", value: $draft.reworkedTasks, format: .number)
                                    TextField("Minutes", value: $draft.supervisionMinutes, format: .number)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.28))
    }
}

private struct ValueLine: View {
    let label: String
    let value: Decimal
    let color: Color
    let bold: Bool

    init(_ label: String, value: Decimal, color: Color, bold: Bool = false) {
        self.label = label
        self.value = value
        self.color = color
        self.bold = bold
    }

    var body: some View {
        HStack {
            Label(label, systemImage: "square.fill")
                .foregroundStyle(color)
            Spacer()
            Text(OasisFormat.currency(value))
                .fontWeight(bold ? .semibold : .regular)
        }
        .font(.subheadline)
    }
}

private struct ReliabilityLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

private struct TokenMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddAgentSheet: View {
    @EnvironmentObject private var store: OasisStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = ""
    @State private var provider = ""
    @State private var model = ""
    @State private var hourlyRate: Decimal = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Agent Profile")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $name)
                TextField("Role", text: $role)
                TextField("Provider", text: $provider)
                TextField("Model", text: $model)
                TextField(
                    "Loaded human hourly rate",
                    value: $hourlyRate,
                    format: .number.precision(.fractionLength(0...2))
                )
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Agent") {
                    store.addAgent(
                        AgentProfile(
                            name: name,
                            role: role,
                            provider: provider,
                            model: model,
                            status: .idle,
                            sessions: 0,
                            messages: 0,
                            acceptedTasks: 0,
                            failedTasks: 0,
                            reworkedTasks: 0,
                            inputTokens: 0,
                            outputTokens: 0,
                            totalTokensReported: 0,
                            toolCalls: 0,
                            externalCost: 0,
                            computeCost: 0,
                            supervisionMinutes: 0,
                            equivalentHumanHours: 0,
                            loadedHourlyRate: hourlyRate,
                            directRevenueInfluenced: 0,
                            avoidedVendorSpend: 0,
                            source: "Manual",
                            tags: []
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
