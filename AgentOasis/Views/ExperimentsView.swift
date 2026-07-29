import SwiftUI

struct ExperimentsView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var selectedID: UUID?
    @State private var showingAddExperiment = false

    private var experiments: [Experiment] {
        store.workspace.experiments.sorted { $0.startedAt > $1.startedAt }
    }

    private var selected: Experiment? {
        let id = selectedID ?? experiments.first?.id
        return store.workspace.experiments.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                "Experiments",
                subtitle: "Price, release, metadata, marketing, and product changes with explicit baselines."
            ) {
                Button {
                    showingAddExperiment = true
                } label: {
                    Label("New Experiment", systemImage: "plus")
                }
            }
            .padding(24)

            Divider()

            HSplitView {
                List(experiments, selection: $selectedID) { experiment in
                    ExperimentRow(experiment: experiment)
                        .tag(experiment.id)
                }
                .listStyle(.inset)
                .frame(minWidth: 290, idealWidth: 330, maxWidth: 390)

                if let selected {
                    ExperimentDetailView(experiment: selected)
                        .id(selected.id)
                } else {
                    EmptyStateView(
                        title: "No Experiment Selected",
                        message: "Create an experiment to keep business changes and their evidence together.",
                        systemImage: "flask"
                    )
                }
            }
        }
        .sheet(isPresented: $showingAddExperiment) {
            AddExperimentSheet()
                .environmentObject(store)
        }
        .onAppear {
            if selectedID == nil { selectedID = experiments.first?.id }
        }
    }
}

private struct ExperimentRow: View {
    let experiment: Experiment

    private var color: Color {
        switch experiment.status {
        case .planned: .secondary
        case .running: OasisPalette.gold
        case .completed: OasisPalette.green
        case .inconclusive: OasisPalette.coral
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: experiment.status == .running ? "flask.fill" : "flask")
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(experiment.title)
                    .font(.subheadline.weight(.medium))
                Text("\(experiment.appName) - \(experiment.kind.rawValue.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(experiment.status.rawValue.capitalized)
                .font(.caption)
                .foregroundStyle(color)
        }
        .padding(.vertical, 5)
    }
}

private struct ExperimentDetailView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var draft: Experiment

    init(experiment: Experiment) {
        _draft = State(initialValue: experiment)
    }

    private var lift: Double? {
        AnalyticsEngine.experimentLift(draft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(draft.title)
                            .font(.system(size: 24, weight: .semibold))
                        Text("\(draft.appName) - \(draft.kind.rawValue.capitalized)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Status", selection: $draft.status) {
                        ForEach(ExperimentStatus.allCases) { status in
                            Text(status.rawValue.capitalized).tag(status)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    Button("Save") { store.updateExperiment(draft) }
                        .buttonStyle(.borderedProminent)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 175), spacing: 12)],
                    spacing: 12
                ) {
                    MetricTile(
                        title: "Baseline",
                        value: OasisFormat.currency(draft.baselineProceeds),
                        detail: draft.beforeValue,
                        systemImage: "backward.end",
                        color: .secondary
                    )
                    MetricTile(
                        title: "Observed",
                        value: OasisFormat.currency(draft.observedProceeds),
                        detail: draft.afterValue,
                        systemImage: "forward.end",
                        color: OasisPalette.teal
                    )
                    MetricTile(
                        title: "Preliminary lift",
                        value: lift.map { OasisFormat.percent($0, signed: true) } ?? "No baseline",
                        detail: "\(draft.observationWindowDays)-day observation window",
                        systemImage: "chart.line.uptrend.xyaxis",
                        color: (lift ?? 0) >= 0 ? OasisPalette.green : OasisPalette.coral
                    )
                }

                OasisPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("Hypothesis")
                        TextEditor(text: $draft.hypothesis)
                            .frame(minHeight: 82)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.separator.opacity(0.6))
                            )
                    }
                }

                OasisPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Change and measurement")
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                            GridRow {
                                Text("Before").foregroundStyle(.secondary)
                                TextField("Before", text: $draft.beforeValue)
                            }
                            GridRow {
                                Text("After").foregroundStyle(.secondary)
                                TextField("After", text: $draft.afterValue)
                            }
                            GridRow {
                                Text("Started").foregroundStyle(.secondary)
                                DatePicker("Started", selection: $draft.startedAt, displayedComponents: .date)
                                    .labelsHidden()
                            }
                            GridRow {
                                Text("Window").foregroundStyle(.secondary)
                                Stepper(
                                    "\(draft.observationWindowDays) days",
                                    value: $draft.observationWindowDays,
                                    in: 7...180
                                )
                            }
                            GridRow {
                                Text("Baseline proceeds").foregroundStyle(.secondary)
                                TextField(
                                    "Baseline",
                                    value: $draft.baselineProceeds,
                                    format: .number.precision(.fractionLength(0...2))
                                )
                            }
                            GridRow {
                                Text("Observed proceeds").foregroundStyle(.secondary)
                                TextField(
                                    "Observed",
                                    value: $draft.observedProceeds,
                                    format: .number.precision(.fractionLength(0...2))
                                )
                            }
                        }
                    }
                }

                OasisPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(
                            "Confounders and interpretation",
                            subtitle: "Record anything else that could have moved the result"
                        )
                        TextEditor(text: $draft.confounders)
                            .frame(minHeight: 74)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.separator.opacity(0.6))
                            )
                        Text("Notes")
                            .font(.subheadline.weight(.medium))
                        TextEditor(text: $draft.notes)
                            .frame(minHeight: 74)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.separator.opacity(0.6))
                            )
                        Label(
                            "Agent Oasis reports association. A before/after change is not automatically proof of causation.",
                            systemImage: "checkmark.seal"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.28))
    }
}

private struct AddExperimentSheet: View {
    @EnvironmentObject private var store: OasisStore
    @Environment(\.dismiss) private var dismiss
    @State private var appID: UUID?
    @State private var title = ""
    @State private var kind: ExperimentKind = .price
    @State private var hypothesis = ""
    @State private var before = ""
    @State private var after = ""
    @State private var days = 30

    private var selectedApp: PortfolioApp? {
        store.workspace.apps.first(where: { $0.id == appID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Experiment")
                .font(.title2.weight(.semibold))
            Form {
                Picker("Product", selection: $appID) {
                    Text("Portfolio-wide").tag(UUID?.none)
                    ForEach(store.workspace.apps) { app in
                        Text(app.name).tag(Optional(app.id))
                    }
                }
                TextField("Title", text: $title)
                Picker("Kind", selection: $kind) {
                    ForEach(ExperimentKind.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                TextField("Hypothesis", text: $hypothesis, axis: .vertical)
                TextField("Before", text: $before)
                TextField("After", text: $after)
                Stepper("\(days)-day window", value: $days, in: 7...180)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Experiment") {
                    store.addExperiment(
                        Experiment(
                            appID: appID,
                            appName: selectedApp?.name ?? "Portfolio",
                            title: title,
                            kind: kind,
                            status: .planned,
                            startedAt: Date(),
                            hypothesis: hypothesis,
                            beforeValue: before,
                            afterValue: after,
                            observationWindowDays: days,
                            baselineProceeds: 0,
                            observedProceeds: 0,
                            confounders: "",
                            notes: ""
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560, height: 600)
    }
}
