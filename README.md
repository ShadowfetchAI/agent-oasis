# Agent Oasis

A native macOS operating ledger for products, agents, APIs, experiments, costs, and
business value. Local-first, encrypted on disk, no server and no account.

macOS 14+ · SwiftUI + Charts · MIT licensed

[Product page](https://www.shadowfetch.com/agent-oasis) ·
[Latest signed release](https://github.com/ShadowfetchAI/agent-oasis/releases/latest)

---

## The idea it is built around

Most tools that claim to measure what AI agents are "worth" quietly add three estimates to
one invoice and print an ROI. Agent Oasis refuses to do that.

Every value input carries its **provenance** — `measured` (imported or observed, and
re-derivable from a source) or `estimated` (a person typed it). Cash and modelled value are
computed separately, displayed separately, and **never summed anywhere in the app**:

| | what it is |
|---|---|
| **Cash** | money that actually moved: real costs, and revenue someone measured |
| **Modelled** | capacity value, avoided spend, asserted revenue — judgements, useful for planning |

**Nothing is ever fabricated.** A new workspace is empty. The app ships with no sample data
at all — not as a default, not behind a setting. `DemoWorkspace` lives in the test target, so
the shipped binary is structurally incapable of inventing a record, and a test walks the app
sources and fails if that machinery returns. Every figure you see is one you put there.

**Confidence measures evidence, not activity.** An agent with four hand-entered value inputs
scores **zero confidence** no matter how many tasks it completed today. Staleness can lower
that score; nothing can inflate it. If the number has no evidence behind it, the app says so
rather than dressing a guess in a percentage.

**Experiments refuse attribution when a confounder is recorded.** A lift figure a reader
cannot distinguish from seasonality is worse than no figure, because it gets repeated without
its caveat. The raw arithmetic is still available to anyone who explicitly asks for it.

## Features

- AES-256-GCM encrypted workspace, key held in the macOS Keychain
- Touch ID / Mac password owner gate, auto-lock on inactivity, sleep and screen lock
- **Attention Inbox** on Command Center — actionable gaps only (blocked agents, refused
  attribution, stale sources, zero-evidence modelled value, missing backups)
- **Command palette (⌘K)** plus ⌘1–⌘9 navigation, ⌘N create, ⌘I import, ⌘E export
- Import **preview** with drag-and-drop CSV/TSV — counts before anything is written
- Duplicate agents and experiments without inventing measured evidence
- Read-only App Store Connect app-record sync using a vault-held `.p8` key
- App Store Sales and Trends import for units and financial observations
- Cash and modelled-value ledger with per-entry confidence
- Experiment timeline with baselines, confounders and honest attribution
- Per-agent cost, supervision, capacity, revenue influence and ROI — split by provenance
- Read-only fleet telemetry over an SSH alias, with a configurable profiles path
- Encrypted secret vault and a metadata-only credential inventory
- Owner-authenticated encrypted backup, recovery key, plaintext CSV export
- Append-only audit trail, hash-chained so removing or editing an entry is detectable, and
 never recording secret values

## Install

Download the signed and notarized DMG from
[Releases](https://github.com/ShadowfetchAI/agent-oasis/releases/latest), open it, and drag
Agent Oasis to Applications. The release is universal for Apple Silicon and Intel Macs.

See [SETUP.md](SETUP.md) for App Store Connect, fleet telemetry and backups.

## Build

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). `project.yml` is the source of truth; the `.xcodeproj` is
generated and not committed.

```sh
xcodegen generate
xcodebuild -project AgentOasis.xcodeproj -scheme AgentOasis \
  -destination 'platform=macOS' -derivedDataPath DerivedData test
```

`project.yml` does not pin a developer account. To build without an Apple Developer account,
pass `CODE_SIGNING_ALLOWED=NO` (this is what CI does), or set your own team ID and bundle
prefix as described in [SETUP.md](SETUP.md).

Debug builds accept `--demo-unlocked`, which skips the authentication dialog for UI work and
automated capture. It is compiled out of Release builds.

## Security boundaries

There is no server. The workspace is encrypted before it touches Application Support, written
`0600` by creation rather than chmod-after-write, and connectors receive narrowly scoped
credentials inside the app process. Agent prompts and audit summaries never receive raw
secret values.

The credential inventory reads filenames, sizes, modification dates and POSIX permissions
only. It never opens a candidate file.

An exported CSV is intentionally plaintext. Encrypted `.oasisbackup` files require the
separately stored recovery key.

### Known limitations

Stated plainly, because a security section that only lists strengths is marketing.

- **The app is not sandboxed.** It spawns `/usr/bin/ssh` for fleet telemetry, which the
  sandbox forbids. This is a deliberate trade for a directly-distributed tool and it is why
  Agent Oasis is not a Mac App Store app.
- **Unsigned source builds use a compatibility fallback.** The official Developer ID release
  includes the provisioning profile and keychain entitlement needed for the data protection
  keychain. An unsigned local build cannot claim that entitlement, so it falls back to the
  legacy keychain rather than locking the owner out of an existing workspace.

## Tests

```sh
xcodebuild -project AgentOasis.xcodeproj -scheme AgentOasis \
  -destination 'platform=macOS' test
```

55+ tests cover the cipher (round trip, tamper detection, wrong-key rejection, file mode),
the App Store Connect JWT, the delimited-text importers, Attention Inbox rules, import
preview non-mutation, agent duplication provenance, and the provenance rules above —
including that a fully-estimated agent reports zero confidence, that a workspace written
before provenance existed decodes as estimated rather than silently claiming measurement, that
the configurable fleet paths reject shell injection and `..` escapes, and — added after an
audit found them — that an unreadable workspace is recoverable from a backup **while locked
out**, that a failed restore is a no-op on your data, and that re-importing the same sales
report does not double your revenue.

See [CHANGELOG.md](CHANGELOG.md) for release notes.

## Licence

MIT. See [LICENSE](LICENSE).
