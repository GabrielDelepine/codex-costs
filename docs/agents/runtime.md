# Runtime and distribution

- Prefer native filesystem notifications, batch bursts without postponing updates indefinitely, and ignore unrelated writes. Keep a low-frequency recovery check, activation/wake handling and midnight rollover.
- Cache parsed sessions; reread only changed files, always in full. Do not introduce incremental JSON parsing. Handle creation, deletion, atomic replacement and title-index changes without rereading unrelated logs.
- Calendar availability may inspect directory metadata/filenames without parsing out-of-range logs. Keep unchanged directory listings cached.
- Keep file I/O/parsing off the UI thread. Serialize cache ownership, reject stale range results and avoid overlapping scans, leaked watchers or repeated cost calculation during rendering.
- Pricing refresh is independent of log updates: six-hour cadence, manual refresh, timeout and validated local fallback. Do not add a server or background daemon merely for convenience.
- Build with installed Apple tools and `./build.sh`; no open Xcode project or extra package manager. Ignore generated artifacts. Preserve macOS 14+ support unless requirements explicitly change.
- The script builds the host architecture; release assets may be universal. Verify actual architectures, minimum OS, bundle version and signature before describing a binary.
- Ad-hoc signing is not Developer ID signing or notarization. Never claim GitHub signs/notarizes downloads. Document the actual distribution status.
- For releases, package the `.app` as a DMG, verify the final image and generate its SHA-256 afterwards. Recompute checksums whenever the asset changes. Do not silently publish a ZIP in place of the intended DMG.

Verify relevant runtime changes: initial load, unchanged files, one-file updates, title-only edits, new/deleted/replaced files, partial writes, ranges, wake/recovery and network failure. Use temporary synthetic data rather than modifying real Codex logs.

## Startup benchmark

Compare fresh in-memory scans with unchanged refreshes using synthetic logs only:

```sh
startup_check_dir=$(mktemp -d)
xcrun swiftc -O -swift-version 5 -parse-as-library Core.swift Tests/StartupBenchmark.swift -o "$startup_check_dir/startup-benchmark"
"$startup_check_dir/startup-benchmark"
rm -r "$startup_check_dir"
```

The fixture contains 48 files, 768 requests and about 120 MB of conversation content. Generation is outside the timed scans. Each of three runs uses a new session cache and checks that an unchanged refresh rereads no files. This measures log scans with warm filesystem caches, not full app startup or cold disk access.

## Versioning

- Use `MAJOR.MINOR.PATCH`. Set the version in `build.sh` when preparing a release, not for each commit or local build.
- Every distributed artifact needs a unique public version. Rebuilding a different artifact for distribution requires at least a PATCH increment, even from the same commit.
- Keep both Apple bundle version fields consistent with the public version. Display no separate build counter.

## Release-update checks

Run the focused fixtures without live network or personal logs:

```sh
update_check_dir=$(mktemp -d)
xcrun swiftc -swift-version 5 -parse-as-library Updates.swift Tests/UpdatesChecks.swift -o "$update_check_dir/updates-checks"
"$update_check_dir/updates-checks"
rm -r "$update_check_dir"
```

These checks cover release/version parsing and scheduling, not the full app. In the running app, also inspect the menu, progress, current/newer/available versions, missing release dates, failure/retry, automatic-check toggle and release link.
