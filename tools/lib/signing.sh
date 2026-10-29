# Shared Developer ID signing and notarization helpers, sourced by make-dmg.sh and install.sh.
# Notarization reads credentials from the keychain profile NOTARY_PROFILE (default "NotchHub").

NOTARY_PROFILE="${NOTARY_PROFILE:-NotchHub}"
DEV_ID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"' || true)
SPARKLE_VERSIONED="Contents/Frameworks/Sparkle.framework/Versions/B"

# Build settings for a Developer ID Release build; empty without the certificate.
SIGN_ARGS=()
if [[ -n "$DEV_ID" ]]; then
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$DEV_ID" OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
fi

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

# Notarizes and staples an .app bundle in place, then checks Gatekeeper accepts it.
notarize_app() {
  local app="$1" zip
  zip="$(mktemp -d)/${app:t:r}.zip"
  ditto -c -k --keepParent "$app" "$zip"
  echo "Submitting ${app:t} to Apple notary service..."
  xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -rf "${zip:h}"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl -a -vv "$app"
}
