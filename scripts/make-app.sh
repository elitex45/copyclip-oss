#!/bin/bash
# Builds CopyClipOSS.app into ./build with hardened runtime, ad-hoc signed.
# Pass a signing identity as $1 (e.g. "Developer ID Application: ...") to sign for distribution.
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="${1:--}"
swift build -c release 2>&1 | tail -1
APP=build/CopyClipOSS.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CopyClipOSS "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --options runtime --entitlements Resources/entitlements.plist -s "$IDENTITY" "$APP"
codesign --verify --verbose=2 "$APP"
echo "Built $APP"
