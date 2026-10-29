#!/bin/bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
stage() {
    if [[ -t 1 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]]; then
        printf '\n\033[36m%s\033[0m\n' "$*"
    else
        printf '\n%s\n' "$*"
    fi
}

for command in git gh xcrun hdiutil codesign ditto shasum; do
    command -v "$command" >/dev/null || fail "Install or configure $command first."
done
export GIT_SSH_COMMAND="ssh -o ConnectTimeout=15 -o BatchMode=yes"
export GH_HTTP_TIMEOUT=30
[[ -z "$(git status --porcelain)" ]] || fail 'Commit or move local changes before preparing a release.'
default_branch=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
[[ -n "$default_branch" ]] || fail 'Could not determine the default branch.'
git fetch origin "$default_branch" --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$default_branch")" ]] || fail "Start from the current origin/$default_branch commit."

printf 'Release source: origin/%s (%s).\n' "$default_branch" "$(git rev-parse --short "origin/$default_branch")"
printf 'Prepare a host-architecture DMG and push a release branch and tag.\nYour checkout stays unchanged. GitHub publication and app testing remain manual.\n'
printf '\nVersion (MAJOR.MINOR.PATCH; empty cancels): '
if ! read -r version || [[ -z "$version" ]]; then exit 0; fi
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'Use a version such as 1.1.0, without a v prefix.'
tag="v$version"
branch="codex/release-$version"
if git show-ref --verify --quiet "refs/tags/$tag"; then fail "Tag $tag already exists. Use a new version."; fi
remote_tag=$(git ls-remote --tags origin "refs/tags/$tag")
[[ -z "$remote_tag" ]] || fail "Remote tag $tag already exists."
output="$PWD/build/release-$version"
[[ ! -e "$output" ]] || fail "Output already exists: $output. Use a new version if it was distributed."
printf '\n1. Prepare and push %s\n2. Cancel\nSelection: ' "$tag"
if ! read -r selection || [[ "$selection" == 2 ]]; then exit 0; fi
[[ "$selection" == 1 ]] || fail 'Choose 1 or 2.'

temporary_dir=$(mktemp -d)
release_tree="$temporary_dir/source"
cleanup() {
    result=$?
    if [[ "$result" != 0 ]]; then
        printf 'Release stopped. Inspect local branch %s and tag %s before retrying. Assets, if created, remain in %s.\n' "$branch" "$tag" "$output" >&2
    fi
    git worktree remove --force "$release_tree" >/dev/null 2>&1 || true
    rm -rf "$temporary_dir"
}
trap cleanup EXIT
stage '1. Prepare isolated release source'
git worktree add -b "$branch" "$release_tree" "origin/$default_branch"
sed -E "s/^version=\"[^\"]*\"/version=\"$version\"/" "$release_tree/build.sh" > "$temporary_dir/build.sh"
cat "$temporary_dir/build.sh" > "$release_tree/build.sh"
if ! git -C "$release_tree" diff --quiet; then
    git -C "$release_tree" add build.sh
    git -C "$release_tree" commit -m "Prepare release $version"
    if [[ "$(git -C "$release_tree" config --bool commit.gpgsign || true)" == true ]]; then
        git -C "$release_tree" verify-commit HEAD
    fi
fi
stage '2. Build and check release metadata'
(cd "$release_tree" && ./build.sh)
app="$release_tree/build/Codex Costs.app"
for key in CFBundleVersion CFBundleShortVersionString; do
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$app/Contents/Info.plist")" == "$version" ]] || fail "Unexpected $key."
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")" == 14.0 ]] || fail 'Unexpected minimum macOS version.'
codesign --verify --deep --strict "$app"
xcrun lipo -info "$app/Contents/MacOS/CodexCosts"
xcrun vtool -show-build "$app/Contents/MacOS/CodexCosts"
codesign -dv "$app" 2>&1
stage '3. Package and verify the DMG'
mkdir "$temporary_dir/image"
ditto "$app" "$temporary_dir/image/Codex Costs.app"
ln -s /Applications "$temporary_dir/image/Applications"
mkdir -p "$output"
asset="Codex-Costs-$version-$(uname -m).dmg"
hdiutil create -volname 'Codex Costs' -srcfolder "$temporary_dir/image" -format UDZO "$output/$asset"
hdiutil verify "$output/$asset"
(cd "$output" && shasum -a 256 "$asset" > SHA256SUMS.txt && shasum -a 256 -c SHA256SUMS.txt)
stage '4. Tag and push'
git -C "$release_tree" tag -a "$tag" -m "Codex Costs $version"
if [[ "$(git config --bool tag.gpgsign || true)" == true ]]; then
    git verify-tag "$tag"
fi
if ! git push --atomic origin "refs/heads/$branch" "refs/tags/$tag"; then
    fail "Push failed. Artifacts remain in $output; local branch $branch and tag $tag remain. Check the remote before retrying the same atomic push. Do not rebuild a distributed version."
fi
stage 'Release assets are ready. Remaining manual steps:'
printf '1. Mount and test %s, including copying the app to Applications.\n' "$output/$asset"
printf '2. If the version changed, open and merge a PR from %s into %s.\n' "$branch" "$default_branch"
printf '3. Create a stable GitHub release using existing tag %s.\n' "$tag"
printf '   Attach %s and SHA256SUMS.txt from %s.\n' "$asset" "$output"
printf '4. Add release notes and publish. State: %s, macOS 14+, ad-hoc signed, not notarized.\n' "$(uname -m)"
printf '\nhttps://github.com/GabrielDelepine/codex-costs/releases/new\n'
