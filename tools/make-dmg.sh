#!/bin/zsh
# Builds a Release NotchHub and packages it as dist/NotchHub-<version>.dmg for sharing.
#
# With a "Developer ID Application" certificate in the keychain the app and DMG are signed
# for distribution, notarized and stapled. Notarization reads credentials from the keychain
# profile NOTARY_PROFILE (default "NotchHub"), created once with:
#   xcrun notarytool store-credentials NotchHub --apple-id <apple-id> --team-id <team-id>
# Without that certificate it falls back to Apple Development signing, or ad-hoc signing when no
# Apple Development identity exists either (Gatekeeper will warn in both cases).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

NOTARY_PROFILE="${NOTARY_PROFILE:-NotchHub}"
DEV_ID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"' || true)
SPARKLE_VERSIONED="Contents/Frameworks/Sparkle.framework/Versions/B"

# Sparkle's helpers must carry our Developer ID, hardened runtime and a timestamp for notarization.
# Inside-out order, as in Sparkle's "Code signing" documentation for non-sandboxed apps.
resign_for_distribution() {
  local app="$1" sparkle="$1/$SPARKLE_VERSIONED"
  local -a sign=(codesign --force --sign "$DEV_ID" --options runtime --timestamp)
  if [[ -d "$sparkle" ]]; then
    "${sign[@]}" "$sparkle/XPCServices/Installer.xpc"
    "${sign[@]}" --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
    "${sign[@]}" "$sparkle/Autoupdate"
    "${sign[@]}" "$sparkle/Updater.app"
    "${sign[@]}" "$app/Contents/Frameworks/Sparkle.framework"
  fi
  "${sign[@]}" --preserve-metadata=entitlements "$app"
  codesign --verify --deep --strict "$app"
}

SIGN_ARGS=()
if [[ -n "$DEV_ID" ]]; then
  echo "Signing with: $DEV_ID"
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$DEV_ID" OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
else
  echo "warning: no Developer ID Application certificate; the DMG will not be notarized" >&2
fi

xcodegen generate --quiet
xcodebuild build \
  -project NotchHub.xcodeproj \
  -scheme NotchHub \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build \
  -quiet \
  "${SIGN_ARGS[@]}"

APP="build/Build/Products/Release/NotchHub.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP" "$STAGING/NotchHub.app"
if [[ -n "$DEV_ID" ]]; then
  resign_for_distribution "$STAGING/NotchHub.app"
fi
ln -s /Applications "$STAGING/Applications"
cp tools/dmg/KURULUM.txt "$STAGING/KURULUM.txt"

mkdir -p dist
DMG="dist/NotchHub-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "NotchHub $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [[ -z "$DEV_ID" ]]; then
  # Ad-hoc ("-") when this machine has no Apple Development identity either.
  FALLBACK_ID="-"
  if security find-identity -v -p codesigning | grep -q '"Apple Development'; then
    FALLBACK_ID="Apple Development"
  fi
  codesign --sign "$FALLBACK_ID" --timestamp=none "$DMG"
  echo "Created $DMG (not notarized)"
  exit 0
fi

codesign --sign "$DEV_ID" --timestamp "$DMG"
echo "Submitting to Apple notary service..."
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG"
echo "Created $DMG (notarized)"
