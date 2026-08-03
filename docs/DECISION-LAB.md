# Decision Lab

Decision Lab turns workspace evidence into a queue of explicit, reviewable decisions. It is
an aid to operator judgement, not an autonomous finance system.

## Portfolio queue

Each product is evaluated against rolling 30-day windows anchored to its latest observation.
Only observations in the product's configured currency enter its proceeds comparison.

The queue can recommend five postures:

| Posture | Trigger in 2.0 |
|---|---|
| **Scale** | Proceeds increased at least 20% and at least half the product's observations are confirmed |
| **Hold and measure** | Change remains inside the decision band and a comparable prior window exists |
| **Investigate** | Proceeds declined at least 20%, or current proceeds fell to zero after a non-zero prior window |
| **Refresh data** | The latest observation is at least 21 days old |
| **Add evidence** | No observation exists, or a prior comparison window does not yet exist |

The decision score combines product health, evidence coverage, freshness, and observed
trend. It sorts the queue; it is not a probability or revenue forecast. The rationale beside
each decision is the authoritative explanation.

## Agent frontier

Agent decisions use the existing economics model and preserve its provenance boundary.

- No measured value input: add evidence.
- Rework at or above 25%: investigate review loops and task definitions.
- Acceptance below 70%: investigate reliability before adding volume.
- Positive measured cash value with at least 50% evidence coverage: scale.
- Everything else: hold and measure.

Cash net value and modelled net value are separate columns. A modelled labor saving is not
added to the ledger or represented as money received.

## Scenario Studio

Scenario Studio accepts:

- customer price
- monthly units
- expected proceeds rate after store fees and tax
- refund rate
- variable cost per unit
- monthly operating cost
- human hours avoided
- loaded hourly rate

The result separates customer sales, expected cash proceeds, variable cost, operating cost,
net cash, and modelled capacity value. Sensitivity points use 50%, 75%, 100%, 125%, and 150%
of planned unit volume. Break-even units are rounded up to the first whole unit that covers
monthly operating cost.

Scenario output is never written into the cash ledger. It remains a planning calculation.

## Checkpoints

A checkpoint records the current summary, recent confirmed portfolio proceeds, agent cash
and modelled value, fleet evidence ratio, tracked product count, and active-agent count. It
does not copy vault values or API secrets.

Use a checkpoint immediately before a price change, release, marketing campaign, agent
workflow change, or major cost decision. Later checkpoints show deltas against that preserved
baseline without rewriting history.

## Executive brief

The Briefing tab exports Markdown or self-contained HTML. It includes:

- the current accounting summary
- excluded foreign-currency disclosure
- attention items
- portfolio and agent decision queues
- scenario notes and checkpoint deltas
- evidence and provenance caveats

The brief intentionally excludes vault items, private keys, secret values, and recovery keys.
The export itself is plaintext; store it accordingly.
