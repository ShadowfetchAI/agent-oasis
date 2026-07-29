import AppKit
import SwiftUI

struct ConnectionsView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var editingConnection: ConnectionProfile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    "Connections",
                    subtitle: "Brokered data access with explicit read/write boundaries and freshness."
                ) {
                    StatusIndicator(
                        text: "Secrets stay inside the encrypted workspace",
                        systemImage: "lock.shield.fill",
                        color: OasisPalette.green
                    )
                }

                OasisPanel {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.title)
                            .foregroundStyle(OasisPalette.teal)
                            .frame(width: 42)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Credential broker")
                                .font(.headline)
                            Text("Connectors receive only the secret they need, perform a bounded operation, and return normalized records. Agent prompts and audit summaries never receive raw secret values.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(spacing: 12) {
                    ForEach(store.workspace.connections) { connection in
                        ConnectionRow(
                            connection: connection,
                            isSyncingHermes: store.isSyncingHermes,
                            isSyncingApple: store.isSyncingApple,
                            configure: { editingConnection = connection },
                            primaryAction: { runPrimaryAction(connection) }
                        )
                    }
                }

                OasisPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(
                            "Normalization contract",
                            subtitle: "Every imported observation keeps its origin and confidence"
                        )
                        HStack(spacing: 22) {
                            NormalizationItem(
                                icon: "calendar",
                                title: "Observation time",
                                detail: "Source date and import time"
                            )
                            NormalizationItem(
                                icon: "dollarsign.circle",
                                title: "Currency",
                                detail: "Original currency retained"
                            )
                            NormalizationItem(
                                icon: "checkmark.seal",
                                title: "Confidence",
                                detail: "Known, estimated, inferred, unknown"
                            )
                            NormalizationItem(
                                icon: "number",
                                title: "Evidence hash",
                                detail: "Audit identity without secret content"
                            )
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.28))
        .sheet(item: $editingConnection) { connection in
            ConnectionEditor(connection: connection)
                .environmentObject(store)
        }
    }

    private func runPrimaryAction(_ connection: ConnectionProfile) {
        switch connection.kind {
        case .hermesFleet:
            Task { await store.syncHermesFleet() }
        case .appStoreConnect:
            let keyID = connection.configuration["keyID", default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if connection.secretItemID != nil, !keyID.isEmpty {
                Task { await store.syncAppStoreConnect() }
            } else {
                editingConnection = connection
            }
        case .delimitedFiles:
            let panel = NSOpenPanel()
            panel.title = "Import Sales or Ledger Report"
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.allowedContentTypes = []
            guard panel.runModal() == .OK, let url = panel.url else { return }
            store.importData(from: url)
        case .credentialIndex:
            let panel = NSOpenPanel()
            panel.title = "Choose Credential Folder to Index"
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            guard panel.runModal() == .OK, let folder = panel.url else { return }
            Task { await store.scanCredentialInventory(folder: folder) }
        case .manual:
            store.selection = .ledger
        case .website, .linux:
            editingConnection = connection
        }
    }
}

private struct ConnectionRow: View {
    let connection: ConnectionProfile
    let isSyncingHermes: Bool
    let isSyncingApple: Bool
    let configure: () -> Void
    let primaryAction: () -> Void

    private var icon: String {
        switch connection.kind {
        case .appStoreConnect: "apple.logo"
        case .hermesFleet: "cpu"
        case .delimitedFiles: "tablecells"
        case .credentialIndex: "key.horizontal"
        case .manual: "square.and.pencil"
        case .website: "globe"
        case .linux: "terminal"
        }
    }

    private var actionTitle: String {
        switch connection.kind {
        case .hermesFleet: isSyncingHermes ? "Syncing..." : "Sync Now"
        case .appStoreConnect:
            if connection.secretItemID == nil
                || connection.configuration["keyID", default: ""].isEmpty {
                "Set Up"
            } else {
                isSyncingApple ? "Syncing..." : "Sync Apps"
            }
        case .delimitedFiles: "Import Report"
        case .credentialIndex: "Index Folder"
        case .manual: "Open Ledger"
        case .website, .linux: "Configure"
        }
    }

    var body: some View {
        OasisPanel {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(connection.status.color)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 38, height: 38)
                    .background(connection.status.color.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(connection.name)
                            .font(.headline)
                        StatusIndicator(
                            text: connection.status.title,
                            systemImage: connection.status.systemImage,
                            color: connection.status.color
                        )
                    }
                    Text(connection.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Label(connection.accessMode.title, systemImage: "hand.raised.fill")
                        Label(connection.endpoint, systemImage: "network")
                        Label("\(connection.recordsImported) records", systemImage: "tray.full")
                        Label(OasisFormat.relative(connection.lastSync), systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 18)

                HStack {
                    Button(action: configure) {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help("Configure connection")
                    Button(actionTitle, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            (isSyncingHermes && connection.kind == .hermesFleet)
                                || (isSyncingApple && connection.kind == .appStoreConnect)
                        )
                }
            }
        }
    }
}

private struct NormalizationItem: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(OasisPalette.teal)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConnectionEditor: View {
    @EnvironmentObject private var store: OasisStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ConnectionProfile

    init(connection: ConnectionProfile) {
        _draft = State(initialValue: connection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Configure \(draft.kind.title)")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $draft.name)
                TextField("Endpoint or SSH host", text: $draft.endpoint)
                Picker("Access", selection: $draft.accessMode) {
                    ForEach(AccessMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Secret", selection: $draft.secretItemID) {
                    Text("No secret selected").tag(UUID?.none)
                    ForEach(store.workspace.vaultItems) { item in
                        Text("\(item.service) - \(item.label)").tag(Optional(item.id))
                    }
                }
                if draft.kind == .appStoreConnect {
                    TextField(
                        "Issuer ID (blank for an individual key)",
                        text: configurationBinding("issuerID")
                    )
                    TextField(
                        "Key ID",
                        text: configurationBinding("keyID")
                    )
                    TextField(
                        "Vendor number",
                        text: configurationBinding("vendorNumber")
                    )
                }
                TextField("Notes", text: $draft.notes, axis: .vertical)
            }
            .formStyle(.grouped)

            Label(
                draft.accessMode == .readOnly
                    ? "This connection is constrained to read-only operations."
                    : "Review write access carefully before enabling automated actions.",
                systemImage: draft.accessMode == .readOnly ? "eye.fill" : "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(draft.accessMode == .readOnly ? OasisPalette.green : OasisPalette.gold)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if draft.kind == .hermesFleet {
                        var settings = store.workspace.settings
                        settings.remoteHermesHost = draft.endpoint
                        store.updateSettings(settings, workspaceName: store.workspace.name)
                    }
                    if draft.kind == .appStoreConnect {
                        draft.accessMode = .readOnly
                        let hasKeyID = !draft.configuration["keyID", default: ""]
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                        draft.status = draft.secretItemID != nil && hasKeyID
                            ? .stale
                            : .needsSetup
                    } else if draft.kind == .hermesFleet {
                        draft.accessMode = .readOnly
                    }
                    store.updateConnection(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560, height: draft.kind == .appStoreConnect ? 600 : 480)
    }

    private func configurationBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { draft.configuration[key, default: ""] },
            set: { draft.configuration[key] = $0 }
        )
    }
}
