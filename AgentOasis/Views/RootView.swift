import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: OasisStore
    @EnvironmentObject private var activityMonitor: UserActivityMonitor
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isDropTargeted = false

    private let lockTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.isUnlocked {
                unlockedContent
            } else {
                UnlockView()
            }
        }
        .alert(
            "Agent Oasis",
            isPresented: Binding(
                get: { store.errorMessage != nil || store.noticeMessage != nil },
                set: { visible in
                    if !visible {
                        store.errorMessage = nil
                        store.noticeMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                store.errorMessage = nil
                store.noticeMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? store.noticeMessage ?? "")
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $store.showingCommandPalette) {
            CommandPaletteView()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.showingShortcutsSheet) {
            KeyboardShortcutsSheet()
        }
        .sheet(isPresented: $store.showingWhatsNew, onDismiss: {
            store.markReleaseNotesSeen(store.marketingVersion)
        }) {
            WhatsNewSheet()
        }
        .sheet(isPresented: Binding(
            get: { store.pendingImportURL != nil && store.pendingImportSummary != nil },
            set: { visible in
                if !visible { store.cancelImportPreview() }
            }
        )) {
            if let url = store.pendingImportURL, let summary = store.pendingImportSummary {
                ImportPreviewSheet(url: url, summary: summary)
                    .environmentObject(store)
            }
        }
#if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--demo-unlocked"),
                  store.lockState == .locked else { return }
            await store.unlock()
        }
#endif
        .onReceive(lockTimer) { now in
            guard store.isUnlocked else { return }
            let threshold = TimeInterval(store.workspace.settings.autoLockMinutes * 60)
            if now.timeIntervalSince(activityMonitor.lastActivity) >= threshold {
                store.lock(reason: "Locked after inactivity")
            }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.willSleepNotification
            )
        ) { _ in
            store.lock(reason: "Locked before system sleep")
        }
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: Notification.Name("com.apple.screenIsLocked")
            )
        ) { _ in
            store.lock(reason: "Locked with the Mac screen")
        }
        .onChange(of: store.lockState) { _, newValue in
            if newValue == .unlocked, store.shouldShowWhatsNewOnUnlock() {
                store.showingWhatsNew = true
            }
        }
    }

    private var unlockedContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 224, ideal: 248, max: 300)
        } detail: {
            detail
                .background(OasisBackdrop())
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(OasisPalette.teal, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                            .padding(12)
                            .overlay {
                                Text("Drop CSV or TSV to preview import")
                                    .font(.headline)
                                    .padding(12)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.showingCommandPalette = true
                } label: {
                    Label("Command Palette", systemImage: "command")
                }
                .help("Open command palette (⌘K)")

                Menu {
                    Button("Import Report…") { store.requestImportPicker() }
                    Divider()
                    Button("Export Ledger CSV") { store.exportLedgerCSV() }
                    Button("Export Portfolio CSV") { store.exportPortfolioCSV() }
                    Button("Export Encrypted Backup") { store.exportBackup() }
                } label: {
                    Label("Import / Export", systemImage: "square.and.arrow.up.on.square")
                }

                Button {
                    store.lock(reason: "Locked by user")
                } label: {
                    Image(systemName: "lock")
                }
                .help("Lock Agent Oasis")
            }
        }
    }

    private var sidebar: some View {
        List(
            selection: Binding<AppSection?>(
                get: { store.selection },
                set: { if let value = $0 { store.selection = value } }
            )
        ) {
            Section {
                sidebarItem(.commandCenter)
            }
            Section("Intelligence") {
                sidebarItem(.portfolio)
                sidebarItem(.agents)
                sidebarItem(.ledger)
                sidebarItem(.experiments)
            }
            Section("System") {
                sidebarItem(.connections)
                sidebarItem(.vault)
                sidebarItem(.audit)
            }
            Section {
                sidebarItem(.settings)
            }
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Local workspace", systemImage: "lock.fill")
                        .foregroundStyle(OasisPalette.green)
                    Text("Updated \(OasisFormat.relative(store.workspace.updatedAt))")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.vertical, 3)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .navigationTitle("Agent Oasis")
    }

    private func sidebarItem(_ section: AppSection) -> some View {
        Label {
            Text(section.title)
                .font(.system(size: 13, weight: store.selection == section ? .semibold : .regular))
        } icon: {
            Image(systemName: section.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(store.selection == section ? OasisPalette.teal : .secondary)
        }
        .padding(.vertical, 2)
        .tag(section)
    }

    @ViewBuilder
    private var detail: some View {
        switch store.selection {
        case .commandCenter:
            CommandCenterView()
        case .portfolio:
            PortfolioView()
        case .agents:
            AgentsView()
        case .ledger:
            LedgerView()
        case .experiments:
            ExperimentsView()
        case .connections:
            ConnectionsView()
        case .vault:
            VaultView()
        case .audit:
            AuditView()
        case .settings:
            SettingsView()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let value = item as? URL {
                url = value
            } else {
                url = nil
            }
            guard let url else { return }
            DispatchQueue.main.async {
                store.beginImportPreview(from: url)
            }
        }
        return true
    }
}
