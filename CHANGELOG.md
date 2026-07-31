# Changelog

## 1.1.0 — Operator Workspace (2026-07-30)

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

## 1.0.0 — Flagship polish

- Refined materials UI, searchable Agents/Portfolio, context-menu copy actions.
