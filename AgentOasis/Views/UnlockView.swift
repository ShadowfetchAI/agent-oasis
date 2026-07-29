import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var store: OasisStore

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Image("AppMark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 124, height: 124)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Agent Oasis")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Your encrypted operating ledger is locked.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await store.unlock() }
                } label: {
                    Label(
                        store.lockState == .authenticating ? "Authenticating..." : "Unlock Workspace",
                        systemImage: "touchid"
                    )
                    .frame(width: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.lockState == .authenticating)

                VStack(spacing: 7) {
                    Label("AES-256-GCM encrypted on disk", systemImage: "lock.shield")
                    Label("Encryption key held in this Mac's Keychain", systemImage: "key.fill")
                    Label("No account or Agent Oasis server", systemImage: "externaldrive.fill.badge.checkmark")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            }
            .padding(48)
        }
        .frame(minWidth: 780, minHeight: 540)
    }
}
