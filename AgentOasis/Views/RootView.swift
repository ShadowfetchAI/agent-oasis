import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: OasisStore
    @EnvironmentObject private var activityMonitor: UserActivityMonitor
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
        // README: "For UI validation without an authentication dialog, Debug builds accept
        // the --demo-unlocked launch argument." It still required a click, which defeats
        // automated UI capture. Debug-only and compiled out of Release, exactly as before.
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
    }

    private var unlockedContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 224, ideal: 248, max: 300)
        } detail: {
            detail
                // A quiet backdrop so the material panels have something to sit ON. Flat
                // opaque panels on a flat opaque window is what made this read as a form
                // rather than an instrument; depth is what a 2026 macOS app gets for free
                // from materials, and materials need a ground to be translucent against.
                .background(OasisBackdrop())
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    importReport()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import a sales or ledger report")

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

    private func importReport() {
        let panel = NSOpenPanel()
        panel.title = "Import Agent Oasis Data"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = []
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.importData(from: url)
    }
}
