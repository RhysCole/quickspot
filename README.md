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
| `Enter` | Play the selected result — a track on its own, an album or playlist as a whole |
| `Ctrl+Enter` | Add it to the queue (tracks only) |
| `Shift+Enter` | Play its album, starting from it |
| `Tab` / `Shift+Tab` | Move the selection |
| `Down` | Play / pause |
| `Left` / `Right` | Previous / next track |
| `Escape` | Dismiss |

The arrows control playback rather than the result list, and work with the
field empty — so the overlay is a remote as well as a launcher, without
reaching for the mouse. The selection moves with `Tab` instead, since the
launcher is used by typing and pressing Enter far more often than by walking a
list. One consequence worth knowing: `Left` and `Right` no longer move the text
cursor. `Home`, `End` and clicking still do.

Acting on a result leaves the overlay open, so a run of track changes does not
mean re-summoning the launcher between each one. Escape, or a click outside the
card, is the only way out.

Search covers tracks, albums and playlists at once. The three kinds are
interleaved rather than listed one after another: only three rows are visible,
so appending albums after every track would put them out of sight on every
search, and taking one of each in turn keeps the top result of all three kinds
on screen.

The results area is always three rows, whether or not there is anything in
them, so the card is the same size every time it drops in. Results past the
third stay reachable by scrolling. To its right, a third of the width shows the
next five tracks in the queue.

## The controls

Play, pause, skip and seek go over MPRIS — the same D-Bus interface your
keyboard's media keys use — whenever there is a local player to talk to. That
is a call to a process on this machine rather than a network round trip, so the
buttons respond immediately, they need no Spotify token, and they cannot fail
the way the Web API does when Spotify has quietly deactivated the device that
was playing a moment ago.

It is deliberately not restricted to Spotify. A browser playing YouTube exports
the same interface, so the controls work on it too, and the panel names the app
it is pointed at when that app is not Spotify. Buttons are greyed out when the
current player says it cannot do something — a live stream that cannot seek, a
video with no previous track.

When nothing is playing locally — the usual case being playback on a phone —
the controls fall back to Spotify's Web API, which is the only way to reach a
device that is not on this machine.

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
theme's own accent stands in. A sleeve that is essentially black or greyscale
gets white instead of the theme, because a black cover coming up green is a
thing no one can explain by looking at it. Blob colours are capped in
brightness: the text is sized for contrast against the card, not against a pale
blob that happens to drift under it.

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
