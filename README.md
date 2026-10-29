# Codex Costs

A small native macOS app to compare local Codex token usage and estimate its cost at current OpenAI API rates. No API key, account, server or third-party dependencies are required.

Pick a day or date range, compare conversations, and open the info panel for token counters and applied prices. Conversation titles open in Codex; IDs can be copied from the info panel. The interface is English, with dates and numbers formatted using macOS regional preferences.

[Download](https://github.com/GabrielDelepine/codex-costs/releases) · [Report a problem](https://github.com/GabrielDelepine/codex-costs/issues) · [Contribute](#contributing)

> Estimates use current Standard API prices in USD. They are not ChatGPT subscription charges, remaining allowances or historical invoices. Unreliable estimates are shown as unavailable and excluded from totals.

![Codex Costs conversation table](./docs/screenshot_2026-10-22.avif)

## Download and install

Requires macOS 14 Sonoma or later, Apple Silicon or Intel, and Codex logs in the default `~/.codex` directory.

1. Download the `.dmg` application asset from [Releases](https://github.com/GabrielDelepine/codex-costs/releases). The automatic source archives are not compiled apps.
2. Open the disk image and drag **Codex Costs.app** to **Applications**.
3. Open the app. If macOS blocks it, see below.

### Signing and first launch

Builds are **ad-hoc signed and not notarized**. If you trust the release, follow [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445). After attempting to launch it, macOS may offer **Open Anyway** in **System Settings → Privacy & Security**.

If the release includes `SHA256SUMS.txt`, place it beside the DMG and run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

An `OK` result confirms the file matches the published checksum. It does not establish authenticity, Developer ID signing or notarization.

## Understanding the estimate

### Prices and refreshes

Prices come from [tools.pwa.ovh](https://tools.pwa.ovh/openai-pricing), which cites [OpenAI's published pricing](https://developers.openai.com/api/docs/pricing). Only Standard API token rates in USD are used; Fast, Ultrafast, Batch and Flex rates are excluded.

Refreshing prices recalculates visible conversations, including older ones. The footer's **via tools.pwa.ovh** date identifies when the source catalogue was retrieved, not the latest download attempt. Prices refresh every six hours while the app runs, or manually. Failed downloads preserve the last valid catalogue and its retrieval date; without one, estimates are unavailable.

### Token counting and pricing

The app calculates differences between cumulative log counters and validates each difference against the last-request counters. Repeated unchanged events do not add usage.

Input includes cached reads and writes. Output includes reasoning; neither is added twice:

```text
ordinary input = total input − cached reads − cache writes

request cost = ordinary input × input rate
             + cached reads × cached-input rate
             + output × output rate
```

Requests with cache writes are currently unavailable because their retention duration, needed to select a price, is unknown. Costs use decimal arithmetic and are summed before display rounding.

The info panel shows only the model/context price grids used by available request estimates. Checked components contributed tokens; unchecked components were unused. If the conversation total is unavailable, those grids describe only the requests that could be priced.

### Inspect individual requests

Conversation totals, counters, applied pricing and log information appear first in the info panel. An **Individual requests** table appears at the bottom, in log order, with a sequence number, recorded usage-event time, model, context tier and estimated cost for each request. Select a row to inspect its input, cached reads, cache writes and output counters, full timestamp and any unavailable-estimate reason. Request details also show reasoning tokens (already included in output), input excluding cache, output excluding reasoning, and cached reads as a percentage of total input (unavailable when total input is zero). A cost breakdown shows ordinary input, cached reads and output using the same unrounded Decimal calculation as the request total; components are unavailable when the request cannot be priced. Reasoning is not charged again. Display rounding can make component amounts differ from the displayed total when added. The panel automatically scrolls to reveal the selected request’s details, including when navigating with the keyboard. Hover over a time, model, context or cost for its full value or explanation. The table scrolls for longer conversations.

There is no context-group summary in the request section: context is shown per request. A usage timestamp is not an inferred request start time; missing timestamps remain explicit. Request estimates do not replace an unavailable conversation estimate or imply complete coverage. Repeated unchanged usage events do not create duplicate requests.

### Context pricing assumptions

The estimator selects a context tier **per request**, using total input including cache, and applies that tier to the entire request. It does not use conversation totals or the model's context-window capacity.

These are disclosed assumptions: the pricing endpoint does not verify those billing semantics. Models without context-specific prices use their published grid without an invented threshold.

### Unavailable estimates

An estimate is unavailable when the conversation contains multiple models, a model or required price is missing, counters are incomplete or inconsistent, counters reset, usage cannot be matched to a request, or cache-write retention is unknown. A required `null` price means unknown, not free. Model aliases are not guessed.

A partial final JSON line is retried after the file changes; an invalid interior line prevents estimation. These checks favor an explained gap over a guessed amount.

## Coverage and known limitations

The app reads:

- Active logs: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
- Archived logs: `~/.codex/archived_sessions/rollout-*.jsonl`.
- Conversation titles: `~/.codex/session_index.jsonl`.

There is no custom Codex-home setting. Archived conversations retain their original local creation date. Duplicate IDs are counted once, preferring an active copy; copied parent metadata does not replace a fork's identity.

**Work conversations are not currently covered.** Guardian Reviews are excluded from rows, totals and calendar availability. Coverage depends on local files and their evolving format, not on all devices, accounts or Codex surfaces. A missing conversation does not imply zero usage.

Parsed usage lives in memory. Deleted source files disappear from the app; it is not a permanent history archive. Missing history can have several causes, and automatic deletion by Codex has not been established.

Estimates exclude tool fees, subagent usage recorded in separate sessions, image and voice generation, regional surcharges and account-specific pricing.

## Privacy and local storage

Session logs are read-only. Prompts, titles, IDs and counters stay on your Mac. Network requests retrieve the pricing catalogue and public GitHub release metadata; there is no analytics service or authentication requirement.

The last valid pricing catalogue is saved at `~/Library/Application Support/CodexCosts/pricing.json`. App preferences, pricing download time and release-check metadata use macOS user defaults. Parsed conversation usage is not persisted.

## How updates work

### Usage and prices

Usage updates for any selected date range. **Auto-select today** starts enabled on each launch and follows day changes at the next log check. Selecting dates disables it; cancelling the calendar preserves the selection and mode.

Filesystem notifications refresh usage promptly while a window is visible and batch updates while all windows are hidden or obscured. Showing a window or waking the Mac triggers a check. A recovery loop waits 60 seconds between checks; sleep, suspension and scan duration can delay it. This is not a guaranteed midnight deadline. Only changed logs are reparsed; price refreshes are independent.

### Application releases

**Codex Costs → Check for Updates…** checks the latest stable GitHub release. Automatic checks start enabled, run every 72 hours after success, and retry failures after one hour while the app runs. Manual checks bypass that schedule and work with automatic checks disabled. Background checks never open a window or take focus.

An **Update available** indicator opens saved release details, even after a later check fails. **View Release on GitHub** opens the release for manual download; the app does not install or restart itself. **Later** closes the window and leaves the indicator available. Failure is reported separately from being up to date, and newer local versions are not offered a downgrade. Release dates come from GitHub releases; unavailable dates are not replaced with build dates.

## Build from source

Requires a Mac with Xcode's Swift tools installed and selected. A few Swift files, `build.sh` and a small Makefile deliberately replace an Xcode project; no package installation is needed.

```sh
git clone https://github.com/GabrielDelepine/codex-costs.git
cd codex-costs
./build.sh --open
```

`./build.sh` builds without launching. It produces `build/Codex Costs.app` for the host architecture, includes the MIT license and applies an ad-hoc signature. `make build` and `make run` provide build and launch shortcuts.

The About window shows the public version, source commit and build dates. Modified builds identify their commit as the base source. Release versioning, architecture and packaging requirements are in the [runtime and distribution guide](docs/agents/runtime.md).

## Contributing

Keep the app small, native and local: Swift and Apple frameworks, no third-party dependencies, and a one-command build. Prefer clear behavior and unavailable estimates to extra controls or speculative calculations.

### Report a problem

[Open an issue](https://github.com/GabrielDelepine/codex-costs/issues) with the app/macOS versions, expected and actual behavior, and a minimal reproduction. For missing conversations, include their approximate creation date and whether they are project-associated, projectless or Work conversations. For calculation problems, provide only relevant redacted counters and model information. Label suspected causes as hypotheses. Never publish full logs, prompts, credentials or private screenshots.

### Prepare and verify a change

Read [AGENTS.md](AGENTS.md) for worktree isolation and the relevant task guides. Humans can use the same guides as checklists.

Keep essential product, installation and contribution information here. Link to focused documentation for lengthy procedures. Revise existing explanations when behavior changes; remove obsolete or redundant text while preserving essential estimation assumptions and coverage limits.

- Run `./build.sh` after code changes. Inspect changed UI in the running app, including selection, accessibility and unavailable states.
- Check parsing, pricing and caching with synthetic fixtures, never edited personal logs. Compilation alone does not establish correctness.
- For documentation changes, check facts, links and consistency.

Focused release-update checks are described in the [runtime guide](docs/agents/runtime.md#release-update-checks); they are not a full app test suite.

### Test an open pull request

Run `make pr` (or `make pull-request`) in a macOS terminal and enter a listed PR number. Testing uses a temporary worktree and leaves your checkout unchanged. Only test code you trust: the PR's build runs with your user permissions. The script quits a running Codex Costs instance; the test app may share its preferences.

Quit the test app completely to return to the terminal. Publishing results or screenshots and merging each require explicit choices. Failed tests never offer merging. See the [testing guide](docs/pull-request-testing.md) for requirements, privacy precautions and recovery details.

## License

[MIT](LICENSE). Copies and substantial portions must retain its copyright and license notice. The software is provided **AS IS**, without warranty. Estimates may be incomplete or inaccurate; see [estimation assumptions](#understanding-the-estimate) and [coverage limits](#coverage-and-known-limitations).
