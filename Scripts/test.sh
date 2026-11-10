#!/bin/zsh
# Runs the test suite.
set -euo pipefail
cd "$(dirname "$0")/.."

# With Command Line Tools only (no Xcode), Swift Testing lives outside the default search paths:
# point the compiler and the runtime at it. With Xcode (CI), plain `swift test` works.
TOOLS=/Library/Developer/CommandLineTools/Library/Developer
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
  swift test \
    -Xswiftc -F$TOOLS/Frameworks \
    -Xlinker -F$TOOLS/Frameworks \
    -Xlinker -rpath -Xlinker $TOOLS/Frameworks \
    -Xlinker -rpath -Xlinker $TOOLS/usr/lib \
    "$@"
else
  swift test "$@"
fi
