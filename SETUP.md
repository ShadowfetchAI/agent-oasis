# Set up Agent Oasis

Agent Oasis starts empty and works offline. Connections are optional and read-only.

## 1. Install

Download the signed and notarized universal DMG from the
[latest GitHub release](https://github.com/ShadowfetchAI/agent-oasis/releases/latest).
Open the DMG, drag Agent Oasis to Applications, and launch it.

On first launch:

1. Authenticate with Touch ID or the Mac password.
2. Choose a base currency in Settings.
3. Export an encrypted backup.
4. Reveal the recovery key and store it separately from the backup.

The workspace is encrypted before it is written to:

```text
~/Library/Application Support/Agent Oasis/workspace.aovault
```

There is no sample company or hidden seed data. Add records manually, import CSV/TSV, or
configure one of the optional read-only connections below.

## 2. App Store Connect

Agent Oasis supports two independent jobs:

- **App records**: names, bundle IDs, platforms, and record state.
- **Sales reports**: Apple's latest available daily Summary Sales report, including units
  and developer proceeds.

Keeping separate keys is recommended because the Apple roles required for those jobs may
differ. Agent Oasis can reuse one key when your organization has deliberately granted it
both capabilities.

### Create the keys

1. Open [App Store Connect API integrations](https://appstoreconnect.apple.com/access/integrations/api).
2. Create the least-privileged key that can read app records.
3. Create a separate key that can read Sales and Reports.
4. Download each `.p8` file immediately. Apple permits a private key download only once.
5. Record each Key ID and, for team keys, the Issuer ID.
6. Find the Vendor Number in App Store Connect under Payments and Financial Reports.

Do not grant Admin merely to make setup easier. Role availability varies with App Store
Connect account type and Apple may change role names or permissions; verify the current
access table in App Store Connect before creating a key.

### Store the keys

1. In Agent Oasis, open **Vault**.
2. Add the app-record `.p8` as one vault item.
3. Add the Sales and Reports `.p8` as a second vault item when using separate keys.
4. Open **Connections** and edit **App Store Connect**.
5. Select the app-record vault item and enter its Issuer ID and Key ID.
6. Enter the Vendor Number.
7. Select the optional sales vault item and enter its Issuer ID and Key ID.
8. Save, then choose **Sync Apps & Sales**.

For an individual API key, leave Issuer ID blank. Agent Oasis creates a short-lived ES256
token with the correct individual-key subject. For a team key, Issuer ID is required.

### What sync does

The app-record request and sales request run independently. If one fails, successful data
from the other can still be imported and the failure remains visible on the connection.

The sales request uses Apple's documented endpoint and filters:

```text
GET /v1/salesReports
filter[frequency]=DAILY
filter[reportType]=SALES
filter[reportSubType]=SUMMARY
filter[vendorNumber]=YOUR_VENDOR_NUMBER
filter[version]=1_0
```

Apple returns a gzip report. Agent Oasis decompresses it in an owner-only temporary
directory, imports the text through the same previewed/idempotent pipeline as manual files,
and removes the temporary directory immediately.

Apple daily reports are not real-time. The latest available report may represent the prior
day or an earlier day. Agent Oasis preserves Apple's source date rather than labelling the
download time as the sales date.

For more detail, see [docs/APP-STORE-CONNECT.md](docs/APP-STORE-CONNECT.md).

## 3. Manual imports

Use the toolbar Import button or drop a CSV/TSV file on Command Center or Ledger. The preview
shows what will be added before any write occurs.

Agent Oasis recognizes official Apple Summary Sales columns, including Units, Developer
Proceeds, Proceeds Currency, Apple Identifier, SKU, Title, and Begin Date. Developer Proceeds
is a per-unit value in that report, so the importer multiplies it by signed units exactly
once. Re-importing the same source replaces matching evidence instead of double-counting it.

Generic ledger and observation files remain supported. Keep source filenames stable when
using corrected re-exports so idempotent replacement can identify the original import.

## 4. Hermes fleet telemetry

Fleet telemetry is read-only and optional. It runs one command over an SSH alias and parses
the returned profile and service metadata.

1. Confirm `ssh yourhost` works non-interactively with key authentication.
2. In Settings, set **Remote host** to that SSH alias.
3. Set **Profiles path** relative to the remote home directory. The default is
   `.hermes-shadowfetch/profiles`.
4. Set **Gateway unit pattern**. The default is `hermes-gw@*.service`.
5. Open Connections and sync Hermes Fleet.

Paths are validated before they reach the shell. Absolute paths, traversal with `..`, and
shell metacharacters are rejected.

## 5. Backups and recovery

An encrypted `.oasisbackup` is useful only with its recovery key.

- Export backups regularly and before major imports.
- Store the recovery key separately from both the Mac and the backup.
- Test recovery with a disposable workspace before relying on the process operationally.
- Plain CSV and executive-brief exports are intentionally unencrypted; protect them as you
  would any financial report.

If the primary workspace becomes unreadable, the recovery flow can restore a backup before
normal unlock. A failed restore leaves the existing bytes untouched. Destructive workspace
operations retain a pre-operation snapshot.

## 6. Build from source

```sh
brew install xcodegen
git clone https://github.com/ShadowfetchAI/agent-oasis.git
cd agent-oasis
xcodegen generate
xcodebuild -project AgentOasis.xcodeproj -scheme AgentOasis \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

To sign with your own Apple team:

```sh
export AGENT_OASIS_DEVELOPMENT_TEAM=ABCDE12345
export AGENT_OASIS_BUNDLE_PREFIX=com.yourdomain
xcodegen generate
```

Nothing in the repository is pinned to Shadowfetch's team or bundle prefix.

## Network boundary

Only two outbound destinations are possible in the application source:

| Destination | Trigger |
|---|---|
| `api.appstoreconnect.apple.com` | You configure and run App Store Connect sync |
| Your SSH alias | You configure and run Hermes fleet sync |

There is no analytics endpoint, crash reporter, update check, or Shadowfetch data service.
See [docs/SECURITY.md](docs/SECURITY.md) for the complete boundary.
