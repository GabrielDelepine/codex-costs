#!/bin/bash
set -euo pipefail

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

project_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_directory"
repository="GabrielDelepine/codex-costs"
repository_url="https://github.com/$repository"
api_url="https://api.github.com/repos/$repository/pulls"

# Use the terminal's own palette so both light and dark themes stay legible.
bold='' reset='' cyan='' green='' yellow='' red=''
if [[ -t 1 && -t 2 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]]; then
    bold=$'\033[1m'
    reset=$'\033[0m'
    cyan=$'\033[36m'
    green=$'\033[32m'
    yellow=$'\033[33m'
    red=$'\033[31m'
fi

section() {
    printf '\n  %s%s%s%s\n' "$bold" "$cyan" "$1" "$reset"
}

# Keep successful tool output quiet; show indented diagnostics on failure.
run_quietly() {
    local error_message="$1"
    shift

    if "$@" >"$temporary_directory/command.log" 2>&1; then
        return 0
    fi

    sed 's/^/    /' "$temporary_directory/command.log" >&2
    fail "$error_message"
}

fail() {
    printf '\n    %s✕ Test stopped%s\n    %s\n\n' "$red$bold" "$reset" "$*" >&2
    exit 1
}

# Bound GitHub CLI requests without changing the user's gh configuration.
run_gh() (
    GH_HOST=github.com GH_PROMPT_DISABLED=1 gh "$@" &
    local command_pid=$! watchdog_pid result
    (
        sleep 45 &
        timer_pid=$!
        trap 'kill "$timer_pid" 2>/dev/null || true' EXIT
        trap 'exit 0' TERM HUP INT
        if wait "$timer_pid"; then
            kill -TERM "$command_pid" 2>/dev/null || true
        fi
    ) &
    watchdog_pid=$!
    trap 'kill "$watchdog_pid" 2>/dev/null || true' EXIT
    trap 'kill "$command_pid" 2>/dev/null || true; exit 130' INT
    trap 'kill "$command_pid" 2>/dev/null || true; exit 143' TERM HUP
    if wait "$command_pid"; then result=0; else result=$?; fi
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    return "$result"
)

# EOF and cancellation always mean no permission to publish or merge.
ask_yes_no() {
    local answer
    while true; do
        printf '\n    %s [yN] ' "$1"
        if ! read -r answer; then
            printf '\n\n'
            return 2
        fi
        printf '\n'
        case "$answer" in
            [yY]|[yY][eE][sS]) return 0 ;;
            ''|[nN]|[nN][oO]) return 1 ;;
            *) printf '    Enter y or n.\n' ;;
        esac
    done
}

cleanup() {
    # Never force removal: unexpected changes in the test worktree are preserved.
    if [[ -d "$test_worktree" ]]; then
        if git worktree remove "$test_worktree" >"$temporary_directory/cleanup.log" 2>&1; then
            rmdir "$worktree_directory" 2>/dev/null || true
        else
            printf '\n    Test worktree retained: %s\n' "$test_worktree" >&2
            printf '    Inspect it, then remove it with: git worktree remove %q\n' "$test_worktree" >&2
        fi
    else
        rmdir "$worktree_directory" 2>/dev/null || true
    fi
    git update-ref -d "$test_reference" 2>/dev/null || true
    if [[ "$app_may_be_running" == true ]]; then
        printf '\n    The test app may still be running. Its files were kept at:\n    %s\n' "$temporary_directory" >&2
        printf '    After quitting it, remove them with: rm -rf %q\n' "$temporary_directory" >&2
    else
        rm -rf "$temporary_directory"
    fi
}

# Only consider image files created on the Desktop during this test. Names and
# their localized dates are deliberately ignored; every candidate is previewed.
collect_screenshots() {
    local image creation_time
    screenshot_choices=()
    [[ -d "$HOME/Desktop" ]] || return 0
    while IFS= read -r -d '' image; do
        case "$image" in
            *.[pP][nN][gG]|*.[jJ][pP][gG]|*.[jJ][pP][eE][gG]|*.[gG][iI][fF]|*.[wW][eE][bB][pP]) ;;
            *) continue ;;
        esac
        creation_time=$(stat -f '%B' "$image" 2>/dev/null) || continue
        [[ "$creation_time" =~ ^[0-9]+$ ]] || continue
        if (( creation_time >= test_started && creation_time <= test_finished )); then
            screenshot_choices+=("$image")
        fi
    done < <(find "$HOME/Desktop" -maxdepth 1 -type f -print0)
}

# Read-only checks. A permission level alone does not establish merge readiness.
check_merge_ready() {
    local permission snapshot current_head current_base current_state current_draft mergeable merge_status
    if ! permission=$(run_gh api "repos/$repository" --jq '.permissions.push' 2>"$temporary_directory/github.log"); then
        printf '    Merge unavailable: could not verify your GitHub permissions.\n'
        return 1
    fi
    if [[ "$permission" != true ]]; then
        printf '    Merge unavailable: your GitHub account does not have write access.\n'
        return 1
    fi
    if ! snapshot=$(run_gh pr view "$pull_number" --repo "$repository" \
        --json headRefOid,baseRefOid,state,isDraft,mergeable,mergeStateStatus \
        --jq '[.headRefOid, .baseRefOid, .state, (.isDraft | tostring), .mergeable, .mergeStateStatus] | @tsv' \
        2>"$temporary_directory/github.log"); then
        printf '    Merge unavailable: could not verify the PR status.\n'
        return 1
    fi
    IFS=$'\t' read -r current_head current_base current_state current_draft mergeable merge_status <<< "$snapshot"
    if [[ "$current_state" != OPEN || "$current_draft" != false ]]; then
        printf '    Merge unavailable: the PR is closed or a draft.\n'
        return 1
    fi
    if [[ "$current_head" != "$tested_head" || "$current_base" != "$tested_base" ]]; then
        printf '    Merge unavailable: the PR or its target branch changed. Run a new test.\n'
        return 1
    fi
    if [[ "$mergeable" == CONFLICTING ]]; then
        printf '    Merge unavailable: the PR has merge conflicts.\n'
        return 1
    fi
    if [[ "$mergeable" != MERGEABLE || "$merge_status" != CLEAN ]]; then
        printf '    Merge unavailable: GitHub reports pending checks, reviews or rules, or an unknown merge status.\n'
        return 1
    fi
}

share_feedback() {
    local test_successful="$1"
    local image snapshot attach_help can_attach permission merge_method option selection
    local attachments=() merge_methods=()
    if ! command -v gh >/dev/null 2>&1 || ! run_gh auth status --hostname github.com >"$temporary_directory/github.log" 2>&1; then
        printf '\n    To continue, install GitHub CLI if needed and run: gh auth login --hostname github.com\n'
        printf '    Sign in to post a comment, attach screenshots and merge eligible PRs from this script.\n'
        printf '    PR: %s\n' "$pull_url"
        return
    fi

    permission=$(run_gh api "repos/$repository" --jq '.permissions.push' 2>"$temporary_directory/github.log") || permission=false
    attach_help=$(run_gh pr comment --help 2>/dev/null) || attach_help=''
    can_attach=false
    if [[ "$permission" == true && "$attach_help" == *--attach* ]]; then
        can_attach=true
    fi
    if [[ "$can_attach" == true ]]; then
        collect_screenshots
        for image in "${screenshot_choices[@]+"${screenshot_choices[@]}"}"; do
            printf '\n    Screenshot from this test: %s\n' "$image"
            # Preview an immutable copy with a safe attachment name. A Desktop
            # edit or a '#' in its original filename cannot change the upload.
            option=$((${#attachments[@]} + 1))
            mkdir -p "$temporary_directory/attachments/$option"
            snapshot="$temporary_directory/attachments/$option/screenshot.${image##*.}"
            if ! cp "$image" "$snapshot"; then
                printf '    Could not copy this screenshot; skipping it.\n'
                continue
            fi
            printf '    Close the Quick Look preview to return to this terminal.\n'
            if ! qlmanage -p "$snapshot" >/dev/null 2>&1; then
                printf '    Could not preview this screenshot; skipping it.\n'
                continue
            fi
            if ask_yes_no 'Include this screenshot in the PR comment? Check that private data is hidden.'; then
                attachments+=("$snapshot")
                if [[ ${#attachments[@]} -eq 50 ]]; then
                    printf '    GitHub accepts at most 50 attachments per comment.\n'
                    break
                fi
            fi
        done
        if [[ ${#screenshot_choices[@]} -eq 0 ]]; then
            printf '    No screenshots found on the Desktop during this test.\n'
        fi
    else
        printf '    Automatic screenshots require repository write access and gh pr comment --attach support.\n'
        printf '    You can attach screenshots manually on GitHub: %s\n' "$pull_url"
    fi

    if [[ "$test_successful" == true ]]; then
        printf 'Tested successfully %s\n' "$tested_commit_short" >"$temporary_directory/comment.md"
    else
        printf 'Test failed %s\n' "$tested_commit_short" >"$temporary_directory/comment.md"
    fi
    printf '\n    Comment to publish:\n\n'
    sed 's/^/      /' "$temporary_directory/comment.md"
    if [[ ${#attachments[@]} -gt 0 ]]; then
        printf '\n    Screenshots: %s\n' "${#attachments[@]}"
    fi
    if ask_yes_no 'Post this comment to GitHub?'; then
        local comment_arguments=(pr comment "$pull_number" --repo "$repository" --body-file "$temporary_directory/comment.md")
        for image in "${attachments[@]+"${attachments[@]}"}"; do
            comment_arguments+=(--attach "$image")
        done
        if ! run_gh "${comment_arguments[@]}"; then
            printf '    Comment publication failed. Check the PR before retrying to avoid duplicates.\n'
        fi
    fi

    if [[ "$test_successful" != true ]]; then
        return
    fi
    if ! check_merge_ready; then
        return
    fi
    if ! run_gh api "repos/$repository" >"$temporary_directory/response.json" 2>"$temporary_directory/github.log"; then
        printf '    Could not check allowed merge methods. Review the PR on GitHub.\n'
        return
    fi
    while IFS= read -r merge_method; do
        [[ -n "$merge_method" ]] && merge_methods+=("$merge_method")
    done <<< "$(parse_response methods)"
    if [[ ${#merge_methods[@]} -eq 0 ]]; then
        printf '    No supported merge method is enabled. Review the PR on GitHub.\n'
        return
    fi
    if ! ask_yes_no "Merge PR #$pull_number?"; then
        return
    fi
    printf '\n    Merge method:\n'
    for ((option=0; option<${#merge_methods[@]}; option++)); do
        printf '    %s  %s\n' "$((option + 1))" "${merge_methods[$option]}"
    done
    printf '    0  Do not merge\n'
    while true; do
        printf '    › '
        read -r selection || return 0
        [[ "$selection" == 0 ]] && return 0
        for ((option=0; option<${#merge_methods[@]}; option++)); do
            if [[ "$selection" == "$((option + 1))" ]]; then
                merge_method="${merge_methods[$option]}"
                if ! check_merge_ready; then
                    return
                fi
                # REST merges immediately or refuses. It never enables auto-merge,
                # enters a merge queue, bypasses rules or switches a local branch.
                if run_gh api --method PUT "repos/$repository/pulls/$pull_number/merge" \
                    -f "sha=$tested_head" -f "merge_method=$merge_method" \
                    --jq 'if .merged then .message else error(.message) end'; then
                    printf '    PR #%s merged successfully.\n' "$pull_number"
                else
                    printf '    GitHub refused or could not confirm the merge. Check the PR before retrying.\n'
                fi
                return
            fi
        done
        printf '    Enter a listed number, or 0 to cancel.\n'
    done
}

fetch_json() {
    if ! curl --disable --fail --silent --show-error --location \
        --connect-timeout 10 --max-time 30 \
        --header 'Accept: application/vnd.github+json' \
        "$1" --output "$temporary_directory/response.json"; then
        fail "GitHub is unreachable or its anonymous request limit has been reached. Try again later; no token is required."
    fi
}

# JXA is provided by macOS: parse JSON without jq, Python or extra packages.
parse_response() {
    osascript -l JavaScript - "$temporary_directory/response.json" "$1" <<'JAVASCRIPT'
ObjC.import('Foundation');
function run(arguments) {
    var file = $.NSString.stringWithContentsOfFileEncodingError(arguments[0], $.NSUTF8StringEncoding, null);
    var response = JSON.parse(ObjC.unwrap(file));
    if (arguments[1] === 'list') {
        return response.map(function (pull) {
            var title = pull.title.replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ');
            return '#' + pull.number + ' — ' + title;
        }).join('\n');
    }
    if (arguments[1] === 'methods') {
        return ['squash', 'merge', 'rebase'].filter(function (method) {
            var key = method === 'merge' ? 'allow_merge_commit' : 'allow_' + method + '_merge';
            return response[key] === true;
        }).join('\n');
    }
    if (response.state !== 'open') return 'closed';
    if (response.mergeable === null) return 'pending';
    if (response.mergeable !== true) return 'conflict';
    return response.merge_commit_sha;
}
JAVASCRIPT
}

printf '\n  %s%sCODEX COSTS%s  /  PR test\n' "$bold" "$cyan" "$reset"
printf '    Build and run a PR\n'
printf '    (The PR will be tested as merged with its target branch so you can check\n'
printf '    that the combined app works before merging it on GitHub.)\n'

section 'How it works'
printf '    %s1%s  Choose an open PR.\n' "$cyan" "$reset"
printf '    %s2%s  Prepare the test merge in a separate worktree.\n' "$cyan" "$reset"
printf '    %s3%s  Build and open the app; any running instance will be quit first.\n' "$cyan" "$reset"
printf '\n    Your branch and local changes stay in place.\n'
printf '    The script will execute code from the PR you choose.\n'
printf '    After quitting, report the result and optionally publish feedback or merge.\n'

[[ "$(uname -s)" == Darwin ]] || fail "This script requires macOS."
[[ -t 0 ]] || fail "Run this script in an interactive terminal."
for required_command in git curl osascript open pgrep qlmanage xcrun; do
    command -v "$required_command" >/dev/null 2>&1 || fail "Required macOS tool is unavailable: $required_command"
done

origin_url=$(git remote get-url origin)
case "$origin_url" in
    "git@github.com:$repository"|"git@github.com:$repository.git"|\
    "$repository_url"|"$repository_url.git"|\
    "ssh://git@github.com/$repository"|"ssh://git@github.com/$repository.git") ;;
    *) fail "origin must point to $repository_url; current value: $origin_url" ;;
esac

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/codex-costs-pr.XXXXXX")
worktree_directory=$(mktemp -d "${TMPDIR:-/tmp}/codex-costs-worktree.XXXXXX")
test_worktree="$worktree_directory/source"
test_reference="refs/codex-costs-tests/$(basename "$worktree_directory")"
app_may_be_running=false
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

section '1 / 3 · Choose a PR'
printf '    Loading from GitHub…\n'
pull_choices=()
page=1
while true; do
    fetch_json "$api_url?state=open&sort=updated&direction=desc&per_page=100&page=$page"
    page_choices=$(parse_response list)
    [[ -n "$page_choices" ]] || break

    while IFS= read -r choice; do
        pull_choices+=("$choice")
    done <<< "$page_choices"
    page=$((page + 1))
done

if [[ ${#pull_choices[@]} -eq 0 ]]; then
    printf '    No open PRs to test. Check back soon!\n'
    exit 0
fi

printf '\n    %sOpen PRs%s\n\n' "$bold" "$reset"
for choice in "${pull_choices[@]}"; do
    printf '    %s%s%s\n\n' "$cyan$bold" "$choice" "$reset"
done

printf '    %s0%s    Cancel\n\n' "$yellow" "$reset"
printf '    Enter a PR number (without #), then press Return.\n'
while true; do
    printf '    %s›%s ' "$cyan$bold" "$reset"
    read -r selection || exit 0
    if [[ "$selection" == 0 ]]; then
        printf '\n    See you next time! No changes made.\n\n'
        exit 0
    fi
    selected_choice=''
    if [[ "$selection" =~ ^[1-9][0-9]*$ ]]; then
        for choice in "${pull_choices[@]}"; do
            if [[ "${choice%% *}" == "#$selection" ]]; then
                selected_choice="$choice"
                break
            fi
        done
    fi
    if [[ -n "$selected_choice" ]]; then
        break
    fi
    printf '    %s!%s Enter a listed PR number (without #), or 0 to cancel.\n' "$yellow" "$reset"
done

pull_number="$selection"
pull_url="$repository_url/pull/$pull_number"
section '2 / 3 · Prepare the test merge'
printf '    %s%s%s\n    %s\n' "$bold" "$selected_choice" "$reset" "$pull_url"
printf '\n    GitHub generates a test merge combining this PR with its target branch.\n'
printf '    This lets you check how the app works after merging.\n'
printf '    Later changes to the target branch or the PR can change the result.\n'
printf '    PRs with merge conflicts cannot be tested until those conflicts are resolved.\n'
printf '    Publishing feedback and merging require separate choices after the test.\n'

# Request fresh mergeability before trusting GitHub's synthetic merge ref.
merge_commit=pending
for attempt in 1 2 3 4 5; do
    fetch_json "$api_url/$pull_number"
    merge_commit=$(parse_response detail)
    [[ "$merge_commit" == pending ]] || break
    printf '    GitHub is preparing the test merge (%s/5)…\n' "$attempt"
    sleep 2
done
case "$merge_commit" in
    closed) fail "This PR is no longer open." ;;
    pending) fail "GitHub has not finished computing the test merge. Try again shortly." ;;
    conflict) fail "GitHub cannot merge this PR automatically. Resolve its conflicts before testing." ;;
esac
[[ "$merge_commit" =~ ^[0-9a-f]{40}$ ]] || fail "GitHub did not provide a valid test merge commit."

# A private ref and --no-write-fetch-head avoid disturbing another session's
# FETCH_HEAD. Never change origin or fetch into a local working branch.
run_quietly "Could not fetch the test merge. The PR may have changed or have conflicts." \
    env GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 fetch \
    --no-write-fetch-head --no-tags --no-recurse-submodules "$repository_url.git" \
    "refs/pull/$pull_number/merge:$test_reference"
[[ "$(git rev-parse "$test_reference")" == "$merge_commit" ]] || fail "The test merge changed during selection. Run the script again."
tested_base=$(git rev-parse "$merge_commit^1")
tested_head=$(git rev-parse "$merge_commit^2")
run_quietly "Could not create the isolated test worktree." \
    git worktree add --detach "$test_worktree" "$merge_commit"
tested_commit_short=$(git -C "$test_worktree" rev-parse --short HEAD)

section '3 / 3 · Build and test'
run_quietly "The build failed. Your original checkout is unchanged." \
    /bin/bash -c 'cd "$1" && ./build.sh' bash "$test_worktree"
# Move all build output outside the worktree before removing it without force.
run_quietly "Could not preserve the test application." \
    mv "$test_worktree/build" "$temporary_directory/output"
test_app="$temporary_directory/output/Codex Costs.app"
[[ -d "$test_app" ]] || fail "The build did not produce Codex Costs.app."
run_quietly "Could not remove the test worktree; it will be retained for inspection." \
    git worktree remove "$test_worktree"
rmdir "$worktree_directory"

printf '\n    Quitting Codex Costs if it is already running…\n'
# Checking running bundle identifiers avoids launching an app just to quit it.
osascript <<'APPLESCRIPT'
tell application "System Events"
    set appIsRunning to exists (application processes whose bundle identifier is "ovh.pwa.codex-costs")
end tell
if appIsRunning then
    tell application id "ovh.pwa.codex-costs" to quit
end if
APPLESCRIPT

for attempt in 1 2 3 4 5; do
    if ! pgrep -x CodexCosts >/dev/null; then
        break
    fi
    sleep 1
done
if pgrep -x CodexCosts >/dev/null; then
    fail "The app did not quit. Quit it manually, then run the script again."
fi

printf '\n    The test app will open. Quit the app completely to return here.\n'
printf '    Your terminal will wait; closing only the app window is not enough.\n'
test_started=$(date +%s)
app_may_be_running=true
if ! open -n -W "$test_app"; then
    fail "Could not confirm that the test app closed. Its files will be retained."
fi
app_may_be_running=false
test_finished=$(date +%s)
rm -rf "$temporary_directory/output"
test_successful=false
if ask_yes_no 'Was the test successful?'; then
    test_successful=true
else
    answer_status=$?
    if [[ "$answer_status" -eq 2 ]]; then
        exit 0
    fi
fi
share_feedback "$test_successful"
printf '\n    Test finished. PR: %s\n\n' "$pull_url"
