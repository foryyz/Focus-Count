#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
IOS_ICON="apps/ios/FocusCount/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
swift scripts/generate-ios-icon.swift "$IOS_ICON"
ICON_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/focuscount-icons.XXXXXX")"
trap 'rm -rf "$ICON_TEMP"' EXIT
ICON_SET="$ICON_TEMP/FocusCount.iconset"
mkdir -p "$ICON_SET" apps/macos/Resources
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$IOS_ICON" --out "$ICON_SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$IOS_ICON" --out "$ICON_SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_SET" -o apps/macos/Resources/FocusCount.icns
