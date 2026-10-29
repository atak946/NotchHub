# NotchHub integrations

Send notch alerts from any script, terminal or app.

| File | Purpose |
|------|---------|
| `notchhub` | POSIX `sh` CLI: post alerts, open a panel tab, wrap a command (`notchhub done`) |
| `notchhub.zsh` | zsh hook: alert when a command runs longer than 30 s |
| `xcode-build-finished.sh` (+ `xcode-build-succeeded.sh`, `xcode-build-failed.sh`) | Xcode Behaviors scripts |

NotchHub must be running with **Settings › Integrations › Accept alerts from scripts and apps** on.

## Install

```sh
# 1. CLI on your PATH (pick any directory already on PATH)
ln -s "$PWD/tools/Integrations/notchhub" /usr/local/bin/notchhub

# 2. zsh hook - add this ONE line to ~/.zshrc (Settings › Integrations › "Copy zsh setup line" copies it)
source /path/to/NotchHub/tools/Integrations/notchhub.zsh
```

Open a new terminal tab afterwards. Nothing in your shell config is changed automatically.

## CLI

```sh
notchhub "Deploy finished"
notchhub --title "Backup done" --subtitle "42 GB" --style success --icon externaldrive.fill
notchhub --title "On call" --style urgent --duration 0          # stays until dismissed
notchhub --title "Coverage" --subtitle "81 %" --key ci.coverage  # same key replaces the previous alert
notchhub --title "PR ready" --open https://example.com/pulls/1
notchhub open timer                                              # shelf | media | timer | calendar | status
notchhub done -- dotnet build                                    # ✓ dotnet build · 1m 12s  /  ✗ … failed (exit 1)
```

`notchhub done` returns the wrapped command's exit status, so it is safe in `&&` chains and CI scripts.

| Option | Values |
|--------|--------|
| `--title` | required (≤ 80 characters, longer text is truncated) |
| `--subtitle` | ≤ 160 characters |
| `--style` | `info` (blue), `reminder` (orange, pulses), `success` (green), `urgent` (red, pulses) |
| `--icon` | SF Symbol name, e.g. `hammer.fill`; unknown names fall back to `bell` |
| `--duration` | seconds on screen (max 3600), `0` = sticky; default 6 |
| `--key` | coalescing key `[A-Za-z0-9._-]`, ≤ 64 characters |
| `--open` | `http`, `https` or `file` URL. Web URLs open in the browser; file URLs are only revealed in Finder |

## zsh hook

```
✓ dotnet build · 1m 12s
✗ npm test failed (exit 1) · 45s
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `NOTCHHUB_MIN_SECONDS` | `30` | minimum runtime before an alert |
| `NOTCHHUB_IGNORE` | vim, less, ssh, top, tmux, `docker attach`, `kubectl exec`, `git log`, … | replaces the ignore list (space separated; escape spaces in two-word entries: `docker\ attach`) |
| `NOTCHHUB_IGNORE_EXTRA` | – | appended to the ignore list |
| `NOTCHHUB_NOTIFY_INTERRUPTED` | `0` | `1` also alerts for Ctrl-C (exit 130) |
| `NOTCHHUB_DISABLE` | `0` | `1` switches the hook off |

REPLs (`python`, `node`, `psql`, …) are ignored only when started without arguments. The hook posts in the
background (`&!`) so your prompt never waits; it uses zsh's own `zsocket`, then `nc -U`, then `open -g`.

## Xcode

Xcode › Settings › Behaviors:

- **Build › Succeeds** › Run › choose `xcode-build-succeeded.sh`
- **Build › Fails** › Run › choose `xcode-build-failed.sh`

Both files must stay executable and next to `notchhub`.

## Protocol

**URL scheme** (also works with `open -g "notchhub://…"`):

```
notchhub://alert?title=…&subtitle=…&style=info|reminder|success|urgent&icon=<SF Symbol>&duration=<sec|0>&key=…&open=<url>
notchhub://open?module=shelf|media|timer|calendar|status
```

**Local socket** `~/Library/Application Support/NotchHub/notchhub.sock` (mode 0600, current user only): one JSON object
per line, same field names plus `"action": "alert" | "open"` (default `alert`). Each line gets a reply line;
clients should read it before closing (a connection closed immediately after writing may be dropped):

```sh
printf '%s\n' '{"title":"Hello","style":"success"}' | nc -U -w 2 ~/Library/Application\ Support/NotchHub/notchhub.sock
# {"ok":true,"warnings":[]}
```

Finished commands may send `command`, `exit` and `elapsed` (seconds) instead of a title; NotchHub then builds the
title, style and icon itself. Unknown fields are ignored with a warning. At most 10 requests per 10 seconds are
accepted; extra requests are dropped (`"rate limited"`).

Any app or web page can open a `notchhub://` URL, so URL alerts are labelled **Harici** in the notch, are limited to
10 per minute, and can be switched off with **Settings › Integrations › Web/URL üzerinden uyarılara izin ver**.
With that toggle off only the local socket (and therefore the CLI and zsh hook) is accepted.
