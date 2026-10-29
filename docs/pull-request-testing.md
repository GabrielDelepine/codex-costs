# Test a pull request

Run `make pr`, `make pull-request` or `./scripts/pull-request.sh` in a macOS terminal. Select a listed GitHub PR number, or `0` to cancel. Public API rate limits apply. Local testing needs no account, GitHub CLI or extra package. `NO_COLOR=1` disables styling.

## Isolation and app lifecycle

By default, the script tests GitHub's synthetic merge of the PR and its target branch, verifies the SHA and builds in a temporary detached worktree. An approved rebase instead tests the rewritten PR head. Your branch, local changes, untracked files, remote configuration and `FETCH_HEAD` stay unchanged. Worktrees share Git objects and metadata. **Only test trusted code:** the PR's build executes with your user permissions.

After a successful build, the script gracefully quits any running Codex Costs instance and launches the test app. Both apps use the same bundle identifier and may share preferences. Quit the app completely to return to the terminal; closing its window is insufficient. Build failure leaves the existing app running.

The script normally removes temporary files. If interrupted while the app may be running, or if unexpected worktree changes prevent cleanup, it retains files and prints recovery instructions.

## Optional signed rebase

With an authenticated GitHub CLI account, the script checks every PR commit's author against your account. Unknown or other authors, co-author credits and incomplete commit listings keep the synthetic merge test. Only PRs targeting `main` with source repository write access offer rebasing.

When the PR already contains the current `main` and every commit title includes its PR number, the script tests the existing PR head without asking, rewriting commits or pushing the PR branch. It still offers the final fast-forward after a successful test. Otherwise, “Rebase commits on main?” defaults to yes; choose no to keep the existing merge test. Missing PR numbers still require confirmation even when the branch already contains `main`. Accepting rewrites the commits in the isolated worktree, preserves their author dates, message bodies and merge structure, and adds `(#PR-number)` to each title unless already present. Git follows your local commit-signing configuration and verifies required signatures before publishing. Rewriting existing signed commits requires signing to be enabled; no unsigned replacement is published.

The script updates the PR source branch with `--force-with-lease` pinned to its original head, then builds the rebased head. It never rewrites your checkout or a local branch. A failed or cancelled test does not undo the published rebase. Rebase, signing or push failures stop the test and retain the worktree for inspection; check GitHub before retrying an uncertain push. To discard an unfinished rebase, run `git -C <retained-worktree> rebase --abort`, then remove that worktree.

## Feedback and screenshots

Successful and failed tests can be reported through an authenticated GitHub CLI account. Missing authentication produces sign-in instructions; the script does not install tools or sign you in. After a publication or merge error, check GitHub before retrying: a request can succeed despite a client error.

Automatic image attachments require repository write access and `gh pr comment --attach` support. Candidates are images created directly on `~/Desktop` during the app test, identified by filesystem creation time. Other images may appear; screenshots saved elsewhere are not detected.

Each candidate is copied and previewed in Quick Look before you approve it. Check for private data. Desktop originals are never changed or deleted. Publishing the result and approved images requires a separate confirmation. Without attachment support, text feedback remains available and images can be attached manually on GitHub.

Result comments identify the commit used to build the app: the prepared PR head when rebasing was accepted or already unnecessary, otherwise the synthetic merge commit. The synthetic merge hash may differ from the final merged commit.

## Optional merge

Merging is offered only after a successful test, with repository write access, an open non-draft PR, unchanged PR/target commits and GitHub's `CLEAN` merge status. Failed tests, conflicts, pending checks/reviews and unknown permissions do not offer merging.

After an accepted rebase, or when the PR head was already prepared, the final question offers a fast-forward into `main`, defaulting to no. It pushes the exact tested head without force or a new merge commit. Readiness is checked again after confirmation. A divergent update to `main` rejects the push, and server branch protections still apply; the script does not bypass them. GitHub recognizes the PR as merged when its head becomes part of `main`.

Without a rebase, a separate confirmation lets you choose an enabled squash, merge or rebase method, or cancel. Permissions and readiness are rechecked. GitHub locks the operation to the tested PR head and enforces server protections; the target can still advance before processing because the merge API has no target-commit lock. The script does not enable auto-merge, enter a merge queue or delete branches.

Run `/bin/bash Tests/PullRequestChecks.sh` for isolated checks of prompt defaults, signed rebases, commit messages, ownership checks, failure handling and local fast-forward pushes. The fixtures use temporary signing keys and repositories and never contact GitHub or launch the app.
