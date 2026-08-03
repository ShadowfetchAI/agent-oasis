# Agent Oasis 2.0 test drive

## Build profile

- Marketing version: 2.0.0
- Build: 5
- Minimum macOS: 14.0
- Architectures: Apple silicon and Intel
- Official distribution: Developer ID Application, Hardened Runtime, notarized DMG
- Workspace: local AES-256-GCM encrypted file

The exact bundle identifier, Developer ID signature, notarization result, DMG size, and
SHA-256 checksum are published with each GitHub release. Do not copy these values from an old
test-drive note; verify the downloaded artifact itself.

## First launch

Agent Oasis opens locked. Touch ID or the Mac password unlocks an empty local workspace.
The app does not create sample revenue, products, agents, or experiments.

Before adding important data:

1. Set the base currency in Settings.
2. Export an encrypted backup.
3. Reveal the recovery key and store it separately.
4. Add one real record or preview an import.

## Flagship walkthrough

1. **Portfolio** - add a product or import App Store evidence.
2. **Agents** - record actual operating cost and label capacity assumptions.
3. **Ledger** - confirm the base-currency cash total and any excluded-currency disclosure.
4. **Experiments** - add a baseline and record a confounder to see attribution refusal.
5. **Decision Lab / Portfolio** - inspect the evidence-ranked next-decision queue.
6. **Decision Lab / Agents** - compare measured cash and modelled value separately.
7. **Decision Lab / Scenario Studio** - test price and unit assumptions without changing the
   ledger.
8. **Decision Lab / Briefing** - capture a checkpoint and export an HTML executive brief.
9. **Audit** - verify the hash chain and confirm no secret value appears in event summaries.
10. **Lock** - use `Command-Shift-L`, then authenticate again.

## Optional connections

- **App Store Connect app records**: read-only API key stored in the vault.
- **App Store Connect Sales and Reports**: optional separate read-only key plus Vendor Number.
- **Hermes Fleet**: read-only SSH telemetry through an operator-configured alias.
- **Credential Inventory**: filename and permission metadata only; candidate files are not
  opened.

See [SETUP.md](../SETUP.md) for configuration and
[docs/APP-STORE-CONNECT.md](../docs/APP-STORE-CONNECT.md) for Apple report semantics.

## Release verification

After downloading the DMG:

```sh
shasum -a 256 Agent-Oasis-2.0.0.dmg
spctl --assess --type open --context context:primary-signature -v Agent-Oasis-2.0.0.dmg
xcrun stapler validate Agent-Oasis-2.0.0.dmg
```

Compare the checksum with the value on the GitHub release page.
