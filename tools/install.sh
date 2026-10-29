#!/bin/zsh
# Builds a Release NotchHub and installs it to /Applications, replacing a running copy.
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="NotchHub.app"
DEST="/Applications/$APP_NAME"

cd "$ROOT"
xcodegen generate --quiet
xcodebuild build \
  -project NotchHub.xcodeproj \
  -scheme NotchHub \
  -configuration Release \
  -derivedDataPath build \
  -quiet

if pgrep -x NotchHub >/dev/null; then
  pkill -x NotchHub
  sleep 1
fi

rm -rf "$DEST"
ditto "build/Build/Products/Release/$APP_NAME" "$DEST"
codesign --verify --strict "$DEST"
open "$DEST"
echo "Installed $DEST"
