# QuickSpot — Design

**Date:** 2026-09-05
**Plugin id:** `io.github.rhyscole.quickspot`
**Repository:** `RhysCole/quickspot` (public, MIT)
**Target:** Omarchy 4.0.2 / Quickshell 0.3.1

## Summary

QuickSpot is an Omarchy shell plugin that provides a Walker-style launcher for
Spotify. A keybind drops a search field in from the top of the screen, directly
beneath the clock. Typing searches the Spotify catalogue for tracks; Enter plays
the highlighted track immediately. It is a launcher, not a player: it has no
transport controls, no library browser, and no bar widget.

## Goals

- Summon-to-playing in one keybind and one Enter press.
- Visually indistinguishable from the rest of the desktop: every colour comes
  from the active Omarchy theme.
- Smooth entrance animation from the top edge.
- Self-contained: no dependency on any other third-party plugin's internals.

## Non-goals

- Replacing `quickshell.spotify` or the official Spotify client. QuickSpot
  controls playback; it does not implement a player UI.
- Browsing playlists, albums, artists, or the user's library.
- Managing the librespot daemon's lifecycle.
- Lyrics, artwork galleries, or any bar presence.

## Context

The development machine already runs `quickshell.spotify` v1.0.3, which
installed a librespot daemon (`omarchy-spotify`) that registers on the session
bus as `org.mpris.MediaPlayer2.OmarchySpotify` and advertises the `spotify`
URI scheme. QuickSpot treats that daemon as one possible playback target among
all Spotify Connect devices, never as a requirement. If the user uninstalls
`quickshell.spotify`, QuickSpot continues to work against any other Connect
device.

## Architecture

The plugin declares two kinds in a single manifest:

- `service` — `Service.qml`, mounted at shell startup, resident for the session.
  Owns OAuth, the token refresh timer, the Web API client, device resolution,
  and the search-history file.
- `overlay` — `Overlay.qml`, `keepLoaded: true`. Owns the window, the entrance
  animation, the result list, and key handling.

The split exists because token refresh must run on a timer regardless of
whether the overlay is visible. Once a resident service exists to hold that,
the search and history logic follow it into plain JavaScript modules that can
be unit-tested without a compositor.

`keepLoaded: true` on the overlay keeps the layer-shell window alive between
summons so the entrance animation starts immediately rather than cold-loading
QML on every invocation. This mirrors `omarchy.image-picker`, which sets the
same flag for the same reason.

### Modules

| File | Responsibility |
|---|---|
| `Service.qml` | Auth lifecycle, token timer, API requests, device resolution, history persistence |
| `Overlay.qml` | Window, scrim, card, animation, list, key handling |
| `TrackRow.qml` | One result row: artwork, title, artist, duration |
| `Auth.js` | PKCE verifier/challenge derivation, authorize-URL construction, token-response parsing |
| `Api.js` | Endpoint URL building, request-body construction, HTTP error classification |
| `Search.js` | Search response to view model, dedupe, duration and artist formatting |
| `Recent.js` | Search-history list operations |

The four `.js` modules are pure functions. They contain no I/O, no QML types,
and no network access, which is what makes them testable in isolation.

## Auth

Authorization Code with PKCE. No client secret, so no credential is ever
committed to the public repository.

### Per-user client ID

A Spotify developer application in development mode is limited to 25
individually allowlisted users. A single client ID shipped inside a public
plugin would therefore fail for every installer except those the author had
manually allowlisted. QuickSpot does not ship a client ID. Each installer
registers their own free Spotify application and enters the ID into QuickSpot's
own first-run screen. The README documents the registration steps.

The first-run screen lives inside the overlay itself: when no client ID is
configured, the overlay renders a short explanation and a paste field instead
of the search field. This is deliberate rather than a fallback. Omarchy's
settings panel only reads a settings schema from `manifest.barWidget.schema`,
and only for plugins that declare the `bar-widget` kind (`shell.qml:675`).
QuickSpot declares `service` and `overlay`, so it has no settings form
available to it, and adding a bar widget purely to obtain one would contradict
the non-goals.

This is the plugin's only non-zero first-run friction, and it is unavoidable
given Spotify's quota model.

### Flow

1. The overlay is summoned and the service holds no valid token.
2. The service starts a one-shot loopback listener:
   `socat TCP4-LISTEN:<port>,bind=127.0.0.1,reuseaddr`.
   This is the same mechanism `quickshell.spotify` uses in
   `AuthManager.qml:233`, and `socat` is a standard Omarchy dependency.
3. The default browser opens Spotify's consent page.
4. The redirect lands on the listener; the authorization code is exchanged for
   an access token and a refresh token.

The redirect port is a setting with a fixed default. Spotify matches the
registered redirect URI exactly, so the README states that changing the port
requires changing it in the Spotify dashboard as well.

This loopback listener is the only subprocess QuickSpot ever spawns, and it
runs only during first login. Search and playback are pure QML.

### Scopes

`user-modify-playback-state` and `user-read-playback-state`. Nothing further.
Search history is stored locally, so `user-read-recently-played` is not
requested.

### Token storage

The refresh token is written to `~/.local/state/quickspot/oauth.json` with mode
0600. The access token is held in memory only. It is refreshed proactively 60
seconds before expiry and reactively on any `401`. A failed refresh clears
stored state and returns the overlay to the logged-out prompt; it does not
retry in a loop.

## Search

`GET /v1/search?type=track&limit=20&q=<query>`, debounced 180ms. Each request
carries a serial number; a response whose serial is stale is discarded, so a
slow response for a prefix cannot overwrite results for a longer query.

QuickSpot performs no client-side ranking. Spotify's server-side relevance
ordering is preserved as returned. Re-scoring 20 already-ranked results with a
local fuzzy match would degrade ordering rather than improve it.

`Search.js` is therefore pure transformation:

- Response JSON to a flat array of view models.
- Duration in milliseconds to `m:ss`.
- Artist array to a joined display string.
- Album artwork URL selection (smallest image at or above the row height).
- Dedupe of entries identical in both track name and artist set, which removes
  the regional duplicates Spotify commonly returns.

### History

`Recent.js` plus a `FileView` on `~/.local/state/quickspot/history.json`. The
last 10 queries, deduplicated, most recent first. Written on submit, not on
keystroke. Shown when the search field is empty. Pressing Enter on a history
entry refills the field and runs the search.

### Failure states

No client ID configured, not logged in, network error, and zero results each
render as a single explanatory row in the list area. The overlay never presents
an empty box with no explanation.

## Playback

`GET /v1/me/player/devices` resolves the target: the first device with
`is_active` true, otherwise none.

| Key | Request |
|---|---|
| `Enter` | `PUT /v1/me/player/play?device_id=<id>` with `{"uris":["spotify:track:<id>"]}` |
| `Ctrl+Enter` | `POST /v1/me/player/queue?uri=spotify:track:<id>&device_id=<id>` |
| `Shift+Enter` | `PUT /v1/me/player/play?device_id=<id>` with `{"context_uri":"spotify:album:<id>","offset":{"uri":"spotify:track:<id>"}}` |

### No active device

If the device list is empty, or the play call returns `404 NO_ACTIVE_DEVICE`,
QuickSpot falls back to `Quickshell.Services.Mpris` and calls `openUri` on
`org.mpris.MediaPlayer2.OmarchySpotify`, waking the local librespot daemon.

This fallback covers play-now only. MPRIS has no queue verb and no album-context
verb, so `Ctrl+Enter` and `Shift+Enter` report inline that they need an active
Connect device rather than silently doing nothing.

If the daemon has idle-shut-down, its bus name is absent and there is nothing to
wake. QuickSpot reports this plainly. Starting a stopped daemon belongs to
`quickshell.spotify`, not here.

### Error handling

- `403` renders "Spotify Premium required" inline. All playback endpoints
  require Premium.
- `401` triggers one silent token refresh, then a re-auth prompt if that fails.
- `429` respects the `Retry-After` header and reports the wait inline.

## Overlay

### Window

A fullscreen `PanelWindow` with all four anchors true, `WlrLayer.Overlay`,
`WlrKeyboardFocus.Exclusive`, and `ExclusionMode.Ignore`, matching
`omarchy.emojis`. Because the window covers the screen, card positioning and the
entrance animation are ordinary QML inside it: no layer-shell margin arithmetic,
and clipping is inherent.

### Position

The card anchors to `parent.top` with a configurable `topMargin`, centred
horizontally. On the development machine this places it directly beneath the
clock, because the clock is the bar's `centerAnchor` and is therefore pinned to
exact screen centre.

The default `topMargin` derives from `Style.bar` tokens plus a gap. It is
overridable because the machine runs `hancore.shibumi.bar` rather than the stock
bar, and third-party bars may differ in height. See Settings below.

### Animation

The card's `y` animates from `-height` to its resting position over
approximately 200ms with `Easing.OutCubic`. The scrim's opacity fades from 0 to
1 on the same curve. Dismissal reverses this at roughly 150ms.

Result arrival does not re-trigger the entrance. The card's height animates
independently so that the list growing does not read as a second entrance.

### Theming

Every colour is drawn from the shell's `Color.menu` group: `background`,
`border`, `scrim`, `text`, `selectedBackground`, `selectedText`. No colour is
hardcoded, so theme changes and light themes are followed automatically without
plugin code. `TextField` and `PopupCard` from `qs.Ui` are already theme-aware
and are used rather than reimplemented.

### Keys

| Key | Action |
|---|---|
| `Escape` | Dismiss |
| `Up` / `Down` | Move selection |
| `Tab` | Next result |
| `Enter` | Play now |
| `Ctrl+Enter` | Add to queue |
| `Shift+Enter` | Play the track's album from that track |

A dimmed hint row along the bottom edge lists the modifier bindings so they are
discoverable.

## Settings

QuickSpot has no entry in Omarchy's settings panel, for the reason given under
Auth. Settings persist instead as a top-level entry in the `plugins` array of
`~/.config/omarchy/shell.json`, which is where the shell already stores
configuration for non-bar plugins:

```json
{
  "plugins": [
    {
      "id": "io.github.rhyscole.quickspot",
      "clientId": "<spotify application client id>",
      "redirectPort": 8788,
      "topMargin": 0
    }
  ]
}
```

`clientId` is written by the first-run screen through the shell's own
`updateEntryInline` API, so the user never edits a file to log in.
`redirectPort` and `topMargin` are documented in the README as hand-edited keys;
both have working defaults and neither is needed for normal use. `topMargin` of
`0` means "derive from `Style.bar`"; any other value overrides it.

### Summoning

`omarchy-shell shell summon io.github.rhyscole.quickspot`, bound to a key in
`~/.config/hypr/bindings.lua`. The binding is documented in the README rather
than installed automatically; the plugin does not modify the user's Hyprland
configuration.

## Testing

`qmltestrunner` exercises the four JavaScript modules headlessly against JSON
fixtures, with no compositor and no network:

| Test | Covers |
|---|---|
| `tst_auth.qml` | PKCE verifier and challenge derivation, authorize-URL construction, token-response parsing, expiry arithmetic |
| `tst_api.qml` | Endpoint URL and body construction for all three playback actions, HTTP error classification |
| `tst_search.qml` | Response to view model, duration and artist formatting, artwork selection, dedupe |
| `tst_recent.qml` | History insertion, dedupe, ordering, cap at 10 |

`run-tests.sh` runs the suite. Fixtures are captured Spotify API responses with
identifiers and personal data replaced.

The QML files hold only presentation and I/O wiring, thin enough that their
defects are visible on screen rather than needing a test harness.

Development follows test-driven development: a failing test precedes each
implementation step.

## Repository layout

```
manifest.json
Service.qml      Overlay.qml      TrackRow.qml
Auth.js          Api.js           Search.js        Recent.js
tests/tst_*.qml  tests/fixtures/*.json  run-tests.sh
README.md        LICENSE          docs/
```

The repository is the live plugin directory,
`~/.config/omarchy/plugins/io.github.rhyscole.quickspot/`, checked out from
`RhysCole/quickspot`. This matches how Omarchy plugins are installed and means
edits hot-reload into the running shell as they are saved. The manifest
validator refuses symlinks inside a plugin folder but skips `.git`, so a git
checkout is a valid plugin directory.

Commits are conventional-commit style, one per passing step, pushed
continuously, so `main` is always at a state where the test suite passes.

## Constraints and risks

- Spotify Premium is required for every playback endpoint. Search alone works
  without it, so the plugin degrades to a search box that cannot play.
- Each installer must register their own Spotify developer application.
- The redirect port must match the registered URI exactly.
- `Quickshell.Services.Mpris` `openUri` behaviour is verified as present in
  Quickshell 0.3.1 but the daemon's response to it is asserted from the
  librespot MPRIS interface, not yet exercised end to end. First implementation
  step against a live daemon should confirm it.
