# Development

Technical details that do not fit in the [README](../README.md): building, local configuration, releases and
the README screenshots.

## Build from source

You need Xcode with the macOS 26 SDK, plus [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen

# Optional: your own bundle id, team and signing identity.
# Without this file the app builds with ad-hoc signing.
cp Config/Local.xcconfig.example Config/Local.xcconfig

xcodegen generate

# Build
xcodebuild -project NotchHub.xcodeproj -scheme NotchHub -derivedDataPath build build
open build/Build/Products/Debug/NotchHub.app

# Test
xcodebuild -project NotchHub.xcodeproj -scheme NotchHub -derivedDataPath build test
```

`NotchHub.xcodeproj` is generated, so do not edit it by hand. Run `xcodegen generate` again after adding or
removing files. `./tools/install.sh` builds a Release copy and installs it to `/Applications`.

## Local configuration

Settings that only apply to your machine (bundle id, team, signing, update feed) go in
`Config/Local.xcconfig`. That file is gitignored, and the tracked defaults are in `Config/Shared.xcconfig`.

## Localization

Turkish is the source language and English the translation, both in
`NotchHub/Resources/Localizable.xcstrings`. Keys are written in Turkish. The language can be changed under
**Settings › General › Language**; it applies after a relaunch.

## Releases and updates

Signed and notarized DMGs are published on the GitHub Releases page. Installed copies check the release feed
once a day with [Sparkle](https://sparkle-project.org) and offer the update in the notch. Each update is
verified with an EdDSA signature before it is installed. The check can be turned off under
**Settings › General › Updates**.

Builds from source without `SU_FEED_URL` / `SU_PUBLIC_ED_KEY` in `Config/Local.xcconfig` have updates
disabled.

Maintainers publish a release with `tools/release.sh <version>`. One-time key setup is
`tools/setup-sparkle-keys.sh`.

## CLI, URL scheme and socket

Scripts can post alerts to the notch:

```sh
ln -s "$PWD/tools/Integrations/notchhub" /usr/local/bin/notchhub
notchhub --title "Deploy finished" --style success
notchhub done -- swift build        # alert with duration and exit status

# ~/.zshrc: alert when a command runs longer than 30 s
source /path/to/NotchHub/tools/Integrations/notchhub.zsh
```

Alerts arrive over a local Unix socket that only your user can open (mode 0600). Alerts sent through
`notchhub://` URLs are labelled **Harici** (external) and limited to 10 per minute. You can turn them off in
**Settings › Integrations**. See [`tools/Integrations/README.md`](../tools/Integrations/README.md) for the full
CLI, URL and socket reference, and for the Xcode build hooks.

## README screenshots

The images in `docs/images/<lang>/` are rendered by the app itself from built-in demo data, so they can never
contain real meetings, names, messages or paths:

```sh
tools/render-screenshots.sh            # builds Debug, renders English and Turkish
tools/render-screenshots.sh --skip-build
```

The script runs the app binary with `--render-screenshots <dir>` (or `NOTCHHUB_RENDER_SCREENSHOTS=<dir>`).
In that mode NotchHub shows no window and starts no monitor. It builds its services from the fixtures in
`NotchHub/Features/Screenshots/`, uses throwaway defaults and a temporary folder, renders each PNG and quits.
The clock is moved to a mid-morning time zone so the agenda looks like a working day.
`DemoFixturesTests` checks that the demo data holds nothing from the machine it runs on.
