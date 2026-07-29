import SwiftUI

/// The cyberpunk ground the whole app sits on.
///
/// The app icon is neon cyan and magenta on near-black. The interface was white panels on a
/// white window with a green button - it ignored its own brand, and "black text on white" is
/// the one look that reads as a form rather than an instrument. This is a single reusable
/// backdrop so every surface shares one horizon instead of each view inventing its own.
///
/// Drawn, not shipped as an image: it scales to any window size, costs no bundle weight, and
/// recolours itself if the palette moves. The grid is deliberately faint - it should register
/// as depth at a glance and never compete with a number.
struct OasisBackdrop: View {
    /// Animate the glow. Off for previews, screenshots and reduced-motion.
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift: CGFloat = 0

    private var shouldAnimate: Bool { animated && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Base: deep blue-black, never pure #000 - pure black kills the glow and
                // flattens every material stacked on top of it.
                LinearGradient(
                    colors: [
                        Color(red: 0.031, green: 0.039, blue: 0.071),
                        Color(red: 0.055, green: 0.055, blue: 0.102),
                        Color(red: 0.024, green: 0.031, blue: 0.055)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Neon bloom, pulled straight from the app icon.
                RadialGradient(
                    colors: [OasisNeon.cyan.opacity(0.28), .clear],
                    center: UnitPoint(x: 0.08 + drift * 0.04, y: 0.04),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.72
                )
                RadialGradient(
                    colors: [OasisNeon.magenta.opacity(0.22), .clear],
                    center: UnitPoint(x: 0.94 - drift * 0.04, y: 0.92),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.68
                )
                RadialGradient(
                    colors: [OasisNeon.violet.opacity(0.16), .clear],
                    center: UnitPoint(x: 0.62, y: 0.34 + drift * 0.03),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.5
                )

                OasisGrid(spacing: 46)
                    .stroke(OasisNeon.cyan.opacity(0.055), lineWidth: 0.6)

                // Vignette, so panels near the edges keep their contrast.
                RadialGradient(
                    colors: [.clear, .black.opacity(0.42)],
                    center: .center,
                    startRadius: min(w, h) * 0.28,
                    endRadius: max(w, h) * 0.78
                )
            }
            .ignoresSafeArea()
            .onAppear {
                guard shouldAnimate else { return }
                withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                    drift = 1
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Neon accents taken from the Agent Oasis icon.
enum OasisNeon {
    static let cyan = Color(red: 0.24, green: 0.86, blue: 0.94)
    static let magenta = Color(red: 0.94, green: 0.38, blue: 0.85)
    static let violet = Color(red: 0.55, green: 0.42, blue: 0.98)
    static let lime = Color(red: 0.45, green: 0.94, blue: 0.62)
    static let amber = Color(red: 1.00, green: 0.76, blue: 0.33)
}

/// A faint perspective-free grid. Cheap to draw and resolution independent.
struct OasisGrid: Shape {
    var spacing: CGFloat = 44

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard spacing > 0 else { return path }
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

extension View {
    /// Neon rim + outer glow for anything that should read as energised.
    func neonGlow(_ color: Color, radius: CGFloat = 14, intensity: Double = 0.55) -> some View {
        shadow(color: color.opacity(intensity), radius: radius)
            .shadow(color: color.opacity(intensity * 0.45), radius: radius * 2.2)
    }
}
