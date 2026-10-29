#!/bin/zsh
# Renders the README screenshots from built-in demo data (no personal data is ever read) into
# docs/images/<lang>/*.png, in Turkish and English, and exports the app icon to docs/images/icon.png.
#
# The app binary runs headless in screenshot mode (`--render-screenshots <dir>`): it shows no window,
# starts no monitor, renders the PNGs and exits.
#
# Usage: tools/render-screenshots.sh [--skip-build]
set -euo pipefail

ROOT="${0:A:h:h}"
DERIVED_DATA="${NOTCHHUB_SCREENSHOT_DERIVED_DATA:-$ROOT/build/screenshots}"
APP_BINARY="$DERIVED_DATA/Build/Products/Debug/NotchHub.app/Contents/MacOS/NotchHub"
IMAGES="$ROOT/docs/images"
LANGUAGES=(en tr)
# Region formats per language: 24-hour clock and °C in both sets.
typeset -A LOCALES=(en en_GB tr tr_TR)
TIMEOUT_SECONDS=120

cd "$ROOT"

if [[ "${1:-}" != "--skip-build" ]]; then
  xcodegen generate --quiet
  xcodebuild build \
    -project NotchHub.xcodeproj \
    -scheme NotchHub \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    -destination 'platform=macOS,arch=arm64' \
    -quiet
fi

[[ -x "$APP_BINARY" ]] || { echo "error: $APP_BINARY not found; build first" >&2; exit 1; }

# Runs the renderer for one language with a timeout, so a hang never blocks the script.
render() {
  local lang=$1 out=$2
  rm -rf "$out"
  mkdir -p "$out"
  "$APP_BINARY" --render-screenshots "$out" -AppleLanguages "($lang)" -AppleLocale "${LOCALES[$lang]}" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( waited >= TIMEOUT_SECONDS )); then
      kill "$pid" 2>/dev/null || true
      echo "error: rendering ($lang) timed out" >&2
      return 1
    fi
    sleep 1
    (( waited += 1 ))
  done
  wait "$pid"
}

for lang in $LANGUAGES; do
  echo "Rendering $lang…"
  render "$lang" "$IMAGES/$lang"
done

cp NotchHub/Assets.xcassets/AppIcon.appiconset/icon_256x256@1x.png "$IMAGES/icon.png"

echo "Screenshots:"
ls -lh "$IMAGES"/*/*.png | awk '{ print $5, $9 }'
