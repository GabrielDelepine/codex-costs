# Runtime and distribution

- Prefer native filesystem notifications, debounce bursts and ignore unrelated writes. Keep a low-frequency recovery check, activation/wake handling and midnight rollover.
- Cache parsed sessions; reread only changed files, always in full. Do not introduce incremental JSON parsing. Handle creation, deletion, atomic replacement and title-index changes without rereading unrelated logs.
- Calendar availability may inspect directory metadata/filenames without parsing out-of-range logs. Keep unchanged directory listings cached.
- Keep file I/O/parsing off the UI thread. Serialize cache ownership, reject stale range results and avoid overlapping scans, leaked watchers or repeated cost calculation during rendering.
- Pricing refresh is independent of log updates: six-hour cadence, manual refresh, timeout and validated local fallback. Do not add a server or background daemon merely for convenience.
- Build with installed Apple tools and `./build.sh`; no open Xcode project or extra package manager. Ignore generated artifacts. Preserve macOS 14+ support unless requirements explicitly change.
- The script builds the host architecture; release assets may be universal. Verify actual architectures, minimum OS, bundle version and signature before describing a binary.
- Ad-hoc signing is not Developer ID signing or notarization. Never claim GitHub signs/notarizes downloads. Document the actual distribution status.
- For releases, package the `.app` as a DMG, verify the final image and generate its SHA-256 afterwards. Recompute checksums whenever the asset changes. Do not silently publish a ZIP in place of the intended DMG.

Verify relevant runtime changes: initial load, unchanged files, one-file updates, title-only edits, new/deleted/replaced files, partial writes, ranges, wake/recovery and network failure. Use temporary synthetic data rather than modifying real Codex logs.
