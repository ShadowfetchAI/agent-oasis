import CryptoKit
import Foundation
import XCTest

@MainActor
final class AttentionAndDuplicateTests: XCTestCase {
    func testAttentionInboxSurfacesBlockedAgentAndMissingBackup() {
        var state = WorkspaceState()
        state.agents = [
            AgentProfile(
                name: "Blocked Bot",
                role: "Ops",
                provider: "Test",
                model: "Test",
                status: .blocked,
                sessions: 0,
                messages: 0,
                acceptedTasks: 0,
                failedTasks: 0,
                reworkedTasks: 0,
                inputTokens: 0,
                outputTokens: 0,
                totalTokensReported: 0,
                toolCalls: 0,
                externalCost: 10,
                computeCost: 0,
                supervisionMinutes: 0,
                equivalentHumanHours: 8,
                loadedHourlyRate: 100,
                directRevenueInfluenced: 0,
                avoidedVendorSpend: 0,
                lastSeen: nil,
                source: "Test",
                tags: []
            )
        ]
        state.ledger = [
            LedgerEntry(
                date: Date(),
                type: .expense,
                category: "API",
                entityKind: .agent,
                entityName: "Blocked Bot",
                description: "Cost",
                amount: 10,
                currency: "USD",
                source: "Test",
                confidence: .confirmed,
                notes: ""
            )
        ]

        let items = AttentionEngine.items(for: state)
        XCTAssertTrue(items.contains(where: { $0.id.hasPrefix("blocked-") }))
        XCTAssertTrue(items.contains(where: { $0.id == "backup-missing" }))
        XCTAssertTrue(items.contains(where: { $0.id.hasPrefix("zero-evidence-") }))
    }

    func testAttributionRefusedBecomesAttentionItem() {
        var state = WorkspaceState()
        state.experiments = [
            Experiment(
                appName: "Demo App",
                title: "Price test",
                kind: .price,
                status: .completed,
                startedAt: Date().addingTimeInterval(-86400 * 30),
                endedAt: Date(),
                hypothesis: "Higher price lifts proceeds",
                beforeValue: "$4.99",
                afterValue: "$6.99",
                observationWindowDays: 14,
                baselineProceeds: 1_000,
                observedProceeds: 1_200,
                confounders: "Holiday sale overlapped the window",
                notes: ""
            )
        ]

        let items = AttentionEngine.items(for: state)
        XCTAssertTrue(items.contains(where: { $0.id.hasPrefix("confounder-") }))
        XCTAssertEqual(
            items.first(where: { $0.id.hasPrefix("confounder-") })?.severity,
            .warning
        )
    }

    func testPreviewImportDoesNotMutateWorkspace() throws {
        var state = WorkspaceState()
        let beforeCount = state.ledger.count
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-preview-\(UUID().uuidString).csv")
        try """
        date,type,category,entity,description,amount,currency,source,confidence,notes
        2026-01-15T00:00:00Z,expense,API,Business,Tokens,12.50,USD,Test,confirmed,
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try ImportExportService.previewDelimitedFile(at: url, against: state)
        XCTAssertEqual(summary.ledgerEntriesAdded, 1)
        XCTAssertEqual(state.ledger.count, beforeCount)
    }

    func testDuplicateAgentResetsTelemetryAndProvenance() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ao-dup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = try EncryptedWorkspaceRepository(baseDirectory: directory)
        let key = SymmetricKey(size: .bits256)
        let store = OasisStore(
            repository: repository,
            keyProvider: { _ in key },
            ownerAuthenticator: { _ in nil }
        )
        await store.unlock()
        XCTAssertTrue(store.isUnlocked)

        let agent = AgentProfile(
            name: "Fleet Runner",
            role: "Ship",
            provider: "Hermes",
            model: "local",
            status: .active,
            sessions: 40,
            messages: 400,
            acceptedTasks: 12,
            failedTasks: 1,
            reworkedTasks: 0,
            inputTokens: 90_000,
            outputTokens: 10_000,
            totalTokensReported: 100_000,
            toolCalls: 30,
            externalCost: 40,
            computeCost: 5,
            supervisionMinutes: 20,
            equivalentHumanHours: 6,
            loadedHourlyRate: 80,
            directRevenueInfluenced: 500,
            avoidedVendorSpend: 100,
            lastSeen: Date(),
            source: "Hermes telemetry",
            tags: ["fleet"],
            valueBasis: AgentValueBasis(
                equivalentHumanHours: .measured,
                loadedHourlyRate: .estimated,
                directRevenueInfluenced: .measured,
                avoidedVendorSpend: .estimated
            )
        )
        store.addAgent(agent)
        let original = store.workspace.agents[0]

        let copy = store.duplicateAgent(original)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.sessions, 0)
        XCTAssertEqual(copy.inputTokens, 0)
        XCTAssertNil(copy.lastSeen)
        XCTAssertEqual(copy.source, "Manual duplicate")
        XCTAssertEqual(copy.basis.measuredCount, 0)
        XCTAssertEqual(store.workspace.agents.count, 2)
    }
}
