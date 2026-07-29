import XCTest

final class DemoAndHermesTests: XCTestCase {
    func testDemoWorkspaceHasEveryOperationalSurfacePopulated() {
        let state = DemoWorkspace.make()

        XCTAssertGreaterThanOrEqual(state.apps.count, 5)
        XCTAssertGreaterThanOrEqual(state.agents.count, 4)
        XCTAssertFalse(state.ledger.isEmpty)
        XCTAssertFalse(state.experiments.isEmpty)
        XCTAssertTrue(state.connections.contains(where: { $0.kind == .appStoreConnect }))
        XCTAssertTrue(state.connections.contains(where: { $0.kind == .hermesFleet }))
        XCTAssertFalse(state.audit.isEmpty)
    }

    func testHermesResponseParsingPreservesReportedTokenCategories() throws {
        let output = """
        VERSION\tHermes Agent v0.18.2
        PROFILE_COUNT\t2
        ACTIVE_GATEWAYS\t1
        KANBAN\ttriage 1 todo 3
        AGENT\tkai-kimber\t1\t12\t320\t88\t100000\t9000\t420000
        AGENT\tresearch\t0\t4\t90\t21\t30000\t3500\t101000
        """

        let result = try HermesConnector.parse(output)

        XCTAssertEqual(result.profileCount, 2)
        XCTAssertEqual(result.activeGateways, 1)
        XCTAssertEqual(result.agents.count, 2)
        XCTAssertEqual(result.agents[0].name, "kai-kimber")
        XCTAssertEqual(result.agents[0].inputTokens, 100_000)
        XCTAssertEqual(result.agents[0].outputTokens, 9_000)
        XCTAssertEqual(result.agents[0].totalTokensReported, 420_000)
        XCTAssertNotEqual(
            result.agents[0].inputTokens + result.agents[0].outputTokens,
            result.agents[0].totalTokensReported
        )
    }
}
