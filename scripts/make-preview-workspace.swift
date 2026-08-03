import Foundation

@main
struct MakePreviewWorkspace {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(
                Data("usage: make-preview-workspace <output.json>\n".utf8)
            )
            throw CocoaError(.fileWriteInvalidFileName)
        }

        let now = Date()
        var workspace = DemoWorkspace.make(now: now)
        workspace.name = "Shadowfetch Studio"
        workspace.settings.lastSeenReleaseNotes = "3.0.0"
        for appIndex in workspace.apps.indices {
            for observationIndex in workspace.apps[appIndex].observations.indices {
                workspace.apps[appIndex].observations[observationIndex].confidence = .confirmed
                workspace.apps[appIndex].observations[observationIndex].source = "Isolated preview fixture"
            }
        }
        workspace.businessSnapshots = [
            BusinessSnapshot(
                capturedAt: now.addingTimeInterval(-30 * 86_400),
                label: "Before portfolio pricing review",
                currency: "USD",
                cashRevenue: 1_940,
                cashExpenses: 812,
                netCash: 1_128,
                recentPortfolioProceeds: 164,
                agentCashNetValue: 530,
                agentModeledNetValue: 18_600,
                trackedApps: workspace.apps.count,
                activeAgents: workspace.agents.filter { $0.status == .active }.count,
                fleetEvidenceRatio: 0.42
            )
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try encoder.encode(workspace).write(to: output, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: output.path
        )
    }
}
