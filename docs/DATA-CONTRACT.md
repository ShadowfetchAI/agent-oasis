# Data and accounting contract

Agent Oasis follows a conservative contract so a dashboard cannot silently become a claim
the underlying records do not support.

## Cash and modelled value

Cash is ledger revenue minus ledger expense in the workspace base currency. Agent capacity,
avoided vendor spend, supervision estimates, and attributed influence remain modelled value.
The two classes are presented side by side and never added together.

Scenario Studio does not create ledger records. A plan remains a plan until the operator
imports or records an actual outcome.

## Provenance

Value inputs are either:

- **Measured**: derived from an import or named observed source.
- **Estimated**: entered as an assumption or created from a duplicated planning record.

Evidence coverage is the measured share of relevant inputs. More tasks do not increase that
ratio. Staleness can reduce trust in evidence; activity cannot promote an estimate to a
measurement.

## Currencies

The workspace has one base currency for aggregate cash reporting. Ledger entries in other
currencies remain stored but are excluded from cash totals and monthly cash flow. The UI and
executive brief disclose the number and codes of excluded currencies.

Each portfolio product also has a currency. Its decision windows use observations only in
that currency. This prevents a product's USD and EUR rows from being compared or summed as
if they represented identical units of account.

Agent Oasis never downloads exchange rates and never applies an implicit conversion.

## App Store proceeds

For official Apple Summary Sales reports:

```text
row proceeds = Developer Proceeds per unit * signed Units
```

The sign is preserved for returns and reversals. Rows are grouped by product, source date,
and proceeds currency. Import identity includes the source name and source date so repeated
imports update existing evidence rather than doubling it.

## Experiment attribution

An experiment may calculate a raw difference while still refusing attribution. Recording a
confounder means the app will not present the difference as attributable lift. The raw data
remains available for inspection.

## Checkpoints

Checkpoints are immutable summaries of what was known at a point in time. They preserve cash
and modelled values separately and use the base currency active at capture. They are not
retroactively recalculated when later imports change the workspace.

## Exports

Executive briefs and CSV exports contain business records, not vault secrets. They are
plaintext by design and leave the encrypted workspace boundary when saved.
