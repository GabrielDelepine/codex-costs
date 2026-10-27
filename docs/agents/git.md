# Git workflow

## Pull request isolation

- Determine the repository’s default branch from GitHub. Never assume its name or use the current local branch as a substitute. If it cannot be determined or fetched, stop and report the blocker.
- Before making changes, fetch the default branch from the GitHub remote and create a fresh working branch from that exact remote-tracking commit. Use a separate worktree when needed to preserve existing local work.
- Never base the branch on another PR, an existing feature branch, or an outdated local default branch. Stacked PRs require explicit user authorization.
- If relevant changes already exist elsewhere, apply only the changes required for this PR onto the fresh branch. Do not merge the source branch or carry over unrelated commits.
- Before opening the PR, fetch the default branch again. If it has advanced, rebase onto its latest remote state, resolve conflicts, and rerun the required checks. Coordinate explicitly before rewriting a branch shared with other contributors.
- Inspect every commit and the complete diff against the fetched default branch. Remove unrelated changes and commits inherited from other PRs before proceeding.
- Open the PR targeting the repository’s default branch. Read [Pull requests](pull-requests.md) for its description and validation requirements.

## Commit signing

- Inspect the effective local Git configuration before creating or rewriting commits. If it requires signing, preserve the configured signing identity and mechanism; never disable or bypass signing.
- When signing is configured, sign every commit created or rewritten, including amended, squashed, rebased, and cherry-picked commits. Pass explicit signing options where needed, especially with low-level Git commands; do not assume every command honors `commit.gpgsign`.
- Verify required signatures before pushing. If signing or verification fails, resolve the issue or report the blocker; never publish an unsigned replacement.
- If the local Git configuration does not require signing, do not impose it. Repository merge requirements may still require the developer to provide signed commits before merging.
- Git commit signing is separate from application signing; see [Runtime and distribution](runtime.md) for binary signing.

## Commit structure within a pull request

- Keep separate commits only for distinct, coherent features or changes whose separation helps review. A PR implementing one coherent change should normally contain one commit.
- Fold corrections, review feedback, layout refinements, and other fixes into the commit they modify. Before opening or updating a PR, review its entire commit history and squash fixup commits into their relevant commits.
- Preserve the final file contents when rewriting history, and sign rewritten commits when required by the local configuration.
- Coordinate explicitly before rewriting commits on a shared branch. When rewriting published commits, update the existing PR branch with `--force-with-lease`. Never use an unprotected force push.
