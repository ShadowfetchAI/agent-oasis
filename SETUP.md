# Setting up Agent Oasis

Agent Oasis starts with an **empty** workspace — it never invents records — and runs fully
offline. The sections below are for connecting it to your own data. All of them are optional.

## 1. Install or build

The easiest path is the signed, notarized DMG on the
[latest release](https://github.com/ShadowfetchAI/agent-oasis/releases/latest). Open it and
drag Agent Oasis to Applications.

To build from source:

```sh
brew install xcodegen
git clone https://github.com/ShadowfetchAI/agent-oasis.git
cd agent-oasis
xcodegen generate
open AgentOasis.xcodeproj
```

Press ⌘R. That's it — no account, no API key, no team ID required.

To build from the command line without signing:

```sh
xcodebuild -project AgentOasis.xcodeproj -scheme AgentOasis \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

### Signing with your own Apple team

Copy `.envrc.example` to `.envrc`, fill in your Team ID and bundle prefix, then re-run
`xcodegen generate`. Nothing in the repo is pinned to the original author's account.

```sh
export AGENT_OASIS_DEVELOPMENT_TEAM=ABCDE12345
export AGENT_OASIS_BUNDLE_PREFIX=com.yourdomain
```

## 2. App Store Connect (optional)

Lets Agent Oasis read your own app records. It is **read-only** and never submits anything.

1. Go to [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api).
2. Create a key with the **Developer** role — that is enough for reading app records, and the
   least privilege that works. Do not grant Admin.
3. Download the `.p8`. **Apple lets you download it exactly once.**
4. Note the **Key ID**. Note the **Issuer ID** too if this is a team key; leave Issuer blank
   for an individual key.
5. In Agent Oasis: **Vault → Add item**, choose the `.p8`, then **Connections → App Store
   Connect** and enter the Key ID.

The `.p8` is stored in the encrypted workspace, never in plaintext, and is used only to sign
a short-lived (15 minute) ES256 token sent to `api.appstoreconnect.apple.com`.

**App records are not financial data.** To get proceeds and units, download a Sales and Trends
report from App Store Connect and import it with the toolbar Import button. Agent Oasis will
not silently infer revenue it has not been given.

## 3. Fleet telemetry (optional)

Reads agent activity over SSH. Read-only; it runs one command and parses the output.

1. Make sure `ssh yourhost` works non-interactively (key-based, no password prompt).
2. **Settings → Remote host**: your SSH alias.
3. **Settings → Profiles path**: where agent profiles live, relative to `$HOME`.
   Default `.hermes-shadowfetch/profiles`.
4. **Settings → Gateway unit pattern**: the systemd `--user` unit pattern for a running
   agent. Default `hermes-gw@*.service`.

If nothing is found, the error names the directory it searched so you can correct the path.

## 4. Back up before you rely on it

**Vault → Export encrypted backup**, and **Vault → Reveal recovery key** (stored separately).
The workspace is encrypted with a key held in your Mac's Keychain — lose the Mac without a
backup and the data is gone. This is early software; treat it accordingly.

## What leaves your machine

Two hosts appear anywhere in the source:

| host | when |
|---|---|
| `api.appstoreconnect.apple.com` | only if you configure an App Store Connect key |
| your SSH host | only if you configure fleet telemetry |

No analytics, no telemetry, no crash reporting, no update check. Verify it yourself:

```sh
grep -rhoE "https?://[a-zA-Z0-9.-]+" AgentOasis | sort -u
```
