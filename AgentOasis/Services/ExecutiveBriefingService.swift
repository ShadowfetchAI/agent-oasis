import Foundation

enum ExecutiveBriefingService {
    static func markdown(for state: WorkspaceState, now: Date = Date()) -> String {
        let summary = AnalyticsEngine.summary(for: state)
        let apps = DecisionEngine.portfolioDecisions(for: state, now: now)
        let agents = DecisionEngine.agentDecisions(for: state)
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short

        var lines: [String] = [
            "# Agent Oasis Executive Brief",
            "",
            "**Workspace:** \(state.name)",
            "**Generated:** \(formatter.string(from: now))",
            "",
            "> Measured cash and modelled value are intentionally reported separately.",
            "",
            "## Measured cash",
            "",
            "- Revenue recorded: \(money(summary.cashRevenue, currency: state.settings.baseCurrency))",
            "- Cash expenses: \(money(summary.cashExpenses, currency: state.settings.baseCurrency))",
            "- Net cash: \(money(summary.netCash, currency: state.settings.baseCurrency))",
            "- Recent portfolio proceeds: \(money(DecisionEngine.recentPortfolioProceeds(for: state, now: now), currency: state.settings.baseCurrency))",
            "- Agent cash net value: \(money(summary.agentCashNetValue, currency: state.settings.baseCurrency))",
            "",
            "## Modelled value",
            "",
            "- Agent modelled net value: \(money(summary.agentModeledNetValue, currency: state.settings.baseCurrency))",
            "- Fleet evidence coverage: \(percent(summary.fleetEvidenceRatio))",
            "",
            "Modelled value is planning information. It is not added to net cash.",
            "",
            "## Portfolio decisions",
            ""
        ]

        if apps.isEmpty {
            lines.append("No portfolio records are available.")
        } else {
            for item in apps.prefix(12) {
                lines.append("- **\(item.appName)** — \(item.disposition.title): \(item.rationale)")
            }
        }

        lines.append(contentsOf: ["", "## Agent decisions", ""])
        if agents.isEmpty {
            lines.append("No agent profiles are available.")
        } else {
            for item in agents.prefix(12) {
                lines.append("- **\(item.agentName)** — \(item.disposition.title): \(item.rationale)")
            }
        }

        lines.append(contentsOf: ["", "## Experiments", ""])
        let running = state.experiments.filter { $0.status == .running }
        if running.isEmpty {
            lines.append("No experiments are currently running.")
        } else {
            for experiment in running {
                let outcome: String
                switch AnalyticsEngine.attribution(for: experiment) {
                case .attributable(let lift): outcome = "attributable lift \(percent(lift))"
                case .notAttributable(let reason): outcome = "attribution refused — \(reason)"
                case .insufficientData(let reason): outcome = reason
                }
                lines.append("- **\(experiment.title)** — \(outcome)")
            }
        }

        lines.append(contentsOf: ["", "## Data health", ""])
        let sourceProblems = state.connections.filter {
            $0.status == .error || $0.status == .stale || $0.status == .needsSetup
        }
        lines.append("- \(state.apps.count) tracked products")
        lines.append("- \(state.agents.count) agent profiles")
        lines.append("- \(sourceProblems.count) connections need attention")
        lines.append("- \(state.snapshots.count) saved business checkpoints")
        if summary.excludedCurrencyEntryCount > 0 {
            lines.append(
                "- \(summary.excludedCurrencyEntryCount) cash entries in "
                    + "\(summary.excludedCurrencies.joined(separator: ", ")) were preserved but excluded "
                    + "from \(state.settings.baseCurrency) totals; Agent Oasis does not invent FX rates"
            )
        }
        lines.append("")
        lines.append("Generated locally by Agent Oasis. Vault items and secret values are never included.")
        return lines.joined(separator: "\n")
    }

    static func html(for state: WorkspaceState, now: Date = Date()) -> String {
        let markdown = markdown(for: state, now: now)
        var blocks: [String] = []
        var listIsOpen = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let value = String(line)
            if value.hasPrefix("- ") {
                if !listIsOpen {
                    blocks.append("<ul>")
                    listIsOpen = true
                }
                blocks.append("<li>\(inline(String(value.dropFirst(2))))</li>")
                continue
            }
            if listIsOpen {
                blocks.append("</ul>")
                listIsOpen = false
            }
            if value.hasPrefix("# ") {
                blocks.append("<h1>\(escape(String(value.dropFirst(2))))</h1>")
            } else if value.hasPrefix("## ") {
                blocks.append("<h2>\(escape(String(value.dropFirst(3))))</h2>")
            } else if value.hasPrefix("> ") {
                blocks.append("<aside>\(inline(String(value.dropFirst(2))))</aside>")
            } else if !value.isEmpty {
                blocks.append("<p>\(inline(value))</p>")
            }
        }
        if listIsOpen { blocks.append("</ul>") }
        let body = blocks.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Agent Oasis Executive Brief</title>
        <style>
        :root{color-scheme:light dark;--ink:#172126;--muted:#59666c;--rule:#cad5d8;--accent:#08798a;--paper:#f7faf9}
        @media(prefers-color-scheme:dark){:root{--ink:#edf4f4;--muted:#aebbbc;--rule:#3d4a4d;--accent:#61cad7;--paper:#101718}}
        *{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
        main{max-width:900px;margin:0 auto;padding:64px 54px 80px}h1{font-size:42px;line-height:1.08;margin:0 0 28px}h2{font-size:22px;margin:38px 0 12px;padding-top:18px;border-top:1px solid var(--rule)}p{margin:7px 0;color:var(--muted)}strong{color:var(--ink)}aside{margin:24px 0;padding:16px 18px;border-left:4px solid var(--accent);background:color-mix(in srgb,var(--accent) 9%,transparent);font-weight:650}ul{margin:10px 0 22px;padding-left:22px}li{margin:8px 0;color:var(--muted)}li::marker{color:var(--accent)}
        @media print{body{background:#fff;color:#111}main{padding:24px}h2{break-after:avoid}li{break-inside:avoid}}
        </style></head><body><main>\(body)</main></body></html>
        """
    }

    private static func money(_ value: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value) \(currency)"
    }

    private static func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "0%"
    }

    private static func inline(_ source: String) -> String {
        var escaped = escape(source)
        while let start = escaped.range(of: "**"),
              let end = escaped.range(of: "**", range: start.upperBound..<escaped.endIndex) {
            escaped.replaceSubrange(end, with: "</strong>")
            escaped.replaceSubrange(start, with: "<strong>")
        }
        return escaped
    }

    private static func escape(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
