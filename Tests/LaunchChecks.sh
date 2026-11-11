#!/bin/bash
# Exercise make run with a fake build and mocked macOS commands only.
set -euo pipefail
project_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
checks_directory=$(mktemp -d "${TMPDIR:-/tmp}/codex-costs-launch-checks.XXXXXX")
checks_directory=$(cd "$checks_directory" && pwd -P)
trap 'rm -rf "$checks_directory"' EXIT
fixture_directory="$checks_directory/Checkout with spaces"
mkdir -p "$fixture_directory/scripts" "$checks_directory/bin"
cp "$project_directory/Makefile" "$fixture_directory/"
cp "$project_directory/scripts/"{run,app-launch}.sh "$fixture_directory/scripts/"
cat >"$fixture_directory/build.sh" <<'BUILD'
#!/bin/bash
printf 'build\n' >>"$LAUNCH_CHECK_LOG"
exit "${BUILD_RESULT:-0}"
BUILD
cat >"$checks_directory/bin/command-stub" <<'STUB'
#!/bin/bash
case "${0##*/}" in
    osascript)
        cat >/dev/null
        printf 'quit\n' >>"$LAUNCH_CHECK_LOG"
        exit "${QUIT_RESULT:-0}" ;;
    pgrep) exit "${RUNNING_RESULT:-1}" ;;
    sleep) exit 0 ;;
    open)
        printf 'open\n' >>"$LAUNCH_CHECK_LOG"
        printf '%s\n' "$@" >"$LAUNCH_CHECK_ARGS"
        exit "${OPEN_RESULT:-0}" ;;
esac
STUB
chmod +x "$fixture_directory/build.sh" "$checks_directory/bin/command-stub"
for command in osascript pgrep sleep open; do
    ln -s command-stub "$checks_directory/bin/$command"
done
export PATH="$checks_directory/bin:$PATH"
export LAUNCH_CHECK_LOG="$checks_directory/actions" LAUNCH_CHECK_ARGS="$checks_directory/arguments"
unset OFFLINE PACKET_LOSS CODEX_COSTS_SIMULATE_OFFLINE CODEX_COSTS_SIMULATE_PACKET_LOSS || true
unset BUILD_RESULT QUIT_RESULT RUNNING_RESULT OPEN_RESULT || true

for scenario in normal offline packet-loss both invalid build-failure quit-failure still-running open-failure; do
    (
        : >"$LAUNCH_CHECK_LOG"
        offline=0; loss=0; mode=Normal; expected_result=0
        expected_actions=$'build\nquit\nopen'
        case "$scenario" in
            offline) export OFFLINE=1; offline=1; mode=Offline ;;
            packet-loss) export PACKET_LOSS=1; loss=1; mode='100% packet loss' ;;
            both) export OFFLINE=1 PACKET_LOSS=1; offline=1; loss=1; mode='Offline (100% packet loss also enabled; Offline takes precedence)' ;;
            invalid) export OFFLINE=invalid; expected_result=2; expected_actions='' ;;
            build-failure) export BUILD_RESULT=1; expected_result=2; expected_actions=build ;;
            quit-failure) export QUIT_RESULT=1; expected_result=2; expected_actions=$'build\nquit' ;;
            still-running) export RUNNING_RESULT=0; expected_result=2; expected_actions=$'build\nquit' ;;
            open-failure) export OPEN_RESULT=1; expected_result=2 ;;
        esac
        result=0
        make -s -C "$fixture_directory" run >"$checks_directory/output" 2>&1 || result=$?
        [[ "$result" == "$expected_result" ]]
        [[ "$(cat "$LAUNCH_CHECK_LOG")" == "$expected_actions" ]]
        if [[ "$expected_result" == 0 ]]; then
            /usr/bin/grep -Fq 'OFFLINE=1 make run' "$checks_directory/output"
            /usr/bin/grep -Fq 'PACKET_LOSS=1 make run' "$checks_directory/output"
            /usr/bin/grep -Fq "Selected mode: $mode" "$checks_directory/output"
            [[ "$(cat "$LAUNCH_CHECK_ARGS")" == "$(printf '%s\n' -n --env \
                "CODEX_COSTS_SIMULATE_OFFLINE=$offline" --env "CODEX_COSTS_SIMULATE_PACKET_LOSS=$loss" \
                "$fixture_directory/build/Codex Costs.app")" ]]
        fi
    )
    printf 'PASS local launch: %s\n' "$scenario"
done
