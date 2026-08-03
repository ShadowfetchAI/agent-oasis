# Changelog

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
