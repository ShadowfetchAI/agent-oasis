# Security model

Agent Oasis is designed for financial records, agent telemetry, experiments, and API
credentials that should remain under the Mac owner's control.

## Protected assets

- workspace records and business checkpoints
- imported sales and ledger evidence
- agent and experiment data
- API private keys stored in the vault
- encrypted backup material

## Local storage

The workspace is encoded and encrypted with AES-256-GCM before it reaches Application
Support. Its symmetric key is stored in the macOS Keychain and protected by the app's
keychain access group in the official signed build.

Workspace, backup, and temporary sales-report files are created owner-only. Authentication
failure or ciphertext tampering does not produce a partially decoded workspace.

## Owner gate and locking

Touch ID or the Mac password gates unlock. The app can automatically lock after inactivity,
on Mac sleep, and on screen lock. Locking clears unlocked workspace state from the store.

This controls access through Agent Oasis; it does not claim to protect a compromised macOS
administrator account or a process already capable of inspecting another process's memory.

## Network boundary

There is no Shadowfetch backend. Network activity occurs only after explicit configuration:

- HTTPS requests to `api.appstoreconnect.apple.com` for App Store Connect sync.
- `/usr/bin/ssh` to the operator-configured alias for Hermes telemetry.

The app has no analytics, telemetry, crash reporting, advertising SDK, remote update check,
or hidden model/API call.

## Secret handling

- `.p8` keys are vault items inside the encrypted workspace.
- App Store Connect tokens are generated in memory and expire after 15 minutes.
- Audit events record action summaries, never secret values.
- Executive briefs exclude the vault and all API secrets.
- Credential inventory reads filename, size, date, and POSIX mode only; it does not open
  credential candidates.
- Temporary Apple report directories are randomized and removed after use.

## Integrity and recovery

Audit entries form a hash chain. Editing or removing a past entry makes chain verification
fail. The chain is evidence of workspace-history integrity; it is not a remote timestamp or
third-party notarization.

Encrypted backups use a separately revealed recovery key. Restore is staged and authenticated
before replacing the workspace. Failed recovery leaves the existing file untouched, and
destructive operations retain a pre-operation copy.

## Distribution hardening

Official releases use:

- Developer ID Application signing
- Hardened Runtime
- `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` in Release, preventing accidental shipment of the
  development `get-task-allow` entitlement
- Apple notarization and ticket stapling
- SHA-256 checksum publication
- universal arm64 and x86_64 binary

## Deliberate limitations

1. **Not sandboxed.** Optional fleet telemetry invokes `/usr/bin/ssh`, which conflicts with
   the Mac App Sandbox. Agent Oasis is directly distributed rather than submitted to the Mac
   App Store.
2. **Unsigned source-build fallback.** A source build without the official provisioning
   profile cannot use the release keychain access group. It uses the compatibility keychain
   path so a developer is not locked out.
3. **Plaintext exports.** CSV, Markdown, and HTML exports are intentionally readable outside
   the app and are not protected by workspace encryption.
4. **Local compromise.** Malware or an administrator with sufficient access to the running
   user account can defeat local application protections.
5. **No automatic FX conversion.** This is an accounting integrity choice, not a missing
   security feature; users must convert currencies through a source they trust.

## Reporting a vulnerability

Open a private security advisory in the
[GitHub repository](https://github.com/ShadowfetchAI/agent-oasis/security/advisories/new)
instead of publishing active exploit details in a public issue.
