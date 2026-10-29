# Usage and pricing

- Local logs are an internal, evolving format. Missing data is unknown, not zero. Handle malformed/partial lines, duplicates, resets and inaccessible/deleted files explicitly.
- Never sum cumulative snapshots. Validate request deltas against last-request counters; avoid double-counting copied or re-observed sessions.
- Input includes cached reads/writes; output includes reasoning. Ordinary input = input - reads - writes. Never add reasoning twice. Reject inconsistent counters.
- Match explicit model IDs. Do not invent aliases or infer the model from the selected UI setting. Multiple-model sessions currently have no estimate; changing this requires reliable per-request attribution.
- Use `Decimal` and explicit price units/divisors. Round only for display. A required null price blocks estimation. Nonzero writes with unknown retention block estimation.
- Calculate per request, then sum. A context threshold uses request input, never conversation totals or context-window capacity. Preserve the disclosed assumptions where the endpoint leaves semantics unknown.
- Estimates use current Standard API token rates, not subscription billing or historical invoices. Recalculate when the catalogue changes. Exclude unsupported charges; label partial totals and unavailable rows.
- Consume the JSON pricing endpoint only; no HTML scraping. Validate schema; save atomically. Preserve last valid prices and source `fetchedAt` after failure. `expiresAt` is endpoint cache expiry, not commercial validity.
- History must disclose observation gaps. Retain only necessary metadata/counters if persistence is added; never imply complete coverage or copy full conversation contents.

For changed logic, use focused synthetic fixtures: known arithmetic/cache split, threshold boundaries, missing data and relevant parser edge cases. Describe the scope of those checks; do not claim a full app test suite passed. Keep README coverage/limits accurate.

## Daily-usage checks

Run the focused request-date, pricing and cache fixtures without personal logs or network access:

```sh
daily_check_dir=$(mktemp -d)
xcrun swiftc -swift-version 5 -parse-as-library Core.swift Tests/DailyUsageChecks.swift -o "$daily_check_dir/daily-checks"
"$daily_check_dir/daily-checks"
rm -r "$daily_check_dir"
```
