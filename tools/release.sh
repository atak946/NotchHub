#!/bin/zsh
# Publishes NotchHub <version> to GitHub Releases with a signed Sparkle appcast.
#
#   tools/release.sh 1.3.0            bump, build, notarize, sign appcast, commit, tag, push, release
#   tools/release.sh 1.3.0 --dry-run  same build and appcast, but no commit, tag, push or release
#
# Prerequisites: a clean git tree, `gh auth login`, Config/Local.xcconfig with SU_FEED_URL and
# SU_PUBLIC_ED_KEY, and the Sparkle EdDSA private key in the login Keychain (tools/setup-sparkle-keys.sh).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

readonly LOCAL_XCCONFIG="Config/Local.xcconfig"
readonly DERIVED_DATA="build"
readonly SPARKLE_TOOLS_DIR="$DERIVED_DATA/sparkle-tools"
readonly DIST="dist"
readonly UPDATES_DIR="$DIST/updates"
readonly APPCAST_NAME="appcast.xml"

VERSION=""
DRY_RUN=false

die() { print -u2 "error: $*"; exit 1; }
step() { print "==> $*"; }

usage() {
  print -u2 "usage: tools/release.sh <major.minor.patch> [--dry-run]"
  exit 2
}

parse_args() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY_RUN=true ;;
      -h|--help) usage ;;
      -*) print -u2 "error: unknown option $arg"; usage ;;
      *) [[ -z "$VERSION" ]] || usage; VERSION="$arg" ;;
    esac
  done
  [[ -n "$VERSION" ]] || usage
  [[ "$VERSION" =~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ]] \
    || die "'$VERSION' is not a semantic version (expected e.g. 1.3.0)"
}

require_tools() {
  local tool
  for tool in git gh xcodegen xcodebuild; do
    command -v "$tool" >/dev/null || die "'$tool' is not installed"
  done
}

require_clean_tree() {
  [[ -z "$(git status --porcelain)" ]] && return
  if $DRY_RUN; then
    print -u2 "warning: the git tree has uncommitted changes (allowed for --dry-run only)"
  else
    die "the git tree has uncommitted changes; commit or stash them first"
  fi
}

require_new_tag() {
  if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
    die "tag v$VERSION already exists"
  fi
}

require_gh_auth() {
  gh auth status >/dev/null 2>&1 || die "GitHub CLI is not authenticated; run 'gh auth login'"
}

# Reads a resolved build setting without printing it (handles includes and $(SLASH)-style URLs).
build_setting() {
  print -r -- "$BUILD_SETTINGS" | awk -v key="$1" '$1 == key && $2 == "=" { sub(/^[^=]*= ?/, ""); print; exit }'
}

require_update_config() {
  [[ -f "$LOCAL_XCCONFIG" ]] || die "$LOCAL_XCCONFIG is missing; copy Config/Local.xcconfig.example and fill it in"
  xcodegen generate --quiet
  BUILD_SETTINGS=$(xcodebuild -showBuildSettings -project NotchHub.xcodeproj -target NotchHub -configuration Release 2>/dev/null) \
    || die "could not read build settings from the Xcode project"
  FEED_URL=$(build_setting SU_FEED_URL)
  PUBLIC_KEY=$(build_setting SU_PUBLIC_ED_KEY)
  unset BUILD_SETTINGS
  [[ -n "$FEED_URL" ]] || die "SU_FEED_URL is empty in $LOCAL_XCCONFIG (note: '//' starts an xcconfig comment, write https:/\$()/github.com/...)"
  [[ "$FEED_URL" == https://* ]] || die "SU_FEED_URL in $LOCAL_XCCONFIG must be an https URL"
  [[ -n "$PUBLIC_KEY" ]] || die "SU_PUBLIC_ED_KEY is empty in $LOCAL_XCCONFIG; run tools/setup-sparkle-keys.sh"
}

resolve_repo() {
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) \
    || die "could not determine the GitHub repository; add a GitHub remote and run 'gh repo set-default'"
  local expected="https://github.com/$REPO/releases/latest/download/$APPCAST_NAME"
  [[ "$FEED_URL" == "$expected" ]] || die "SU_FEED_URL does not match this repository; expected $expected"
  DOWNLOAD_PREFIX="https://github.com/$REPO/releases/download/v$VERSION/"
}

# Sparkle's command line tools ship in the resolved package artifacts; download them as a fallback.
find_sparkle_bin() {
  xcodebuild -resolvePackageDependencies -project NotchHub.xcodeproj -scheme NotchHub \
    -derivedDataPath "$DERIVED_DATA" >/dev/null 2>&1 || die "could not resolve Swift packages"
  local tool
  tool=$(find "$DERIVED_DATA/SourcePackages/artifacts" -type f -path '*/bin/generate_appcast' 2>/dev/null | head -1 || true)
  if [[ -z "$tool" ]]; then
    download_sparkle_tools
    tool="$SPARKLE_TOOLS_DIR/bin/generate_appcast"
  fi
  [[ -x "$tool" ]] || die "Sparkle's generate_appcast was not found"
  SPARKLE_BIN="${tool:h}"
}

download_sparkle_tools() {
  local resolved="NotchHub.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" version
  version=$(grep -A6 '"sparkle"' "$resolved" 2>/dev/null | sed -nE 's/.*"version" *: *"([^"]+)".*/\1/p' | head -1 || true)
  [[ -n "$version" ]] || die "could not find the resolved Sparkle version in $resolved"
  step "Downloading Sparkle $version tools"
  mkdir -p "$SPARKLE_TOOLS_DIR"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" \
    | tar -xJ -C "$SPARKLE_TOOLS_DIR" || die "could not download Sparkle $version tools"
}

# The Keychain private key must belong to the public key the app ships with.
require_matching_private_key() {
  local keychain_key
  keychain_key=$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null) \
    || die "no Sparkle EdDSA private key in the login Keychain; run tools/setup-sparkle-keys.sh"
  [[ "$keychain_key" == "$PUBLIC_KEY" ]] \
    || die "the Keychain's Sparkle key does not match SU_PUBLIC_ED_KEY in $LOCAL_XCCONFIG"
}

bump_versions() {
  local build
  build=$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([0-9]+)"?.*/\1/p' project.yml | head -1)
  [[ -n "$build" ]] || die "CURRENT_PROJECT_VERSION not found in project.yml"
  NEW_BUILD=$((build + 1))
  step "Version $VERSION (build $NEW_BUILD)"
  sed -i '' -E \
    -e "s/^( *MARKETING_VERSION: *).*/\1\"$VERSION\"/" \
    -e "s/^( *CURRENT_PROJECT_VERSION: *).*/\1\"$NEW_BUILD\"/" \
    project.yml
}

build_dmg() {
  step "Building, signing and notarizing the DMG"
  tools/make-dmg.sh
  DMG="$DIST/NotchHub-$VERSION.dmg"
  [[ -f "$DMG" ]] || die "$DMG was not produced by tools/make-dmg.sh"
}

# Keeps older appcast items by starting from the published appcast, then signs the new DMG.
generate_appcast() {
  step "Generating the signed appcast"
  rm -rf "$UPDATES_DIR"
  mkdir -p "$UPDATES_DIR"
  gh release download --repo "$REPO" --pattern "$APPCAST_NAME" --dir "$UPDATES_DIR" >/dev/null 2>&1 \
    || print "    no published appcast yet; starting a new one"
  cp "$DMG" "$UPDATES_DIR/"
  "$SPARKLE_BIN/generate_appcast" --download-url-prefix "$DOWNLOAD_PREFIX" "$UPDATES_DIR" \
    || die "generate_appcast failed"
  cp "$UPDATES_DIR/$APPCAST_NAME" "$DIST/$APPCAST_NAME"
}

publish() {
  if $DRY_RUN; then
    step "Dry run: skipping commit, tag, push and release"
    print "    built $DMG and $DIST/$APPCAST_NAME; discard the version bump with 'git checkout project.yml'"
    return
  fi
  step "Committing and tagging v$VERSION"
  git add project.yml
  git commit -m "chore: release v$VERSION"
  git tag -a "v$VERSION" -m "NotchHub $VERSION"
  git push --follow-tags
  step "Creating the GitHub release"
  gh release create "v$VERSION" "$DMG" "$DIST/$APPCAST_NAME" \
    --repo "$REPO" --title "NotchHub $VERSION" --generate-notes
}

main() {
  parse_args "$@"
  require_tools
  require_clean_tree
  require_new_tag
  require_gh_auth
  require_update_config
  resolve_repo
  find_sparkle_bin
  require_matching_private_key
  bump_versions
  build_dmg
  generate_appcast
  publish
  step "Done: NotchHub $VERSION"
}

main "$@"
