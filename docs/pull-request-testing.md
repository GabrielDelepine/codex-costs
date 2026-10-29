# Test a pull request

Run `make pr`, `make pull-request` or `./scripts/pull-request.sh` in a macOS terminal. Select a listed GitHub PR number, or `0` to cancel. Public API rate limits apply. Local testing needs no account, GitHub CLI or extra package. `NO_COLOR=1` disables styling.

## Isolation and app lifecycle

The script tests GitHub's synthetic merge of the PR and its target branch, verifies the SHA and builds in a temporary detached worktree. Your branch, local changes, untracked files, remote configuration and `FETCH_HEAD` stay unchanged. Worktrees share Git objects and metadata. **Only test trusted code:** the PR's build executes with your user permissions.

After a successful build, the script gracefully quits any running Codex Costs instance and launches the test app. Both apps use the same bundle identifier and may share preferences. Quit the app completely to return to the terminal; closing its window is insufficient. Build failure leaves the existing app running.

The script normally removes temporary files. If interrupted while the app may be running, or if unexpected worktree changes prevent cleanup, it retains files and prints recovery instructions.

## Feedback and screenshots

Successful and failed tests can be reported through an authenticated GitHub CLI account. Missing authentication produces sign-in instructions; the script does not install tools or sign you in. After a publication or merge error, check GitHub before retrying: a request can succeed despite a client error.

Automatic image attachments require repository write access and `gh pr comment --attach` support. Candidates are images created directly on `~/Desktop` during the app test, identified by filesystem creation time. Other images may appear; screenshots saved elsewhere are not detected.

Each candidate is copied and previewed in Quick Look before you approve it. Check for private data. Desktop originals are never changed or deleted. Publishing the result and approved images requires a separate confirmation. Without attachment support, text feedback remains available and images can be attached manually on GitHub.

Result comments identify the tested synthetic merge commit. Its hash may differ from the final merged commit.

## Optional merge

Merging is offered only after a successful test, with repository write access, an open non-draft PR, unchanged PR/target commits and GitHub's `CLEAN` merge status. Failed tests, conflicts, pending checks/reviews and unknown permissions do not offer merging.

A separate confirmation lets you choose an enabled squash, merge or rebase method, or cancel. Permissions and readiness are rechecked. GitHub locks the operation to the tested PR head and enforces server protections; the target can still advance before processing because the merge API has no target-commit lock. The script does not enable auto-merge, enter a merge queue or delete branches.
