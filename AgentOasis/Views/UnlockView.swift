import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var store: OasisStore
    @State private var pulse = false

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
                .disabled(isAuthenticating)
                .opacity(isAuthenticating ? 0.65 : 1)

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
