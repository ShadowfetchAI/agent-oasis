# Agent Oasis

A native macOS operating ledger for products, agents, APIs, experiments, costs, and
business value. Local-first, encrypted on disk, no server and no account.

macOS 14+ · SwiftUI + Charts · MIT licensed

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
- Read-only App Store Connect app-record sync using a vault-held `.p8` key
- App Store Sales and Trends import for units and financial observations
- Cash and modelled-value ledger with per-entry confidence
- Experiment timeline with baselines, confounders and honest attribution
- Per-agent cost, supervision, capacity, revenue influence and ROI — split by provenance
- Read-only fleet telemetry over an SSH alias, with a configurable profiles path
- Encrypted secret vault and a metadata-only credential inventory
- Owner-authenticated encrypted backup, recovery key, plaintext CSV export
- Append-only audit trail that never records secret values

## Install

No signed binary release yet. Agent Oasis needs a Developer ID certificate to pass Gatekeeper
on someone else's Mac, and shipping an unsigned build that dies at a security warning is worse
than shipping none. **Build from source for now** — it takes about a minute.

## Build

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). `project.yml` is the source of truth; the `.xcodeproj` is
generated and not committed.

```sh
xcodegen generate
xcodebuild -project AgentOasis.xcodeproj -scheme AgentOasis \
  -destination 'platform=macOS' -derivedDataPath DerivedData test
```

`project.yml` pins `DEVELOPMENT_TEAM` to the original author's team. To build without an
Apple Developer account, pass `CODE_SIGNING_ALLOWED=NO` (this is what CI does) or set your
own team ID.

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

- **The Keychain item is not yet in the data protection keychain.** That requires a
  `keychain-access-groups` entitlement and a provisioning profile. `KeychainService` probes
  for it at launch and falls back to the legacy keychain rather than refusing to start, so
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is **not currently enforced**. See the
  comment in `AgentOasis.entitlements`.
- **The Touch ID gate is advisory, not cryptographic.** The workspace key is not bound to
  biometry with `SecAccessControl`, so a process running as you can read it from the Keychain
  without passing the gate. The gate protects the interface, not the key.
- **The app is not sandboxed.** It spawns `/usr/bin/ssh` for fleet telemetry, which the
  sandbox forbids. This is a deliberate trade for a directly-distributed tool and it is why
  Agent Oasis is not a Mac App Store app.
- **The Touch ID gate is not bound to the key.** See above — this is the most meaningful
  remaining gap.

## Tests

```sh
xcodebuild -project AgentOasis.xcodeproj -scheme AgentOasis \
  -destination 'platform=macOS' test
```

25 tests cover the cipher (round trip, tamper detection, wrong-key rejection, file mode),
the App Store Connect JWT, the delimited-text importers, and the provenance rules above —
including that a fully-estimated agent reports zero confidence, that a workspace written
before provenance existed decodes as estimated rather than silently claiming measurement, and
that the configurable fleet paths reject shell injection and `..` escapes.

## Licence

MIT. See [LICENSE](LICENSE).
