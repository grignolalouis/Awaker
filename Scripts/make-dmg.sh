#!/bin/zsh
# Builds Awaker.app and packs it into build/Awaker.dmg for sharing:
# the app, a shortcut to /Applications to drag it onto, and first-launch instructions.
#
# The app is signed ad hoc (no Apple Developer ID), so macOS asks each recipient to allow it once.
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/build.sh

STAGING=build/dmg
DMG=build/Awaker.dmg
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/Awaker.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp Resources/Read-me.txt "$STAGING/"

hdiutil create -volname "Awaker" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "✓ $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
