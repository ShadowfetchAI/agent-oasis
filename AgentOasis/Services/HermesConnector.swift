import Foundation

struct HermesAgentSnapshot: Hashable {
    var name: String
    var isGatewayActive: Bool
    var sessions: Int
    var messages: Int
    var toolCalls: Int
    var inputTokens: Int64
    var outputTokens: Int64
    var totalTokensReported: Int64
}

struct HermesFleetSnapshot: Hashable {
    var fetchedAt: Date
    var version: String
    var profileCount: Int
    var activeGateways: Int
    var kanbanSummary: String
    var agents: [HermesAgentSnapshot]
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

enum HermesConnector {
    static func fetchFleetSnapshot(
        host: String,
        profilesPath: String = ".hermes-shadowfetch/profiles",
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
        guard !profilesPath.isEmpty,
              profilesPath.unicodeScalars.allSatisfy(pathAllowed.contains),
              !profilesPath.hasPrefix("/"),
              !profilesPath.contains(".."),
              !gatewayUnitPattern.isEmpty,
              gatewayUnitPattern.unicodeScalars.allSatisfy(pathAllowed.contains) else {
            throw HermesConnectorError.invalidLayout
        }

        let remoteCommand = #"""
HERMES_BIN="$(command -v hermes 2>/dev/null || true)"
if [ -z "$HERMES_BIN" ] && [ -x "$HOME/.local/bin/hermes" ]; then HERMES_BIN="$HOME/.local/bin/hermes"; fi
printf 'VERSION\t'
if [ -n "$HERMES_BIN" ]; then "$HERMES_BIN" --version 2>/dev/null | head -1; else printf 'Unavailable\n'; fi
printf 'PROFILE_COUNT\t'
find "$HOME/\#(profilesPath)" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '
printf '\nACTIVE_GATEWAYS\t'
systemctl --user list-units '\#(gatewayUnitPattern)' --state=running --no-legend 2>/dev/null | wc -l | tr -d ' '
printf '\nKANBAN\t'
if [ -n "$HERMES_BIN" ]; then "$HERMES_BIN" kanban stats 2>/dev/null | tr '\n' ' ' | tr '\t' ' '; fi
printf '\n'
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

    static func parse(
        _ output: String,
        searchedPath: String = ".hermes-shadowfetch/profiles"
    ) throws -> HermesFleetSnapshot {
        var version = "Unknown"
        var profileCount = 0
        var activeGateways = 0
        var kanban = ""
        var agents: [HermesAgentSnapshot] = []

        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let key = parts.first else { continue }
            switch key {
            case "VERSION":
                if parts.count > 1 { version = parts[1] }
            case "PROFILE_COUNT":
                if parts.count > 1 { profileCount = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0 }
            case "ACTIVE_GATEWAYS":
                if parts.count > 1 { activeGateways = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0 }
            case "KANBAN":
                if parts.count > 1 { kanban = parts[1].trimmingCharacters(in: .whitespaces) }
            case "AGENT":
                guard parts.count >= 9 else { continue }
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
            default:
                continue
            }
        }

        guard profileCount > 0 || !agents.isEmpty else {
            throw HermesConnectorError.noProfilesFound(searched: searchedPath)
        }
        return HermesFleetSnapshot(
            fetchedAt: Date(),
            version: version,
            profileCount: profileCount,
            activeGateways: activeGateways,
            kanbanSummary: kanban,
            agents: agents.sorted { $0.name < $1.name }
        )
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
