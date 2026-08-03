# Hermes Fleet

Hermes Fleet is a read-only dashboard for a live [Hermes](https://github.com/ShadowfetchAI)
agentic-operations install: kanban shape, the open decision queue, roster, gateway process
liveness, and structural fleet integrity, read over SSH in one hardened round trip.

This is not Shadowfetch-specific. Any Hermes install works, provided its host answers to
`ssh <host>` (whatever that resolves via `~/.ssh/config`) and its profiles, tools, and state
directories match Settings. The defaults assume the stock `~/.hermes-shadowfetch/` layout; every
path is configurable precisely because a hardcoded path would only ever work on the machine it
was written against.

## What is read, and how

One SSH connection per sync, running a single combined command that emits tagged sections. Each
domain below names the exact command behind it:

| Section | Command | Format |
|---|---|---|
| Version, profile count, active gateways | `hermes --version`, a directory listing, `systemctl --user list-units` | plain text |
| Kanban shape | `hermes kanban stats --json` | JSON |
| Oldest blocked cards | `hermes kanban list --status blocked --sort created --json` | JSON |
| Decision queue | `decide.py list --status open --json` | JSON |
| Roster | `hermes profile list` | text table |
| Gateway process liveness | `hermes gateway list` | text |
| Fleet structural integrity | `cat .../state/fleet_integrity.json` (written by `fleet_integrity.py`) | JSON |
| Per-agent telemetry | `hermes insights --days 30`, once per profile | text, scraped |

## What is never read

Kanban cards and decisions carry a free-text body (`body` on a card, `context`/`recommendation`/
`options` on a decision) that on a real install contains internal, often strategic content -
named-executive decisions, support-queue specifics, commercial routing negotiations. Agent Oasis
never decodes it.

This is not a filtering step applied after the fact - it is the absence of a property to decode
into. `HermesKanbanCard` and `HermesDecisionQueueItem` (`AgentOasis/Services/HermesConnector.swift`)
declare `id`, `title`, `assignee`/`raisedBy`, `status`, `priority`/`authority`, and
`createdAt`/`ackDeadline`. They do not declare `body`, `context`, `recommendation`, `options`, or
`links`. `JSONDecoder` drops undeclared keys before a Swift value exists; there is nothing to
remember to strip, because there is nothing written that could hold it. `ackCount` is derived by
counting the `acks` array's elements against a zero-property placeholder type, so even the
existence of an acknowledgement is kept without its free-text note.

`HermesFleetServiceTests.swift` locks this in two ways: `testKanbanCardBodyNeverDecodes` and the
decision-queue equivalent feed a real, sensitive-looking body through the parser, then re-encode
the resulting model and assert the sensitive text is absent from the output - not just "no field
named body," but "the text is nowhere," which also catches a future refactor that copies body
text into a differently-named field.

## What is never invented

There is no fleet-wide "duty success rate" anywhere on a real Hermes install - not in `hermes`,
not in any of its sibling scripts under `~/.hermes-shadowfetch/bin/`. Hermes Fleet does not
synthesize one. It reports kanban shape, decision-queue shape, fleet structural integrity
(`clean`/`issues` from `fleet_integrity.py`), gateway process liveness, and per-agent token
counters - all things a real Hermes install can actually state, worded as what they are rather
than dressed up as a single confidence number. `testSnapshotHasNoFabricatedSuccessRateField`
in the test suite fails the build if a field matching that shape is ever added.

## Configuration

Settings exposes five values, all under the "Hermes Fleet" connection:

- **Host** - the SSH destination (`remoteHermesHost`, default `shadowfetch-linux`)
- **Profiles path** - relative to `$HOME` (`hermesProfilesPath`, default `.hermes-shadowfetch/profiles`)
- **Tools path** - relative to `$HOME`, where `decide.py` lives (`hermesToolsPath`, default `.hermes-shadowfetch/bin`)
- **State path** - relative to `$HOME`, where `fleet_integrity.json` is written (`hermesStatePath`, default `.hermes-shadowfetch/state`)
- **Gateway unit pattern** - the systemd `--user` unit glob for a running agent gateway (`hermesGatewayUnitPattern`, default `hermes-gw@*.service`)

Every one of these is validated before it reaches the remote command: relative only, no `..`, and
restricted to a charset that excludes quotes, `$`, backticks, and spaces - the same defense used
for the SSH hostname itself. `HermesFleetServiceTests.testNewPathParametersRejectInjectionAndEscape`
and `DemoAndHermesTests.testFleetLayoutRejectsInjectionAndEscape` exercise this directly.

## Threat model

- The SSH connection is read-only by construction: every remote command is a read (`cat`,
  `list`, `stats`, `--version`, `systemctl list-units`). Nothing on the remote host is started,
  stopped, written, or deleted.
- A 45-second watchdog terminates the SSH process if the remote command connects and then hangs;
  `ConnectTimeout=8` bounds the initial handshake separately.
- Output and error pipes are drained concurrently with the wait, not sequentially - a naive
  wait-then-read ordering can deadlock once the child fills a ~64 KB pipe buffer.
- Whatever authentication `ssh <host>` would normally use (key, agent, `~/.ssh/config` alias)
  applies unchanged; Agent Oasis supplies no credentials of its own and stores none for this
  connection.
- The app is not App Sandboxed because sandboxing would block the `/usr/bin/ssh` invocation this
  feature depends on. See [docs/SECURITY.md](SECURITY.md) for the complete threat model.
