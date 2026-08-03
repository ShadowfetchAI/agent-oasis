import Foundation

/// A row from `hermes insights --days N`, one per agent, text-scraped by design (see
/// `HermesFleetService` doc comment for why no richer telemetry endpoint exists).
struct HermesAgentSnapshot: Codable, Hashable {
    var name: String
    var isGatewayActive: Bool
    var sessions: Int
    var messages: Int
    var toolCalls: Int
    var inputTokens: Int64
    var outputTokens: Int64
    var totalTokensReported: Int64
}

/// A kanban card, deliberately missing its `body`/`context` field. The remote JSON always
/// includes it (see docs/HERMES-FLEET.md) - this struct just never declares a property for it,
/// so `JSONDecoder` drops it on the floor before it ever becomes a value in memory. That is the
/// entire redaction mechanism: there is no "fetch then hide" step to get wrong.
struct HermesKanbanCard: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var assignee: String?
    var status: String
    var priority: Int?
    var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, title, assignee, status, priority
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
        status = try container.decode(String.self, forKey: .status)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        if let epoch = try container.decodeIfPresent(Double.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSince1970: epoch)
        } else {
            createdAt = nil
        }
    }

    // Mirrors init(from:): createdAt as a raw epoch Double, not the decoder's date
    // strategy (.iso8601 for the persisted workspace). Without this, the synthesized
    // Encodable would write an ISO8601 string that init(from:) then fails to read back.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(assignee, forKey: .assignee)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(createdAt?.timeIntervalSince1970, forKey: .createdAt)
    }

    // Memberwise, for tests and fixture construction.
    init(id: String, title: String, assignee: String?, status: String, priority: Int?, createdAt: Date?) {
        self.id = id
        self.title = title
        self.assignee = assignee
        self.status = status
        self.priority = priority
        self.createdAt = createdAt
    }
}

struct HermesKanbanHealth: Codable, Hashable {
    var byStatus: [String: Int]
    var oldestBlocked: [HermesKanbanCard]

    var total: Int { byStatus.values.reduce(0, +) }
}

/// An open pending-decision, deliberately missing `context`/`recommendation`/`options`/`links` -
/// same redaction mechanism as `HermesKanbanCard`. Real decision bodies observed on the source
/// Hermes install contain named-executive strategic content; only the queue shape (who raised
/// it, what authority it needs, when it's due) belongs in a screenshot.
struct HermesDecisionQueueItem: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var authority: String?
    var raisedBy: String?
    var status: String
    var ackDeadlineRaw: String?
    var ackCount: Int

    /// Covers both the server's schema (`acks` - an array counted, never itself decoded into a
    /// value) and this app's own persisted schema (`ackCount` - a plain integer written by
    /// `encode(to:)`), so round-tripping through the encrypted workspace blob doesn't lose the
    /// count the way decoding only the server's key would.
    private enum CodingKeys: String, CodingKey {
        case id, title, authority, status, acks, ackCount
        case raisedBy = "raised_by"
        case ackDeadlineRaw = "ack_deadline"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        authority = try container.decodeIfPresent(String.self, forKey: .authority)
        raisedBy = try container.decodeIfPresent(String.self, forKey: .raisedBy)
        status = try container.decode(String.self, forKey: .status)
        ackDeadlineRaw = try container.decodeIfPresent(String.self, forKey: .ackDeadlineRaw)
        if let persistedCount = try container.decodeIfPresent(Int.self, forKey: .ackCount) {
            ackCount = persistedCount
        } else {
            // Acks carry a free-text `note` in the real payload; only the count is kept, via an
            // element type with zero declared properties so nothing from an individual ack
            // decodes.
            struct AckPresence: Decodable {}
            ackCount = (try? container.decodeIfPresent([AckPresence].self, forKey: .acks))??.count ?? 0
        }
    }

    init(id: String, title: String, authority: String?, raisedBy: String?, status: String, ackDeadlineRaw: String?, ackCount: Int) {
        self.id = id
        self.title = title
        self.authority = authority
        self.raisedBy = raisedBy
        self.status = status
        self.ackDeadlineRaw = ackDeadlineRaw
        self.ackCount = ackCount
    }

    /// Round-trips through the app's own encrypted workspace blob, not the server's schema -
    /// `ackCount` is written as a plain integer rather than reconstructing an `acks` array,
    /// which `init(from:)` above reads back in preference to re-deriving it from `acks`.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(authority, forKey: .authority)
        try container.encodeIfPresent(raisedBy, forKey: .raisedBy)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(ackDeadlineRaw, forKey: .ackDeadlineRaw)
        try container.encode(ackCount, forKey: .ackCount)
    }

    /// Hermes writes deadlines as local naive timestamps with no offset. Parsed best-effort for
    /// sorting and an urgency indicator; the raw string is always shown too so a parse failure
    /// never hides information, it just loses the color cue.
    var ackDeadline: Date? {
        guard let ackDeadlineRaw else { return nil }
        return HermesFleetService.naiveDateFormatter.date(from: ackDeadlineRaw)
    }
}

struct HermesRosterEntry: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var model: String
    var gatewayState: String
    var alias: String
}

struct HermesGatewayStatus: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var running: Bool
    var pid: Int?
}

struct HermesIntegrityStatus: Codable, Hashable {
    var checkedAtRaw: String?
    var agentCount: Int?
    var clean: Bool?
    var issues: [String]

    /// Covers both the server's schema (four separate name arrays, flattened into `issues` with
    /// a label prefix) and this app's own persisted schema (`issues` written directly by
    /// `encode(to:)`), the same dual-format approach as `HermesDecisionQueueItem`.
    private enum CodingKeys: String, CodingKey {
        case agentCount = "agents"
        case clean
        case checkedAtRaw = "checked_at"
        case issues
        case missingProfileSymlink = "missing_profile_symlink"
        case brokenProfileSymlink = "broken_profile_symlink"
        case profileNotASymlink = "profile_not_a_symlink"
        case maskedFleetUnits = "masked_fleet_units"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkedAtRaw = try container.decodeIfPresent(String.self, forKey: .checkedAtRaw)
        agentCount = try container.decodeIfPresent(Int.self, forKey: .agentCount)
        clean = try container.decodeIfPresent(Bool.self, forKey: .clean)
        if let persistedIssues = try container.decodeIfPresent([String].self, forKey: .issues) {
            issues = persistedIssues
        } else {
            var found: [String] = []
            for (key, label) in [
                (CodingKeys.missingProfileSymlink, "missing profile symlink"),
                (CodingKeys.brokenProfileSymlink, "broken profile symlink"),
                (CodingKeys.profileNotASymlink, "profile not a symlink"),
                (CodingKeys.maskedFleetUnits, "masked fleet unit"),
            ] {
                let names = (try? container.decodeIfPresent([String].self, forKey: key)) ?? nil ?? []
                found.append(contentsOf: names.map { "\(label): \($0)" })
            }
            issues = found
        }
    }

    init(checkedAtRaw: String?, agentCount: Int?, clean: Bool?, issues: [String]) {
        self.checkedAtRaw = checkedAtRaw
        self.agentCount = agentCount
        self.clean = clean
        self.issues = issues
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(checkedAtRaw, forKey: .checkedAtRaw)
        try container.encodeIfPresent(agentCount, forKey: .agentCount)
        try container.encodeIfPresent(clean, forKey: .clean)
        try container.encode(issues, forKey: .issues)
    }

    var checkedAt: Date? {
        guard let checkedAtRaw else { return nil }
        return HermesFleetService.naiveDateFormatter.date(from: checkedAtRaw)
    }
}

struct HermesFleetSnapshot: Codable, Hashable {
    var fetchedAt: Date
    var version: String
    var profileCount: Int
    var activeGateways: Int
    var kanbanSummary: String
    var agents: [HermesAgentSnapshot]
    var kanbanHealth: HermesKanbanHealth?
    var decisionQueue: [HermesDecisionQueueItem]?
    var roster: [HermesRosterEntry]?
    var gateways: [HermesGatewayStatus]?
    var integrity: HermesIntegrityStatus?
}

enum HermesConnectorError: LocalizedError {
    case invalidHost
    case invalidLayout
    case commandFailed(String)
    case malformedResponse
    case noProfilesFound(searched: String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            "The SSH host must contain only letters, numbers, dots, underscores, or hyphens."
        case .invalidLayout:
            "The fleet paths must be relative and may contain only letters, numbers, dots, "
                + "underscores, hyphens, slashes, @ and *."
        case .noProfilesFound(let searched):
            "No agent profiles were found in ~/\(searched) on the remote host. If your agents "
                + "live elsewhere, change the profiles path in Settings."
        case .commandFailed(let message):
            "Hermes telemetry failed: \(message)"
        case .malformedResponse:
            "The Hermes host returned an unrecognized telemetry response."
        }
    }
}

/// Reads a Hermes fleet over SSH: one hardened, read-only round trip that returns kanban shape,
/// the open decision queue, roster, gateway process liveness, structural fleet integrity, and
/// per-agent token telemetry.
///
/// This is not Shadowfetch-specific. Any Hermes install works, provided its host is reachable by
/// `ssh <host>` (whatever that resolves via ~/.ssh/config) and its profiles/tools/state
/// directories match Settings (defaults assume the stock `~/.hermes-shadowfetch/` layout).
///
/// No aggregate "duty success rate" is reported anywhere in this file, because no such number
/// exists on a Hermes install to read - `hermes` and its sibling scripts report kanban shape,
/// decision-queue shape, fleet structural integrity, and per-agent counters, not a synthesized
/// success percentage. Inventing one here would be exactly the kind of manufactured confidence
/// this app's own Decision Lab exists to refuse elsewhere.
///
/// Redaction: kanban cards and decisions carry a free-text body (`body`/`context`) that, on a
/// real install, contains internal strategic content (named-executive decisions, support-queue
/// specifics, App Store routing negotiations). `HermesKanbanCard` and `HermesDecisionQueueItem`
/// simply never declare those keys, so `JSONDecoder` drops them before a value exists - there is
/// no filtering step downstream to get wrong or forget.
enum HermesFleetService {
    /// Hermes' own timestamps (`decide.py`, `fleet_integrity.py`) are naive local time with no
    /// offset, e.g. "2026-08-02T22:28:07". Shared across all naive-timestamp decoding here.
    static let naiveDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let jsonDecoder: JSONDecoder = JSONDecoder()

    static func fetchFleetSnapshot(
        host: String,
        profilesPath: String = ".hermes-shadowfetch/profiles",
        toolsPath: String = ".hermes-shadowfetch/bin",
        statePath: String = ".hermes-shadowfetch/state",
        gatewayUnitPattern: String = "hermes-gw@*.service"
    ) async throws -> HermesFleetSnapshot {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !host.isEmpty, host.unicodeScalars.allSatisfy(allowed.contains) else {
            throw HermesConnectorError.invalidHost
        }

        // These are interpolated into a command that runs on the remote host, so they are an
        // injection surface exactly like the hostname is. Slashes are allowed because a path
        // needs them; quotes, spaces, $ and backticks are not.
        let pathAllowed = allowed.union(CharacterSet(charactersIn: "/@*"))
        func validPath(_ value: String) -> Bool {
            !value.isEmpty
                && value.unicodeScalars.allSatisfy(pathAllowed.contains)
                && !value.hasPrefix("/")
                && !value.contains("..")
        }
        guard validPath(profilesPath), validPath(toolsPath), validPath(statePath),
              !gatewayUnitPattern.isEmpty,
              gatewayUnitPattern.unicodeScalars.allSatisfy(pathAllowed.contains) else {
            throw HermesConnectorError.invalidLayout
        }

        let remoteCommand = #"""
HERMES_BIN="$(command -v hermes 2>/dev/null || true)"
if [ -z "$HERMES_BIN" ] && [ -x "$HOME/.local/bin/hermes" ]; then HERMES_BIN="$HOME/.local/bin/hermes"; fi
DECIDE_BIN=""
if [ -x "$HOME/\#(toolsPath)/decide.py" ]; then DECIDE_BIN="$HOME/\#(toolsPath)/decide.py"; fi

echo '===VERSION==='
if [ -n "$HERMES_BIN" ]; then "$HERMES_BIN" --version 2>/dev/null | head -1; else printf 'Unavailable\n'; fi

echo '===PROFILE_COUNT==='
find "$HOME/\#(profilesPath)" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '

echo '===ACTIVE_GATEWAYS==='
systemctl --user list-units '\#(gatewayUnitPattern)' --state=running --no-legend 2>/dev/null | wc -l | tr -d ' '

echo '===KANBAN_STATS==='
if [ -n "$HERMES_BIN" ]; then "$HERMES_BIN" kanban stats --json 2>/dev/null; fi

echo '===KANBAN_BLOCKED==='
if [ -n "$HERMES_BIN" ]; then "$HERMES_BIN" kanban list --status blocked --sort created --json 2>/dev/null; fi

echo '===DECISIONS==='
if [ -n "$DECIDE_BIN" ]; then python3 "$DECIDE_BIN" list --status open --json 2>/dev/null; fi

echo '===ROSTER==='
if [ -n "$HERMES_BIN" ]; then "$HERMES_BIN" profile list 2>/dev/null; fi

echo '===GATEWAYS==='
if [ -n "$HERMES_BIN" ]; then "$HERMES_BIN" gateway list 2>/dev/null; fi

echo '===INTEGRITY==='
cat "$HOME/\#(statePath)/fleet_integrity.json" 2>/dev/null

echo '===AGENTS==='
ACTIVE_NAMES="$(systemctl --user list-units '\#(gatewayUnitPattern)' --state=running --no-legend 2>/dev/null | sed -n 's/.*hermes-gw@\([^ ]*\)\.service.*/\1/p')"
for PROFILE in "$HOME/\#(profilesPath)"/*; do
  [ -d "$PROFILE" ] || continue
  NAME="$(basename "$PROFILE")"
  ACTIVE=0
  printf '%s\n' "$ACTIVE_NAMES" | grep -qx "$NAME" && ACTIVE=1
  INSIGHTS=""
  if [ -n "$HERMES_BIN" ]; then INSIGHTS="$(HERMES_HOME="$PROFILE" "$HERMES_BIN" insights --days 30 2>/dev/null)"; fi
  SESSIONS="$(printf '%s\n' "$INSIGHTS" | sed -n 's/.*Sessions:[[:space:]]*\([0-9,]*\).*/\1/p' | head -1 | tr -d ',')"
  MESSAGES="$(printf '%s\n' "$INSIGHTS" | sed -n 's/.*Messages:[[:space:]]*\([0-9,]*\).*/\1/p' | head -1 | tr -d ',')"
  TOOLS="$(printf '%s\n' "$INSIGHTS" | sed -n 's/.*Tool calls:[[:space:]]*\([0-9,]*\).*/\1/p' | head -1 | tr -d ',')"
  INPUT="$(printf '%s\n' "$INSIGHTS" | sed -n 's/.*Input tokens:[[:space:]]*\([0-9,]*\).*/\1/p' | head -1 | tr -d ',')"
  OUTPUT="$(printf '%s\n' "$INSIGHTS" | sed -n 's/.*Output tokens:[[:space:]]*\([0-9,]*\).*/\1/p' | head -1 | tr -d ',')"
  TOTAL="$(printf '%s\n' "$INSIGHTS" | sed -n 's/.*Total tokens:[[:space:]]*\([0-9,]*\).*/\1/p' | head -1 | tr -d ',')"
  printf 'AGENT\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$NAME" "$ACTIVE" "${SESSIONS:-0}" "${MESSAGES:-0}" "${TOOLS:-0}" "${INPUT:-0}" "${OUTPUT:-0}" "${TOTAL:-0}"
done
echo '===END==='
"""#

        let result = try await run(
            executable: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=8",
                // "--" ends option parsing. The host charset permits "-", and ssh reads a
                // leading dash as a flag, so without this a host of "-Fsomething" is an
                // option rather than a destination. The charset excludes "=", "/" and space,
                // which makes the classic -oProxyCommand= route impractical, but relying on
                // a character class to be exhaustive is the weaker of the two guarantees.
                "--",
                host,
                remoteCommand
            ]
        )
        guard result.status == 0 else {
            throw HermesConnectorError.commandFailed(result.error.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try parse(result.output, searchedPath: profilesPath)
    }

    /// Splits the combined remote output on its `===MARKER===` section headers and parses each
    /// section with the format appropriate to it (line-oriented for VERSION/PROFILE_COUNT/
    /// ACTIVE_GATEWAYS/AGENTS, JSON for KANBAN_STATS/KANBAN_BLOCKED/DECISIONS/INTEGRITY, and the
    /// two remaining Hermes CLI text tables for ROSTER/GATEWAYS).
    static func parse(
        _ output: String,
        searchedPath: String = ".hermes-shadowfetch/profiles"
    ) throws -> HermesFleetSnapshot {
        var sections: [String: String] = [:]
        var currentKey: String?
        var currentLines: [String] = []
        func flush() {
            if let key = currentKey {
                sections[key] = currentLines.joined(separator: "\n")
            }
            currentLines = []
        }
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text.hasPrefix("===") && text.hasSuffix("===") {
                flush()
                currentKey = String(text.dropFirst(3).dropLast(3))
                continue
            }
            currentLines.append(text)
        }
        flush()

        var version = "Unknown"
        var profileCount = 0
        var activeGateways = 0
        var agents: [HermesAgentSnapshot] = []

        for line in (sections["VERSION"] ?? "").split(whereSeparator: \.isNewline) where !line.isEmpty {
            version = String(line)
            break
        }
        if let raw = sections["PROFILE_COUNT"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            profileCount = Int(raw) ?? 0
        }
        if let raw = sections["ACTIVE_GATEWAYS"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            activeGateways = Int(raw) ?? 0
        }
        for line in (sections["AGENTS"] ?? "").split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.first == "AGENT", parts.count >= 9 else { continue }
            agents.append(
                HermesAgentSnapshot(
                    name: parts[1],
                    isGatewayActive: parts[2] == "1",
                    sessions: Int(parts[3]) ?? 0,
                    messages: Int(parts[4]) ?? 0,
                    toolCalls: Int(parts[5]) ?? 0,
                    inputTokens: Int64(parts[6]) ?? 0,
                    outputTokens: Int64(parts[7]) ?? 0,
                    totalTokensReported: Int64(parts[8]) ?? 0
                )
            )
        }

        guard profileCount > 0 || !agents.isEmpty else {
            throw HermesConnectorError.noProfilesFound(searched: searchedPath)
        }

        let kanbanHealth = parseKanbanHealth(
            statsJSON: sections["KANBAN_STATS"],
            blockedJSON: sections["KANBAN_BLOCKED"]
        )
        let decisionQueue = parseDecisionQueue(sections["DECISIONS"])
        let roster = parseRoster(sections["ROSTER"])
        let gateways = parseGateways(sections["GATEWAYS"])
        let integrity = parseIntegrity(sections["INTEGRITY"])
        let kanbanSummary = kanbanHealth.map { health in
            health.byStatus
                .sorted { $0.key < $1.key }
                .map { "\($0.key) \($0.value)" }
                .joined(separator: ", ")
        } ?? ""

        return HermesFleetSnapshot(
            fetchedAt: Date(),
            version: version,
            profileCount: profileCount,
            activeGateways: activeGateways,
            kanbanSummary: kanbanSummary,
            agents: agents.sorted { $0.name < $1.name },
            kanbanHealth: kanbanHealth,
            decisionQueue: decisionQueue,
            roster: roster,
            gateways: gateways,
            integrity: integrity
        )
    }

    private static func parseKanbanHealth(statsJSON: String?, blockedJSON: String?) -> HermesKanbanHealth? {
        struct StatsDTO: Decodable {
            var byStatus: [String: Int]
            private enum CodingKeys: String, CodingKey { case byStatus = "by_status" }
        }
        guard let statsJSON,
              let data = statsJSON.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              !data.isEmpty,
              let stats = try? jsonDecoder.decode(StatsDTO.self, from: data) else {
            return nil
        }
        var blocked: [HermesKanbanCard] = []
        if let blockedJSON,
           let blockedData = blockedJSON.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
           !blockedData.isEmpty {
            blocked = (try? jsonDecoder.decode([HermesKanbanCard].self, from: blockedData)) ?? []
        }
        return HermesKanbanHealth(
            byStatus: stats.byStatus,
            oldestBlocked: Array(blocked.sorted { ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture) }.prefix(10))
        )
    }

    private static func parseDecisionQueue(_ json: String?) -> [HermesDecisionQueueItem]? {
        guard let json,
              let data = json.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              !data.isEmpty else { return nil }
        return try? jsonDecoder.decode([HermesDecisionQueueItem].self, from: data)
    }

    private static func parseIntegrity(_ json: String?) -> HermesIntegrityStatus? {
        guard let json,
              let data = json.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              !data.isEmpty else { return nil }
        return try? jsonDecoder.decode(HermesIntegrityStatus.self, from: data)
    }

    /// `hermes profile list` prints a fixed header, a rule of box-drawing dashes, then one row
    /// per profile with columns separated by runs of 2+ spaces (exact column widths vary with
    /// the longest value in each, so splitting on fixed offsets is not reliable - splitting on
    /// whitespace runs is). The synthetic "default" template profile is not a real employee and
    /// is excluded.
    private static func parseRoster(_ text: String?) -> [HermesRosterEntry]? {
        guard let text else { return nil }
        var entries: [HermesRosterEntry] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("Profile"), !trimmed.hasPrefix("─") else { continue }
            let columns = trimmed
                .split(separator: /\s{2,}/)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count >= 3 else { continue }
            var name = columns[0]
            name = String(name.drop(while: { !$0.isLetter && !$0.isNumber }))
            guard !name.isEmpty, name.lowercased() != "default" else { continue }
            entries.append(
                HermesRosterEntry(
                    name: name,
                    model: columns[1],
                    gatewayState: columns[2],
                    alias: columns.count > 3 ? columns[3] : "—"
                )
            )
        }
        return entries.isEmpty ? nil : entries.sorted { $0.name < $1.name }
    }

    /// `hermes gateway list` prints "Gateways:" then one "✓/✗ name — PID N" or
    /// "✓/✗ name — not running" line per profile. The synthetic "default (current)" entry is
    /// excluded the same way the roster parser excludes it.
    private static func parseGateways(_ text: String?) -> [HermesGatewayStatus]? {
        guard let text else { return nil }
        var entries: [HermesGatewayStatus] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("✓") || trimmed.hasPrefix("✗") else { continue }
            let running = trimmed.hasPrefix("✓")
            let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            guard let dashRange = rest.range(of: "—") else { continue }
            var name = rest[rest.startIndex..<dashRange.lowerBound].trimmingCharacters(in: .whitespaces)
            if let parenRange = name.range(of: "(current)") {
                name = String(name[name.startIndex..<parenRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            guard !name.isEmpty, name.lowercased() != "default" else { continue }
            let tail = rest[dashRange.upperBound...].trimmingCharacters(in: .whitespaces)
            var pid: Int?
            if tail.hasPrefix("PID") {
                pid = Int(tail.dropFirst(3).trimmingCharacters(in: .whitespaces))
            }
            entries.append(HermesGatewayStatus(name: name, running: running, pid: pid))
        }
        return entries.isEmpty ? nil : entries.sorted { $0.name < $1.name }
    }

    private static func run(executable: URL, arguments: [String]) async throws -> (
        status: Int32,
        output: String,
        error: String
    ) {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            try process.run()

            // DRAIN BEFORE WAITING. The previous order was waitUntilExit() first, then
            // readDataToEndOfFile(). A pipe holds about 64 KB; once the child fills it the
            // child blocks on write while the parent blocks on wait, and neither ever moves.
            // Nothing recovers from that - the app hangs with no error, forever. Reading
            // concurrently on both descriptors is what makes the wait safe.
            let outputTask = Task.detached(priority: .userInitiated) {
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            }
            let errorTask = Task.detached(priority: .userInitiated) {
                errorPipe.fileHandleForReading.readDataToEndOfFile()
            }

            // A watchdog, because ConnectTimeout only bounds the TCP handshake. A remote
            // command that connects and then hangs would otherwise never return.
            let watchdog = DispatchWorkItem { [weak process] in
                guard let process, process.isRunning else { return }
                process.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: watchdog)

            process.waitUntilExit()
            let (outputData, errorData) = await (outputTask.value, errorTask.value)
            watchdog.cancel()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            return (process.terminationStatus, output, error)
        }.value
    }
}
