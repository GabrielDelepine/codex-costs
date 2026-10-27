# Agent instructions

Keep Codex Costs a tiny, native, local macOS utility for understanding Codex token usage and estimated API cost.

- Write all repository content in English: code, identifiers, comments, documentation, scripts, interactive prompts, status output, error messages, and agent instructions. Preserve external data such as original PR or conversation titles.
- Use Swift and Apple frameworks only. No third-party dependencies, web UI, backend, account or API-key requirement.
- Preserve `./build.sh`, standalone `.app` output and few, readable source files. Add abstraction only for a concrete need.
- Keep logs read-only and private. Never upload conversation data or commit personal logs, caches, credentials or build output.
- Prefer an explained unavailable estimate to a guessed cost. State assumptions and coverage gaps.
- Keep changes focused. Update affected documentation; distinguish implemented behavior from proposals.

Read only the relevant guides before editing; combine them for cross-cutting work:

| Change | Guide |
| --- | --- |
| Interface, calendar, navigation, formatting, icons | [Interface](docs/agents/interface.md) |
| Log parsing, token counters, pricing, totals, history | [Usage](docs/agents/usage.md) |
| File watching, caching, concurrency, build, distribution | [Runtime](docs/agents/runtime.md) |
| Bash scripts, terminal menus, PR testing helpers | [Bash](docs/agents/bash.md) |

After code changes, run `./build.sh` and relevant checks from the guides. For documentation-only changes, check facts, links and consistency; compilation is unnecessary. Human contribution guidance is in [README.md](README.md#contributing).

## Versioning

- Use Semantic Versioning: MAJOR.MINOR.PATCH.
- Each distributed artifact must have a unique public version.
- If rebuilding produces a different artifact intended for distribution, increment at least PATCH, even when the source commit is unchanged.
- Do not use a separate build number to distinguish distributed artifacts.
- Display the public version without a parenthesized build number.
- Keep any build metadata required by Apple consistent with the public version.
- Change the version when preparing a release, not on every commit or local build.
