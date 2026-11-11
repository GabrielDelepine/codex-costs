#!/bin/bash
# Shared launch helpers. Callers set launch_target and launch_script.

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

fail() {
    printf '\n    %s✕ Test stopped%s\n    %s\n\n' "$red$bold" "$reset" "$*" >&2
    exit 1
}

usage() {
    cat <<HELP
Usage: make $launch_target                 Normal networking
       OFFLINE=1 make $launch_target       Simulate no network connection
       PACKET_LOSS=1 make $launch_target   Simulate an available connection where requests time out

Direct script options: ./scripts/$launch_script [--offline] [--packet-loss]

  --offline      Start the app with Simulate Offline enabled.
  --packet-loss  Start the app with Simulate 100% Packet Loss enabled.
  --help, -h     Show this help without contacting GitHub or launching the app.

Variables accept 0 or 1 and can be combined; Offline takes precedence.
GitHub access stays online. Hold Option in the app menu to change simulations.
HELP
}

parse_arguments() {
    CODEX_COSTS_SIMULATE_OFFLINE=${OFFLINE-${CODEX_COSTS_SIMULATE_OFFLINE:-0}}
    CODEX_COSTS_SIMULATE_PACKET_LOSS=${PACKET_LOSS-${CODEX_COSTS_SIMULATE_PACKET_LOSS:-0}}
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --offline) CODEX_COSTS_SIMULATE_OFFLINE=1 ;;
            --packet-loss) CODEX_COSTS_SIMULATE_PACKET_LOSS=1 ;;
            --help|-h) usage; exit 0 ;;
            *) fail "Unknown option: $1. Run ./scripts/$launch_script --help for usage." ;;
        esac
        shift
    done
    case "$CODEX_COSTS_SIMULATE_OFFLINE" in
        0|1) ;;
        *) fail "OFFLINE must be 0 or 1." ;;
    esac
    case "$CODEX_COSTS_SIMULATE_PACKET_LOSS" in
        0|1) ;;
        *) fail "PACKET_LOSS must be 0 or 1." ;;
    esac
}

show_network_testing() {
    local selected_mode=Normal
    if [[ "$CODEX_COSTS_SIMULATE_OFFLINE" == 1 ]]; then
        selected_mode=Offline
        if [[ "$CODEX_COSTS_SIMULATE_PACKET_LOSS" == 1 ]]; then
            selected_mode='Offline (100% packet loss also enabled; Offline takes precedence)'
        fi
    elif [[ "$CODEX_COSTS_SIMULATE_PACKET_LOSS" == 1 ]]; then
        selected_mode='100% packet loss'
    fi
    section 'Network testing'
    printf '    make %s                 Normal networking\n' "$launch_target"
    printf '    OFFLINE=1 make %s       Simulate no network connection\n' "$launch_target"
    printf '    PACKET_LOSS=1 make %s   Simulate an available connection where requests time out\n' "$launch_target"
    printf '\n    Selected mode: %s\n' "$selected_mode"
    printf '    Only the app simulates network failures; the scripts stay online.\n'
    printf '    Hold Option in the app menu to change simulations during testing.\n'
}

launch_app() {
    local app_path="$1"
    shift
    open -n "$@" \
        --env "CODEX_COSTS_SIMULATE_OFFLINE=${CODEX_COSTS_SIMULATE_OFFLINE:-0}" \
        --env "CODEX_COSTS_SIMULATE_PACKET_LOSS=${CODEX_COSTS_SIMULATE_PACKET_LOSS:-0}" \
        "$app_path"
}

quit_running_app() {
    local attempt
    printf '\n    Quitting Codex Costs if it is already running…\n'
    # Checking running bundle identifiers avoids launching an app just to quit it.
    osascript <<'APPLESCRIPT' || fail "Could not ask the app to quit. Quit it manually, then retry."
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
}
