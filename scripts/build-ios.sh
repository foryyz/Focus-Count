#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# A full Xcode installation is required. This builds an unsigned simulator app.
xcodebuild -project apps/ios/FocusCount.xcodeproj -scheme FocusCount \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath dist/ios/DerivedData CODE_SIGNING_ALLOWED=NO build
printf 'Built: %s/dist/ios/DerivedData/Build/Products/Debug-iphonesimulator/FocusCount.app\n' "$PWD"
