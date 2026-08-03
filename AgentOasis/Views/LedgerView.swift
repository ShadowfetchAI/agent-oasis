import SwiftUI

struct LedgerView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var search = ""
    @State private var typeFilter: LedgerEntryType?
    @State private var showingAddEntry = false

    private var entries: [LedgerEntry] {
        store.workspace.ledger
            .filter {
                (typeFilter == nil || $0.type == typeFilter)
                    && (search.isEmpty
                        || $0.description.localizedCaseInsensitiveContains(search)
                        || $0.entityName.localizedCaseInsensitiveContains(search)
                        || $0.category.localizedCaseInsensitiveContains(search))
            }
            .sorted { $0.date > $1.date }
    }

    private var summary: WorkspaceSummary {
        AnalyticsEngine.summary(for: store.workspace)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(
                    "Ledger",
                    subtitle: "Actual cash, modeled value, source evidence, and confidence."
                ) {
                    HStack {
                        Menu {
                            Button("All entry types") { typeFilter = nil }
                            Divider()
                            ForEach(LedgerEntryType.allCases) { type in
                                Button(type.title) { typeFilter = type }
                            }
                        } label: {
                            Label(
                                typeFilter?.title ?? "All Types",
                                systemImage: "line.3.horizontal.decrease.circle"
                            )
                        }
                        Button {
                            showingAddEntry = true
                        } label: {
                            Label("Add Entry", systemImage: "plus")
                        }
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 185), spacing: 12)],
                    spacing: 12
                ) {
                    MetricTile(
                        title: "Recorded revenue",
                        value: OasisFormat.currency(
                            summary.cashRevenue,
                            code: store.workspace.settings.baseCurrency
                        ),
                        detail: "Actual and imported proceeds in the base currency",
                        systemImage: "arrow.down.left.circle",
                        color: OasisPalette.green
                    )
                    MetricTile(
                        title: "Recorded expenses",
                        value: OasisFormat.currency(
                            summary.cashExpenses,
                            code: store.workspace.settings.baseCurrency
                        ),
                        detail: "Cash outflows only",
                        systemImage: "arrow.up.right.circle",
                        color: OasisPalette.coral
                    )
                    MetricTile(
                        title: "Net cash",
                        value: OasisFormat.currency(
                            summary.netCash,
                            code: store.workspace.settings.baseCurrency
                        ),
                        detail: "Excludes modeled capacity value",
                        systemImage: "equal.circle",
                        color: OasisPalette.teal
                    )
                    MetricTile(
                        title: "Capacity value",
                        value: OasisFormat.currency(summary.capacityValue),
                        detail: "Modeled separately from cash",
                        systemImage: "hourglass",
                        color: OasisPalette.indigo
                    )
                }
            }
            .padding(24)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    TextField("Search ledger", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                    Spacer()
                    Text("\(entries.count) records")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)

                Divider()

                if entries.isEmpty {
                    EmptyStateView(
                        title: "No Matching Ledger Entries",
                        message: "Change the filter or add a revenue, expense, or modeled value record.",
                        systemImage: "list.bullet.rectangle"
                    )
                } else {
                    List(entries) { entry in
                        LedgerRow(entry: entry)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            AddLedgerEntrySheet()
                .environmentObject(store)
        }
        .onChange(of: store.pendingNewItem) { _, pending in
            guard pending, store.selection == .ledger else { return }
            showingAddEntry = true
            store.pendingNewItem = false
        }
    }
}

private struct LedgerRow: View {
    let entry: LedgerEntry

    private var color: Color {
        switch entry.type {
        case .revenue: OasisPalette.green
        case .expense: OasisPalette.coral
        case .cashSavings: OasisPalette.teal
        case .capacityValue: OasisPalette.indigo
        case .riskAvoidance: OasisPalette.gold
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.type == .expense ? "arrow.up.right" : "arrow.down.left")
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.description)
                        .font(.subheadline.weight(.medium))
                    Text(entry.type.title)
                        .font(.caption)
                        .foregroundStyle(color)
                }
                Text("\(entry.entityName) - \(entry.category)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(OasisFormat.currency(
                    entry.type == .expense ? -entry.amount : entry.amount,
                    code: entry.currency
                ))
                .font(.system(.body, design: .rounded).weight(.medium))
                Text(entry.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .trailing, spacing: 3) {
                StatusIndicator(
                    text: entry.confidence.rawValue.capitalized,
                    systemImage: entry.confidence == .confirmed ? "checkmark.seal.fill" : "questionmark.circle",
                    color: entry.confidence == .confirmed ? OasisPalette.green : OasisPalette.gold
                )
                Text(entry.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 125, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

private struct AddLedgerEntrySheet: View {
    @EnvironmentObject private var store: OasisStore
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var type: LedgerEntryType = .expense
    @State private var category = ""
    @State private var entityKind: LedgerEntityKind = .business
    @State private var entityName = ""
    @State private var description = ""
    @State private var amount: Decimal = 0
    @State private var currency = "USD"
    @State private var source = "Manual"
    @State private var confidence: DataConfidence = .confirmed
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Ledger Entry")
                .font(.title2.weight(.semibold))
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Type", selection: $type) {
                    ForEach(LedgerEntryType.allCases) { Text($0.title).tag($0) }
                }
                TextField("Category", text: $category)
                Picker("Entity kind", selection: $entityKind) {
                    ForEach(LedgerEntityKind.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                TextField("Entity name", text: $entityName)
                TextField("Description", text: $description)
                TextField(
                    "Amount",
                    value: $amount,
                    format: .number.precision(.fractionLength(0...2))
                )
                TextField("Currency", text: $currency)
                TextField("Source", text: $source)
                Picker("Confidence", selection: $confidence) {
                    ForEach(DataConfidence.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Entry") {
                    store.addLedgerEntry(
                        LedgerEntry(
                            date: date,
                            type: type,
                            category: category,
                            entityKind: entityKind,
                            entityName: entityName,
                            description: description,
                            amount: amount,
                            currency: currency,
                            source: source,
                            confidence: confidence,
                            notes: notes
                        )
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || amount == 0)
            }
        }
        .padding(24)
        .frame(width: 560, height: 650)
    }
}
