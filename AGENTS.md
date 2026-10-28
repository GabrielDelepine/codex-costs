# Agent instructions

Keep Codex Costs a tiny, native, local macOS utility for understanding Codex token usage and estimated API cost.

- Write all repository content in English: code, identifiers, comments, documentation, scripts, interactive prompts, status output, error messages, and agent instructions. Preserve external data such as original PR or conversation titles.
- Use Swift and Apple frameworks only. No third-party dependencies, web UI, backend, account or API-key requirement.
- Preserve `./build.sh`, standalone `.app` output and few, readable source files. Add abstraction only for a concrete need.
- Keep logs read-only and private. Never upload conversation data or commit personal logs, caches, credentials or build output.
- Prefer an explained unavailable estimate to a guessed cost. State assumptions and coverage gaps.
- Keep changes focused. Update affected documentation; distinguish implemented behavior from proposals.

Before modifying repository files, read [Git](docs/agents/git.md) and verify that the current directory is the dedicated Git worktree for this task. Reuse it when continuing the same task; otherwise, create a dedicated worktree and switch to its directory before editing. If the worktree cannot be created or verified, stop and report the blocker without modifying repository files. Keep the original checkout, its current branch, and any local changes unchanged. Follow the guide’s branch-isolation rules in the dedicated worktree.

For other work, read only the relevant guides; combine them for cross-cutting tasks:

| Change | Guide |
| --- | --- |
| Interface, calendar, navigation, formatting, icons | [Interface](docs/agents/interface.md) |
| Log parsing, token counters, pricing, totals, history | [Usage](docs/agents/usage.md) |
| File watching, caching, concurrency, build, distribution | [Runtime](docs/agents/runtime.md) |
| Bash scripts, terminal menus, PR testing helpers | [Bash](docs/agents/bash.md) |
| Creating or rewriting an issue | [Issues](docs/agents/issues.md) |
| Branches, commits, signing, rebasing, pushing | [Git](docs/agents/git.md) |
| Creating, reviewing or updating a PR | [Pull requests](docs/agents/pull-requests.md) |
| Identifying Codex and contributing models in a PR | [Provenance](docs/agents/provenance.md) |

After code changes, run `./build.sh` and relevant checks from the guides. For documentation-only changes, check facts, links and consistency; compilation is unnecessary. Human contribution guidance is in [README.md](README.md#contributing).

Change versions when preparing a release, not on every commit or local build. Each distributed artifact must have a unique public semantic version; see [Runtime and distribution](docs/agents/runtime.md#versioning).

## Writing style

These rules apply to all generated text: chat replies, documentation, interface text, commit messages, and GitHub content. This includes issue and PR titles, descriptions, reviews, and comments.

- Be concise and direct. Use short, clear sentences and familiar, precise words. Keep one main idea per sentence.
- Preserve the intended meaning and necessary context. Keep required details, evidence, qualifications, and disclosures, even when they need more space.
- Remove repetition, filler, and unnecessary structure. Keep the length proportional to the task.
- Stay polite and respectful. When addressing people, phrase requests as courteous questions or suggestions. Avoid commands or a demanding tone.
