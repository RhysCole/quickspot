# QuickSpot

A Walker-style Spotify track launcher for the [Omarchy](https://omarchy.org) 4 shell.
Press a key, the search field drops in from the top edge, type, press Enter, the
song plays. No window, no player, no browser.

Every colour comes from your active Omarchy theme.

## Requirements

- Omarchy 4 and Quickshell 0.3.1 or newer
- A Spotify **Premium** account (all playback endpoints require it)
- `socat` and `openssl`, both part of a standard Arch install

## Install

```bash
omarchy plugin add https://github.com/RhysCole/quickspot.git --enable
```

## Set up your Spotify application

Spotify caps a development-mode application at 25 allowlisted users, so QuickSpot
cannot ship a shared client ID. Registering your own takes about a minute and is
free.

1. Go to <https://developer.spotify.com/dashboard> and create an app.
2. Set the redirect URI to exactly `http://127.0.0.1:8788/callback`.
3. Copy the client ID.
4. Summon QuickSpot. It asks for the ID on first run — paste it and press Enter.
5. Press Enter again to sign in. A browser tab opens; approve, and it closes itself.

## Bind a key

QuickSpot does not edit your Hyprland config. Add this to
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER SHIFT", "S", "Search Spotify",
  "omarchy-shell shell summon io.github.rhyscole.quickspot")
```

Then `hyprctl reload`.

## Keys

| Key | Action |
| --- | --- |
| `Enter` | Play the selected track now |
| `Ctrl+Enter` | Add it to the queue |
| `Shift+Enter` | Play its album, starting from it |
| `Up` / `Down` / `Tab` | Move the selection |
| `Escape` | Dismiss |

Acting on a result leaves the overlay open, so a run of track changes does not
mean re-summoning the launcher between each one. Escape, or a click outside the
card, is the only way out.

The results area starts at nothing and grows a row at a time as results arrive,
up to three. The rest stay reachable by scrolling.

## Where it plays

QuickSpot targets whichever Spotify Connect device is currently active — your
phone, a speaker, the desktop client, or a local librespot daemon. If nothing is
active, it wakes a local daemon over MPRIS and plays there.

Queueing and album playback need an active Connect device; MPRIS has no verb for
either, so QuickSpot says so rather than failing quietly.

## Settings

QuickSpot has no entry in Omarchy's settings panel: the shell only builds
settings forms for plugins with a bar widget, and QuickSpot deliberately has
none. Settings live in the `plugins` array of `~/.config/omarchy/shell.json`:

```json
{
  "id": "io.github.rhyscole.quickspot",
  "clientId": "your client id",
  "redirectPort": 8788,
  "topMargin": 0
}
```

`clientId` is written for you by the first-run screen. `redirectPort` must match
the redirect URI registered in your Spotify dashboard. `topMargin` is the gap
below the bar in pixels; `0` derives it from the shell's bar tokens, which is
right for the stock bar and may need adjusting for a third-party one.

## The player

Below the results is what is playing now: title, artist and album, transport
controls, a seekable progress bar, and the artwork as a spinning record. It
reads `/v1/me/player` every five seconds while the overlay is open — never while
it is closed — and interpolates the position locally in between, so the bar
moves smoothly without polling harder.

The record spins only while playback is running and holds its angle when paused.
Controls act on whichever Connect device Spotify already considers active.

Behind everything, four blurred blobs drift and pulse in the dominant colours of
the current album art — a lava lamp tinted by what is playing. The track title,
the play button and the progress bar take the album's colour too, lifted in
lightness until they are legible against the card so a dark sleeve cannot make
the text unreadable. Artwork is cached
under `~/.cache/quickspot/art/` and quantized locally; nothing about it is sent
anywhere. When nothing is playing, or a sleeve yields no usable colours, the
theme's own accent stands in.

## What it stores

`~/.local/state/quickspot/` holds `oauth.json`, your refresh token. Nothing
else is written and nothing leaves your machine except requests to Spotify.

## Development

```bash
./run-tests.sh          # headless unit tests, no compositor or network needed
omarchy plugin validate .
```

The four `.js` modules are pure functions covered by `qmltestrunner`. The QML
files hold only presentation and I/O.

## Current state

QuickSpot has not yet been exercised end to end: no session has loaded it into
a running shell, authenticated it against a live Spotify account, played a
track through it, or seen its UI rendered by a compositor. Its pure logic —
PKCE, token parsing, search transformation, and history handling — is covered
by 57 headless unit tests, but the OAuth flow, device resolution, playback
dispatch, and the overlay's on-screen behaviour are verified only by
construction and code review. Expect the first real run to surface integration
issues that unit tests cannot catch.

## Licence

MIT
