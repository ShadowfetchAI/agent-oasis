import AppKit
import Charts
import SwiftUI

/// Colour roles for Agent Oasis.
///
/// The previous palette was six fixed RGB triples that rendered identically in light and dark
/// mode, so dark mode got light-mode's saturation and everything sat flat on an opaque panel.
/// These adapt per appearance, and the semantic names below (`cash`, `modeled`) exist because
/// this app's central distinction is between money that moved and money someone estimated -
/// if that difference is real it should be visible before a label is read.
enum OasisPalette {
    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
    }

    static let teal = adaptive(light: (0.05, 0.47, 0.58), dark: (0.36, 0.79, 0.88))
    static let coral = adaptive(light: (0.83, 0.27, 0.24), dark: (1.00, 0.48, 0.44))
    static let gold = adaptive(light: (0.76, 0.55, 0.09), dark: (0.99, 0.80, 0.36))
    static let green = adaptive(light: (0.13, 0.55, 0.32), dark: (0.42, 0.85, 0.57))
    static let indigo = adaptive(light: (0.28, 0.31, 0.68), dark: (0.62, 0.65, 0.99))
    static let ink = adaptive(light: (0.09, 0.11, 0.13), dark: (0.93, 0.94, 0.96))

    /// Money that actually moved.
    static let cash = green
    /// Estimated value. Deliberately a different hue family from cash, never a shade of it.
    static let modeled = indigo

    static func accentGradient(_ base: Color) -> LinearGradient {
        LinearGradient(
            colors: [base.opacity(0.95), base.opacity(0.62)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Shared geometry. One place, so panels, tiles and badges stay on the same rhythm.
enum OasisMetrics {
    static let corner: CGFloat = 14
    static let tightCorner: CGFloat = 10
    static let panelPadding: CGFloat = 18
    static let gutter: CGFloat = 16
}

extension View {
    /// The standard raised surface: material, hairline, soft shadow, continuous corners.
    func oasisSurface(
        corner: CGFloat = OasisMetrics.corner,
        elevated: Bool = true
    ) -> some View {
        background(.thickMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.separator.opacity(0.40), lineWidth: 0.5)
            )
            .shadow(
                color: .black.opacity(elevated ? 0.20 : 0),
                radius: elevated ? 16 : 0,
                x: 0,
                y: elevated ? 8 : 0
            )
    }
}

/// Says where a number came from, in one glance.
///
/// This is the whole audit finding rendered as a control. An ROI figure with no provenance
/// beside it invites a reader to treat a typed hourly rate exactly like an imported invoice,
/// and the fix is not a disclaimer in the docs - it is making the difference impossible to
/// miss at the point the number is read.
struct ProvenanceBadge: View {
    let provenance: ValueProvenance
    var compact: Bool = false

    private var tint: Color { provenance == .measured ? OasisPalette.cash : OasisPalette.modeled }

    var body: some View {
        Label {
            if !compact { Text(provenance.title) }
        } icon: {
            Image(systemName: provenance == .measured
                ? "checkmark.seal.fill"
                : "pencil.and.outline")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.5))
        .help(provenance.explanation)
        .accessibilityLabel("\(provenance.title). \(provenance.explanation)")
    }
}

/// A confidence read-out that always shows its reasoning.
///
/// The old score was activity dressed as certainty, so the number alone was the problem.
/// Showing the sentence that produced it means a reader can disagree with it.
struct EvidenceMeter: View {
    let confidence: Double
    let reason: String

    private var tint: Color {
        switch confidence {
        case ..<0.01: OasisPalette.coral
        case ..<0.5: OasisPalette.gold
        default: OasisPalette.cash
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Evidence")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(confidence < 0.01 ? "None" : OasisFormat.percent(confidence))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(OasisPalette.accentGradient(tint))
                        .frame(width: max(0, geo.size.width * confidence))
                }
            }
            .frame(height: 5)
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var trailing: AnyView?

    init<Content: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Content = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        let content = trailing()
        self.trailing = content is EmptyView ? nil : AnyView(content)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(OasisPalette.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            trailing
        }
    }
}

struct OasisPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(OasisMetrics.panelPadding)
            .oasisSurface()
    }
}

/// A headline figure.
///
/// `provenance` is optional but is the point of the component: a tile showing money that
/// moved and a tile showing money someone estimated used to be visually identical, which is
/// how an estimate ends up quoted as a result. When provenance is supplied the tile carries
/// its badge, and estimated tiles get a different accent family rather than a paler version
/// of the same one - a shade reads as "less of the same thing", not "a different kind of
/// thing".
struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let color: Color
    var provenance: ValueProvenance?

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OasisPalette.accentGradient(color))
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.14), in: RoundedRectangle(
                        cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let provenance {
                    ProvenanceBadge(provenance: provenance, compact: true)
                }
            }
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OasisPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 28, alignment: .topLeading)
        }
        .padding(OasisMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oasisSurface()
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(OasisPalette.accentGradient(color))
                .frame(height: 3)
                .padding(.horizontal, 14)
                .opacity(hovering ? 1 : 0.75)
        }
        .scaleEffect(hovering ? 1.012 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: hovering)
        .onHover { hovering = $0 }
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StatusIndicator: View {
    let text: String
    let systemImage: String
    let color: Color
    var pulse: Bool = false

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .symbolEffect(.pulse, options: .repeating, isActive: pulse)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .lineLimit(1)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(message)
        )
    }
}

struct CashFlowChart: View {
    let points: [MonthlyPoint]

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Month", point.date, unit: .month),
                y: .value("Revenue", AnalyticsEngine.decimalDouble(point.revenue))
            )
            .foregroundStyle(OasisPalette.green)
            .position(by: .value("Series", "Revenue"))

            BarMark(
                x: .value("Month", point.date, unit: .month),
                y: .value("Expenses", AnalyticsEngine.decimalDouble(point.expenses))
            )
            .foregroundStyle(OasisPalette.coral)
            .position(by: .value("Series", "Expenses"))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartLegend(.hidden)
    }
}

struct ProceedsChart: View {
    let observations: [AppObservation]
    let currency: String

    var body: some View {
        Chart(observations.sorted(by: { $0.date < $1.date })) { observation in
            AreaMark(
                x: .value("Date", observation.date),
                y: .value("Proceeds", AnalyticsEngine.decimalDouble(observation.proceeds))
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [OasisPalette.teal.opacity(0.4), OasisPalette.teal.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            LineMark(
                x: .value("Date", observation.date),
                y: .value("Proceeds", AnalyticsEngine.decimalDouble(observation.proceeds))
            )
            .foregroundStyle(OasisPalette.teal)
            .lineStyle(.init(lineWidth: 2))
            PointMark(
                x: .value("Date", observation.date),
                y: .value("Proceeds", AnalyticsEngine.decimalDouble(observation.proceeds))
            )
            .foregroundStyle(OasisPalette.teal)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(OasisFormat.currency(Decimal(amount), code: currency, compact: true))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
    }
}

enum OasisFormat {
    static func currency(_ value: Decimal, code: String = "USD", compact: Bool = false) -> String {
        let number = NSDecimalNumber(decimal: value)
        if compact, abs(number.doubleValue) >= 1_000 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = code
            formatter.maximumFractionDigits = 1
            return formatter.string(from: NSNumber(value: number.doubleValue / 1_000)).map { "\($0)K" }
                ?? number.stringValue
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? number.stringValue
    }

    static func percent(_ value: Double, signed: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = signed ? "+" : ""
        return formatter.string(from: NSNumber(value: value)) ?? "0%"
    }

    static func integer(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension LifecycleStatus {
    var color: Color {
        switch self {
        case .healthy: OasisPalette.green
        case .watch: OasisPalette.gold
        case .attention: OasisPalette.coral
        case .paused, .archived: .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .watch: "eye.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .paused: "pause.circle.fill"
        case .archived: "archivebox.fill"
        }
    }
}

extension AgentStatus {
    var color: Color {
        switch self {
        case .active: OasisPalette.green
        case .idle: OasisPalette.gold
        case .blocked: OasisPalette.coral
        case .offline: .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .active: "bolt.circle.fill"
        case .idle: "clock.fill"
        case .blocked: "exclamationmark.octagon.fill"
        case .offline: "power"
        }
    }
}

extension ConnectionStatus {
    var color: Color {
        switch self {
        case .connected: OasisPalette.green
        case .needsSetup: OasisPalette.gold
        case .stale: OasisPalette.gold
        case .error: OasisPalette.coral
        case .disabled: .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .needsSetup: "wrench.and.screwdriver.fill"
        case .stale: "clock.badge.exclamationmark.fill"
        case .error: "xmark.octagon.fill"
        case .disabled: "minus.circle.fill"
        }
    }
}
