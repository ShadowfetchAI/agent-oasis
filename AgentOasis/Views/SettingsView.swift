import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var workspaceName = ""
    @State private var settings = WorkspaceSettings()
    @State private var showingResetConfirmation = false
    @State private var backupToRestore: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    "Settings",
                    subtitle: "Workspace identity, security timing, connector defaults, exports, and recovery."
                ) {
                    Button("Save Settings") {
                        store.updateSettings(settings, workspaceName: workspaceName)
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(alignment: .top, spacing: 14) {
                    OasisPanel {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionTitle("Workspace")
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                                GridRow {
                                    Text("Name").foregroundStyle(.secondary)
                                    TextField("Workspace name", text: $workspaceName)
                                }
                                GridRow {
                                    Text("Base currency").foregroundStyle(.secondary)
                                    TextField("Currency", text: $settings.baseCurrency)
                                        .frame(width: 90)
                                }
                                GridRow {
                                    Text("Auto-lock").foregroundStyle(.secondary)
                                    Picker("Auto-lock", selection: $settings.autoLockMinutes) {
                                        Text("5 minutes").tag(5)
                                        Text("15 minutes").tag(15)
                                        Text("30 minutes").tag(30)
                                        Text("60 minutes").tag(60)
                                    }
                                    .labelsHidden()
                                }
                                GridRow {
                                    Text("Hermes host").foregroundStyle(.secondary)
                                    TextField("SSH host", text: $settings.remoteHermesHost)
                                }
                            }
                            Toggle(
                                "Include capacity value in headline decisions",
                                isOn: $settings.showCapacityValueInHeadline
                            )
                            Text("Even when enabled, capacity value remains visually separate from realized cash.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    OasisPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionTitle(
                                "Local storage",
                                subtitle: "Encrypted workspace file"
                            )
                            Text(store.workspaceFilePath)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Divider()
                            Label(
                                "Workspace file: mode 600",
                                systemImage: "lock.fill"
                            )
                            Label(
                                "Encryption key: Keychain, this device only",
                                systemImage: "key.fill"
                            )
                            Label(
                                "Owner gate: Touch ID or Mac password",
                                systemImage: "touchid"
                            )
                        }
                        .font(.subheadline)
                    }
                }

                OasisPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(
                            "Reports and backups",
                            subtitle: "Encrypted backups remain protected; CSV exports are plaintext"
                        )
                        HStack {
                            Button {
                                store.exportBackup()
                            } label: {
                                Label("Export Encrypted Backup", systemImage: "externaldrive.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                            Button {
                                chooseBackupToRestore()
                            } label: {
                                Label("Restore Backup", systemImage: "arrow.counterclockwise")
                            }
                            Button {
                                store.exportLedgerCSV()
                            } label: {
                                Label("Export Ledger CSV", systemImage: "tablecells")
                            }
                            Button {
                                store.exportPortfolioCSV()
                            } label: {
                                Label("Export Portfolio CSV", systemImage: "square.grid.2x2")
                            }
                            Button {
                                store.exportExecutiveBrief()
                            } label: {
                                Label("Export Executive Brief", systemImage: "doc.richtext")
                            }
                            Spacer()
                        }
                        Label(
                            "CSV files are deliberately unencrypted so they can be analyzed elsewhere. Store them accordingly.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(OasisPalette.gold)
                    }
                }

                OasisPanel {
                    HStack(alignment: .top, spacing: 18) {
                        Image("BrandArtwork")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 190, height: 150)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Agent Oasis by Shadowfetch artwork")
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Agent Oasis")
                                .font(.title2.weight(.semibold))
                            Text("Private decision intelligence for apps, APIs, people, and agents.")
                                .font(.headline)
                            Text("A standalone native macOS application. It stores its workspace locally, authenticates through macOS, and does not require an Agent Oasis account or hosted service.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Version \(store.appVersionString)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Button("What’s New") { store.showingWhatsNew = true }
                                Button("Keyboard Shortcuts") { store.showingShortcutsSheet = true }
                                Link("GitHub", destination: URL(string: "https://github.com/ShadowfetchAI/agent-oasis")!)
                            }
                            .font(.caption)
                        }
                        Spacer()
                    }
                }

                OasisPanel {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Erase workspace")
                                .font(.headline)
                            Text("Deletes every app, agent, ledger entry, experiment and vault item. A copy of the current workspace is kept beside it, encrypted with the same key.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Erase Workspace…", role: .destructive) {
                            showingResetConfirmation = true
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.28))
        .onAppear {
            workspaceName = store.workspace.name
            settings = store.workspace.settings
        }
        .confirmationDialog(
            "Erase this workspace?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Erase Everything", role: .destructive) {
                store.eraseWorkspace()
                workspaceName = store.workspace.name
                settings = store.workspace.settings
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Export an encrypted backup first if you need the current records.")
        }
        .sheet(
            isPresented: Binding(
                get: { backupToRestore != nil },
                set: { if !$0 { backupToRestore = nil } }
            )
        ) {
            if let backupToRestore {
                RestoreBackupSheet(
                    filename: backupToRestore.lastPathComponent,
                    restore: { recoveryKey in
                        let restored = await store.restoreBackup(
                            from: backupToRestore,
                            recoveryKey: recoveryKey
                        )
                        if restored {
                            workspaceName = store.workspace.name
                            settings = store.workspace.settings
                        }
                        return restored
                    }
                )
            }
        }
    }

    private func chooseBackupToRestore() {
        let panel = NSOpenPanel()
        panel.title = "Restore Encrypted Agent Oasis Backup"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = []
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backupToRestore = url
    }
}

private struct RestoreBackupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let filename: String
    let restore: (String) async -> Bool
    @State private var recoveryKey = ""
    @State private var isRestoring = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Restore Encrypted Backup")
                .font(.title2.weight(.semibold))
            Text(filename)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Enter the recovery key that was shown by the workspace that created this backup. The backup is validated before the current workspace or Keychain record changes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Base64 recovery key", text: $recoveryKey)
                .textFieldStyle(.roundedBorder)
            Label(
                "Restoring replaces the current encrypted workspace after owner authentication.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(OasisPalette.gold)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(isRestoring)
                Button {
                    Task {
                        isRestoring = true
                        if await restore(recoveryKey) {
                            dismiss()
                        }
                        isRestoring = false
                    }
                } label: {
                    Label(
                        isRestoring ? "Restoring..." : "Authenticate and Restore",
                        systemImage: "touchid"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isRestoring
                )
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
