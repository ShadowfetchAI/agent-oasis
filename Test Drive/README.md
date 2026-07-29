# Agent Oasis Test Drive

## Build

- Version: 0.1 (1)
- Bundle ID: `com.realbobcorbin.AgentOasis`
- Minimum macOS: 14.0
- Architectures: Apple silicon and Intel
- Signing: Apple Development, hardened runtime
- Zip SHA-256:
  `c00a0bb1a38377f3e51dbf5ec8d8fdd429c2317a81140be08bb8efe0f86b3133`

## First Launch

Agent Oasis opens locked. Touch ID or the Mac password unlocks the local
workspace. The first successful unlock creates encrypted sample data at:

`~/Library/Application Support/Agent Oasis/workspace.aovault`

The encryption key is stored in this Mac's Keychain. Export the encrypted
backup and store its separately revealed recovery key before replacing the
sample workspace with important data.

## Connections

- Hermes Fleet: read-only SSH telemetry through the configured host alias.
- App Store Connect: live, read-only app records using a `.p8` key stored in
  the encrypted vault.
- Sales and Trends: CSV or TSV import for units and financial observations.
- Credential Inventory: file metadata and permissions only; secret contents
  are not opened.

App Store authentication alone does not create financial observations. Import
a Sales and Trends report until the separate financial-report API workflow is
configured and validated.
