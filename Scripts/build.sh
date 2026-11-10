#!/bin/zsh
# Builds Awaker.app from the Swift package (Command Line Tools are enough, no Xcode).
#   Scripts/build.sh            -> build/Awaker.app
#   Scripts/build.sh --install  -> also replaces /Applications/Awaker.app and relaunches it
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Awaker.app
CONTENTS=$APP/Contents

echo "→ Compilation"
swift build -c release --product Awaker
BINARY=$(swift build -c release --show-bin-path)/Awaker

echo "→ Bundle"
rm -rf build
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/Awaker"
cp Resources/Info.plist "$CONTENTS/Info.plist"
# The version comes from the VERSION file (changing it on main triggers a release); the build number from CI.
VERSION=$(tr -d '[:space:]' < VERSION)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Set :CFBundleVersion ${GITHUB_RUN_NUMBER:-1}" "$CONTENTS/Info.plist"
cp Assets/logo-mark.svg "$CONTENTS/Resources/"
mkdir -p "$CONTENTS/Resources/Backdrop" "$CONTENTS/Resources/Skins"
cp Assets/Skins/skins.json "$CONTENTS/Resources/Skins/"
cp Assets/Backdrop/backdrop.jpg "$CONTENTS/Resources/Backdrop/"
# Optional animated version of the backdrop (a short seamless loop).
[[ -f Assets/Backdrop/backdrop.mp4 ]] && cp Assets/Backdrop/backdrop.mp4 "$CONTENTS/Resources/Backdrop/"

echo "→ Icône"
swift Scripts/make-icon.swift Assets/logo-mark.svg build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf build/AppIcon.iconset

codesign --force --sign - "$APP"
echo "✓ $APP"

if [[ "${1:-}" == "--install" ]]; then
  # Quit through AppleScript so the app restores normal sleep before it exits.
  osascript -e 'tell application "Awaker" to quit' 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Awaker.app
  cp -R "$APP" /Applications/
  open /Applications/Awaker.app
  echo "✓ Installée : /Applications/Awaker.app"
fi
