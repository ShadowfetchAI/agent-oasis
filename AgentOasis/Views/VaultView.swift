import AppKit
import SwiftUI

struct VaultView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var showingAddSecret = false
    @State private var recoveryKey: String?
    @State private var secretToDelete: VaultItem?
    @State private var isAuthenticatingRecovery = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    "Vault",
                    subtitle: "Encrypted secrets, recovery control, and credential hygiene."
                ) {
                    HStack {
                        Button {
                            importSecretFile()
                        } label: {
                            Label("Import Key File", systemImage: "doc.badge.plus")
                        }
                        Button {
                            showingAddSecret = true
                        } label: {
                            Label("Add Secret", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                    spacing: 12
                ) {
                    MetricTile(
                        title: "Encryption",
                        value: "AES-256",
                        detail: "Authenticated GCM encryption at rest",
                        systemImage: "lock.shield.fill",
                        color: OasisPalette.green
                    )
                    MetricTile(
                        title: "Stored secrets",
                        value: String(store.workspace.vaultItems.count),
                        detail: "Values excluded from audit text",
                        systemImage: "key.fill",
                        color: OasisPalette.gold
                    )
                    MetricTile(
                        title: "Indexed files",
                        value: String(store.workspace.credentialInventory.count),
                        detail: "Metadata only; values were not read",
                        systemImage: "doc.text.magnifyingglass",
                        color: OasisPalette.teal
                    )
                    MetricTile(
                        title: "Workspace",
                        value: "Local only",
                        detail: "No Agent Oasis account or server",
                        systemImage: "externaldrive.fill.badge.checkmark",
                        color: OasisPalette.indigo
                    )
                }

                OasisPanel {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "key.radiowaves.forward.fill")
                            .font(.title)
                            .foregroundStyle(OasisPalette.gold)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Recovery key")
                                .font(.headline)
                            Text("The encrypted backup is only useful with this 256-bit key. Reveal it only when you are ready to store it somewhere separate from the backup.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button {
                            revealRecoveryKey()
                        } label: {
                            Label(
                                isAuthenticatingRecovery ? "Authenticating..." : "Reveal Recovery Key",
                                systemImage: "touchid"
                            )
                        }
                        .disabled(isAuthenticatingRecovery)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(
                        "Encrypted records",
                        subtitle: "Secret values remain masked and are never written to the audit log"
                    )
                    if store.workspace.vaultItems.isEmpty {
                        OasisPanel {
                            Text("No secrets have been stored yet.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 70)
                        }
                    } else {
                        ForEach(store.workspace.vaultItems) { item in
                            OasisPanel {
                                HStack {
                                    Image(systemName: vaultIcon(item.kind))
                                        .font(.title2)
                                        .foregroundStyle(OasisPalette.gold)
                                        .frame(width: 34)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.label)
                                            .font(.headline)
                                        Text("\(item.service) - \(item.account)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(item.maskedHint)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(item.kind.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button(role: .destructive) {
                                        secretToDelete = item
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .help("Remove encrypted record")
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionTitle(
                            "Credential inventory",
                            subtitle: "File metadata and permissions; contents are not opened"
                        )
                        Spacer()
                        Button {
                            indexKnownCredentialFolder()
                        } label: {
                            Label("Index Shadowfetch Folder", systemImage: "folder.badge.gearshape")
                        }
                        Button {
                            chooseCredentialFolder()
                        } label: {
                            Label("Choose Folder", systemImage: "folder")
                        }
                    }

                    OasisPanel {
                        if store.workspace.credentialInventory.isEmpty {
                            Text("No credential folder has been indexed.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 70)
                        } else {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Service").frame(width: 180, alignment: .leading)
                                    Text("File").frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Size").frame(width: 75, alignment: .trailing)
                                    Text("Mode").frame(width: 60, alignment: .trailing)
                                    Text("Modified").frame(width: 120, alignment: .trailing)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 8)
                                ForEach(store.workspace.credentialInventory.prefix(500)) { item in
                                    Divider()
                                    HStack {
                                        Text(item.service)
                                            .frame(width: 180, alignment: .leading)
                                            .lineLimit(1)
                                        Text(item.filename)
                                            .font(.system(.caption, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .lineLimit(1)
                                        Text(ByteCountFormatter.string(
                                            fromByteCount: item.fileSize,
                                            countStyle: .file
                                        ))
                                        .frame(width: 75, alignment: .trailing)
                                        Text(item.posixPermissions)
                                            .foregroundStyle(
                                                ["600", "640"].contains(item.posixPermissions)
                                                    ? OasisPalette.green
                                                    : OasisPalette.coral
                                            )
                                            .frame(width: 60, alignment: .trailing)
                                        Text(item.modifiedAt.map {
                                            OasisFormat.relative($0)
                                        } ?? "Unknown")
                                        .frame(width: 120, alignment: .trailing)
                                    }
                                    .font(.caption)
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.28))
        .sheet(isPresented: $showingAddSecret) {
            AddSecretSheet()
                .environmentObject(store)
        }
        .sheet(
            isPresented: Binding(
                get: { recoveryKey != nil },
                set: { if !$0 { recoveryKey = nil } }
            )
        ) {
            if let recoveryKey {
                RecoveryKeySheet(key: recoveryKey)
            }
        }
        .alert(
            "Remove Secret?",
            isPresented: Binding(
                get: { secretToDelete != nil },
                set: { if !$0 { secretToDelete = nil } }
            ),
            presenting: secretToDelete
        ) { item in
            Button("Remove", role: .destructive) {
                store.deleteVaultItem(id: item.id)
                secretToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                secretToDelete = nil
            }
        } message: { item in
            Text("This permanently removes \(item.label) from the encrypted workspace.")
        }
    }

    private func revealRecoveryKey() {
        isAuthenticatingRecovery = true
        Task {
            defer { isAuthenticatingRecovery = false }
            do {
                try await DeviceOwnerAuthenticator.authenticate(
                    reason: "Reveal the Agent Oasis recovery key."
                )
                recoveryKey = store.recoveryKeyString()
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseCredentialFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Credential Folder to Index"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.scanCredentialInventory(folder: url) }
    }

    private func indexKnownCredentialFolder() {
        let url = URL(fileURLWithPath: "/Volumes/NVME1TB/Shadowfetch/Credentials", isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            store.errorMessage = "The Shadowfetch credential folder is not currently mounted."
            return
        }
        Task { await store.scanCredentialInventory(folder: url) }
    }

    private func importSecretFile() {
        let panel = NSOpenPanel()
        panel.title = "Import a Key or Secret File"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let value = try String(contentsOf: url, encoding: .utf8)
            store.addVaultItem(
                VaultItem(
                    label: url.deletingPathExtension().lastPathComponent,
                    service: url.deletingLastPathComponent().lastPathComponent,
                    account: "",
                    kind: url.pathExtension.lowercased() == "p8" ? .privateKey : .apiKey,
                    secret: value,
                    createdAt: Date(),
                    updatedAt: Date(),
                    notes: "Imported from a user-selected file."
                )
            )
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func vaultIcon(_ kind: VaultItemKind) -> String {
        switch kind {
        case .apiKey: "key.horizontal.fill"
        case .privateKey: "doc.text.fill"
        case .token: "ticket.fill"
        case .password: "ellipsis.rectangle"
        case .account: "person.crop.circle.fill"
        case .recovery: "lifepreserver.fill"
        }
    }
}

private struct AddSecretSheet: View {
    @EnvironmentObject private var store: OasisStore
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var service = ""
    @State private var account = ""
    @State private var kind: VaultItemKind = .apiKey
    @State private var secret = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Encrypted Secret")
                .font(.title2.weight(.semibold))
            Form {
                TextField("Label", text: $label)
                TextField("Service", text: $service)
                TextField("Account", text: $account)
                Picker("Kind", selection: $kind) {
                    ForEach(VaultItemKind.allCases) { item in
                        Text(item.rawValue.capitalized).tag(item)
                    }
                }
                SecureField("Secret value", text: $secret)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .formStyle(.grouped)
            Label(
                "The value is encrypted before it is written to disk and is omitted from audit messages.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Store Secret") {
                    store.addVaultItem(
                        VaultItem(
                            label: label,
                            service: service,
                            account: account,
                            kind: kind,
                            secret: secret,
                            createdAt: Date(),
                            updatedAt: Date(),
                            notes: notes
                        )
                    )
                    secret = ""
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.isEmpty || service.isEmpty || secret.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540, height: 520)
    }
}

private struct RecoveryKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    let key: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Recovery Key", systemImage: "key.radiowaves.forward.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(OasisPalette.gold)
            Text("Store this separately from your encrypted backup. Anyone with both files can open the workspace.")
                .foregroundStyle(.secondary)
            Text(key)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                )
            HStack {
                Spacer()
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(key, forType: .string)
                    let changeCount = pasteboard.changeCount
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                        if pasteboard.changeCount == changeCount {
                            pasteboard.clearContents()
                        }
                    }
                } label: {
                    Label(copied ? "Copied for 60 Seconds" : "Copy Key", systemImage: "doc.on.doc")
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 620)
    }
}
