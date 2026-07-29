import AppKit
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
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .saveItem) {
                Button("Lock Agent Oasis") {
                    appDelegate.store.lock(reason: "Locked by keyboard command")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!appDelegate.store.isUnlocked)
                Divider()
                Button("Export Encrypted Backup") {
                    appDelegate.store.exportBackup()
                }
                .disabled(!appDelegate.store.isUnlocked)
            }
            CommandMenu("Workspace") {
                ForEach(AppSection.allCases) { section in
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

@MainActor
final class AgentOasisAppDelegate: NSObject, NSApplicationDelegate {
    let store = OasisStore()
    let activityMonitor = UserActivityMonitor()
    private var fallbackWindow: NSWindow?

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
