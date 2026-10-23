#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/Codex Costs.app"
SWIFT_CACHE="${TMPDIR:-/tmp}/codex-costs-swift-module-cache"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SWIFT_CACHE"
ICONSET="$PWD/build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
xcrun swiftc -swift-version 5 -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$SWIFT_CACHE" Core.swift History.swift Native.swift App.swift -o "$APP/Contents/MacOS/CodexCosts"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexCosts</string>
<key>CFBundleIdentifier</key><string>ovh.pwa.codex-costs</string>
<key>CFBundleName</key><string>Codex Costs</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Application built: %s\n' "$APP"
if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
