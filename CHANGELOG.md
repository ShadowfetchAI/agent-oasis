# Changelog

## 3.0.0 - Hermes Fleet (2026-08-02)

Agentic operations becomes a first-class part of the workspace, not a sync button buried in
Agents. Hermes Fleet reads a live [Hermes](https://github.com/ShadowfetchAI) install over SSH
and shows what is actually measurable there - kanban shape, the open decision queue, roster,
gateway liveness, and structural fleet integrity - with nothing invented where Hermes itself
has no aggregate to report.

### Hermes Fleet
- Added a dedicated top-level "Hermes Fleet" section, its own sidebar entry and keyboard
  shortcut, replacing the old aggregate-only sync tucked behind the Agents tab.
- Added kanban health: live by-status counts and the oldest blocked cards (title, assignee,
  age) read via `hermes kanban stats --json` and `hermes kanban list --json`.
- Added the open decision queue, grouped and colored by ack-deadline urgency, read via the
  standalone `decide.py list --json` tool.
- Added roster and gateway-process panels read via `hermes profile list` and
  `hermes gateway list`.
- Added fleet structural integrity (`fleet_integrity.py`'s clean/issues state).
- Kept per-agent session/message/token telemetry from the prior release, now living in the
  same dashboard instead of a separate tab.
- Every configurable remote path (profiles, tools, state, gateway unit pattern) is validated
  against the same injection-resistant charset already used for the SSH host, so this works
  against any Hermes install rather than assuming Shadowfetch's own layout.
- No fleet-wide "duty success rate" is reported: no such aggregate exists on a real Hermes
  install, and inventing one would be exactly the manufactured-confidence Decision Lab exists
  to refuse elsewhere in this app.

### Redaction, by construction
- Kanban card bodies and decision context/recommendation/options text - which on a real
  install contain named-executive strategic content - are never decoded into the app. The
  Swift models for both simply have no property for that data; `JSONDecoder` drops it before a
  value exists, so there is no filtering step downstream to get wrong.
- New tests assert the sensitive text is verifiably absent from a re-encoded model, not merely
  that a differently-named field is missing.

### Product and quality
- Added a new `docs/HERMES-FLEET.md` integration contract: exact commands, exact fields kept
  versus dropped, and the full threat model for the expanded SSH surface.
- Expanded the suite to 79 tests, including Hermes JSON/text parsing for every new data
  domain, the redaction guarantee, and injection rejection for the two newly configurable
  remote paths.

## 2.0.0 - Decision Intelligence (2026-08-02)

Agent Oasis grows from an encrypted operating ledger into a private decision workspace.

### Decision Lab
- Added an evidence-ranked portfolio queue with Scale, Hold and measure, Investigate,
  Refresh data, and Add evidence postures.
- Added an agent frontier that keeps measured cash value and modelled capacity value apart.
- Added Scenario Studio with price, unit, refund, proceeds-rate, variable-cost,
  operating-cost, and labor-capacity assumptions.
- Added downside-to-upside volume sensitivity and whole-unit break-even calculation.
- Added business checkpoints and baseline deltas for price, release, cost, and workflow
  decisions.
- Added secret-free Markdown and self-contained HTML executive briefs.

### Direct Apple sales evidence
- Added read-only download of Apple's latest available daily Summary Sales report through
  the documented App Store Connect API.
- Added separate app-record and Sales and Reports vault credentials for least-privilege
  setups, with optional key reuse.
- Added team-key and individual-key JWT handling with 15-minute ES256 tokens.
- Added secure gzip extraction in an owner-only temporary directory with guaranteed cleanup.
- Added partial-sync behavior so successful app metadata or sales evidence is retained when
  the other request fails.

### Accounting integrity
- Official Apple Developer Proceeds is treated as per-unit and multiplied by signed Units
  exactly once.
- Imports are idempotent and corrected re-exports replace matching evidence.
- Apple rows are preserved by source date and proceeds currency.
- Workspace cash totals and monthly cash flow include only the configured base currency.
- Foreign-currency entries remain stored and are disclosed as excluded instead of being
  silently summed or converted.
- Portfolio decision windows use each product's own configured currency.

### Product and quality
- Added Decision Lab navigation, menu commands, Command Palette action, and keyboard shortcut.
- Updated the Connections editor for live sales configuration and clearer read-only status.
- Updated Command Center, Ledger, imports, Settings, and What's New for the 2.0 contract.
- Added a Debug-only external preview harness for repeatable visual QA; no fixture data is
  compiled into Release.
- Expanded the suite to 70 tests, including decision rules, scenarios, checkpoints,
  executive-brief secret exclusion, gzip sales decoding, currencies, and official-report
  arithmetic.

## 1.1.0 - Operator Workspace (2026-07-30)

Flagship upgrade focused on daily operator speed and honest attention.

### Attention Inbox
- Command Center replaces vanity “priority signals” with an **Attention Inbox**.
- Surfaces only actionable gaps: blocked agents, refused experiment attribution, stale/error connections, high modelled value with zero measured inputs, stale measured agents, running experiments waiting on data, and missing/old encrypted backups.
- Each item navigates to the record that needs a decision.

### Command palette & keyboard
- **⌘K** command palette for navigation and common actions.
- **⌘1–⌘9** jump between sections.
- **⌘N** context-aware create, **⌘I** import with preview, **⌘E** ledger CSV export, **⌘/** shortcuts sheet, **⌘⇧L** lock.

### Import preview & drag-and-drop
- Imports show apps / observations / ledger counts **before** writing.
- Drop CSV/TSV onto Command Center or Ledger to preview.
- Toolbar gains an Import / Export menu.

### Duplicate without inventing evidence
- Duplicate agents and experiments from the detail view or context menu.
- Agent duplicates reset telemetry and mark value inputs estimated (`Manual duplicate`).

### Polish
- Settings shows the real marketing/build version from the bundle (was stuck on 0.1).
- What’s New sheet on first unlock of a new marketing version.
- Empty-workspace guide includes one-click Import / Add agent / Command palette.

### Tests
- Coverage for Attention Inbox rules, import preview non-mutation, and agent duplicate provenance.

## 1.0.0 - Flagship polish

- Refined materials UI, searchable Agents/Portfolio, context-menu copy actions.
