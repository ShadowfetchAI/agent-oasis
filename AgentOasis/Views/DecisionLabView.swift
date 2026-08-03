import Charts
import SwiftUI

struct DecisionLabView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var mode: DecisionLabMode = .portfolio
    @State private var customerPrice = 1.99
    @State private var monthlyUnits = 100.0
    @State private var proceedsRate = 85.0
    @State private var refundRate = 2.0
    @State private var variableCost = 0.0
    @State private var operatingCost = 120.0
    @State private var humanHoursAvoided = 20.0
    @State private var loadedHourlyRate = 45.0

    private var portfolio: [PortfolioDecision] {
        DecisionEngine.portfolioDecisions(for: store.workspace)
    }

    private var agents: [AgentDecision] {
        DecisionEngine.agentDecisions(for: store.workspace)
    }

    private var scenarioInput: DecisionScenarioInput {
        DecisionScenarioInput(
            customerPrice: Decimal(max(0, customerPrice)),
            monthlyUnits: Int(max(0, monthlyUnits).rounded()),
            proceedsRate: proceedsRate / 100,
            refundRate: refundRate / 100,
            variableCostPerUnit: Decimal(max(0, variableCost)),
            monthlyOperatingCost: Decimal(max(0, operatingCost)),
            humanHoursAvoided: max(0, humanHoursAvoided),
            loadedHourlyRate: Decimal(max(0, loadedHourlyRate))
        )
    }

    private var scenario: DecisionScenarioResult {
        DecisionEngine.scenario(scenarioInput)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    "Decision Lab",
                    subtitle: "Rank evidence, test assumptions, and preserve the state behind a decision."
                ) {
                    HStack(spacing: 10) {
                        Button {
                            store.captureBusinessSnapshot()
                        } label: {
                            Label("Capture Checkpoint", systemImage: "camera.metering.matrix")
                        }
                        Button {
                            store.exportExecutiveBrief()
                        } label: {
                            Label("Export Brief", systemImage: "doc.richtext")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Picker("Decision view", selection: $mode) {
                    ForEach(DecisionLabMode.allCases) { item in
                        Label(item.title, systemImage: item.systemImage).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch mode {
                case .portfolio:
                    portfolioView
                case .agents:
                    agentView
                case .scenario:
                    scenarioView
                case .briefing:
                    briefingView
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.28))
    }

    private var portfolioView: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: 12)],
                spacing: 12
            ) {
                MetricTile(
                    title: "Recent proceeds",
                    value: OasisFormat.currency(
                        DecisionEngine.recentPortfolioProceeds(for: store.workspace),
                        code: store.workspace.settings.baseCurrency
                    ),
                    detail: "Confirmed and imported cash observations in the last 30 days",
                    systemImage: "banknote",
                    color: OasisPalette.cash,
                    provenance: .measured
                )
                MetricTile(
                    title: "Needs a decision",
                    value: String(portfolio.filter {
                        $0.disposition == .investigate || $0.disposition == .refresh
                    }.count),
                    detail: "Declines, zero-sales reversals, or stale evidence",
                    systemImage: "scope",
                    color: OasisPalette.coral
                )
                MetricTile(
                    title: "Scale candidates",
                    value: String(portfolio.filter { $0.disposition == .scale }.count),
                    detail: "Growth supported by confirmed observations",
                    systemImage: "arrow.up.right",
                    color: OasisPalette.teal
                )
                MetricTile(
                    title: "No baseline",
                    value: String(portfolio.filter { $0.disposition == .instrument }.count),
                    detail: "Do not change price from an empty comparison",
                    systemImage: "waveform.path.ecg",
                    color: OasisPalette.gold
                )
            }

            OasisPanel {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(
                        "Portfolio decision queue",
                        subtitle: "Rolling 30-day windows anchored to each app's freshest observation"
                    )
                    if portfolio.isEmpty {
                        EmptyStateView(
                            title: "No portfolio evidence",
                            message: "Sync App Store Connect or import a Sales and Trends report.",
                            systemImage: "chart.xyaxis.line"
                        )
                        .frame(minHeight: 240)
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                            GridRow {
                                tableHeader("App", width: 210, alignment: .leading)
                                tableHeader("Decision", width: 128, alignment: .leading)
                                tableHeader("30d proceeds", width: 112, alignment: .trailing)
                                tableHeader("Units", width: 70, alignment: .trailing)
                                tableHeader("Trend", width: 82, alignment: .trailing)
                                tableHeader("Evidence", width: 82, alignment: .trailing)
                                tableHeader("Score", width: 58, alignment: .trailing)
                            }
                            Divider().gridCellColumns(7)
                            ForEach(portfolio) { item in
                                GridRow {
                                    Button {
                                        store.selection = .portfolio
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.appName)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(1)
                                            Text(item.rationale)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        .frame(width: 210, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    DecisionPill(disposition: item.disposition)
                                        .frame(width: 128, alignment: .leading)
                                    tableValue(
                                        OasisFormat.currency(
                                            item.currentProceeds,
                                            code: item.currency
                                        ), width: 112
                                    )
                                    tableValue(String(item.currentUnits), width: 70)
                                    tableValue(
                                        item.trend.map { OasisFormat.percent($0, signed: true) } ?? "—",
                                        width: 82,
                                        color: trendColor(item.trend)
                                    )
                                    tableValue(OasisFormat.percent(item.evidenceRatio), width: 82)
                                    tableValue(String(item.decisionScore), width: 58)
                                }
                                .padding(.vertical, 9)
                                Divider().gridCellColumns(7)
                            }
                        }
                    }
                }
            }
        }
    }

    private var agentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                MetricTile(
                    title: "Measured winners",
                    value: String(agents.filter {
                        $0.disposition == .scale && $0.cashNetValue > 0
                    }.count),
                    detail: "Positive cash result with usable evidence",
                    systemImage: "checkmark.seal",
                    color: OasisPalette.cash,
                    provenance: .measured
                )
                MetricTile(
                    title: "Evidence gaps",
                    value: String(agents.filter { $0.disposition == .instrument }.count),
                    detail: "Profiles whose value inputs are still all typed",
                    systemImage: "pencil.and.outline",
                    color: OasisPalette.modeled,
                    provenance: .estimated
                )
                MetricTile(
                    title: "Quality reviews",
                    value: String(agents.filter { $0.disposition == .investigate }.count),
                    detail: "Acceptance or rework is outside the operating band",
                    systemImage: "wrench.and.screwdriver",
                    color: OasisPalette.coral
                )
            }

            OasisPanel {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle(
                        "Agent efficiency frontier",
                        subtitle: "Cash outcome, modelled capacity, delivery quality, and evidence in one row"
                    )
                    if agents.isEmpty {
                        EmptyStateView(
                            title: "No agent economics",
                            message: "Add an agent profile or sync the Hermes fleet.",
                            systemImage: "cpu"
                        )
                        .frame(minHeight: 240)
                    } else {
                        ForEach(agents) { item in
                            HStack(alignment: .center, spacing: 14) {
                                Button {
                                    store.focusedAgentID = item.id
                                    store.selection = .agents
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.agentName)
                                            .font(.headline)
                                        Text(item.rationale)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                DecisionPill(disposition: item.disposition)
                                    .frame(width: 132, alignment: .leading)
                                labeledMetric(
                                    "Cash net",
                                    OasisFormat.currency(item.cashNetValue),
                                    color: item.cashNetValue >= 0 ? OasisPalette.cash : OasisPalette.coral
                                )
                                labeledMetric(
                                    "Modelled",
                                    OasisFormat.currency(item.modeledNetValue),
                                    color: OasisPalette.modeled
                                )
                                labeledMetric("Accepted", OasisFormat.percent(item.acceptanceRate))
                                labeledMetric("Evidence", OasisFormat.percent(item.evidenceRatio))
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var scenarioView: some View {
        HStack(alignment: .top, spacing: 14) {
            OasisPanel {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(
                        "Assumptions",
                        subtitle: "Nothing here changes the ledger until you record a real result"
                    )
                    scenarioField("Customer price", value: $customerPrice, suffix: "$", range: 0...100)
                    scenarioField("Monthly units", value: $monthlyUnits, suffix: "units", range: 0...10000, step: 1)
                    scenarioField("Expected proceeds", value: $proceedsRate, suffix: "%", range: 0...100)
                    scenarioField("Refund rate", value: $refundRate, suffix: "%", range: 0...50)
                    scenarioField("Variable cost / unit", value: $variableCost, suffix: "$", range: 0...100)
                    scenarioField("Monthly operating cost", value: $operatingCost, suffix: "$", range: 0...100000)
                    Divider()
                    scenarioField("Human hours avoided", value: $humanHoursAvoided, suffix: "hours", range: 0...1000)
                    scenarioField("Loaded hourly rate", value: $loadedHourlyRate, suffix: "$", range: 0...500)
                    Label(
                        "Expected proceeds is your assumption. Agent Oasis does not infer an Apple commission or tax rate.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: 410)

            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricTile(
                        title: "Net cash",
                        value: OasisFormat.currency(scenario.netCash),
                        detail: "Expected proceeds minus cash costs",
                        systemImage: "banknote",
                        color: scenario.netCash >= 0 ? OasisPalette.cash : OasisPalette.coral,
                        provenance: .measured
                    )
                    MetricTile(
                        title: "Modelled capacity",
                        value: OasisFormat.currency(scenario.modeledCapacityValue),
                        detail: "Hours avoided × loaded rate; never added to cash",
                        systemImage: "clock.arrow.2.circlepath",
                        color: OasisPalette.modeled,
                        provenance: .estimated
                    )
                    MetricTile(
                        title: "Cash proceeds",
                        value: OasisFormat.currency(scenario.cashProceeds),
                        detail: "After the proceeds and refund assumptions above",
                        systemImage: "arrow.down.to.line",
                        color: OasisPalette.teal
                    )
                    MetricTile(
                        title: "Break-even",
                        value: scenario.breakEvenUnits.map { "\($0) units" } ?? "Not reachable",
                        detail: "Units needed to cover entered operating costs",
                        systemImage: "scale.3d",
                        color: OasisPalette.gold
                    )
                }

                OasisPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(
                            "Unit sensitivity",
                            subtitle: "Net cash when actual volume lands above or below plan"
                        )
                        Chart(DecisionEngine.sensitivity(for: scenarioInput)) { point in
                            BarMark(
                                x: .value("Volume", point.label),
                                y: .value("Net cash", AnalyticsEngine.decimalDouble(point.netCash))
                            )
                            .foregroundStyle(
                                point.netCash >= 0 ? OasisPalette.cash : OasisPalette.coral
                            )
                            .annotation(position: .top) {
                                Text(OasisFormat.currency(point.netCash, compact: true))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(minHeight: 250)
                    }
                }
            }
        }
    }

    private var briefingView: some View {
        HStack(alignment: .top, spacing: 14) {
            OasisPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionTitle(
                            "Executive brief",
                            subtitle: "Generated locally; vault items and secrets are excluded"
                        )
                        Spacer()
                        Button {
                            store.exportExecutiveBrief()
                        } label: {
                            Label("Export HTML", systemImage: "square.and.arrow.up")
                        }
                    }
                    Divider()
                    Text(ExecutiveBriefingService.markdown(for: store.workspace))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)

            OasisPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionTitle(
                            "Business checkpoints",
                            subtitle: "Compare today's state with a preserved decision point"
                        )
                        Spacer()
                        Button {
                            store.captureBusinessSnapshot()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("Capture checkpoint")
                    }
                    if store.workspace.snapshots.isEmpty {
                        EmptyStateView(
                            title: "No checkpoints yet",
                            message: "Capture one before a price, release, or staffing change.",
                            systemImage: "camera.metering.matrix"
                        )
                        .frame(minHeight: 260)
                    } else {
                        ForEach(store.workspace.snapshots.sorted(by: { $0.capturedAt > $1.capturedAt })) { snapshot in
                            checkpointRow(snapshot)
                                .contextMenu {
                                    Button("Delete Checkpoint", role: .destructive) {
                                        store.deleteBusinessSnapshot(id: snapshot.id)
                                    }
                                }
                            Divider()
                        }
                    }
                }
            }
            .frame(width: 390)
        }
    }

    private func checkpointRow(_ snapshot: BusinessSnapshot) -> some View {
        let current = DecisionEngine.makeSnapshot(label: "Current", state: store.workspace)
        let delta = DecisionEngine.delta(current: current, baseline: snapshot)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(snapshot.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(snapshot.capturedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                deltaLabel("Net cash", delta.netCash, currency: snapshot.currency)
                deltaLabel("30d proceeds", delta.recentPortfolioProceeds, currency: snapshot.currency)
            }
            Text("Evidence \(OasisFormat.percent(snapshot.fleetEvidenceRatio)) → \(OasisFormat.percent(current.fleetEvidenceRatio))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func deltaLabel(_ title: String, _ value: Decimal, currency: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text((value >= 0 ? "+" : "") + OasisFormat.currency(value, code: currency))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(value >= 0 ? OasisPalette.cash : OasisPalette.coral)
        }
    }

    private func scenarioField(
        _ title: String,
        value: Binding<Double>,
        suffix: String,
        range: ClosedRange<Double>,
        step: Double = 0.01
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 96)
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func labeledMetric(_ title: String, _ value: String, color: Color = .secondary) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(width: 92, alignment: .trailing)
    }

    private func tableHeader(
        _ value: String,
        width: CGFloat,
        alignment: Alignment
    ) -> some View {
        Text(value.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
            .padding(.vertical, 6)
    }

    private func tableValue(
        _ value: String,
        width: CGFloat,
        color: Color = .primary
    ) -> some View {
        Text(value)
            .font(.caption.monospacedDigit())
            .foregroundStyle(color)
            .frame(width: width, alignment: .trailing)
    }

    private func trendColor(_ trend: Double?) -> Color {
        guard let trend else { return .secondary }
        if trend > 0 { return OasisPalette.cash }
        if trend < 0 { return OasisPalette.coral }
        return .secondary
    }
}

private enum DecisionLabMode: String, CaseIterable, Identifiable {
    case portfolio
    case agents
    case scenario
    case briefing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portfolio: "Portfolio"
        case .agents: "Agents"
        case .scenario: "Scenario Studio"
        case .briefing: "Briefing"
        }
    }

    var systemImage: String {
        switch self {
        case .portfolio: "square.grid.2x2"
        case .agents: "cpu"
        case .scenario: "slider.horizontal.3"
        case .briefing: "doc.richtext"
        }
    }
}

private struct DecisionPill: View {
    let disposition: DecisionDisposition

    private var color: Color {
        switch disposition {
        case .scale: OasisPalette.cash
        case .hold: OasisPalette.teal
        case .investigate: OasisPalette.coral
        case .refresh: OasisPalette.gold
        case .instrument: OasisPalette.modeled
        }
    }

    var body: some View {
        Label(disposition.title, systemImage: disposition.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.13), in: Capsule())
            .lineLimit(1)
    }
}
