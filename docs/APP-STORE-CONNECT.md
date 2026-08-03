# App Store Connect integration

Agent Oasis uses Apple's public App Store Connect API as a read-only evidence source. It does
not create apps, change prices, upload builds, edit availability, or submit releases.

## Two independent scopes

The connection editor separates:

1. **App-record key** for app metadata.
2. **Sales reports key** for Summary Sales reports.

Use separate keys when possible. If one organizational key has both capabilities, leave the
separate sales-key fields blank and Agent Oasis will reuse the app-record key.

Each key lives as a separate encrypted vault item. The connection record stores only the
vault item ID, Key ID, Issuer ID, and Vendor Number. Secret values are not copied into audit
events or exported briefs.

## Authentication

Agent Oasis signs ES256 JSON Web Tokens locally with the selected `.p8` private key. Tokens
expire after 15 minutes.

- Team keys use the configured Issuer ID.
- Individual keys leave Issuer ID blank and use Apple's individual-key token subject.

Requests are sent only to `https://api.appstoreconnect.apple.com`.

## Sales request

The direct sales sync requests the latest available report with Apple's documented filters:

```text
GET /v1/salesReports
filter[frequency]=DAILY
filter[reportType]=SALES
filter[reportSubType]=SUMMARY
filter[vendorNumber]=YOUR_VENDOR_NUMBER
filter[version]=1_0
```

The gzip response is written to a randomly named `0700` temporary directory, decompressed
with the system gzip executable, read as delimited text, and removed with `defer` whether the
operation succeeds or fails. The report file is created owner-only.

## Import semantics

Apple's Summary Sales report supplies Developer Proceeds per unit. Agent Oasis multiplies
that value by signed Units once to create proceeds evidence. Negative units remain negative,
so refunds and reversals reduce proceeds instead of being discarded.

Rows are grouped by source date and proceeds currency. USD and EUR rows for the same product
and day remain separate observations and separate ledger entries. Agent Oasis does not infer
an exchange rate.

The source identity includes the Apple report date. Re-running the same daily sync updates
matching imported evidence instead of adding a duplicate. A corrected report can therefore
replace the earlier result without inflating revenue.

## Availability and failure behavior

Daily reports generally become available after the reporting day, not in real time. Agent
Oasis stores Apple's report date as the evidence date.

App records and sales reports are fetched independently. When one request fails:

- successful data from the other request can still be saved;
- the connection shows the partial failure;
- no private key or token is written to the error or audit log.

## Manual fallback

Download a Summary Sales report from App Store Connect and import the gzip-extracted CSV/TSV
through Agent Oasis. Manual import uses the same arithmetic, currency boundary, preview, and
idempotency rules as direct sync.

## Official references

- [Download Sales and Trends reports](https://developer.apple.com/help/app-store-connect/getting-paid/download-and-view-reports/)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)
- [Generate tokens for API requests](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests)
