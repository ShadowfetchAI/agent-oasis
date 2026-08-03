import AppKit
import CryptoKit
import SwiftUI

@main
struct AgentOasisApp: App {
    @NSApplicationDelegateAdaptor(AgentOasisAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        WindowGroup("Agent Oasis") {
            RootView()
                .environmentObject(appDelegate.store)
                .environmentObject(appDelegate.activityMonitor)
                .frame(minWidth: 1_140, minHeight: 720)
        }
        .defaultSize(width: 1_360, height: 860)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New…") {
                    appDelegate.ensureMainWindow()
                    appDelegate.store.requestNewItem()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!appDelegate.store.isUnlocked)
            }
            CommandGroup(after: .saveItem) {
                Button("Import Report…") {
                    appDelegate.ensureMainWindow()
                    appDelegate.store.requestImportPicker()
                }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(!appDelegate.store.isUnlocked)

                Button("Export Ledger CSV") {
                    appDelegate.ensureMainWindow()
                    appDelegate.store.exportLedgerCSV()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!appDelegate.store.isUnlocked)

                Button("Export Encrypted Backup") {
                    appDelegate.ensureMainWindow()
                    appDelegate.store.exportBackup()
                }
                .disabled(!appDelegate.store.isUnlocked)

                Button("Export Executive Brief") {
                    appDelegate.ensureMainWindow()
                    appDelegate.store.exportExecutiveBrief()
                }
                .disabled(!appDelegate.store.isUnlocked)

                Divider()

                Button("Lock Agent Oasis") {
                    appDelegate.store.lock(reason: "Locked by keyboard command")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!appDelegate.store.isUnlocked)
            }
            CommandGroup(after: .appInfo) {
                Button("What’s New in Agent Oasis") {
                    appDelegate.ensureMainWindow()
                    appDelegate.store.showingWhatsNew = true
                }
                .disabled(!appDelegate.store.isUnlocked)
            }
            CommandMenu("Workspace") {
                Button("Command Palette…") {
                    appDelegate.ensureMainWindow()
                    appDelegate.store.showingCommandPalette = true
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!appDelegate.store.isUnlocked)

                Button("Keyboard Shortcuts") {
                    appDelegate.ensureMainWindow()
                    appDelegate.store.showingShortcutsSheet = true
                }
                .keyboardShortcut("/", modifiers: .command)
                .disabled(!appDelegate.store.isUnlocked)

                Divider()

                ForEach(AppSection.allCases) { section in
                    if let index = section.keyboardIndex {
                        Button(section.title) {
                            appDelegate.ensureMainWindow()
                            appDelegate.store.selection = section
                        }
                        .keyboardShortcut(
                            KeyEquivalent(Character(String(index))),
                            modifiers: .command
                        )
                        .disabled(!appDelegate.store.isUnlocked)
                    } else {
                        Button(section.title) {
                            appDelegate.ensureMainWindow()
                            appDelegate.store.selection = section
                        }
                        .disabled(!appDelegate.store.isUnlocked)
                    }
                }
            }
        }
    }
}

@MainActor
final class AgentOasisAppDelegate: NSObject, NSApplicationDelegate {
    let store: OasisStore
    let activityMonitor = UserActivityMonitor()
    private var fallbackWindow: NSWindow?

    override init() {
#if DEBUG
        store = PreviewWorkspaceBootstrap.makeIfRequested(
            arguments: ProcessInfo.processInfo.arguments
        ) ?? OasisStore()
#else
        store = OasisStore()
#endif
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.ensureMainWindow()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        ensureMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func ensureMainWindow() {
        if let fallbackWindow {
            fallbackWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let visibleWindow = NSApp.windows.first(where: {
            $0.isVisible && $0.canBecomeMain
        }) {
            visibleWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let size = NSSize(
            width: min(1_360, max(1_140, visibleFrame.width * 0.92)),
            height: min(860, max(720, visibleFrame.height * 0.92))
        )
        let frame = NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let root = RootView()
            .environmentObject(store)
            .environmentObject(activityMonitor)
            .frame(minWidth: 1_140, minHeight: 720)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        window.title = "Agent Oasis"
        window.minSize = NSSize(width: 1_140, height: 720)
        window.toolbarStyle = .unified
        window.contentViewController = NSHostingController(rootView: root)
        window.isReleasedWhenClosed = false
        fallbackWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

#if DEBUG
/// Loads an external JSON fixture into an isolated encrypted workspace for visual QA.
/// No fixture records or bypass path are compiled into Release builds.
@MainActor
private enum PreviewWorkspaceBootstrap {
    static func makeIfRequested(arguments: [String]) -> OasisStore? {
        guard let fixtureIndex = arguments.firstIndex(of: "--preview-workspace-json") else {
            return nil
        }
        guard arguments.indices.contains(fixtureIndex + 1) else {
            preconditionFailure("--preview-workspace-json requires a file path")
        }

        do {
            let fixtureURL = URL(fileURLWithPath: arguments[fixtureIndex + 1])
            let storageURL: URL
            if let storageIndex = arguments.firstIndex(of: "--preview-storage"),
               arguments.indices.contains(storageIndex + 1) {
                storageURL = URL(fileURLWithPath: arguments[storageIndex + 1])
            } else {
                storageURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("AgentOasisPreview-\(UUID().uuidString)", isDirectory: true)
            }

            let data = try Data(contentsOf: fixtureURL)
            let decoder = JSONDecoder()
            var workspace = try decoder.decode(WorkspaceState.self, from: data)
            workspace.settings.lastSeenReleaseNotes = "3.0.1"

            let keyMaterial = Data(SHA256.hash(
                data: Data("agent-oasis-isolated-preview-v1".utf8)
            ))
            let key = SymmetricKey(data: keyMaterial)
            let repository = try EncryptedWorkspaceRepository(baseDirectory: storageURL)
            try repository.save(workspace, using: key)

            let store = OasisStore(
                repository: repository,
                keyProvider: { _ in key },
                ownerAuthenticator: { _ in nil }
            )
            if let sectionIndex = arguments.firstIndex(of: "--preview-section"),
               arguments.indices.contains(sectionIndex + 1),
               let section = AppSection(rawValue: arguments[sectionIndex + 1]) {
                store.selection = section
            }
            return store
        } catch {
            preconditionFailure("Could not create isolated preview workspace: \(error)")
        }
    }
}
#endif

@MainActor
final class UserActivityMonitor: ObservableObject {
    @Published private(set) var lastActivity = Date()
    private var monitor: Any?

    init() {
        let mask: NSEvent.EventTypeMask = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .mouseMoved,
            .scrollWheel
        ]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.lastActivity = Date()
            return event
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
