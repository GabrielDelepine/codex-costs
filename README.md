# Codex Costs

**See which local Codex conversations consume tokens, and estimate what that usage would cost at current OpenAI API rates.**

Codex Costs is a small, native macOS app for people who use Codex and want to understand their usage without running terminal reports. Pick a day or a date range, compare conversations in a table, and open the details to see input, cached and output tokens alongside the prices used for the estimate.

Click a conversation title to open it in Codex. The info button opens its details, including the full selectable ID and a **Copy ID** button.

The app reads the Codex session files already on your Mac. You do not need an API key, an additional account or a local server. Your conversation data stays on your computer.

[Download a release](https://github.com/GabrielDelepine/codex-costs/releases) · [Report a problem](https://github.com/GabrielDelepine/codex-costs/issues) · [Contribute](#contributing)

> These are **current API-equivalent token estimates**, not your ChatGPT subscription charges, remaining allowance or historical invoices. Some conversations cannot be priced reliably; the app shows an unavailable estimate rather than inventing a number.

![Luma screenshot](./docs/screenshot_2026-10-22.avif)

## Contents

- [Who is it for?](#who-is-it-for)
- [Why choose Codex Costs?](#why-choose-codex-costs)
- [Download and install](#download-and-install)
- [Understanding the estimate](#understanding-the-estimate)
- [Coverage and known limitations](#coverage-and-known-limitations)
- [Privacy and local storage](#privacy-and-local-storage)
- [How updates work](#how-updates-work)
- [Build from source](#build-from-source)
- [Project structure](#project-structure)
- [Contributing](#contributing)

## Who is it for?

Codex Costs is useful if you want to:

- Find which conversations account for the most estimated usage.
- See how much of the input was served from cache.
- Follow recorded token usage while a conversation progresses.
- Compare conversations across days without repeatedly asking an agent to run a usage report.
- Inspect the counters and assumptions behind an estimated amount.

It is designed around **local Codex session data**. If you need exact billing, account-wide coverage, subscription quota tracking or a complete archive of every conversation, those are different requirements; see [coverage and known limitations](#coverage-and-known-limitations).

## Why choose Codex Costs?

The project deliberately stays small:

- **Native macOS interface.** A table, a compact calendar and an info panel, built with SwiftUI and AppKit. The window has a 1080-point minimum width to leave room for the table’s columns and native spacing.
- **No third-party dependencies.** No Electron runtime, package installation or local service to maintain.
- **No API key required.** Usage comes from local logs; published prices come from a JSON endpoint.
- **Private conversation data.** Titles, IDs, prompts and token counters are not sent to the pricing service.
- **Inspectable estimates.** See the counters, price grids and reasons for unavailable estimates.
- **Simple to build.** One command produces a standalone `.app` using Apple's development tools.

This is a focused desktop utility rather than a general analytics platform. Contributions should preserve that character.

## Download and install

### Requirements

- Mac with Apple Silicon or an Intel processor.
- macOS 14 Sonoma or later.
- Local Codex session files in the default `~/.codex` directory.

### Install a compiled release

1. Open the [Releases page](https://github.com/GabrielDelepine/codex-costs/releases).
2. Download the `.dmg` application asset attached to the release. GitHub's automatically generated source archives are not compiled applications.
3. Open the disk image and drag **Codex Costs.app** to **Applications**.
4. Open the app, then follow [Signing and first launch](#signing-and-first-launch) if macOS blocks it.

### Signing and first launch

Current builds use a local **ad-hoc signature** and are not notarized by Apple. macOS may therefore block the first launch. Publishing a file on GitHub does not add a Developer ID signature or notarization.

If you trust the release, follow [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445). After attempting to open the app, macOS may offer **Open Anyway** in **System Settings → Privacy & Security**.

A release may also include `SHA256SUMS.txt`. Use it to compare the downloaded DMG's SHA-256 fingerprint with the published value. With the DMG and checksum file in the same directory, run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

An `OK` result means the file matches the listed fingerprint. This is an integrity check, not a developer signature, proof of authenticity or an Apple security assessment.

## Understanding the estimate

### Current prices, not historical charges

Codex Costs estimates token usage using **current Standard OpenAI API prices in USD**. Updating the price catalogue recalculates the visible conversations, including older ones. The result is not a reconstruction of what a request cost when it happened.

The app does not convert token counts into a ChatGPT subscription charge or remaining subscription allowance. Fast, Ultrafast, Batch and Flex pricing are not used for the displayed estimate.

### Where prices come from

The app downloads a structured catalogue from [tools.pwa.ovh](https://tools.pwa.ovh/openai-pricing), which identifies [OpenAI's published pricing](https://developers.openai.com/api/docs/pricing) as its source. It currently understands catalogue schema version 5 and does not scrape HTML.

The footer displays the source retrieval date with **via tools.pwa.ovh**. Clicking it opens the endpoint's explanatory web page. The date is the catalogue's `fetchedAt`, not the time of the app's most recent download attempt.

Refreshes are attempted on a six-hour cadence while the app runs, with a manual refresh button. Successful catalogues are validated and saved locally. A failed download or unsupported schema preserves the last valid prices and their original retrieval date. Without a saved catalogue, estimates remain unavailable.

The endpoint's `expiresAt` describes its cache expiration; it does not establish the commercial validity period of the prices.

### How tokens are counted

Session logs contain cumulative usage snapshots as well as counters for the last request. The app calculates differences between cumulative snapshots and checks that each difference matches a recorded request. It does not add the cumulative snapshots together. Repeated unchanged events do not add usage.

Input already includes tokens served from cache, and output already includes reasoning tokens. In terms of exclusive categories:

```text
ordinary input = total input − cached reads − cache writes

estimated token cost =
    ordinary input × applicable input rate
  + cached reads × applicable cached-input rate
  + cache writes × applicable cache-write rate
  + output × applicable output rate
```

Prices have explicit currency and token units. Calculations use decimal arithmetic; amounts are rounded for display, not before adding the request costs.

The current app does not estimate requests with nonzero cache writes because the local counters do not identify the retention duration needed to choose their price.

### Inspect individual requests

The info panel lists validated requests with their sequence number, recorded usage-event timestamp, model, total input, cached reads, cache writes, output, selected context tier and estimated cost or unavailable reason. Expand a request to inspect its counters. A usage timestamp is not an inferred request start time; missing timestamps remain explicit.

Usage and request-cost subtotals are grouped by context tier. With a complete conversation estimate, the unrounded request costs reconcile with its total. Displayed values are rounded independently. If parsing or attribution is incomplete, the conversation remains unavailable and known request subtotals are labeled; they do not imply complete coverage. Repeated unchanged usage events do not create duplicate requests.

### Context pricing assumptions

Context-dependent prices are selected **per request**, not from the sum of an entire conversation or the model's maximum context capacity.

The current estimator explicitly assumes that:

1. Total request input, including cached tokens, determines the context tier.
2. The selected tier applies to the whole request.

The pricing endpoint leaves these details unverified. They are disclosed estimation conventions, not guarantees about billing. If a model has no context-specific columns, the app uses its published grid without inventing a threshold.

### Why an estimate may be unavailable

Examples include:

- More than one model is recorded in the conversation.
- A model or required price is missing from the supported catalogue.
- A necessary price is `null`, meaning unknown rather than free.
- Token counters are missing, inconsistent or reset.
- A cumulative change cannot be matched to a single request.
- Cache writes exist but their retention duration is unknown.
- A log cannot be parsed reliably.

Model aliases are not guessed. A final JSON line still being written is ignored until the file changes again; an invalid interior line prevents estimation.

## Coverage and known limitations

### Local files determine what is visible

The app reads active `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` files, flat archived `~/.codex/archived_sessions/rollout-*.jsonl` files, and titles from `~/.codex/session_index.jsonl`. It uses the default location and does not currently offer a custom Codex-home setting.

Project-associated and projectless sessions can both appear when they are recorded there. This is not a guarantee of coverage across all Codex surfaces, devices or accounts. Archived rollouts use their original local creation date encoded in the filename, rather than their archive date. Duplicate conversation IDs are counted once, preferring an active copy over an archived copy. Other storage locations are not scanned.

The log format is internal to Codex and may change. The app cannot reliably estimate usage that its source files do not expose.

### Work conversations

Conversations created in Work are not currently covered. The app displays this limitation next to its totals and pricing notes. It only reads the supported local Codex rollout format; it does not read private desktop-app caches or infer token usage from chat metadata. No documented Work session export with the required per-request token counters was established during this investigation. This is a limit of the current reader, not evidence that Work stores no usage data. The absence of a Work conversation from the table does not mean it consumed no tokens.

OpenAI documents [desktop and CLI commands separately](https://learn.chatgpt.com/docs/developer-commands). Those commands do not establish a local Work usage-file contract. Supporting another source requires a verified format, reliable model and token attribution, and deduplication by conversation ID.

### Guardian Reviews

Guardian Review sessions are excluded from the table, counts, totals and calendar availability. Detection uses the explicit Guardian source marker, the `codex-auto-review` model or the title `Guardian review`. The source marker also identifies reviews without a recorded model. Calendar classification checks a cached header of up to 64 KiB; unusually large headers without a recognizable marker may remain visible until their metadata becomes identifiable.

### Potentially missing conversations and limited history

There are reports of potentially missing conversations and different amounts of local history between machines. One confirmed coverage gap was archived rollout files: these are now scanned as well as active sessions. This does not establish the cause of every missing conversation or differences between machines; automatic deletion by Codex should not be assumed without evidence.

Codex Costs retains observed conversation metadata and token counters locally, including sessions outside the selected date range. A source that disappears or cannot be read leaves a retained snapshot marked **Source not readable at the latest check** in details. Estimates are recalculated with current prices; stored counters are replaced by conversation ID, never added across observations.

**History details** lists observation periods and provides **Clear retained history**. Clearing forgets saved snapshots and periods; readable source logs are observed again. Codex logs are never changed. A restart or gap longer than two minutes starts a new observation period. These checkpoints do not prove complete coverage: sessions created and removed between checks or while the app was closed may never be captured. Directory/read errors can also leave gaps.

The archive contains IDs, titles, source paths, creation dates, model names, parsed counters, validated requests and parser warnings; it does not copy prompts, messages or raw logs. An unreadable or unsupported archive is preserved and reported rather than overwritten. Save failures are reported; until saving succeeds, new observations exist only in memory.

### Investigating differences in local history

OpenAI’s [app-server documentation](https://learn.chatgpt.com/docs/app-server#api-overview) confirms that archiving moves a thread log into an archived directory, unarchiving restores it to active sessions, and explicit deletion permanently removes a persisted thread and its spawned descendants. It also distinguishes threads loaded in memory from stored threads. Unloading an idle thread from memory is not documented as deleting its saved log.

These documented operations do not establish an automatic seven-day, ten-day or other fixed retention policy. The reported differences between machines remain unexplained without a comparison of their versions, configuration and source inventory. The reader scans active and archived rollouts; this fixes one confirmed source-coverage gap without establishing the cause of every reported history difference.

To investigate a missing conversation locally:

1. Confirm its creation day, not just the day of its latest activity. The table groups rollouts by the local creation timestamp in the filename; a UTC metadata timestamp can fall on a different local day.
2. Look for its ID in active `~/.codex/sessions` and flat `~/.codex/archived_sessions` rollout filenames. Check whether the file moved, rather than assuming it was deleted. Do not modify these sources.
3. Compare the app’s supported source location with the Codex home used by that installation. Another Mac, a remote execution host, another home directory or a Work conversation is not guaranteed to have a supported rollout on this Mac.
4. If a supported file exists but is absent from the selected day, record the app and Codex versions, source category, filename date and any read-error message. Distinguish a missing row from a visible row whose estimate is unavailable.

Keep IDs and file inventories local when possible. A report can describe the source category and date discrepancy without sharing prompts, full logs, credentials or screenshots of private conversations. The app cannot recover a source it never observed or establish why Codex removed or relocated it.

### Date and time formatting

Interface text stays English and conversation titles are preserved. Displayed dates, times, calendar labels, token counts and USD amounts use the Mac’s regional preferences, including its clock format and local time zone. USD remains the estimation currency; regional formatting does not convert amounts. Log filenames and wire timestamps retain their fixed source formats.

### Excluded charges

The estimate excludes tool fees, subagent usage recorded in separate sessions, image and voice generation, regional surcharges and account-specific pricing. It is a view of supported token usage in the listed logs, not an exact invoice.

## Privacy and local storage

Codex Costs reads session logs and the title index without changing them. It does not upload prompts, titles, IDs or token counts to the pricing endpoint. External links are opened only through the corresponding user interaction.

| Data                                      | Location                                                | Persistence                             |
| ----------------------------------------- | ------------------------------------------------------- | --------------------------------------- |
| Codex session logs and titles             | Default `~/.codex` directories                          | Managed by Codex; read-only to this app |
| Parsed session counters and file metadata | App memory                                              | Cache of currently readable source files |
| Observed metadata, counters and observation periods | `~/Library/Application Support/CodexCosts/history.json` | Retained locally until cleared |
| Last valid pricing catalogue              | `~/Library/Application Support/CodexCosts/pricing.json` | Saved locally                           |
| Last successful pricing download time     | macOS user defaults                                     | Saved locally                           |

There is no app account, API key, analytics service or local backend. The normal background network request is to the pricing endpoint.

## How updates work

**Auto-select today** selects the current day immediately and follows date changes at the next recovery check (up to 60 seconds), on activation and after wake. It starts enabled on every app launch. Unchecking it keeps the selected dates fixed; applying a calendar selection also turns it off, while Cancel preserves the current mode and dates. Live usage updates work for any selected date range independently of this option.

Native **FSEvents** notifications watch the `.codex` tree and filter for active session, archived session and title-index changes. Event bursts are batched and debounced; unrelated writes, such as SQLite changes, are ignored.

The app caches each parsed session with its file size, modification date, creation date and inode. New or changed logs are reread **in full**. Unchanged logs are not reparsed, deleted source files leave the parsing cache while observed snapshots are retained, and title-index changes update titles without rereading unchanged session contents.

Calendar availability uses cached directory listings and bounded session headers to exclude internal Guardian Reviews. The log cache itself can limit usage parsing to selected folders; history observation supplies all available and previously observed dates independently of the displayed range. Header classification is cached by file metadata and title-index changes are applied without rereading unchanged logs.

A recovery check runs every 60 seconds, on app activation and after waking the Mac. It covers missed events, missing day folders and midnight changes, and remains available when native watching cannot start. File parsing and history persistence run away from the UI thread. Source discovery and observation cover all available dates independently of the displayed range; unchanged logs remain cached. Pricing downloads are scheduled independently of log updates.

## Build from source

Building requires a Mac with Xcode's Swift tools installed and selected. Xcode does not need to be open; there is no Xcode project or third-party package installation.

```sh
git clone https://github.com/GabrielDelepine/codex-costs.git
cd codex-costs
./build.sh --open
```

Use `./build.sh` to compile without launching. The script builds for the current Mac architecture, creates `build/Codex Costs.app`, generates the macOS icon resources and applies an ad-hoc signature. You can subsequently open the `.app` by double-clicking it.

The script uses Apple's `swiftc`, `sips`, `iconutil` and `codesign`. Generated files stay under the ignored `build/` directory; Swift's module cache is outside the repository.

Release packaging is separate from this local build command. A universal release must contain both architectures. Version metadata, signing status and architecture labels should match the actual package. Generate a release checksum only after the final DMG has been produced, and regenerate it if the asset changes.

## Project structure

| Path                 | Responsibility                                                               |
| -------------------- | ---------------------------------------------------------------------------- |
| `App.swift`          | Interface, app state, pricing downloads and refresh scheduling               |
| `Core.swift`         | Log parsing, per-file cache, date ranges and cost calculation                |
| `History.swift`      | Local observed snapshots, observation periods and atomic persistence          |
| `Native.swift`       | Calendar with per-day availability and native filesystem notifications       |
| `Assets/AppIcon.png` | Selected Code icon, generated with OpenAI ImageGen                           |
| `build.sh`           | Compilation, icon generation, bundle creation and local signing              |
| `AGENTS.md`          | Short shared instructions and task-specific reading routes for coding agents |
| `docs/agents/`       | Focused implementation guidance, loaded when relevant                        |

## Contributing

### Preserve the small-app approach

Contributions are welcome when they make local usage easier to understand while preserving a small, native application. Keep the one-command build, avoid third-party dependencies, use Apple frameworks, and add architecture only when a concrete feature requires it.

Prefer clear behavior to extra controls, and clear unavailable states to speculative cost calculations. Keep data local and leave Codex's own files untouched.

### Report a problem

[Open an issue](https://github.com/GabrielDelepine/codex-costs/issues) with a title describing the problem. Put any proposed solution in the body so the problem can be discussed independently of one implementation.

Include the app and macOS versions, what you expected, what happened and a minimal reproduction where possible. For missing conversations, add the approximate creation date and whether they are project-associated, projectless or Work conversations. For calculation problems, include only the relevant redacted counters and model information. Do not post full logs, prompts, credentials or private conversation screenshots.

Unconfirmed observations are useful too; label them as such rather than presenting a suspected cause as established fact.

### Prepare a focused change

Read [AGENTS.md](AGENTS.md) for the shared constraints. Agents should load only the linked guides relevant to the task; humans can use those same short guides as implementation checklists. Keep product, installation and contribution explanations in this README rather than scattering them across additional human-facing documents.

Keep each change focused on an issue or clearly described problem. Explain the resulting behavior, how you checked it, and any remaining limitations. Update this README when features, installation, data coverage or estimation rules change.

### Verify your change

- **Code changes:** run `./build.sh` and the checks relevant to the affected behavior. Compilation alone does not verify UI or calculation correctness.
- **Interface changes:** inspect the running app, including affected selection, layout, accessibility, empty and unavailable states.
- **Parsing, prices or caching:** use focused synthetic fixtures for the changed logic. Do not modify real Codex logs to create test cases.
- **Documentation-only changes:** check facts, links and Markdown structure; no rebuild is needed.

There is currently no committed automated test suite. Do not describe a build or an ad-hoc check as a full test-suite run.

### Release a build

Package the compiled app in a DMG for download, verify the final image, then calculate its SHA-256. Attach the image and checksum to the GitHub release and document the actual architecture, minimum macOS version and signing status. A checksum does not provide Developer ID signing or notarization.

Do not include personal session files, local pricing caches, credentials or generated build output in source commits.
