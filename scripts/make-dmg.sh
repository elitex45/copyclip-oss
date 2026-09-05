#!/bin/bash
# Packages build/CopyClipOSS.app into build/CopyClipOSS.dmg with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/CopyClipOSS.app
DMG=build/CopyClipOSS.dmg
STAGE=build/dmg-stage
[ -d "$APP" ] || ./scripts/make-app.sh
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "CopyClip OSS" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG"
