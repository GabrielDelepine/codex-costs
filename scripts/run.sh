#!/bin/bash
set -euo pipefail

project_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_directory"
launch_target=run
launch_script=run.sh
source "$project_directory/scripts/app-launch.sh"

parse_arguments "$@"
printf '\n  %s%sCODEX COSTS%s  /  Local run\n' "$bold" "$cyan" "$reset"
show_network_testing
printf '\n    Build and open the app; any running instance will be quit first.\n'
./build.sh || fail "The build failed. The running app was left alone."
quit_running_app
launch_app "$project_directory/build/Codex Costs.app" || fail "Could not open the built app."
