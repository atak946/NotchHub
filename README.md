# NotchHub

NotchHub turns the MacBook notch into a small, interactive control panel. Hover the notch and it opens. Move
away and it closes. While it is closed, small live indicators sit beside the notch.

The app UI is in Turkish.

## Features

- **Notch panel:** hover to open, `⌥⌘N` to toggle, `Esc` to close and `⌘1…6` to switch tabs. A virtual notch
  appears on displays without one.
- **File shelf:** drop files, text or images onto the notch, then drag them out again. Includes Quick Look,
  AirDrop and reveal in Finder.
- **Now playing:** artwork, playback controls and a scrubber for Spotify and Apple Music, plus quick switching
  of the audio output.
- **Timer and Pomodoro:** preset and custom timers, with a countdown beside the notch.
- **Calendar:** shows the next meeting with a one-click Zoom / Teams / Meet join button, today's agenda and
  reminders. Sources are macOS Calendar (EventKit), ICS feeds and Microsoft 365 (optional).
- **Animated notch alerts:** a single queue for reminders, timers, system events and your own scripts.
- **Notes:** quick plain-text notes with checklists. A note picks up meeting and client context automatically.
- **Status monitors:**
  - microphone and camera in use;
  - VPN tunnel state (Cisco Secure Client, GlobalProtect, FortiClient, Ivanti Secure Access, OpenVPN Connect,
    Tunnelblick, WireGuard, Tailscale, NordLayer or any utun/ipsec tunnel);
  - network changes;
  - memory and thermal pressure;
  - meeting mode.
- **Developer tools:** Docker / OrbStack container events, endpoint and TLS certificate checks, and the status
  of a local LLM server.
- **Insights:** unread badges, optional mirroring of notification banners, per-client time tracking and a focus
  guard.
- **Profiles:** one-click client profiles that can open apps and URLs, wait for the VPN, run `docker compose`,
  open VS Code and a terminal. A remote-session indicator is included.
- **Integrations:** a `notchhub://` URL scheme, a local Unix socket, a CLI, a zsh "long command finished" hook
  and Xcode build alerts.

## Requirements

- macOS 26 or later.
- A Mac with a notch is recommended. Other displays get a virtual notch.

## Install

1. Download the latest `NotchHub.dmg` from the GitHub **Releases** page of this repository.
2. Open it and drag **NotchHub** to **Applications**.
3. Launch NotchHub. It lives in the menu bar and has no Dock icon.

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

Settings that only apply to your machine (bundle id, team, signing, update feed) go in
`Config/Local.xcconfig`. That file is gitignored, and the tracked defaults are in `Config/Shared.xcconfig`.

## Permissions

macOS asks for each permission the first time a feature needs it. Features whose permission you decline stay
inactive, and the rest of the app keeps working.

| Permission | Why |
|---|---|
| Calendars | Next meeting, agenda and meeting reminders |
| Automation (Apple Events) | Reading and controlling Spotify and Music |
| Notifications | Timer and Pomodoro notifications |
| Accessibility | Dock unread badges, window titles for time tracking, and reading (and optionally closing) notification banners for mirroring |
| Location (optional) | Weather for your current city (or pick a city manually), and reading the Wi-Fi network name for network-change alerts |
| Login item | "Launch at login" |

Microphone and camera *usage* is detected from CoreAudio / CoreMediaIO state. NotchHub never records audio or
video.

## Privacy

- **Local only:** shelf items, notes, time-tracking data and settings are stored on your Mac. Calendar secrets
  (ICS links, Microsoft tokens) are kept in the Keychain.
- **Notification mirroring:** banners are read from Notification Center through the Accessibility API, shown
  in the notch, and then forgotten. You can limit mirroring to messaging apps or hide message text.
- **Weather:** weather data is fetched from Open-Meteo with approximate coordinates (rounded to about 1 km).
  No API key or account is used, and you can pick a city instead of sharing your location.
- **No telemetry:** NotchHub has no analytics, crash reporting or tracking.
- **Network:** NotchHub only contacts services you configure, such as ICS feeds, Microsoft 365, endpoint
  checks and a local LLM server, plus Open-Meteo for weather (you can turn it off in Settings > Modules).
  The update check fetches only the appcast from this project's GitHub Releases.

## CLI and zsh integration

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
**Settings › Integrations**. See [`tools/Integrations/README.md`](tools/Integrations/README.md) for the full
CLI, URL and socket reference, and for the Xcode build hooks.

## Releases & updates

Signed and notarized DMGs are published on the GitHub Releases page. Installed copies check the release
feed once a day with [Sparkle](https://sparkle-project.org) and offer the update in the notch. The check can
be turned off under Ayarlar → Genel → Güncellemeler. Each update is verified with an EdDSA signature before it
is installed.

Builds from source without `SU_FEED_URL` / `SU_PUBLIC_ED_KEY` in `Config/Local.xcconfig` have updates
disabled.

Maintainers publish a release with `tools/release.sh <version>`. One-time key setup is
`tools/setup-sparkle-keys.sh`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). To report a security issue, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
