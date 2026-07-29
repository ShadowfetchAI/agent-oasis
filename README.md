# Agent Oasis

Agent Oasis is a standalone native macOS operating ledger for products, agents,
APIs, experiments, costs, and attributable business value.

## Test-drive build

- macOS 14 or later
- SwiftUI and Charts
- AES-256-GCM encrypted workspace
- 256-bit workspace key stored in the macOS Keychain as
  `WhenUnlockedThisDeviceOnly`
- Touch ID or Mac password owner gate
- Automatic locking on inactivity, screen lock, and sleep
- Live read-only App Store Connect app-record sync using a vault-held `.p8` key
- App Store Sales and Trends report import for units and financial observations
- Cash and modeled-value ledger
- Experiment timeline with baselines and confounders
- Per-agent cost, supervision, capacity, revenue influence, and ROI
- Read-only Hermes fleet telemetry over the configured SSH alias
- Encrypted secret vault and metadata-only credential inventory
- Owner-authenticated encrypted backup restore, recovery key, and plaintext CSV exports
- Append-only audit trail that excludes secret values

The first launch creates an encrypted sample workspace. Replace or augment the
sample records through the app. Files under `Sample Imports` exercise both
supported import formats.

Configure App Store Connect with a Key ID, an optional Issuer ID (leave it
blank for an individual key), and a `.p8` private key stored in the Agent Oasis
vault. App-record sync does not imply financial access; import a Sales and
Trends report to add proceeds and units.

## Build

```sh
xcodegen generate
xcodebuild \
  -project AgentOasis.xcodeproj \
  -scheme AgentOasis \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  build
```

For UI validation without an authentication dialog, Debug builds accept the
`--demo-unlocked` launch argument. Release builds do not compile this bypass.

## Security boundaries

Agent Oasis does not operate a server. The workspace is encrypted before it is
written to Application Support. Connectors receive narrowly scoped credentials
inside the app process; agent prompts and audit summaries do not receive raw
secret values.

The credential inventory scans filenames, sizes, modification dates, and POSIX
permissions only. It never opens candidate files.

An exported CSV is intentionally plaintext. Encrypted `.oasisbackup` files need
the separately stored recovery key.
