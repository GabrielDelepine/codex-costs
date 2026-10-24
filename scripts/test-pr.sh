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
git_color=never
if [[ -t 1 && -t 2 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]]; then
    git_color=always
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

show_return_command() {
    printf '\n    %sReturn to your branch / commit%s\n' "$bold" "$reset"
    printf '        git switch %q\n' "$return_reference"
}

fail() {
    printf '\n    %s✕ Test stopped%s\n    %s\n\n' "$red$bold" "$reset" "$*" >&2
    exit 1
}

require_clean_checkout() {
    local changes
    changes=$(git status --porcelain --untracked-files=all)
    if [[ -n "$changes" ]]; then
        printf '\n    %s! Save your work before testing%s\n' "$yellow$bold" "$reset" >&2
        printf '    Cannot start the test: your checkout has changed files.\n\n' >&2
        git -c "color.status=$git_color" status --short | sed 's/^/    /' >&2
        printf '\n    Commit your changes or set them aside,\n' >&2
        printf '    then run again: ./scripts/test-pr.sh\n' >&2
        printf '    The script has not changed any files.\n\n' >&2
        exit 1
    fi
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
printf '    %s2%s  Check out the test merge with its target branch.\n' "$cyan" "$reset"
printf '    %s3%s  Build and open the app; any running instance will be quit first.\n' "$cyan" "$reset"
printf '\n    %sBefore you start%s  Your checkout must be clean.\n' "$bold" "$reset"
printf '    The script will execute code from the PR you choose.\n'

[[ "$(uname -s)" == Darwin ]] || fail "This script requires macOS."
require_clean_checkout
[[ -t 0 ]] || fail "Run this script in an interactive terminal."

origin_url=$(git remote get-url origin)
case "$origin_url" in
    "git@github.com:$repository"|"git@github.com:$repository.git"|\
    "$repository_url"|"$repository_url.git"|\
    "ssh://git@github.com/$repository"|"ssh://git@github.com/$repository.git") ;;
    *) fail "origin must point to $repository_url; current value: $origin_url" ;;
esac

return_reference=$(git symbolic-ref --quiet --short HEAD || git rev-parse HEAD)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/codex-costs-pr.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT

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
for index in "${!pull_choices[@]}"; do
    printf '    %s%3s%s  %s\n\n' "$cyan$bold" "$((index + 1))" "$reset" "${pull_choices[$index]}"
done

printf '    %s0%s    Cancel\n\n' "$yellow" "$reset"
printf '    Enter a menu number, then press Return.\n'
while true; do
    printf '    %s›%s ' "$cyan$bold" "$reset"
    read -r selection || exit 0
    if [[ "$selection" == 0 ]]; then
        printf '\n    See you next time! No changes made.\n\n'
        exit 0
    fi
    if [[ "$selection" =~ ^[1-9][0-9]{0,5}$ ]] && ((selection <= ${#pull_choices[@]})); then
        break
    fi
    printf '    %s!%s Enter a menu number, or 0 to cancel.\n' "$yellow" "$reset"
done

selected_choice="${pull_choices[$((selection - 1))]}"
pull_number="${selected_choice%% *}"
pull_number="${pull_number#\#}"
pull_url="$repository_url/pull/$pull_number"
section '2 / 3 · Prepare the test merge'
printf '    %s%s%s\n    %s\n' "$bold" "$selected_choice" "$reset" "$pull_url"
printf '\n    GitHub generates a test merge combining this PR with its target branch.\n'
printf '    This lets you check how the app works after merging.\n'
printf '    Later changes to the target branch or the PR can change the result.\n'
printf '    PRs with merge conflicts cannot be tested until those conflicts are resolved.\n'
printf '    Nothing will be merged or published on GitHub.\n'

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
require_clean_checkout

# Use public HTTPS for this command even when origin normally uses SSH.
run_quietly "Could not fetch the test merge. The PR may have changed or have conflicts." \
    env GIT_TERMINAL_PROMPT=0 git -c credential.helper= \
    -c "remote.origin.url=$repository_url.git" fetch origin "refs/pull/$pull_number/merge"
[[ "$(git rev-parse FETCH_HEAD)" == "$merge_commit" ]] || fail "The test merge changed during selection. Run the script again to test a consistent version."
run_quietly "Could not switch to the test merge. Check your checkout and try again." \
    git switch --detach FETCH_HEAD
show_return_command

section '3 / 3 · Build and open'
run_quietly "The build failed. Review the details above; your checkout remains on the test merge." \
    ./build.sh

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
    fail "The app did not quit. Quit it manually, then open build/Codex Costs.app."
fi

open -n "$project_directory/build/Codex Costs.app"
printf '\n    %s%s✓ The test build is open%s\n' "$green" "$bold" "$reset"
printf '    Check the behavior described in the PR.\n'
section 'Share your feedback. Thank you!'
printf '    • Add a screenshot with private data hidden.\n'
printf '    • Leave a “tested” comment describing what you checked.\n'
printf '\n    %sOpen the PR%s\n    %s\n' "$bold" "$reset" "$pull_url"
show_return_command
printf '    You will remain in detached HEAD until you switch back.\n\n'
