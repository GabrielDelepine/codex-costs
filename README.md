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
- [License](#license)

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

- **Native macOS interface.** A table, a compact calendar and an info panel, built with SwiftUI and AppKit. The window has a 640-point minimum width for side-by-side use. Below 900 points, date and time move beneath conversation titles, and the search and pricing status use separate rows. Conversation titles and model lists stay on one line and truncate with an ellipsis; hovering reveals their full text. The model column uses 145 points, and the estimated-cost column uses 90 points to retain its full heading while leaving more room for titles.
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

**Applied pricing: Short context** (or the applicable context) replaces the separate context heading and shows only the model/context grids used by available request estimates. A conversation can show both short- and long-context grids when its requests used both. Model labels appear only for conversations with multiple recorded models; grids are grouped by model. The explanation of the indicators follows the rate rows. Read-only checked squares identify rate components with nonzero tokens in an available estimate. Unchecked components were not used; unknown unused prices remain explicit. Nonzero cache writes still block estimation because retention is unknown. If the conversation estimate is unavailable, any displayed grids are explicitly limited to available request estimates. Published units are normalized to USD per million tokens using each price’s declared divisor.

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

Project-associated and projectless sessions can both appear when they are recorded there. This is not a guarantee of coverage across all Codex surfaces, devices or accounts. Archived rollouts use their original local creation date encoded in the filename, rather than their archive date. Duplicate conversation IDs are counted once, preferring an active copy over an archived copy. The first session metadata entry identifies a rollout; parent metadata copied into a fork's history does not replace its identity. Other storage locations are not scanned.

The log format is internal to Codex and may change. The app cannot reliably estimate usage that its source files do not expose.

### Work conversations

Conversations created in Work are not currently covered. Their visibility and usable usage-data sources need investigation. The absence of a Work conversation from the table does not mean it consumed no tokens.

### Guardian Reviews

Guardian Review sessions are excluded from the table, counts, totals and calendar availability. Detection uses the explicit Guardian source marker, the `codex-auto-review` model or the title `Guardian review`. The source marker also identifies reviews without a recorded model. Calendar classification checks a cached header of up to 64 KiB; unusually large headers without a recognizable marker may remain visible until their metadata becomes identifiable.

### Potentially missing conversations and limited history

There are reports of potentially missing conversations and different amounts of local history between machines. Including archived rollout files addresses one possible source of missing rows; it does not establish the cause of those reports or differences between machines. Automatic deletion by Codex should not be assumed without evidence.

Codex Costs currently keeps parsed usage in memory, not in a permanent conversation archive. If a source file disappears, its row is removed on a subsequent check. Running the app does not currently preserve a complete history after those files are gone.

A future local history feature would also need to explain gaps: conversations created and removed while the app was closed might never have been observed.

### Date and time formatting

Interface text stays English and conversation titles are preserved. Displayed dates, times, calendar labels, token counts and numeric amounts use the Mac’s regional preferences, including its clock format and local time zone. The API’s `currency` field is validated as USD. Estimated amounts keep a fixed `$` symbol, and detailed rates display the API currency code; regional formatting does not rename or convert the currency. Log filenames and wire timestamps retain their fixed source formats.

### Excluded charges

The estimate excludes tool fees, subagent usage recorded in separate sessions, image and voice generation, regional surcharges and account-specific pricing. It is a view of supported token usage in the listed logs, not an exact invoice.

## Privacy and local storage

Codex Costs reads session logs and the title index without changing them. It does not upload prompts, titles, IDs or token counts to the pricing endpoint. External links are opened only through the corresponding user interaction.

| Data                                      | Location                                                | Persistence                             |
| ----------------------------------------- | ------------------------------------------------------- | --------------------------------------- |
| Codex session logs and titles             | Default `~/.codex` directories                          | Managed by Codex; read-only to this app |
| Parsed session counters and file metadata | App memory                                              | No permanent conversation archive       |
| Last valid pricing catalogue              | `~/Library/Application Support/CodexCosts/pricing.json` | Saved locally                           |
| Last successful pricing download time     | macOS user defaults                                     | Saved locally                           |
| App release metadata, check time and automatic-check preference | macOS user defaults | Saved locally; no conversation data |

There is no app account, API key, analytics service or local backend. Background network requests retrieve prices from the pricing endpoint and public release metadata from GitHub. Release checks send no conversation data and require no GitHub account or token.

## How updates work

### Application releases

Choose **Codex Costs → Check for Updates…** to check GitHub's latest public stable release. Commits, drafts and prereleases are not used. Versions are compared as `MAJOR.MINOR.PATCH` (release tags may start with `v`), so a local build newer than the latest release is not offered a downgrade. A failed request is reported separately from an up-to-date result.

When an update is available, the main window shows a clickable **Update available** indicator. The indicator opens the saved release details, even after a failed background check. The update window compares your version and the latest version, with publication dates formatted using macOS regional preferences. Dates come from the corresponding GitHub releases and are saved locally; **Release date unavailable** is shown when the installed build cannot be matched to a release. Commit and compilation dates are never substituted.

**Later** closes the update window and leaves the indicator available. **View Release on GitHub** opens that specific release in your browser, where you can read the notes and download the DMG. The app does not download, install or relaunch itself. The [installation instructions](#download-and-install) and ad-hoc signing limitations still apply.

**Automatically Check for Updates** is enabled by default and can be changed in the Codex Costs menu or update window. A successful check schedules the next automatic check after 72 hours. Checks run only while the app is running; an overdue check runs after reopening, activation or wake, or at the next recovery check. Failures are silent in the background and retry after one hour while running; restarting also permits a retry. Automatic checks never open a window or take focus. Previously retrieved update metadata remains available after a network failure. Manual checks bypass the schedule and work even when automatic checking is disabled. Disabling automatic checks preserves the existing indicator and does not cancel an in-flight request.

### Local usage and pricing

**Auto-select today** selects the current day immediately and follows date changes at the next log check, including when a window becomes visible again or the Mac wakes. An independent recovery loop waits 60 seconds between checks; this is a fallback, not the live-update interval or a strict midnight deadline. Sleep, suspension and scan duration can delay a check. It starts enabled on every app launch. Unchecking it keeps the selected dates fixed; applying a calendar selection also turns it off, while Cancel preserves the current mode and dates. Live usage updates work for any selected date range independently of this option.

Native **FSEvents** notifications watch the `.codex` tree and filter for active session, archived session and title-index changes. macOS batches events before notifying the app; unrelated writes, such as SQLite changes, are ignored. There is no additional application debounce, so continuous writes never reset a waiting refresh.

| Window state | FSEvents latency | Application delay | Refresh behavior |
| --- | --- | --- | --- |
| At least one window partly visible, even without keyboard focus | 400 ms | None | Scan on each relevant batch; target an updated display within 2 seconds of a relevant write, including continuous writes. |
| All windows hidden, minimized, closed or fully obscured | 30 seconds | None | Check once on transition, then scan on each relevant batch delivered by macOS. |
| A window becomes visible again | Restored to 400 ms | None | Check logs immediately, without waiting for the next event. |

These are scheduling targets, not hard real-time bounds: system delivery, sleep, suspension and unusually long scans can delay display updates. The 2-second target assumes native watching works and the selected logs can be processed within that budget. The hidden-window latency is a 30-second request to macOS, not a strict minimum interval or a wait after the last write; the system may deliver batches earlier. Each visibility transition starts a new stream before checking logs, so pending writes are covered without replaying historical notifications. Already queued callbacks may cause a harmless cached recheck. Scans are serialized, with a follow-up scan when changes arrive during an active scan.

The app caches each parsed session with its file size, modification date, creation date and inode. New or changed logs are reread **in full**. Unchanged logs are not reparsed or re-estimated, deleted files are removed, and title-index changes update titles without rereading unchanged session contents. A new pricing catalogue recalculates all selected estimates.

Calendar availability uses cached directory listings and bounded session headers to exclude internal Guardian Reviews. Usage counters outside the selected range are not parsed. Header classification is cached by file metadata and title-index changes are applied without rereading unchanged logs.

A recovery check runs after each 60-second recovery wait, on visibility transitions and after waking the Mac. It covers missed events, missing day folders and midnight changes, and retries native watching when it cannot start. File parsing runs away from the UI thread, and pricing downloads are scheduled independently of log updates.

## Build from source

Codex Costs is a native macOS app written in Swift. Omitting an Xcode project is a deliberate minimalist choice: a few source files, a build script and a small Makefile keep the development workflow simple and limit project configuration.

Building requires a Mac with Xcode's Swift tools installed and selected. Xcode does not need to be open; there is no third-party package installation.

```sh
git clone https://github.com/GabrielDelepine/codex-costs.git
cd codex-costs
./build.sh --open
```

Use `./build.sh` to compile without launching. The script builds for the current Mac architecture, creates `build/Codex Costs.app`, generates the macOS icon resources and applies an ad-hoc signature. You can subsequently open the `.app` by double-clicking it.

You can also use `make build` to compile, or `make run` to compile and launch the app.

The script uses Apple's `swiftc`, `sips`, `iconutil` and `codesign`. It includes the MIT license and copyright notice in the app's `Contents/Resources/LICENSE` before signing. Generated files stay under the ignored `build/` directory; Swift's module cache is outside the repository.

The About window shows the public semantic version, a GitHub link to the source commit, its committer date, and the build date and time using macOS formatting preferences and the local time zone. These timestamps are recorded during compilation. Builds with local changes identify the commit as the base source; source metadata is unavailable when building without Git history.

Versions follow `MAJOR.MINOR.PATCH` and are set in `build.sh`. Each distributed artifact must have a unique public version: rebuilding a different artifact for distribution requires at least a patch increment, even from the same commit. Local builds do not automatically change the version. Both Apple bundle version fields use the public version; there is no separate displayed build counter.

Release packaging is separate from this local build command. A universal release must contain both architectures. Version metadata, signing status and architecture labels should match the actual package. Generate a release checksum only after the final DMG has been produced, and regenerate it if the asset changes.

## Project structure

| Path                 | Responsibility                                                               |
| -------------------- | ---------------------------------------------------------------------------- |
| `App.swift`          | Interface, app state, pricing downloads and refresh scheduling               |
| `Core.swift`         | Log parsing, per-file cache, date ranges and cost calculation                |
| `Native.swift`       | Calendar with per-day availability and native filesystem notifications       |
| `Updates.swift`      | GitHub release checks, scheduling, saved metadata and native update window    |
| `Tests/UpdatesChecks.swift` | Isolated release-check fixtures, version comparison and scheduling checks |
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

Read [AGENTS.md](AGENTS.md) for the shared constraints and required Git preparation before changes. Its linked guides cover implementation, issues, Git, pull requests and model attribution; load only those required for the task. Humans can use the same short guides as contribution checklists. Keep essential product, installation and contribution information in this README. Link to focused documentation for lengthy procedures or technical details instead of duplicating them.

Keep each change focused on an issue or clearly described problem. Explain the resulting behavior, how you checked it, and any remaining limitations. When a change affects how readers understand, use or contribute to the project, revise the relevant explanation rather than appending a change summary. Replace outdated text and remove details that no longer help; preserve essential estimation assumptions and coverage limits.

### Verify your change

- **Code changes:** run `./build.sh` and the checks relevant to the affected behavior. Compilation alone does not verify UI or calculation correctness.
- **Interface changes:** inspect the running app, including affected selection, layout, accessibility, empty and unavailable states.
- **Parsing, prices or caching:** use focused synthetic fixtures for the changed logic. Do not modify real Codex logs to create test cases.
- **Documentation-only changes:** check facts, links and Markdown structure; no rebuild is needed.

Run the focused release-update checks with Apple's Swift compiler (no live network or personal logs are used):

```sh
update_check_dir=$(mktemp -d)
xcrun swiftc -swift-version 5 -parse-as-library Updates.swift Tests/UpdatesChecks.swift -o "$update_check_dir/updates-checks"
"$update_check_dir/updates-checks"
rm -r "$update_check_dir"
```

These focused checks do not cover the full app or replace manual UI testing. For release updates, also check the menu, progress, current/newer/available versions, unavailable dates, failure/retry, the automatic-check toggle and the release link in a running app.

### Test an open pull request

Run `make pull-request` (or its alias `make pr`) in a macOS terminal. You can also run `./scripts/pull-request.sh` directly. It lists open PRs using GitHub’s public API, without requiring a token, GitHub CLI or an extra package for local testing. Enter a listed GitHub PR number (for example, `21`), or `0` to cancel. Set `NO_COLOR=1` to disable styling; redirected output and `TERM=dumb` also remain plain. Anonymous API rate limits apply.

The script fetches GitHub’s synthetic merge commit into a unique temporary Git ref, verifies its SHA and creates a detached worktree with `mktemp` outside your checkout. It leaves your branch, staged and unstaged changes, untracked files, remote configuration and `FETCH_HEAD` in place. This tests the PR combined with its target branch at that moment; later changes can produce a different result. Worktrees still share Git objects and metadata. Only run code you trust: the selected PR’s `./build.sh` executes with your user permissions.

The build runs in the isolated worktree. Its output moves to a separate temporary directory before the worktree is removed. The script gracefully quits any running Codex Costs instance, then opens the test app with `open -n -W`. The terminal waits until you quit the app completely, then deletes the test build and asks whether the test succeeded. Closing only the window is insufficient. Both successful and failed tests can be reported with screenshots after confirmation. Failed tests never offer merging. The test app uses the same bundle identifier and may share preferences with the installed app. Build failure leaves the existing app running. Git and build failures show diagnostics; unexpected changes in the temporary worktree are preserved for inspection rather than forcibly deleted. If interrupted while the app may be running, the script keeps its files and prints manual cleanup instructions.

After reporting the test result, optional GitHub actions use your authenticated GitHub CLI account. If `gh` is missing or unauthenticated, the script prints `gh auth login --hostname github.com` instructions and the PR URL, then finishes. It does not install tools or sign you in automatically. GitHub CLI requests have a 45-second limit; after a publication or merge error, check GitHub before retrying because the server may have completed the operation.

With repository write access and a version of `gh pr comment` supporting `--attach`, it offers image candidates created directly on `~/Desktop` between launch and return from the app. It uses filesystem creation times, not localized filenames. Other new images can appear; screenshots saved elsewhere are not detected. Each candidate is copied and shown in Quick Look before you choose whether to include it. Check that private data is hidden. No Desktop files are modified or deleted. The script shows `Tested successfully SHORT_HASH` for a successful test or `Test failed SHORT_HASH` for a failed test, using the short hash of the commit checked out in the test worktree, then asks separately before publishing the comment and approved images. Older CLI versions and accounts without upload rights can still post a text comment and attach images manually on GitHub. GitHub limits a comment to 50 attachments. See [GitHub’s attachment documentation](https://docs.github.com/en/github-cli/github-cli/attaching-files-with-github-cli).

The script offers merging only after a successful test and checking repository write access, an open non-draft PR, unchanged PR and target commits, and GitHub’s `CLEAN` merge status. Unknown permissions, pending checks or reviews, conflicts and blocked PRs do not produce a merge prompt. After a separate `[yN]` confirmation, you can choose an enabled squash, merge or rebase method, or cancel. The test hash identifies GitHub’s synthetic merge commit; the final merged commit can have a different hash, especially after squash or rebase. Permissions and readiness are checked again after your selection. The GitHub merge API locks the operation to the tested PR head and enforces server rules; it does not bypass protections, enable auto-merge, enter a merge queue or delete branches. The target branch can still advance between the final check and GitHub processing the request; the API has no equivalent target-commit lock. The script never posts or merges without your corresponding explicit selection.

### Release a build

Package the compiled app in a DMG for download, verify the final image, then calculate its SHA-256. Attach the image and checksum to the GitHub release and document the actual architecture, minimum macOS version and signing status. A checksum does not provide Developer ID signing or notarization.

Do not include personal session files, local pricing caches, credentials or generated build output in source commits.

## License

Codex Costs is licensed under the [MIT License](LICENSE). You may use, modify and redistribute it, including commercially, provided you retain the copyright and license notice in copies or substantial portions of the software.

The software is provided **"AS IS", without warranty of any kind**, with the exclusion of liability stated in the license. Cost estimates are informational and may be incomplete or inaccurate; see [Understanding the estimate](#understanding-the-estimate) and [Coverage and known limitations](#coverage-and-known-limitations).
