import SwiftUI

struct PortfolioView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var selectedAppID: UUID?
    @State private var search = ""
    @State private var showingAddApp = false

    private var filteredApps: [PortfolioApp] {
        store.workspace.apps
            .filter {
                search.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(search)
                    || $0.bundleID.localizedCaseInsensitiveContains(search)
                    || $0.sku.localizedCaseInsensitiveContains(search)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedApp: PortfolioApp? {
        let id = selectedAppID ?? filteredApps.first?.id
        return store.workspace.apps.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                "Portfolio",
                subtitle: "Products, observations, pricing, and health signals."
            ) {
                Button {
                    showingAddApp = true
                } label: {
                    Label("Add Product", systemImage: "plus")
                }
            }
            .padding(24)

            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    List(filteredApps, selection: $selectedAppID) { app in
                        PortfolioRow(app: app)
                            .tag(app.id)
                    }
                    .listStyle(.inset)
                    .searchable(text: $search, placement: .sidebar)
                }
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

                if let selectedApp {
                    AppDetailView(app: selectedApp)
                        .id(selectedApp.id)
                } else {
                    EmptyStateView(
                        title: "No Product Selected",
                        message: "Add a product or select one from the portfolio.",
                        systemImage: "square.grid.2x2"
                    )
                }
            }
        }
        .sheet(isPresented: $showingAddApp) {
            AddAppSheet()
                .environmentObject(store)
        }
        .onAppear {
            if selectedAppID == nil { selectedAppID = filteredApps.first?.id }
        }
        .onChange(of: store.pendingNewItem) { _, pending in
            guard pending, store.selection == .portfolio else { return }
            showingAddApp = true
            store.pendingNewItem = false
        }
    }
}

private struct PortfolioRow: View {
    let app: PortfolioApp

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: app.platform == .macOS ? "macbook" : app.platform == .linux ? "terminal" : "app")
                .font(.title3)
                .foregroundStyle(app.status.color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(app.platform.rawValue)
                    if let trend = AnalyticsEngine.appTrend(app) {
                        Text(OasisFormat.percent(trend, signed: true))
                            .foregroundStyle(trend >= 0 ? OasisPalette.green : OasisPalette.coral)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(OasisFormat.currency(app.latestObservation?.proceeds ?? 0, code: app.currency))
                .font(.caption.weight(.medium))
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy Bundle ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.bundleID, forType: .string)
            }
            Button("Copy SKU") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.sku, forType: .string)
            }
        }
    }
}

private struct AppDetailView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var draft: PortfolioApp

    init(app: PortfolioApp) {
        _draft = State(initialValue: app)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(draft.name)
                            .font(.system(size: 24, weight: .semibold))
                        Text(draft.bundleID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    StatusIndicator(
                        text: draft.status.rawValue.capitalized,
                        systemImage: draft.status.systemImage,
                        color: draft.status.color
                    )
                    Button("Save") {
                        store.updateApp(draft)
                    }
                    .buttonStyle(.borderedProminent)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 165), spacing: 12)],
                    spacing: 12
                ) {
                    MetricTile(
                        title: "Latest proceeds",
                        value: OasisFormat.currency(
                            draft.latestObservation?.proceeds ?? 0,
                            code: draft.currency
                        ),
                        detail: OasisFormat.relative(draft.latestObservation?.date),
                        systemImage: "dollarsign.circle",
                        color: OasisPalette.green
                    )
                    MetricTile(
                        title: "Latest units",
                        value: String(draft.latestObservation?.units ?? 0),
                        detail: AnalyticsEngine.appTrend(draft).map {
                            "\(OasisFormat.percent($0, signed: true)) proceeds movement"
                        } ?? "No prior period",
                        systemImage: "arrow.down.app",
                        color: OasisPalette.teal
                    )
                    MetricTile(
                        title: "Health",
                        value: OasisFormat.percent(draft.healthScore),
                        detail: "Manually adjustable operating signal",
                        systemImage: "heart.text.square",
                        color: draft.status.color
                    )
                }

                OasisPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(
                            "Proceeds history",
                            subtitle: "\(draft.observations.count) source observations"
                        )
                        if draft.observations.isEmpty {
                            Text("Import an App Store sales report to build this history.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 180)
                        } else {
                            ProceedsChart(
                                observations: draft.observations,
                                currency: draft.currency
                            )
                            .frame(minHeight: 230)
                        }
                    }
                }

                OasisPanel {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle("Product record")
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            GridRow {
                                Text("Name").foregroundStyle(.secondary)
                                TextField("Product name", text: $draft.name)
                            }
                            GridRow {
                                Text("Bundle ID").foregroundStyle(.secondary)
                                TextField("Bundle identifier", text: $draft.bundleID)
                            }
                            GridRow {
                                Text("SKU").foregroundStyle(.secondary)
                                TextField("SKU", text: $draft.sku)
                            }
                            GridRow {
                                Text("Platform").foregroundStyle(.secondary)
                                Picker("Platform", selection: $draft.platform) {
                                    ForEach(PlatformKind.allCases) { platform in
                                        Text(platform.rawValue).tag(platform)
                                    }
                                }
                                .labelsHidden()
                            }
                            GridRow {
                                Text("Status").foregroundStyle(.secondary)
                                Picker("Status", selection: $draft.status) {
                                    ForEach(LifecycleStatus.allCases) { status in
                                        Text(status.rawValue.capitalized).tag(status)
                                    }
                                }
                                .labelsHidden()
                            }
                            GridRow {
                                Text("Price").foregroundStyle(.secondary)
                                HStack {
                                    TextField("Price", value: $draft.price, format: .number.precision(.fractionLength(0...2)))
                                        .frame(width: 110)
                                    TextField("Currency", text: $draft.currency)
                                        .frame(width: 80)
                                }
                            }
                            GridRow {
                                Text("Health").foregroundStyle(.secondary)
                                Slider(value: $draft.healthScore, in: 0...1, step: 0.01)
                            }
                        }
                        Divider()
                        Text("Notes")
                            .font(.subheadline.weight(.medium))
                        TextEditor(text: $draft.notes)
                            .font(.body)
                            .frame(minHeight: 76)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.separator.opacity(0.6))
                            )
                    }
                }

                OasisPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Evidence", subtitle: "Newest source records first")
                        ForEach(draft.observations.sorted(by: { $0.date > $1.date }).prefix(12)) { item in
                            HStack {
                                Text(item.date, format: .dateTime.month().day().year())
                                    .frame(width: 130, alignment: .leading)
                                Text("\(item.units) units")
                                Spacer()
                                Text(OasisFormat.currency(item.proceeds, code: item.currency))
                                StatusIndicator(
                                    text: item.confidence.rawValue.capitalized,
                                    systemImage: item.confidence == .confirmed ? "checkmark.seal.fill" : "questionmark.circle",
                                    color: item.confidence == .confirmed ? OasisPalette.green : OasisPalette.gold
                                )
                            }
                            .font(.caption)
                            Divider()
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.28))
    }
}

private struct AddAppSheet: View {
    @EnvironmentObject private var store: OasisStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var bundleID = ""
    @State private var sku = ""
    @State private var platform: PlatformKind = .iOS
    @State private var category = "Utilities"
    @State private var price: Decimal = 0.99
    @State private var currency = "USD"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Product")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $name)
                TextField("Bundle ID", text: $bundleID)
                TextField("SKU", text: $sku)
                Picker("Platform", selection: $platform) {
                    ForEach(PlatformKind.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Category", text: $category)
                TextField("Price", value: $price, format: .number.precision(.fractionLength(0...2)))
                TextField("Currency", text: $currency)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Product") {
                    store.addApp(
                        PortfolioApp(
                            name: name,
                            bundleID: bundleID,
                            sku: sku,
                            platform: platform,
                            category: category,
                            status: .watch,
                            price: price,
                            currency: currency,
                            healthScore: 0.5,
                            notes: "",
                            observations: []
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || bundleID.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
