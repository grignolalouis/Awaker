#!/bin/zsh
# Builds Awaker.app and packs it into build/Awaker.dmg for sharing. Opening it shows the app on the left,
# the Applications folder on the right and an arrow between them (layout in Scripts/dmg-settings.py).
#
# The app is signed ad hoc (no Apple Developer ID), so macOS asks each recipient to allow it once.
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/build.sh

# dmgbuild lays out the window without scripting Finder. It lives in its own Python environment,
# outside build/ (which each build erases).
TOOLS=.build/dmg-tools
if [[ ! -x "$TOOLS/bin/dmgbuild" ]]; then
  # Start clean: a half-made environment from a failed run must not be reused.
  rm -rf "$TOOLS"
  python3 -m venv "$TOOLS"
  "$TOOLS/bin/pip" install --quiet --disable-pip-version-check --no-deps -r Scripts/dmg-requirements.txt
fi

DMG=build/Awaker.dmg
rm -f "$DMG"
"$TOOLS/bin/dmgbuild" -s Scripts/dmg-settings.py \
  -D app=build/Awaker.app -D background=Assets/dmg-background.png \
  "Awaker" "$DMG" >/dev/null
echo "✓ $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
