#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --package-path apps/macos -c release
APP="dist/macos/FocusCount.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp apps/macos/Resources/FocusCount.icns "$APP/Contents/Resources/FocusCount.icns"
BIN_DIR="$(swift build --package-path apps/macos -c release --show-bin-path)"
cp "$BIN_DIR/FocusCount" "$APP/Contents/MacOS/FocusCount"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FocusCount</string>
<key>CFBundleIdentifier</key><string>local.focuscount.app</string>
<key>CFBundleIconFile</key><string>FocusCount.icns</string>
<key>CFBundleName</key><string>FocusCount</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.14.0</string>
<key>CFBundleVersion</key><string>34</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built: %s/%s\n' "$PWD" "$APP"

python3 scripts/package-macos.py
