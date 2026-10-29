# Pull requests

Follow the shared [writing style](../../AGENTS.md#writing-style) for titles, descriptions, reviews, and comments.

## Titles and descriptions

- Write the title and description in English.
- Default to a short description: one brief paragraph explaining the change, a compact validation summary, and specific manual checks when useful. Keep attribution to one sentence. Describe the final result, not the development history. Avoid exhaustive lists of files, checks, preserved behavior, or implementation details. Expand only for material risks or complexity.
- Title the PR around the concrete change delivered by its commits.
- Describe how the application's behavior changes. For changes without a user-facing effect, explain their concrete purpose and result.
- Link to the related issue for the problem and context. Repeat only what is needed to understand the change without duplicating the issue.
- When a PR closes an issue, the very first line of its description must be `Closes #<issue-number>`.
- Every PR description must identify OpenAI Codex and preserve the exact model IDs that contributed. Read [Provenance](provenance.md) for verification and attribution. If Codex implemented the change and opened the PR autonomously, state this explicitly.
- Include validation results only when they help assess the change. Omit routine housekeeping checks and statements that testing is unnecessary or not applicable. Mention pending human testing only when it leaves a relevant behavior unverified. Distinguish automated checks from confirmed human testing, and describe their scope accurately.

Before changing files or performing branch, commit, or push operations, read [Git](git.md). Follow the validation requirements in [AGENTS.md](../../AGENTS.md) and the technical guides relevant to the change.

## Reviewing an existing PR against current changes

- Treat requests such as “check whether this PR is still good” or “check whether it is up to date” as a reassessment of the entire PR against the current default branch, including semantic compatibility. A conflict-free merge is not sufficient evidence of compatibility.
- Determine the default branch from GitHub, fetch its latest state, and identify the changes merged since the PR diverged from it.
- Review the complete PR diff and relevant intervening changes. Check whether newer behavior, assumptions, data flows, caching, interfaces, or documentation invalidate any part of the proposal.
- A request to check or review a PR alone authorizes analysis, not edits or pushes. Report proposed corrections, then explicitly ask: “Here is what should change. Do you confirm that I should make these changes and push them to the PR branch?” An explicit request to make corrections and push them already provides that authorization. Neither request authorizes merging the PR.
- Once authorized, make necessary, focused adjustments and update affected documentation. Follow [Git](git.md): apply the existing PR's relevant changes onto a fresh branch from the fetched default branch, inspect the resulting history, and update the existing PR branch and description. Coordinate before rewriting a shared branch.
- For code changes, run `./build.sh` and relevant automated checks. Add focused synthetic checks for interactions introduced by intervening changes. For documentation-only changes, check facts, links and consistency; compilation is unnecessary. Report validation only when relevant to the review, following the description rules above.
- Before pushing, fetch the default branch again and reassess any new changes. Rebase when necessary, resolve conflicts and rerun affected checks. Inspect the final diff and every PR commit.
- Report relevant compatibility findings, adjustments, validation results, and remaining gaps. Omit routine checks that add no useful review context.
