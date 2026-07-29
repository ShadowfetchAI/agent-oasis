import AppKit
import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var pulse = false
    @State private var recoveryKey = ""
    @State private var isRecovering = false

    private var isAuthenticating: Bool { store.lockState == .authenticating }

    var body: some View {
        ZStack {
            OasisBackdrop()

            VStack(spacing: 28) {
                // The mark, lit from behind so it sits IN the scene rather than on top of it.
                Image("AppMark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        OasisNeon.cyan.opacity(0.75),
                                        OasisNeon.magenta.opacity(0.6)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .neonGlow(OasisNeon.cyan, radius: pulse ? 30 : 20, intensity: 0.5)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Agent Oasis")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, OasisNeon.cyan.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text("Your encrypted operating ledger is locked.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Button {
                    Task { await store.unlock() }
                } label: {
                    Label(
                        isAuthenticating ? "Authenticating…" : "Unlock Workspace",
                        systemImage: isAuthenticating ? "hourglass" : "touchid"
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.88))
                    .frame(width: 244, height: 46)
                    .background(
                        LinearGradient(
                            colors: [OasisNeon.cyan, OasisNeon.violet.opacity(0.92)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .neonGlow(OasisNeon.cyan, radius: 18, intensity: 0.6)
                }
                .buttonStyle(.plain)
                // A dead button that opens a biometric sheet which cannot possibly succeed is
                // worse than a disabled one: the user proves who they are and is refused
                // anyway, with no clue that storage was the problem.
                .disabled(isAuthenticating || store.startupFailure != nil)
                .opacity(isAuthenticating || store.startupFailure != nil ? 0.45 : 1)

                if store.workspaceUnreadable {
                    recoveryPanel
                }

                if let failure = store.startupFailure {
                    // A broken install never gets past this screen, so the explanation has to
                    // live here rather than in an alert the user dismisses and cannot recall.
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Agent Oasis cannot save anything", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(OasisNeon.amber)
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: 460, alignment: .leading)
                    .background(OasisNeon.amber.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(OasisNeon.amber.opacity(0.35), lineWidth: 1))
                }

                VStack(spacing: 9) {
                    assurance("AES-256-GCM encrypted on disk", "lock.shield")
                    assurance("Encryption key held in this Mac's Keychain", "key.fill")
                    assurance("No account or Agent Oasis server", "externaldrive.fill.badge.checkmark")
                }
                .padding(.top, 6)
            }
            .padding(52)
        }
        .frame(minWidth: 820, minHeight: 580)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    /// The way out of an undecryptable workspace.
    ///
    /// This is the whole point of telling people to keep a backup. Without a route from the
    /// LOCKED screen, the backup was unusable in the only situation that produces it: the
    /// workspace file survived a migration and the Keychain item, being
    /// WhenUnlockedThisDeviceOnly, did not.
    private var recoveryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("This workspace cannot be opened on this Mac", systemImage: "key.slash")
                .font(.callout.weight(.semibold))
                .foregroundStyle(OasisNeon.amber)

            Text("The workspace file is intact, but this Mac's encryption key does not open "
                 + "it. This normally happens after moving to a new Mac: the file is copied "
                 + "but the key stays behind, because it is stored for this device only.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Recovery key", text: $recoveryKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))

            HStack(spacing: 10) {
                Button("Restore from backup…") { restore() }
                    .disabled(recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || isRecovering)
                Button("Set aside and start fresh") { setAside() }
                    .disabled(isRecovering)
                if isRecovering { ProgressView().controlSize(.small) }
            }
            .controlSize(.regular)

            Text("Setting aside keeps the unreadable file. Nothing is deleted, so it can still "
                 + "be opened later with the right key.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: 520, alignment: .leading)
        .background(OasisNeon.amber.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(OasisNeon.amber.opacity(0.35), lineWidth: 1))
    }

    private func restore() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Agent Oasis backup"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isRecovering = true
        Task {
            defer { isRecovering = false }
            if await store.recoverFromBackup(url: url, recoveryKey: recoveryKey) {
                recoveryKey = ""
            }
        }
    }

    private func setAside() {
        isRecovering = true
        Task {
            defer { isRecovering = false }
            _ = await store.setAsideUnreadableWorkspace()
        }
    }

    private func assurance(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(OasisNeon.cyan.opacity(0.85))
                .frame(width: 16)
            Text(text)
                .foregroundStyle(.white.opacity(0.55))
        }
        .font(.caption)
    }
}
