#!/bin/bash
# Exercise real rebases/signatures and local remotes; never contact GitHub.
set -euo pipefail
project_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
checks_directory=$(mktemp -d "${TMPDIR:-/tmp}/codex-costs-pr-checks.XXXXXX")
trap 'rm -rf "$checks_directory"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_TERMINAL_PROMPT=0
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL || true
sed -n '/^# Shared app launch/,/^# Start the interactive workflow/{ /^# Start the interactive workflow/d; p; }' \
    "$project_directory/scripts/pull-request.sh" >"$checks_directory/functions.sh"
source "$checks_directory/functions.sh"
ssh-keygen -q -t ed25519 -N '' -f "$checks_directory/signing-key"
repository=owner/project
repository_url=https://github.com/owner/project
pull_number=21
pull_url="$repository_url/pull/21"

assert_equal() {
    if [[ "$1" != "$2" ]]; then
        printf 'Expected <%s>, got <%s>.\n' "$2" "$1" >&2
        exit 1
    fi
}

# Check the launch boundary without opening an app or contacting GitHub.
for scenario in normal offline packet-loss both inherited override env-offline env-packet-loss env-both env-zero env-flag; do
    (
        unset OFFLINE PACKET_LOSS CODEX_COSTS_SIMULATE_OFFLINE CODEX_COSTS_SIMULATE_PACKET_LOSS || true
        expected_offline=0
        expected_loss=0
        case "$scenario" in
            env-offline) OFFLINE=1; parse_arguments; expected_offline=1 ;;
            env-packet-loss) PACKET_LOSS=1; parse_arguments; expected_loss=1 ;;
            env-both) OFFLINE=1; PACKET_LOSS=1; parse_arguments; expected_offline=1; expected_loss=1 ;;
            env-zero)
                CODEX_COSTS_SIMULATE_OFFLINE=1; CODEX_COSTS_SIMULATE_PACKET_LOSS=1
                OFFLINE=0; PACKET_LOSS=0; parse_arguments ;;
            env-flag) OFFLINE=0; parse_arguments --offline; expected_offline=1 ;;
            normal) parse_arguments ;;
            offline) parse_arguments --offline; expected_offline=1 ;;
            packet-loss) parse_arguments --packet-loss; expected_loss=1 ;;
            both) parse_arguments --packet-loss --offline; expected_offline=1; expected_loss=1 ;;
            inherited)
                CODEX_COSTS_SIMULATE_PACKET_LOSS=1
                parse_arguments --offline
                expected_offline=1; expected_loss=1 ;;
            override)
                CODEX_COSTS_SIMULATE_OFFLINE=0
                parse_arguments --offline --offline
                expected_offline=1 ;;
        esac
        expected_mode=Normal
        if [[ "$expected_offline" == 1 && "$expected_loss" == 1 ]]; then
            expected_mode='Offline (100% packet loss also enabled; Offline takes precedence)'
        elif [[ "$expected_offline" == 1 ]]; then
            expected_mode=Offline
        elif [[ "$expected_loss" == 1 ]]; then
            expected_mode='100% packet loss'
        fi
        show_network_testing >"$checks_directory/network-help"
        /usr/bin/grep -Fq "Selected mode: $expected_mode" "$checks_directory/network-help"
        test_app="$checks_directory/App with spaces.app"
        open() { printf '%s\n' "$@" >"$checks_directory/launch-arguments"; }
        launch_app "$test_app" -W
        assert_equal "$(cat "$checks_directory/launch-arguments")" \
            "$(printf '%s\n' -n -W --env "CODEX_COSTS_SIMULATE_OFFLINE=$expected_offline" \
                --env "CODEX_COSTS_SIMULATE_PACKET_LOSS=$expected_loss" "$test_app")"
    )
    printf 'PASS simulation launch flags: %s\n' "$scenario"
done

make -s -C "$project_directory" pr ARGS=--help >"$checks_directory/help"
/usr/bin/grep -q -- '--packet-loss' "$checks_directory/help"
if /bin/bash "$project_directory/scripts/pull-request.sh" --unknown >"$checks_directory/invalid" 2>&1; then exit 1; fi
/usr/bin/grep -q 'Unknown option: --unknown' "$checks_directory/invalid"
printf 'PASS make argument forwarding, help and invalid-option handling\n'

# Noninteractive startup stops before GitHub access or any checkout changes.
if OFFLINE=1 PACKET_LOSS=1 make -s -C "$project_directory" pr </dev/null >"$checks_directory/startup" 2>&1; then exit 1; fi
/usr/bin/grep -Fq 'OFFLINE=1 make pr' "$checks_directory/startup"
/usr/bin/grep -Fq 'PACKET_LOSS=1 make pr' "$checks_directory/startup"
/usr/bin/grep -Fq 'Selected mode: Offline (100% packet loss also enabled; Offline takes precedence)' "$checks_directory/startup"
/usr/bin/grep -Fq 'Run this script in an interactive terminal.' "$checks_directory/startup"
for variable in OFFLINE PACKET_LOSS; do
    if env "$variable=invalid" /bin/bash "$project_directory/scripts/pull-request.sh" >"$checks_directory/invalid-env" 2>&1; then exit 1; fi
    /usr/bin/grep -Fq "$variable must be 0 or 1." "$checks_directory/invalid-env"
done
printf 'PASS make environment forwarding, startup guidance and invalid-value handling\n'

setup_fixture() {
    fixture_directory="$checks_directory/$1"
    mkdir -p "$fixture_directory"
    fixture_remote="$fixture_directory/remote.git"
    git init -q --bare "$fixture_remote"
    git init -q -b main "$fixture_directory/repository"
    cd "$fixture_directory/repository"
    git config user.name 'Fixture Author'
    git config user.email fixture@example.invalid
    git config gpg.format ssh
    git config user.signingkey "$checks_directory/signing-key.pub"
    git config commit.gpgsign true
    echo root >root.txt
    git add root.txt
    git commit -qm Root
    git checkout -qb topic
    echo one >one.txt
    git add one.txt
    git commit -qm $'First change\n\nKeep this body.'
    git commit --allow-empty -qm 'Empty change (#21)'
    echo two >two.txt
    git add two.txt
    git commit -qm 'Second change'
    original_head=$(git rev-parse HEAD)
    git checkout -q main
    echo main >main.txt
    git add main.txt
    git commit -qm 'Main advanced'
    tested_base=$(git rev-parse HEAD)
    tested_head="$original_head"
    git push -q "$fixture_remote" main topic
    git merge --no-ff --no-edit topic -q
    merge_commit=$(git rev-parse HEAD)
    # Fixtures use a separate branch so the caller's checked-out main stays put.
    git checkout -qb fixture-checkout "$tested_base"
    temporary_directory="$fixture_directory/temporary"
    worktree_directory="$fixture_directory/worktree"
    mkdir -p "$temporary_directory" "$worktree_directory"
    test_worktree="$worktree_directory/source"
    git worktree add -q --detach "$test_worktree" "$merge_commit"
    test_reference=refs/fixture/test
    git update-ref "$test_reference" "$merge_commit"
    retain_worktree=false
    rebased=false
    mock_other_author=false
    mock_incomplete=false
    mock_push_race=false
    mock_pending=false
    mock_base_changed=false
    mock_retargeted=false
    mock_permission=true
    mock_rebase_push_failure=false
    mock_signing_failure=false
    mock_fork=false
    mock_comment_failure=false
    : >"$temporary_directory/pushes"
}

# Make command discovery independent of an installed GitHub CLI.
gh() {
    printf 'Unexpected real GitHub CLI call.\n' >&2
    return 1
}

run_gh() {
    if [[ "$1" == auth ]]; then return 0; fi
    if [[ "$1" == pr && "$2" == comment ]]; then
        if [[ "$3" == --help ]]; then return 0; fi
        [[ "$mock_comment_failure" == true ]] && return 1
        cp "$temporary_directory/comment.md" "$temporary_directory/posted-comment"
        return 0
    fi
    if [[ "$1" == pr && "$2" == view ]]; then
        local current_base="$tested_base" merge_status=CLEAN current_base_branch=main
        [[ "$mock_retargeted" == true ]] && current_base_branch=other
        [[ "$mock_base_changed" == true ]] && current_base="$original_head"
        [[ "$mock_pending" == true ]] && merge_status=BLOCKED
        printf '%s\t%s\tOPEN\tfalse\tMERGEABLE\t%s\t%s\n' \
            "$(git --git-dir="$fixture_remote" rev-parse refs/heads/topic)" "$current_base" "$merge_status" "$current_base_branch"
        return 0
    fi
    if [[ "$1" == api && "$2" == user ]]; then echo 42; return 0; fi
    if [[ "$1" == api && "$2" == --paginate ]]; then
        local commit author_id=42
        [[ "$mock_other_author" == true ]] && author_id=99
        if [[ "$mock_incomplete" == true ]]; then return 0; fi
        while IFS= read -r commit; do
            printf '%s\t%s\n' "$commit" "$author_id"
        done < <(git rev-list "$tested_base..$tested_head")
        return 0
    fi
    if [[ "$1" == api && "$2" == "repos/$repository/pulls/$pull_number" ]]; then
        local clone_url="$repository_url.git"
        [[ "$mock_fork" == true ]] && clone_url=https://github.com/owner/fork.git
        printf '%s\ttopic\tmain\t%s\t%s\topen\n' "$clone_url" "$tested_head" "$tested_base"
        return 0
    fi
    if [[ "$1" == api && ( "$2" == "repos/$repository" || "$2" == repos/owner/fork ) ]]; then
        echo "$mock_permission"; return 0
    fi
    printf 'Unexpected GitHub call: %s\n' "$*" >&2
    return 1
}

run_remote_git() {
    printf '%s\n' "$*" >>"$temporary_directory/pushes"
    if [[ "$2" == --force-with-lease=* ]]; then
        [[ "$mock_rebase_push_failure" == true ]] && return 1
        if [[ "$mock_push_race" == true ]]; then
            git --git-dir="$fixture_remote" update-ref refs/heads/topic "$tested_base"
        fi
        git push "$2" "$fixture_remote" "$4"
    else
        git push "$fixture_remote" "$3"
    fi
}

# Exercise the real HTTP wrapper/parser with a cache that repeats a response per URL.
for scenario in pending-ready pending-exhausted conflict closed invalid-hash offline invalid-json; do
    (
        temporary_directory="$checks_directory/merge-$scenario"
        mkdir -p "$temporary_directory"
        api_url=https://api.github.com/repos/owner/project/pulls
        fixture_merge=1111111111111111111111111111111111111111
        : >"$temporary_directory/requests"
        : >"$temporary_directory/sleeps"
        sleep() { printf '%s\n' "$1" >>"$temporary_directory/sleeps"; }
        curl() {
            local url='' output='' header='' seen=false count
            while [[ "$#" -gt 0 ]]; do
                case "$1" in
                    --output) output="$2"; shift ;;
                    --header)
                        [[ "$2" == 'Cache-Control: no-cache' ]] && header=yes
                        shift ;;
                    https://*) url="$1" ;;
                esac
                shift
            done
            [[ "$header" == yes && -n "$output" && -n "$url" ]] || return 1
            if /usr/bin/grep -Fqx "$url" "$temporary_directory/requests"; then seen=true; fi
            printf '%s\n' "$url" >>"$temporary_directory/requests"
            count=$(wc -l <"$temporary_directory/requests")
            if [[ "$scenario" == offline ]]; then return 7; fi
            if [[ "$scenario" == invalid-json ]]; then printf '{' >"$output"; return; fi
            local state=open mergeable=true sha="$fixture_merge"
            case "$scenario" in
                pending-ready) [[ "$count" -eq 1 || "$seen" == true ]] && mergeable=null ;;
                pending-exhausted) mergeable=null ;;
                conflict) mergeable=false ;;
                closed) state=closed ;;
                invalid-hash) sha=invalid ;;
            esac
            printf '{"state":"%s","mergeable":%s,"merge_commit_sha":"%s"}\n' \
                "$state" "$mergeable" "$sha" >"$output"
        }
        if [[ "$scenario" == pending-ready ]]; then
            resolve_test_merge >"$temporary_directory/output"
            assert_equal "$merge_commit" "$fixture_merge"
            assert_equal "$(wc -l <"$temporary_directory/requests" | tr -d ' ')" 2
            assert_equal "$(cat "$temporary_directory/sleeps")" 2
        else
            if (resolve_test_merge >"$temporary_directory/output" 2>&1); then exit 1; fi
            case "$scenario" in
                pending-exhausted)
                    assert_equal "$(wc -l <"$temporary_directory/requests" | tr -d ' ')" 5
                    assert_equal "$(wc -l <"$temporary_directory/sleeps" | tr -d ' ')" 4
                    expected='has not finished computing' ;;
                conflict) expected='Resolve its conflicts' ;;
                closed) expected='no longer open' ;;
                invalid-hash) expected='valid test merge commit' ;;
                offline) expected='GitHub is unreachable' ;;
                invalid-json) expected='invalid PR data' ;;
            esac
            /usr/bin/grep -q "$expected" "$temporary_directory/output"
        fi
    )
    printf 'PASS fresh merge polling: %s\n' "$scenario"
done

# Empty input accepts only the explicit yes default; EOF never grants consent.
ask_yes_no 'Default yes' yes <<< '' >/dev/null
if ask_yes_no 'Default no' <<< '' >/dev/null; then exit 1; fi
if ask_yes_no 'EOF' yes </dev/null >/dev/null; then exit 1; else assert_equal "$?" 2; fi
printf 'PASS prompt defaults and EOF\n'

(
    setup_fixture rebase
    mock_fork=true
    original_date=$(git show -s --format=%aI "$original_head")
    prepare_rebase <<< '' >"$temporary_directory/output"
    assert_equal "$rebased" true
    assert_equal "$(git --git-dir="$fixture_remote" rev-parse topic)" "$tested_head"
    assert_equal "$(git rev-parse HEAD)" "$tested_base"
    assert_equal "$(git show -s --format=%aI "$tested_head")" "$original_date"
    assert_equal "$(git rev-list --count "$tested_base..$tested_head")" 3
    assert_equal "$(git diff "$merge_commit" "$tested_head")" ''
    assert_equal "$(git show -s --format=%s "$tested_head")" 'Second change (#21)'
    assert_equal "$(git show -s --format=%s "$tested_head^1")" 'Empty change (#21)'
    assert_equal "$(git show -s --format=%b "$tested_head~2")" 'Keep this body.'
    while IFS= read -r commit; do
        git "${signature_arguments[@]}" verify-commit "$commit" >/dev/null 2>&1
    done < <(git rev-list "$tested_base..$tested_head")
    # An already-current, fully referenced branch needs no consent or rewrite.
    prepared_head="$tested_head"
    git -C "$test_worktree" checkout -q --detach "$tested_base"
    git -C "$test_worktree" merge -q --no-ff --no-edit "$prepared_head"
    git update-ref "$test_reference" "$(git -C "$test_worktree" rev-parse HEAD)"
    : >"$temporary_directory/pushes"
    prepare_rebase </dev/null >"$temporary_directory/repeated-rebase"
    assert_equal "$rebased" true
    assert_equal "$tested_head" "$prepared_head"
    assert_equal "$(git -C "$test_worktree" rev-parse HEAD)" "$prepared_head"
    assert_equal "$(git rev-parse "$test_reference")" "$prepared_head"
    assert_equal "$(cat "$temporary_directory/pushes")" ''
    if /usr/bin/grep -q 'Rebase commits on main?' "$temporary_directory/repeated-rebase"; then exit 1; fi
    assert_equal "$(git rev-list --count "$tested_base..$tested_head")" 3
    assert_equal "$(git show -s --format=%s "$tested_head")" 'Second change (#21)'
    tested_commit_short=$(git rev-parse --short "$tested_head")
    # The comment decision is followed by the final, default-no merge question.
    share_feedback true <<< $'y\n' >"$temporary_directory/feedback"
    assert_equal "$(cat "$temporary_directory/posted-comment")" "Tested successfully $tested_commit_short"
    assert_equal "$(git --git-dir="$fixture_remote" rev-parse main)" "$tested_base"
    /usr/bin/grep -q 'fast-forward? \[yN\]' "$temporary_directory/feedback"
    merge_fast_forward <<< y >"$temporary_directory/merge-output"
    assert_equal "$(git --git-dir="$fixture_remote" rev-parse main)" "$tested_head"
    assert_equal "$(tail -1 "$temporary_directory/pushes")" "push $repository_url.git $tested_head:refs/heads/main"
)
printf 'PASS signed fork rebase, messages, empty commits, comment hash and fast-forward\n'

(
    setup_fixture merge-history
    tested_head="$merge_commit"
    git push -q "$fixture_remote" "$tested_head:refs/heads/topic"
    prepare_rebase <<< y >"$temporary_directory/output"
    assert_equal "$rebased" true
    assert_equal "$(git rev-list --count "$tested_base..$tested_head")" 4
    assert_equal "$(git rev-list --count --merges "$tested_base..$tested_head")" 1
    assert_equal "$(git diff "$merge_commit" "$tested_head")" ''
    assert_equal "$(git show -s --format=%s "$tested_head")" "Merge branch 'topic' (#21)"
)
printf 'PASS owned merge history preserved and signed\n'

(
    setup_fixture current-without-reference
    # The tip is already tagged, but an older commit still needs the PR number.
    git -C "$test_worktree" checkout -q --detach "$tested_head"
    git -C "$test_worktree" commit --amend -qm 'Second change (#21)'
    tested_head=$(git -C "$test_worktree" rev-parse HEAD)
    git push -q "--force-with-lease=refs/heads/topic:$original_head" "$fixture_remote" "$tested_head:refs/heads/topic"
    # Put main at the original branch point: no rebase is needed, but titles
    # are incomplete even though one of the PR commits already has (#21).
    tested_base=$(git merge-base "$tested_base" "$tested_head")
    git --git-dir="$fixture_remote" update-ref refs/heads/main "$tested_base"
    prepare_rebase <<< n >"$temporary_directory/declined"
    assert_equal "$rebased" false
    assert_equal "$(cat "$temporary_directory/pushes")" ''
    /usr/bin/grep -q 'Rebase commits on main? \[Yn\]' "$temporary_directory/declined"
    prepare_rebase <<< '' >"$temporary_directory/accepted"
    assert_equal "$rebased" true
    assert_equal "$(git show -s --format=%s "$tested_head")" 'Second change (#21)'
    assert_equal "$(git show -s --format=%s "$tested_head~2")" 'First change (#21)'
    assert_equal "$(git show -s --format=%s "$tested_head^1")" 'Empty change (#21)'
)
printf 'PASS current branch with incomplete PR references still asks before rewriting\n'

(
    setup_fixture advanced-main-with-references
    prepare_rebase <<< y >"$temporary_directory/initial"
    git checkout -qb advanced-main "$tested_base"
    echo advanced >advanced.txt
    git add advanced.txt
    git commit -qm 'Main advanced again'
    tested_base=$(git rev-parse HEAD)
    git push -q "$fixture_remote" HEAD:main
    : >"$temporary_directory/pushes"
    prepare_rebase <<< n >"$temporary_directory/declined"
    assert_equal "$rebased" false
    assert_equal "$(cat "$temporary_directory/pushes")" ''
    /usr/bin/grep -q 'Rebase commits on main? \[Yn\]' "$temporary_directory/declined"
)
printf 'PASS main advancing still requires a rebase despite complete PR references\n'

for scenario in other-author incomplete declined coauthor no-permission; do
    (
        setup_fixture "$scenario"
        case "$scenario" in
            other-author) mock_other_author=true ;;
            incomplete) mock_incomplete=true ;;
            coauthor)
                git -C "$test_worktree" checkout -q --detach "$tested_head"
                git -C "$test_worktree" commit --amend -qm $'Second change\n\nCo-authored-by: Someone <someone@example.invalid>'
                tested_head=$(git -C "$test_worktree" rev-parse HEAD)
                ;;
            no-permission) mock_permission=false ;;
        esac
        prepare_rebase <<< n >"$temporary_directory/output"
        assert_equal "$rebased" false
        assert_equal "$(cat "$temporary_directory/pushes")" ''
        assert_equal "$(git --git-dir="$fixture_remote" rev-parse topic)" "$original_head"
    )
    printf 'PASS rebase skipped: %s\n' "$scenario"
done

for scenario in signing-failure signing-disabled verification-failure lease-race push-failure conflict; do
    (
        setup_fixture "$scenario"
        case "$scenario" in
            signing-failure) git config user.signingkey "$checks_directory/missing-key" ;;
            signing-disabled) git config commit.gpgsign false ;;
            verification-failure) git config gpg.ssh.allowedSignersFile "$checks_directory/missing-signers" ;;
            lease-race) mock_push_race=true ;;
            push-failure) mock_rebase_push_failure=true ;;
            conflict)
                git -C "$test_worktree" checkout -q --detach "$tested_base"
                echo conflict >"$test_worktree/one.txt"
                git -C "$test_worktree" add one.txt
                git -C "$test_worktree" commit -qm 'Conflicting base'
                tested_base=$(git -C "$test_worktree" rev-parse HEAD)
                ;;
        esac
        if (prepare_rebase <<< y >"$temporary_directory/output" 2>&1); then exit 1; fi
        assert_equal "$(git --git-dir="$fixture_remote" rev-parse main)" "$(git rev-parse HEAD)"
        if [[ "$scenario" != lease-race ]]; then
            assert_equal "$(git --git-dir="$fixture_remote" rev-parse topic)" "$original_head"
        fi
        /usr/bin/grep -qi 'remote PR is unchanged\|Check GitHub before retrying' "$temporary_directory/output"
    )
    printf 'PASS safe stop: %s\n' "$scenario"
done

for scenario in failed-test comment-failure pending-checks changed-base changed-head retargeted main-race; do
    (
        setup_fixture "$scenario"
        prepare_rebase <<< y >"$temporary_directory/output"
        tested_commit_short=$(git rev-parse --short "$tested_head")
        : >"$temporary_directory/pushes"
        case "$scenario" in
            failed-test) share_feedback false <<< n >"$temporary_directory/feedback" ;;
            comment-failure) mock_comment_failure=true; share_feedback true <<< $'y\ny' >"$temporary_directory/feedback" ;;
            retargeted) mock_retargeted=true; merge_fast_forward <<< y >/dev/null ;;
            pending-checks) mock_pending=true; merge_fast_forward <<< y >/dev/null ;;
            changed-base) mock_base_changed=true; merge_fast_forward <<< y >/dev/null ;;
            changed-head)
                git --git-dir="$fixture_remote" update-ref refs/heads/topic "$original_head"
                merge_fast_forward <<< y >/dev/null
                ;;
            main-race)
                # Simulate a push after readiness checks: the ordinary push must refuse it.
                git checkout -qb concurrent "$tested_base"
                echo concurrent >concurrent.txt
                git add concurrent.txt
                git commit -qm Concurrent
                concurrent_head=$(git rev-parse HEAD)
                git push -q "$fixture_remote" HEAD:main
                merge_fast_forward <<< y >"$temporary_directory/merge-output" 2>&1
                assert_equal "$(git --git-dir="$fixture_remote" rev-parse main)" "$concurrent_head"
                ;;
        esac
        if [[ "$scenario" != main-race ]]; then
            assert_equal "$(cat "$temporary_directory/pushes")" ''
            assert_equal "$(git --git-dir="$fixture_remote" rev-parse main)" "$tested_base"
        fi
    )
    printf 'PASS merge blocked: %s\n' "$scenario"
done
