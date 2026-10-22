# Agent instructions

Keep Codex Costs a tiny, native, local macOS utility for understanding Codex token usage and estimated API cost.

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

After code changes, run `./build.sh` and relevant checks from the guides. For documentation-only changes, check facts, links and consistency; compilation is unnecessary. Human contribution guidance is in [README.md](README.md#contributing).
