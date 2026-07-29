import Charts
import SwiftUI

enum OasisPalette {
    static let teal = Color(red: 0.06, green: 0.51, blue: 0.62)
    static let coral = Color(red: 0.88, green: 0.30, blue: 0.27)
    static let gold = Color(red: 0.88, green: 0.65, blue: 0.16)
    static let green = Color(red: 0.20, green: 0.64, blue: 0.38)
    static let ink = Color(red: 0.09, green: 0.11, blue: 0.13)
    static let indigo = Color(red: 0.31, green: 0.35, blue: 0.70)
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
                    .font(.system(size: 25, weight: .semibold))
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
            .padding(16)
            .background(.background.opacity(0.78))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        OasisPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(minHeight: 28, alignment: .topLeading)
            }
        }
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

    var body: some View {
        Label(text, systemImage: systemImage)
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
