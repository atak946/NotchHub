#!/bin/zsh
# One-time setup of the Sparkle EdDSA signing key used by tools/release.sh.
#
# Sparkle's generate_keys stores the private key in the login Keychain (reusing an existing one)
# and prints the public key, which the app ships with as SU_PUBLIC_ED_KEY.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

readonly DERIVED_DATA="build"

die() { print -u2 "error: $*"; exit 1; }

command -v xcodegen >/dev/null || die "'xcodegen' is not installed"
xcodegen generate --quiet
xcodebuild -resolvePackageDependencies -project NotchHub.xcodeproj -scheme NotchHub \
  -derivedDataPath "$DERIVED_DATA" >/dev/null 2>&1 || die "could not resolve Swift packages"

GENERATE_KEYS=$(find "$DERIVED_DATA/SourcePackages/artifacts" -type f -path '*/bin/generate_keys' 2>/dev/null | head -1 || true)
[[ -x "$GENERATE_KEYS" ]] || die "Sparkle's generate_keys was not found under $DERIVED_DATA/SourcePackages/artifacts"

print "Running Sparkle generate_keys (the Keychain may ask for permission)..."
"$GENERATE_KEYS"

cat <<EOF

Next steps:
  1. Put the public key printed above into Config/Local.xcconfig:
       SU_PUBLIC_ED_KEY = <public key>
     and set the feed (xcconfig treats '//' as a comment, so split it with \$()):
       SU_FEED_URL = https:/\$()/github.com/<owner>/<repo>/releases/latest/download/appcast.xml
  2. Back up the private key somewhere safe and offline. Losing it means existing installs
     can no longer verify updates:
       $GENERATE_KEYS -x <backup-file>
     Restore it on another Mac with:
       $GENERATE_KEYS -f <backup-file>
     Never commit the backup file.
EOF
