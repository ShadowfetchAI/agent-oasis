import SwiftUI

struct AuditView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var search = ""
    @State private var category = "All"

    private var categories: [String] {
        ["All"] + Array(Set(store.workspace.audit.map(\.category))).sorted()
    }

    private var events: [AuditEvent] {
        store.workspace.audit
            .filter {
                (category == "All" || $0.category == category)
                    && (search.isEmpty
                        || $0.action.localizedCaseInsensitiveContains(search)
                        || $0.entityName.localizedCaseInsensitiveContains(search)
                        || $0.summary.localizedCaseInsensitiveContains(search))
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                "Audit",
                subtitle: "Append-only evidence of workspace changes without credential values."
            ) {
                StatusIndicator(
                    text: "\(store.workspace.audit.count) events",
                    systemImage: "checkmark.seal.fill",
                    color: OasisPalette.green
                )
            }
            .padding(24)

            Divider()

            HStack {
                TextField("Search audit trail", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 190)
                Spacer()
                Text("Secrets are redacted by design")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)

            Divider()

            if events.isEmpty {
                EmptyStateView(
                    title: "No Matching Audit Events",
                    message: "Change the search or category filter.",
                    systemImage: "checkmark.seal"
                )
            } else {
                List(events) { event in
                    AuditEventRow(event: event)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct AuditEventRow: View {
    let event: AuditEvent

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.action)
                        .font(.subheadline.weight(.medium))
                    Text(event.category)
                        .font(.caption)
                        .foregroundStyle(color)
                }
                Text(event.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(event.entityName)
                    Text(event.actor)
                    // Full digest is 64 hex chars; show a readable prefix and put
                    // the whole thing behind a tooltip and in the accessibility label.
                    Text(event.evidenceHash.prefix(16))
                        .help(event.evidenceHash)
                        .accessibilityLabel("Evidence hash \(event.evidenceHash)")
                        .font(.system(.caption2, design: .monospaced))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(event.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 115, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    private var icon: String {
        switch event.category {
        case "Security", "Vault": "lock.shield.fill"
        case "Import", "Export", "Backup": "tray.and.arrow.down.fill"
        case "Connection": "point.3.connected.trianglepath.dotted"
        case "Experiment": "flask.fill"
        case "Agent": "cpu"
        default: "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch event.category {
        case "Security", "Vault": OasisPalette.gold
        case "Connection": OasisPalette.teal
        case "Experiment": OasisPalette.indigo
        case "Agent": OasisPalette.green
        default: .secondary
        }
    }
}
