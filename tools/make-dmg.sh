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

source tools/lib/signing.sh

if [[ -n "$DEV_ID" ]]; then
  echo "Signing with: $DEV_ID"
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
  # Staple the app itself too, so Gatekeeper accepts it offline after it is copied out of the DMG
  # (and after Sparkle installs it); a ticket on the DMG alone does not travel with the app.
  notarize_app "$STAGING/NotchHub.app"
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
