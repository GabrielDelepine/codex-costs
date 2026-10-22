# Codex Costs

A tiny native macOS 14+ app. No third-party dependencies, API key, local server or Xcode project. Compile with the Swift tools provided by Xcode, for the current Mac architecture.

## Build and launch

```sh
git clone https://github.com/GabrielDelepine/codex-costs.git
cd codex-costs
```

Then:

```sh
./build.sh --open
```

The app is created at `build/Codex Costs.app`. Open it later by double-clicking, or move it to Applications. Xcode does not need to be running. The build uses local ad-hoc signing, without a developer certificate.

## Interface

The interface is English only. Conversation titles remain exactly as recorded by Codex; logs are never translated. Dates and numeric formatting use English conventions and the Mac's local time zone.

- Click the calendar button to open the compact SwiftUI date calendar, rendered without scaling. Days without conversation files and future dates are greyed out and disabled. Click an available day, then Shift-click another available day to select a range. Both endpoints are included and capped at today. Apply commits the selection; Cancel preserves the current range.
- Follow today switches back to the current day and advances after midnight. Applying a custom range turns it off.
- Conversations are sorted by creation date/time. A range includes sessions whose files belong to its day folders; a session created earlier remains in its original folder even when it receives new messages later.
- Click a conversation ID to open `codex://threads/ID`. Right-click to copy the ID. Guardian review IDs are plain, selectable text because these reviews do not open as Codex conversations.
- The info button shows token counters, per-million Standard prices, context tiers and any reason an estimate is unavailable. Rates are shown only in this detail panel.
- The price date always displays `via tools.pwa.ovh` and links to https://tools.pwa.ovh/openai-pricing.
- Search filters by title, ID or model. The total includes only visible conversations with available estimates; unavailable rows are counted separately.

## File updates

FSEvents watches the `.codex` tree and filters notifications to the sessions directory and title index. Notifications are batched for approximately 0.4 seconds, with an additional 0.35-second debounce before checking files. SQLite and unrelated `.codex` changes are ignored.

Each session is cached in memory with its file size, modification/creation dates and inode. Only changed or new logs are read, always **in full**. Deleted files are removed. Switching ranges discards sessions outside the selected range. Renaming a title updates cached rows without rereading the session logs. In the main table, estimates are cached until usage or prices change.

Calendar availability is derived from day-directory metadata and rollout filenames, without parsing logs outside the selected range. Day listings are cached and refreshed when files are created or removed.

A recovery check runs every 60 seconds, on activation and after wake. It checks file metadata but does not reparse unchanged logs. The recovery also covers missing day folders and the midnight rollover. It remains available if native watching cannot start.

## Prices

The app downloads https://tools.pwa.ovh/api/v1/openai-pricing (schema 5). It attempts a download when the previous attempt/success is over six hours old, including after sleep. The refresh button forces a new request. Pricing requests do not block filesystem updates.

A successful download is validated and atomically saved to `~/Library/Application Support/CodexCosts/pricing.json`. Network/schema failures preserve the last valid catalogue and its original source retrieval date. If no catalogue is available, prices and estimates are unavailable. An expired endpoint cache timestamp does not erase the saved catalogue or imply that commercial prices expired.

Only the pricing endpoint is contacted; conversation titles, IDs and logs are not uploaded. Clicking an ID opens the local Codex app; clicking the pricing link opens its web page.

## Calculation and limits

The result estimates **token costs at current Standard API rates**, in USD. It is not a subscription charge or historical invoice. New prices recalculate the displayed range. Tools, subagents, images, voice, account-specific pricing and regional surcharges are excluded.

For each request, a delta of cumulative token counters must match the recorded last-request counters. Repeated unchanged events are ignored. Missing, inconsistent or reset counters prevent an estimate. A partially written final JSON line is ignored until the next file change; an invalid interior line prevents an estimate.

Ordinary input = total input − cached reads − cache writes. Reasoning is already included in output. Calculations use `Decimal`, explicit currency units and token denominators; rounding occurs only for display.

The footer explicitly identifies the estimation convention: total per-request input, including cached tokens, determines the context tier; that tier applies to the whole request. The endpoint leaves these two details unverified. For models without context columns, the published grid is used without inventing a threshold.

Nonzero cache writes prevent estimation because local counters do not identify their retention. A required `null` price is unknown, never free. Conversations with multiple models have no estimate by product choice. Model aliases are never guessed.

Codex's local log schema is internal and may change. The app prefers an unavailable estimate to silently treating missing counters as zero. Ongoing responses appear only once Codex records their token usage.

## Source files

- `App.swift`: English interface, state, pricing download/cache and refresh scheduling.
- `Core.swift`: JSONL parser, per-file cache, date ranges and cost calculation.
- `Native.swift`: SwiftUI calendar with per-day availability and native filesystem notifications.
- `build.sh`: compile, create app bundle and sign locally.
- `Assets/AppIcon.png`: selected Code icon; the build generates all macOS icon sizes and the `.icns` resource using Apple's `sips` and `iconutil`.
- `.gitignore`: excludes generated builds and Finder metadata.

The selected icon was generated with OpenAI ImageGen. Build artefacts, pricing cache and local Codex logs are not included in the repository.

Validated during this update: one-file rereads, unchanged-file cache hits, title-only updates, file deletion and atomic replacement, partial/completed JSON lines, inclusive range changes including a DST transition, native file creation/append notifications, calendar range selection, and pricing/token arithmetic.
