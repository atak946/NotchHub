#!/bin/zsh
# Builds a Release NotchHub and installs it to /Applications, replacing a running copy.
#
# With a "Developer ID Application" certificate the app is signed, notarized and stapled before
# it is installed (see tools/lib/signing.sh). Pass --skip-notarize for a quick local signed build.
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="NotchHub.app"
DEST="/Applications/$APP_NAME"
NOTARIZE=true
[[ "${1:-}" == "--skip-notarize" ]] && NOTARIZE=false

cd "$ROOT"
source tools/lib/signing.sh

xcodegen generate --quiet
xcodebuild build \
  -project NotchHub.xcodeproj \
  -scheme NotchHub \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build \
  -quiet \
  "${SIGN_ARGS[@]}"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "build/Build/Products/Release/$APP_NAME" "$STAGING/$APP_NAME"

if [[ -n "$DEV_ID" ]]; then
  resign_for_distribution "$STAGING/$APP_NAME"
  if $NOTARIZE; then
    notarize_app "$STAGING/$APP_NAME"
  else
    echo "warning: skipping notarization; Gatekeeper will report this copy as unnotarized" >&2
  fi
else
  echo "warning: no Developer ID Application certificate; installing a non-notarized build" >&2
fi

if pgrep -x NotchHub >/dev/null; then
  pkill -x NotchHub
  sleep 1
fi

rm -rf "$DEST"
ditto "$STAGING/$APP_NAME" "$DEST"
codesign --verify --strict "$DEST"
open "$DEST"
echo "Installed $DEST"
