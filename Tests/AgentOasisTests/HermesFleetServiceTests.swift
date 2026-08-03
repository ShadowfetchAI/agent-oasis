import XCTest

final class HermesFleetServiceTests: XCTestCase {
    /// Real payload shape from `hermes kanban stats --json` and
    /// `hermes kanban list --status blocked --sort created --json` on a live Hermes install.
    private func combinedOutput(
        kanbanStats: String = "",
        kanbanBlocked: String = "",
        decisions: String = "",
        roster: String = "",
        gateways: String = "",
        integrity: String = ""
    ) -> String {
        """
        ===VERSION===
        Hermes Agent v1.0.0
        ===PROFILE_COUNT===
        2
        ===ACTIVE_GATEWAYS===
        2
        ===KANBAN_STATS===
        \(kanbanStats)
        ===KANBAN_BLOCKED===
        \(kanbanBlocked)
        ===DECISIONS===
        \(decisions)
        ===ROSTER===
        \(roster)
        ===GATEWAYS===
        \(gateways)
        ===INTEGRITY===
        \(integrity)
        ===AGENTS===
        AGENT\tamara-okafor\t1\t12\t320\t88\t100000\t9000\t420000
        ===END===
        """
    }

    // MARK: - Kanban

    func testKanbanStatsAndBlockedCardsParse() throws {
        let statsJSON = """
        {"by_status": {"blocked": 117, "done": 840, "scheduled": 2, "todo": 48, "triage": 1}, "by_assignee": {}, "oldest_ready_age_seconds": null, "now": 1785724264}
        """
        let blockedJSON = """
        [{"id": "t_e57eded7", "title": "Stand up measured support queue", "body": "Sensitive strategic content here.", "assignee": "nia-holloway", "status": "blocked", "priority": 3, "created_at": 1784750952}]
        """
        let output = combinedOutput(kanbanStats: statsJSON, kanbanBlocked: blockedJSON)

        let result = try HermesFleetService.parse(output)

        let health = try XCTUnwrap(result.kanbanHealth)
        XCTAssertEqual(health.byStatus["blocked"], 117)
        XCTAssertEqual(health.byStatus["done"], 840)
        XCTAssertEqual(health.total, 117 + 840 + 2 + 48 + 1)
        XCTAssertEqual(health.oldestBlocked.count, 1)
        XCTAssertEqual(health.oldestBlocked[0].id, "t_e57eded7")
        XCTAssertEqual(health.oldestBlocked[0].assignee, "nia-holloway")
        XCTAssertEqual(health.oldestBlocked[0].priority, 3)
    }

    /// The redaction guarantee: a real card body containing internal strategic content must
    /// never survive into the decoded model, even when the raw JSON carries it. This is not a
    /// filtering step to remember - `HermesKanbanCard` has no `body` property to decode into.
    func testKanbanCardBodyNeverDecodes() throws {
        let blockedJSON = """
        [{"id": "t_x", "title": "Title", "body": "SENSITIVE: named-executive strategic content, support metrics, App Store routing.", "assignee": "a", "status": "blocked", "priority": 1, "created_at": 1700000000}]
        """
        let output = combinedOutput(kanbanStats: "{\"by_status\": {\"blocked\": 1}}", kanbanBlocked: blockedJSON)
        let result = try HermesFleetService.parse(output)
        let card = try XCTUnwrap(result.kanbanHealth?.oldestBlocked.first)

        // Mirror-check: re-encode the parsed card and confirm the sensitive text is nowhere in
        // the output, not just "no property named body".
        let reencoded = try JSONEncoder().encode(card)
        let reencodedString = String(data: reencoded, encoding: .utf8) ?? ""
        XCTAssertFalse(reencodedString.contains("SENSITIVE"))
        XCTAssertFalse(reencodedString.contains("named-executive"))
    }

    func testKanbanCardRoundTripsCreatedAtThroughPersistence() throws {
        let blockedJSON = """
        [{"id": "t_x", "title": "Title", "assignee": "a", "status": "blocked", "priority": 1, "created_at": 1700000000}]
        """
        let output = combinedOutput(kanbanStats: "{\"by_status\": {\"blocked\": 1}}", kanbanBlocked: blockedJSON)
        let result = try HermesFleetService.parse(output)
        let card = try XCTUnwrap(result.kanbanHealth?.oldestBlocked.first)
        XCTAssertEqual(card.createdAt?.timeIntervalSince1970, 1700000000)

        // Persist and reload, as the encrypted workspace does. A synthesized Encodable would
        // write createdAt under the app's own date strategy instead of the epoch Double that
        // init(from:) expects, corrupting every workspace with a blocked card on next launch.
        let persisted = try JSONEncoder().encode(card)
        let reloaded = try JSONDecoder().decode(HermesKanbanCard.self, from: persisted)
        XCTAssertEqual(
            reloaded.createdAt?.timeIntervalSince1970, 1700000000,
            "createdAt must survive an app-internal encode/decode round trip"
        )
    }

    // MARK: - Decision queue

    func testDecisionQueueParsesShapeOnly() throws {
        let decisionsJSON = """
        [{"id": "20260802-3978", "ts": "2026-08-02T09:11:11", "raised_by": "veronica-polar", "kind": "ops", "authority": "management", "title": "Governance finding", "context": "SENSITIVE full case text naming board members and dollar figures.", "options": ["a", "b"], "recommendation": "do the thing", "ack_deadline": "2026-08-02T13:11:11", "acks": [{"by": "amara-okafor", "ts": "x", "note": "seen"}], "status": "open"}]
        """
        let output = combinedOutput(decisions: decisionsJSON)
        let result = try HermesFleetService.parse(output)

        let queue = try XCTUnwrap(result.decisionQueue)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue[0].id, "20260802-3978")
        XCTAssertEqual(queue[0].authority, "management")
        XCTAssertEqual(queue[0].raisedBy, "veronica-polar")
        XCTAssertEqual(queue[0].status, "open")
        XCTAssertEqual(queue[0].ackCount, 1)
        XCTAssertEqual(queue[0].ackDeadlineRaw, "2026-08-02T13:11:11")

        let reencoded = try JSONEncoder().encode(queue[0])
        let reencodedString = String(data: reencoded, encoding: .utf8) ?? ""
        XCTAssertFalse(reencodedString.contains("SENSITIVE"))
        XCTAssertFalse(reencodedString.contains("do the thing"))
    }

    func testDecisionQueueRoundTripsAckCountThroughPersistence() throws {
        let decisionsJSON = """
        [{"id": "1", "title": "T", "status": "open", "authority": "owner", "raised_by": "x", "acks": [{"by": "a"}, {"by": "b"}]}]
        """
        let output = combinedOutput(decisions: decisionsJSON)
        let result = try HermesFleetService.parse(output)
        let item = try XCTUnwrap(result.decisionQueue?.first)
        XCTAssertEqual(item.ackCount, 2)

        // Persist and reload, as the encrypted workspace does.
        let persisted = try JSONEncoder().encode(item)
        let reloaded = try JSONDecoder().decode(HermesDecisionQueueItem.self, from: persisted)
        XCTAssertEqual(reloaded.ackCount, 2, "ackCount must survive an app-internal encode/decode round trip")
    }

    // MARK: - Roster and gateways

    func testRosterParsesFixedWidthTableAndExcludesDefault() throws {
        let rosterText = """
         Profile          Model                        Gateway      Alias        Distribution
         ───────────────    ───────────────────────────    ───────────    ───────────    ────────────────────
         ◆default         gpt-5.5                      stopped      —            —
          amara-okafor    gpt-5.5                      running      —            amara-okafor@1.0.0
        """
        let output = combinedOutput(roster: rosterText)
        let result = try HermesFleetService.parse(output)

        let roster = try XCTUnwrap(result.roster)
        XCTAssertEqual(roster.count, 1, "the synthetic default profile must be excluded")
        XCTAssertEqual(roster[0].name, "amara-okafor")
        XCTAssertEqual(roster[0].model, "gpt-5.5")
        XCTAssertEqual(roster[0].gatewayState, "running")
    }

    func testGatewayListParsesRunningAndStoppedExcludingDefault() throws {
        let gatewayText = """
        Gateways:
          ✗ default (current)        — not running
          ✓ amara-okafor             — PID 1514957
          ✗ anika-rao                — not running
        """
        let output = combinedOutput(gateways: gatewayText)
        let result = try HermesFleetService.parse(output)

        let gateways = try XCTUnwrap(result.gateways)
        XCTAssertEqual(gateways.count, 2, "the synthetic default entry must be excluded")
        let amara = try XCTUnwrap(gateways.first { $0.name == "amara-okafor" })
        XCTAssertTrue(amara.running)
        XCTAssertEqual(amara.pid, 1_514_957)
        let anika = try XCTUnwrap(gateways.first { $0.name == "anika-rao" })
        XCTAssertFalse(anika.running)
        XCTAssertNil(anika.pid)
    }

    // MARK: - Integrity

    func testIntegrityStatusParsesCleanAndDirty() throws {
        let cleanJSON = """
        {"checked_at": "2026-08-02T22:28:07", "agents": 39, "missing_profile_symlink": [], "broken_profile_symlink": [], "profile_not_a_symlink": [], "masked_fleet_units": [], "all_masked_units": [], "clean": true}
        """
        let clean = try HermesFleetService.parse(combinedOutput(integrity: cleanJSON))
        let cleanStatus = try XCTUnwrap(clean.integrity)
        XCTAssertEqual(cleanStatus.clean, true)
        XCTAssertEqual(cleanStatus.agentCount, 39)
        XCTAssertTrue(cleanStatus.issues.isEmpty)

        let dirtyJSON = """
        {"checked_at": "2026-08-02T22:28:07", "agents": 39, "missing_profile_symlink": ["ghost-agent"], "broken_profile_symlink": [], "profile_not_a_symlink": [], "masked_fleet_units": ["hermes-gw@stale.service"], "clean": false}
        """
        let dirty = try HermesFleetService.parse(combinedOutput(integrity: dirtyJSON))
        let dirtyStatus = try XCTUnwrap(dirty.integrity)
        XCTAssertEqual(dirtyStatus.clean, false)
        XCTAssertEqual(dirtyStatus.issues.count, 2)
    }

    // MARK: - Injection rejection for the new path parameters

    func testNewPathParametersRejectInjectionAndEscape() async {
        let bad = ["../../etc", "/etc/passwd", "tools; rm -rf ~", "tools$(whoami)", "tools`id`", "tools with space", ""]
        for path in bad {
            do {
                _ = try await HermesFleetService.fetchFleetSnapshot(host: "example", toolsPath: path)
                XCTFail("Accepted a dangerous tools path: \(path)")
            } catch let error as HermesConnectorError {
                guard case .invalidLayout = error else {
                    return XCTFail("Wrong rejection for tools path \(path): \(error)")
                }
            } catch {
                XCTFail("Tools path \(path) reached the network layer")
            }

            do {
                _ = try await HermesFleetService.fetchFleetSnapshot(host: "example", statePath: path)
                XCTFail("Accepted a dangerous state path: \(path)")
            } catch let error as HermesConnectorError {
                guard case .invalidLayout = error else {
                    return XCTFail("Wrong rejection for state path \(path): \(error)")
                }
            } catch {
                XCTFail("State path \(path) reached the network layer")
            }
        }
    }

    // MARK: - No fabricated aggregates

    /// There is no aggregate "duty success rate" anywhere on a real Hermes install (confirmed by
    /// direct investigation of the CLI and its sibling scripts). This locks that decision in:
    /// the snapshot type must never grow a field that looks like one.
    func testSnapshotHasNoFabricatedSuccessRateField() {
        let mirror = Mirror(reflecting: HermesFleetSnapshot(
            fetchedAt: Date(), version: "v", profileCount: 0, activeGateways: 0,
            kanbanSummary: "", agents: []
        ))
        let suspiciousNames = mirror.children.compactMap(\.label).filter {
            $0.localizedCaseInsensitiveContains("successRate")
                || $0.localizedCaseInsensitiveContains("dutySuccess")
        }
        XCTAssertTrue(suspiciousNames.isEmpty, "found fabricated-looking field(s): \(suspiciousNames)")
    }
}
