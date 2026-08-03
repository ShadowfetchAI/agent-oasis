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
        ===VERSION===
        Hermes Agent v0.18.2
        ===PROFILE_COUNT===
        2
        ===ACTIVE_GATEWAYS===
        1
        ===KANBAN_STATS===
        ===KANBAN_BLOCKED===
        ===DECISIONS===
        ===ROSTER===
        ===GATEWAYS===
        ===INTEGRITY===
        ===AGENTS===
        AGENT\tkai-kimber\t1\t12\t320\t88\t100000\t9000\t420000
        AGENT\tresearch\t0\t4\t90\t21\t30000\t3500\t101000
        ===END===
        """

        let result = try HermesFleetService.parse(output)

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

    /// The fleet paths are interpolated into a remote shell command, so they are an injection
    /// surface exactly like the hostname. Making them configurable created this risk; the
    /// validation is what makes the feature safe rather than merely flexible.
    func testFleetLayoutRejectsInjectionAndEscape() async {
        let bad = [
            "../../etc",                     // escapes $HOME
            "/etc/passwd",                   // absolute
            "profiles; rm -rf ~",            // command separator
            "profiles$(whoami)",             // substitution
            "profiles`id`",                  // backticks
            "profiles with space",
            ""
        ]
        for path in bad {
            do {
                _ = try await HermesFleetService.fetchFleetSnapshot(
                    host: "example", profilesPath: path)
                XCTFail("Accepted a dangerous profiles path: \(path)")
            } catch let error as HermesConnectorError {
                guard case .invalidLayout = error else {
                    return XCTFail("Wrong rejection for \(path): \(error)")
                }
            } catch {
                // A connection failure means validation passed and it tried to run - a fail.
                XCTFail("Path \(path) reached the network layer")
            }
        }
    }

    /// An empty result must say what it looked for, not just "malformed".
    func testEmptyFleetNamesTheSearchedPath() {
        do {
            _ = try HermesFleetService.parse("", searchedPath: "custom/agents")
            XCTFail("Empty telemetry should not parse")
        } catch let error as HermesConnectorError {
            guard case .noProfilesFound(let searched) = error else {
                return XCTFail("Expected .noProfilesFound, got \(error)")
            }
            XCTAssertEqual(searched, "custom/agents")
            XCTAssertTrue(
                error.errorDescription?.contains("custom/agents") == true,
                "The message a user reads must name the directory that was searched."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
