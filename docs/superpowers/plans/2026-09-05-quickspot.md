# QuickSpot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Omarchy 4 shell plugin that drops a Spotify track-search launcher in from the top of the screen and plays the selected track on the active Spotify Connect device.

**Architecture:** A single plugin declaring two kinds. `Service.qml` is a resident service owning OAuth, token refresh, the Web API client, device resolution, and search history. `Overlay.qml` is a `keepLoaded` fullscreen layer-shell overlay owning the window, entrance animation, result list, and key handling. All logic that can be pure is extracted into four plain JavaScript modules tested headlessly with `qmltestrunner`.

**Tech Stack:** Quickshell 0.3.1 (QML), Qt 6, `Quickshell.Services.Mpris`, `Quickshell.Io` (`Process`, `FileView`), QML `XMLHttpRequest`, `openssl` and `socat` for PKCE only, `qmltestrunner` for tests.

**Spec:** `docs/superpowers/specs/2026-09-05-quickspot-design.md`

## Global Constraints

- Target Omarchy 4.0.2 and Quickshell 0.3.1. Do not use APIs absent from those versions.
- Plugin id is exactly `io.github.rhyscole.quickspot`. It appears in `manifest.json`, in IPC targets, and in the `shell.json` `plugins[]` entry. It must match everywhere.
- `manifest.json` `schemaVersion` must be the JSON number `1`, not the string `"1"`.
- Every declared kind requires its matching `entryPoints` key: `service` needs `entryPoints.service`, `overlay` needs `entryPoints.overlay`.
- Entry-point paths must be relative, must not contain `..`, and the files must exist.
- No symlinks anywhere inside the plugin folder. The validator refuses them; `.git` is exempt.
- No hardcoded colours. Every colour comes from the shell's `Color` singleton, `Color.menu.*` group: `background`, `text`, `border`, `scrim`, `selectedBackground`, `selectedText`.
- OAuth scopes are exactly `user-modify-playback-state` and `user-read-playback-state`.
- No client ID, token, refresh token, or personal identifier is ever committed. Fixtures use placeholder ids.
- Refresh token is written to `~/.local/state/quickspot/oauth.json` with mode `0600`.
- Tests run with `/usr/lib/qt6/bin/qmltestrunner`. The four `.js` modules must stay free of QML types, I/O, and network calls so they remain testable headlessly.
- Conventional-commit messages. Commit and push at the end of every task so `main` is always green.
- The repository is the live plugin directory at `~/.config/omarchy/plugins/io.github.rhyscole.quickspot/`. Saving a file hot-reloads the running shell.

---

### Task 1: Scaffold, manifest, and a running test harness

Produces a plugin folder that `omarchy plugin validate` accepts and a test runner that executes. Nothing works yet; everything after this builds on a known-good base.

**Files:**
- Create: `manifest.json`
- Create: `Service.qml`
- Create: `Overlay.qml`
- Create: `run-tests.sh`
- Test: `tests/tst_harness.qml`

**Interfaces:**
- Consumes: nothing.
- Produces: a validating plugin folder; `./run-tests.sh` as the command every later task uses to run the suite.

- [ ] **Step 1: Write the failing test**

Create `tests/tst_harness.qml`:

```qml
import QtQuick
import QtTest

TestCase {
  name: "Harness"

  function test_runnerExecutes() {
    compare(1 + 1, 2)
  }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./run-tests.sh`
Expected: FAIL — `bash: ./run-tests.sh: No such file or directory`. The harness itself is what is missing.

- [ ] **Step 3: Write the test runner**

Create `run-tests.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

runner=/usr/lib/qt6/bin/qmltestrunner
if [[ ! -x $runner ]]; then
  echo "run-tests.sh: Qt 6 qmltestrunner not found at $runner" >&2
  exit 1
fi

root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "$runner" -input "$root/tests"
```

Then: `chmod +x run-tests.sh`

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `./run-tests.sh`
Expected: PASS — `Totals: 2 passed, 0 failed, 0 skipped` (QtTest counts its own `initTestCase`/`cleanupTestCase`).

- [ ] **Step 5: Write the manifest and entry-point stubs**

Create `manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "io.github.rhyscole.quickspot",
  "name": "QuickSpot",
  "version": "0.1.0",
  "author": "Rhys Cole",
  "license": "MIT",
  "description": "Walker-style Spotify track launcher that drops in from the top edge",
  "kinds": [
    "service",
    "overlay"
  ],
  "keepLoaded": true,
  "entryPoints": {
    "service": "Service.qml",
    "overlay": "Overlay.qml"
  }
}
```

Create `Service.qml`:

```qml
import QtQuick

QtObject {
  id: root
}
```

Create `Overlay.qml`:

```qml
import QtQuick
import Quickshell

Item {
  id: root
}
```

- [ ] **Step 6: Validate the plugin folder**

Run: `omarchy plugin validate .`
Expected: exit code 0, no output. Confirm with `echo $?`.

- [ ] **Step 7: Commit and push**

```bash
git add manifest.json Service.qml Overlay.qml run-tests.sh tests/tst_harness.qml
git commit -m "feat: scaffold plugin manifest and qmltestrunner harness"
git push origin main
```

---

### Task 2: PKCE generation and `Auth.js`

The pure half of the OAuth flow: generating PKCE material in a shell script, and parsing every string the flow produces. No network, no QML.

**Files:**
- Create: `scripts/pkce.sh`
- Create: `Auth.js`
- Test: `tests/tst_auth.qml`

**Interfaces:**
- Consumes: `run-tests.sh` from Task 1.
- Produces:
  - `Auth.parsePkceOutput(raw) -> { ok: bool, verifier: string, challenge: string, state: string, error: string }`
  - `Auth.normalizedPort(value) -> int`
  - `Auth.authorizeUrl(clientId, redirectUri, challenge, state) -> string`
  - `Auth.parseCallbackRequestLine(line) -> { ok: bool, code: string, state: string, error: string }`
  - `Auth.parseTokenResponse(text, nowMs) -> { ok: bool, accessToken: string, refreshToken: string, expiresAt: number, error: string }`
  - `Auth.successResponse() -> string` (raw HTTP response written back through socat)
  - `Auth.SCOPES -> string`
  - `Auth.DEFAULT_PORT -> int`

- [ ] **Step 1: Write the failing test**

Create `tests/tst_auth.qml`:

```qml
import QtQuick
import QtTest

import "../Auth.js" as Auth

TestCase {
  name: "Auth"

  function test_parsePkceOutputAcceptsWellFormedLine() {
    var verifier = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG"
    var challenge = "GFEDCBA9876543210zyxwvutsrqponmlkjihgfedcba"
    var raw = verifier + " " + challenge + " state-token"
    var result = Auth.parsePkceOutput(raw)
    verify(result.ok)
    compare(result.verifier, verifier)
    compare(result.challenge, challenge)
    compare(result.state, "state-token")
  }

  function test_parsePkceOutputRejectsShortVerifier() {
    var result = Auth.parsePkceOutput("tooshort challenge state")
    verify(!result.ok)
    verify(result.error.length > 0)
  }

  function test_parsePkceOutputRejectsMissingFields() {
    verify(!Auth.parsePkceOutput("only-one-field").ok)
    verify(!Auth.parsePkceOutput("").ok)
  }

  function test_normalizedPortClampsOutOfRange() {
    compare(Auth.normalizedPort(8788), 8788)
    compare(Auth.normalizedPort(80), Auth.DEFAULT_PORT)
    compare(Auth.normalizedPort(70000), Auth.DEFAULT_PORT)
    compare(Auth.normalizedPort("not a number"), Auth.DEFAULT_PORT)
  }

  function test_authorizeUrlEncodesEveryParameter() {
    var url = Auth.authorizeUrl("client 1", "http://127.0.0.1:8788/callback", "chal+lenge", "st/ate")
    verify(url.indexOf("https://accounts.spotify.com/authorize?") === 0)
    verify(url.indexOf("client_id=client%201") !== -1)
    verify(url.indexOf("redirect_uri=http%3A%2F%2F127.0.0.1%3A8788%2Fcallback") !== -1)
    verify(url.indexOf("code_challenge=chal%2Blenge") !== -1)
    verify(url.indexOf("code_challenge_method=S256") !== -1)
    verify(url.indexOf("state=st%2Fate") !== -1)
    verify(url.indexOf("response_type=code") !== -1)
    verify(url.indexOf("user-modify-playback-state") !== -1)
  }

  function test_parseCallbackRequestLineExtractsCodeAndState() {
    var result = Auth.parseCallbackRequestLine(
      "GET /callback?code=abc%2Bdef&state=xyz HTTP/1.1")
    verify(result.ok)
    compare(result.code, "abc+def")
    compare(result.state, "xyz")
  }

  function test_parseCallbackRequestLineReportsSpotifyDenial() {
    var result = Auth.parseCallbackRequestLine(
      "GET /callback?error=access_denied&state=xyz HTTP/1.1")
    verify(!result.ok)
    compare(result.error, "access_denied")
  }

  function test_parseCallbackRequestLineIgnoresUnrelatedLines() {
    verify(!Auth.parseCallbackRequestLine("Host: 127.0.0.1:8788").ok)
    verify(!Auth.parseCallbackRequestLine("").ok)
  }

  function test_parseTokenResponseComputesAbsoluteExpiry() {
    var body = JSON.stringify({
      access_token: "at-1",
      refresh_token: "rt-1",
      expires_in: 3600
    })
    var result = Auth.parseTokenResponse(body, 1000000)
    verify(result.ok)
    compare(result.accessToken, "at-1")
    compare(result.refreshToken, "rt-1")
    compare(result.expiresAt, 1000000 + 3600 * 1000)
  }

  function test_parseTokenResponseKeepsEmptyRefreshTokenWhenAbsent() {
    var body = JSON.stringify({ access_token: "at-2", expires_in: 60 })
    var result = Auth.parseTokenResponse(body, 0)
    verify(result.ok)
    compare(result.refreshToken, "")
  }

  function test_parseTokenResponseRejectsErrorPayload() {
    var body = JSON.stringify({ error: "invalid_grant" })
    var result = Auth.parseTokenResponse(body, 0)
    verify(!result.ok)
    compare(result.error, "invalid_grant")
  }

  function test_parseTokenResponseRejectsGarbage() {
    verify(!Auth.parseTokenResponse("<html>nope</html>", 0).ok)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./run-tests.sh`
Expected: FAIL — the `../Auth.js` import cannot be resolved, so the `Auth` test case errors out.

- [ ] **Step 3: Write `Auth.js`**

Create `Auth.js`:

```javascript
.pragma library

var DEFAULT_PORT = 8788
var SCOPES = "user-modify-playback-state user-read-playback-state"
var AUTHORIZE_ENDPOINT = "https://accounts.spotify.com/authorize"
var TOKEN_ENDPOINT = "https://accounts.spotify.com/api/token"

function normalizedPort(value) {
  var port = parseInt(value, 10)
  if (isNaN(port) || port < 1024 || port > 65535) return DEFAULT_PORT
  return port
}

function parsePkceOutput(raw) {
  var parts = String(raw || "").trim().split(/\s+/)
  if (parts.length !== 3) return { ok: false, error: "Malformed PKCE output", verifier: "", challenge: "", state: "" }
  if (!/^[A-Za-z0-9._~-]{43,128}$/.test(parts[0]))
    return { ok: false, error: "Invalid PKCE verifier", verifier: "", challenge: "", state: "" }
  if (!/^[A-Za-z0-9_-]{43,128}$/.test(parts[1]))
    return { ok: false, error: "Invalid PKCE challenge", verifier: "", challenge: "", state: "" }
  if (parts[2].length === 0)
    return { ok: false, error: "Missing OAuth state", verifier: "", challenge: "", state: "" }
  return { ok: true, error: "", verifier: parts[0], challenge: parts[1], state: parts[2] }
}

function authorizeUrl(clientId, redirectUri, challenge, state) {
  var params = [
    "response_type=code",
    "client_id=" + encodeURIComponent(clientId),
    "redirect_uri=" + encodeURIComponent(redirectUri),
    "code_challenge_method=S256",
    "code_challenge=" + encodeURIComponent(challenge),
    "state=" + encodeURIComponent(state),
    "scope=" + encodeURIComponent(SCOPES)
  ]
  return AUTHORIZE_ENDPOINT + "?" + params.join("&")
}

function parseCallbackRequestLine(line) {
  var text = String(line || "")
  var match = text.match(/^GET\s+\/\S*\?(\S*)\s+HTTP/)
  if (!match) return { ok: false, code: "", state: "", error: "" }

  var query = {}
  var pairs = match[1].split("&")
  for (var i = 0; i < pairs.length; i++) {
    var pair = pairs[i].split("=")
    if (pair.length !== 2) continue
    query[decodeURIComponent(pair[0])] = decodeURIComponent(pair[1].replace(/\+/g, "%2B"))
  }

  if (query.error) return { ok: false, code: "", state: "", error: query.error }
  if (!query.code) return { ok: false, code: "", state: "", error: "No authorization code in callback" }
  return { ok: true, code: query.code, state: query.state || "", error: "" }
}

function parseTokenResponse(text, nowMs) {
  var payload
  try {
    payload = JSON.parse(String(text || ""))
  } catch (e) {
    return { ok: false, accessToken: "", refreshToken: "", expiresAt: 0, error: "Malformed token response" }
  }
  if (payload.error)
    return { ok: false, accessToken: "", refreshToken: "", expiresAt: 0, error: String(payload.error) }
  if (!payload.access_token)
    return { ok: false, accessToken: "", refreshToken: "", expiresAt: 0, error: "No access token in response" }

  var lifetime = parseInt(payload.expires_in, 10)
  if (isNaN(lifetime)) lifetime = 3600
  return {
    ok: true,
    error: "",
    accessToken: String(payload.access_token),
    refreshToken: payload.refresh_token ? String(payload.refresh_token) : "",
    expiresAt: nowMs + lifetime * 1000
  }
}

function successResponse() {
  var body = "<!doctype html><meta charset=utf-8><title>QuickSpot</title>"
    + "<body style=\"font-family:sans-serif;text-align:center;padding-top:4rem\">"
    + "<h1>QuickSpot is connected</h1><p>You can close this tab.</p>"
  return "HTTP/1.1 200 OK\r\n"
    + "Content-Type: text/html; charset=utf-8\r\n"
    + "Content-Length: " + body.length + "\r\n"
    + "Connection: close\r\n\r\n"
    + body
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `./run-tests.sh`
Expected: PASS — all 11 `Auth` tests green alongside the harness test.

- [ ] **Step 5: Write the PKCE script**

Create `scripts/pkce.sh`:

```bash
#!/usr/bin/env bash
# Emits one line: "<verifier> <challenge> <state>".
#
# QML's JavaScript engine has neither a CSPRNG nor SHA-256, so PKCE material
# cannot be generated in the shell process. openssl is part of the Arch base
# system.
set -euo pipefail

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

verifier=$(openssl rand 32 | b64url)
challenge=$(printf '%s' "$verifier" | openssl dgst -sha256 -binary | b64url)
state=$(openssl rand 16 | b64url)

printf '%s %s %s\n' "$verifier" "$challenge" "$state"
```

Then: `chmod +x scripts/pkce.sh`

- [ ] **Step 6: Verify the script produces material `Auth.js` accepts**

Run: `./scripts/pkce.sh | awk '{ print length($1), length($2), length($3) }'`
Expected: `43 43 22` — a 32-byte verifier and SHA-256 digest each base64url-encode to 43 characters, and 16 random bytes to 22. Both lengths satisfy the `{43,128}` patterns in `parsePkceOutput`.

- [ ] **Step 7: Commit and push**

```bash
git add Auth.js scripts/pkce.sh tests/tst_auth.qml
git commit -m "feat: add PKCE generation and OAuth string parsing"
git push origin main
```

---

### Task 3: `Api.js` — endpoint construction and error classification

Every URL, request body, and HTTP-status interpretation the plugin needs, as pure functions.

**Files:**
- Create: `Api.js`
- Test: `tests/tst_api.qml`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `Api.searchUrl(query, limit) -> string`
  - `Api.devicesUrl() -> string`
  - `Api.playUrl(deviceId) -> string`
  - `Api.queueUrl(trackUri, deviceId) -> string`
  - `Api.playTrackBody(trackUri) -> string`
  - `Api.playAlbumBody(albumUri, trackUri) -> string`
  - `Api.classifyError(status, bodyText) -> { kind: string, message: string }` where `kind` is one of `"unauthorized"`, `"forbidden"`, `"noDevice"`, `"rateLimited"`, `"network"`, `"unknown"`
  - `Api.retryAfterMs(headerValue) -> number`
  - `Api.activeDeviceId(payloadText) -> string`

- [ ] **Step 1: Write the failing test**

Create `tests/tst_api.qml`:

```qml
import QtQuick
import QtTest

import "../Api.js" as Api

TestCase {
  name: "Api"

  function test_searchUrlEncodesQueryAndLimitsType() {
    var url = Api.searchUrl("m83 midnight & city", 20)
    verify(url.indexOf("https://api.spotify.com/v1/search?") === 0)
    verify(url.indexOf("type=track") !== -1)
    verify(url.indexOf("limit=20") !== -1)
    verify(url.indexOf("q=m83%20midnight%20%26%20city") !== -1)
  }

  function test_searchUrlClampsLimit() {
    verify(Api.searchUrl("x", 0).indexOf("limit=1") !== -1)
    verify(Api.searchUrl("x", 999).indexOf("limit=50") !== -1)
  }

  function test_playUrlOmitsDeviceWhenUnknown() {
    compare(Api.playUrl(""), "https://api.spotify.com/v1/me/player/play")
    compare(Api.playUrl("dev1"), "https://api.spotify.com/v1/me/player/play?device_id=dev1")
  }

  function test_queueUrlEncodesUri() {
    var url = Api.queueUrl("spotify:track:abc", "dev1")
    verify(url.indexOf("uri=spotify%3Atrack%3Aabc") !== -1)
    verify(url.indexOf("device_id=dev1") !== -1)
  }

  function test_playTrackBodyUsesUrisArray() {
    var body = JSON.parse(Api.playTrackBody("spotify:track:abc"))
    compare(body.uris.length, 1)
    compare(body.uris[0], "spotify:track:abc")
  }

  function test_playAlbumBodyUsesContextAndOffset() {
    var body = JSON.parse(Api.playAlbumBody("spotify:album:xyz", "spotify:track:abc"))
    compare(body.context_uri, "spotify:album:xyz")
    compare(body.offset.uri, "spotify:track:abc")
  }

  function test_classifyErrorMapsStatuses() {
    compare(Api.classifyError(401, "").kind, "unauthorized")
    compare(Api.classifyError(403, "").kind, "forbidden")
    compare(Api.classifyError(404, "").kind, "noDevice")
    compare(Api.classifyError(429, "").kind, "rateLimited")
    compare(Api.classifyError(0, "").kind, "network")
    compare(Api.classifyError(500, "").kind, "unknown")
  }

  function test_classifyErrorForbiddenMentionsPremium() {
    verify(Api.classifyError(403, "").message.toLowerCase().indexOf("premium") !== -1)
  }

  function test_classifyErrorPrefersSpotifyMessage() {
    var body = JSON.stringify({ error: { status: 500, message: "Service unavailable" } })
    compare(Api.classifyError(500, body).message, "Service unavailable")
  }

  function test_retryAfterMsParsesSecondsAndDefaults() {
    compare(Api.retryAfterMs("3"), 3000)
    compare(Api.retryAfterMs(""), 1000)
    compare(Api.retryAfterMs("nonsense"), 1000)
  }

  function test_activeDeviceIdPicksActiveDevice() {
    var payload = JSON.stringify({ devices: [
      { id: "a", is_active: false },
      { id: "b", is_active: true }
    ]})
    compare(Api.activeDeviceId(payload), "b")
  }

  function test_activeDeviceIdReturnsEmptyWhenNoneActive() {
    compare(Api.activeDeviceId(JSON.stringify({ devices: [{ id: "a", is_active: false }] })), "")
    compare(Api.activeDeviceId(JSON.stringify({ devices: [] })), "")
    compare(Api.activeDeviceId("garbage"), "")
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./run-tests.sh`
Expected: FAIL — `../Api.js` cannot be resolved.

- [ ] **Step 3: Write `Api.js`**

Create `Api.js`:

```javascript
.pragma library

var BASE = "https://api.spotify.com/v1"

function searchUrl(query, limit) {
  var capped = parseInt(limit, 10)
  if (isNaN(capped) || capped < 1) capped = 1
  if (capped > 50) capped = 50
  return BASE + "/search?q=" + encodeURIComponent(query)
    + "&type=track&limit=" + capped
}

function devicesUrl() {
  return BASE + "/me/player/devices"
}

function playUrl(deviceId) {
  if (!deviceId) return BASE + "/me/player/play"
  return BASE + "/me/player/play?device_id=" + encodeURIComponent(deviceId)
}

function queueUrl(trackUri, deviceId) {
  var url = BASE + "/me/player/queue?uri=" + encodeURIComponent(trackUri)
  if (deviceId) url += "&device_id=" + encodeURIComponent(deviceId)
  return url
}

function playTrackBody(trackUri) {
  return JSON.stringify({ uris: [trackUri] })
}

function playAlbumBody(albumUri, trackUri) {
  return JSON.stringify({ context_uri: albumUri, offset: { uri: trackUri } })
}

function spotifyMessage(bodyText) {
  try {
    var payload = JSON.parse(String(bodyText || ""))
    if (payload && payload.error && payload.error.message) return String(payload.error.message)
  } catch (e) {}
  return ""
}

function classifyError(status, bodyText) {
  var detail = spotifyMessage(bodyText)
  switch (parseInt(status, 10)) {
  case 401:
    return { kind: "unauthorized", message: detail || "Spotify sign-in expired" }
  case 403:
    return { kind: "forbidden", message: detail || "Spotify Premium required" }
  case 404:
    return { kind: "noDevice", message: detail || "No active Spotify device" }
  case 429:
    return { kind: "rateLimited", message: detail || "Spotify is rate limiting requests" }
  case 0:
    return { kind: "network", message: detail || "Could not reach Spotify" }
  default:
    return { kind: "unknown", message: detail || "Spotify returned an error" }
  }
}

function retryAfterMs(headerValue) {
  var seconds = parseInt(headerValue, 10)
  if (isNaN(seconds) || seconds < 0) return 1000
  return seconds * 1000
}

function activeDeviceId(payloadText) {
  var payload
  try {
    payload = JSON.parse(String(payloadText || ""))
  } catch (e) {
    return ""
  }
  var devices = (payload && payload.devices) || []
  for (var i = 0; i < devices.length; i++)
    if (devices[i] && devices[i].is_active === true) return String(devices[i].id || "")
  return ""
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `./run-tests.sh`
Expected: PASS — all 12 `Api` tests green.

- [ ] **Step 5: Commit and push**

```bash
git add Api.js tests/tst_api.qml
git commit -m "feat: add Spotify endpoint construction and error classification"
git push origin main
```

---
### Task 4: `Search.js` — response transformation

Turns a Spotify search payload into the exact rows the list renders. Pure, fixture-driven.

**Files:**
- Create: `Search.js`
- Create: `tests/fixtures/search-tracks.json`
- Test: `tests/tst_search.qml`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `Search.formatDuration(ms) -> string`
  - `Search.joinArtists(artists) -> string`
  - `Search.pickArtwork(images, minSize) -> string`
  - `Search.dedupe(rows) -> array`
  - `Search.toRows(payloadText) -> array` of `{ id, uri, name, artists, albumName, albumUri, durationText, artworkUrl }`

- [ ] **Step 1: Write the fixture**

Create `tests/fixtures/search-tracks.json`. Every identifier is a placeholder; nothing here came from a real account.

```json
{
  "tracks": {
    "items": [
      {
        "id": "trk1",
        "uri": "spotify:track:trk1",
        "name": "Midnight City",
        "duration_ms": 243000,
        "artists": [{ "name": "M83" }],
        "album": {
          "name": "Hurry Up, We're Dreaming",
          "uri": "spotify:album:alb1",
          "images": [
            { "url": "https://example.invalid/large.jpg", "height": 640 },
            { "url": "https://example.invalid/medium.jpg", "height": 300 },
            { "url": "https://example.invalid/small.jpg", "height": 64 }
          ]
        }
      },
      {
        "id": "trk2",
        "uri": "spotify:track:trk2",
        "name": "Midnight City",
        "duration_ms": 243000,
        "artists": [{ "name": "M83" }],
        "album": {
          "name": "Hurry Up, We're Dreaming (Deluxe)",
          "uri": "spotify:album:alb2",
          "images": []
        }
      },
      {
        "id": "trk3",
        "uri": "spotify:track:trk3",
        "name": "Midnight City - Remix",
        "duration_ms": 381000,
        "artists": [{ "name": "M83" }, { "name": "Eric Prydz" }],
        "album": {
          "name": "Remixes",
          "uri": "spotify:album:alb3",
          "images": [{ "url": "https://example.invalid/remix.jpg", "height": 300 }]
        }
      }
    ]
  }
}
```

- [ ] **Step 2: Write the failing test**

Create `tests/tst_search.qml`:

```qml
import QtQuick
import QtTest

import "../Search.js" as Search

TestCase {
  name: "Search"

  property string fixture: ""

  function initTestCase() {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("fixtures/search-tracks.json"), false)
    request.send(null)
    fixture = request.responseText
    verify(fixture.length > 0)
  }

  function test_formatDurationPadsSeconds() {
    compare(Search.formatDuration(243000), "4:03")
    compare(Search.formatDuration(381000), "6:21")
    compare(Search.formatDuration(59000), "0:59")
    compare(Search.formatDuration(0), "0:00")
    compare(Search.formatDuration(-5), "0:00")
  }

  function test_joinArtistsUsesCommas() {
    compare(Search.joinArtists([{ name: "M83" }]), "M83")
    compare(Search.joinArtists([{ name: "M83" }, { name: "Eric Prydz" }]), "M83, Eric Prydz")
    compare(Search.joinArtists([]), "")
  }

  function test_pickArtworkChoosesSmallestAboveMinimum() {
    var images = [
      { url: "large", height: 640 },
      { url: "medium", height: 300 },
      { url: "small", height: 64 }
    ]
    compare(Search.pickArtwork(images, 64), "small")
    compare(Search.pickArtwork(images, 100), "medium")
    compare(Search.pickArtwork(images, 700), "large")
    compare(Search.pickArtwork([], 64), "")
  }

  function test_toRowsMapsEveryField() {
    var rows = Search.toRows(fixture)
    compare(rows[0].id, "trk1")
    compare(rows[0].uri, "spotify:track:trk1")
    compare(rows[0].name, "Midnight City")
    compare(rows[0].artists, "M83")
    compare(rows[0].albumName, "Hurry Up, We're Dreaming")
    compare(rows[0].albumUri, "spotify:album:alb1")
    compare(rows[0].durationText, "4:03")
    compare(rows[0].artworkUrl, "https://example.invalid/small.jpg")
  }

  function test_toRowsDedupesSameNameAndArtists() {
    var rows = Search.toRows(fixture)
    compare(rows.length, 2)
    compare(rows[0].id, "trk1")
    compare(rows[1].id, "trk3")
  }

  function test_dedupeKeepsDistinctArtistSets() {
    var rows = Search.dedupe([
      { name: "Song", artists: "A" },
      { name: "Song", artists: "B" },
      { name: "Song", artists: "A" }
    ])
    compare(rows.length, 2)
  }

  function test_dedupeKeepsTheFirstOccurrence() {
    var rows = Search.dedupe([
      { name: "Song", artists: "A", id: "first" },
      { name: "Song", artists: "A", id: "second" }
    ])
    compare(rows.length, 1)
    compare(rows[0].id, "first")
  }

  function test_toRowsReturnsEmptyOnGarbage() {
    compare(Search.toRows("not json").length, 0)
    compare(Search.toRows("").length, 0)
    compare(Search.toRows(JSON.stringify({})).length, 0)
  }
}
```

The fixture's second entry is a deliberate duplicate of the first by name and artist, so `test_toRowsDedupesSameNameAndArtists` proves dedupe fires on realistic data rather than on a synthetic array.

- [ ] **Step 3: Run the test to verify it fails**

Run: `./run-tests.sh`
Expected: FAIL — `../Search.js` cannot be resolved.

- [ ] **Step 4: Write `Search.js`**

Create `Search.js`:

```javascript
.pragma library

function formatDuration(ms) {
  var total = Math.floor(Number(ms) / 1000)
  if (isNaN(total) || total < 0) total = 0
  var minutes = Math.floor(total / 60)
  var seconds = total % 60
  return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
}

function joinArtists(artists) {
  var list = artists || []
  var names = []
  for (var i = 0; i < list.length; i++)
    if (list[i] && list[i].name) names.push(String(list[i].name))
  return names.join(", ")
}

function pickArtwork(images, minSize) {
  var list = images || []
  if (list.length === 0) return ""

  var best = null
  for (var i = 0; i < list.length; i++) {
    var image = list[i]
    if (!image || !image.url) continue
    var height = Number(image.height) || 0
    if (height >= minSize && (best === null || height < Number(best.height))) best = image
  }
  if (best) return String(best.url)

  var largest = null
  for (var j = 0; j < list.length; j++) {
    var candidate = list[j]
    if (!candidate || !candidate.url) continue
    if (largest === null || Number(candidate.height) > Number(largest.height)) largest = candidate
  }
  return largest ? String(largest.url) : ""
}

function dedupe(rows) {
  var seen = {}
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var key = rows[i].name + " " + rows[i].artists
    if (seen[key]) continue
    seen[key] = true
    out.push(rows[i])
  }
  return out
}

function toRows(payloadText) {
  var payload
  try {
    payload = JSON.parse(String(payloadText || ""))
  } catch (e) {
    return []
  }

  var items = (payload && payload.tracks && payload.tracks.items) || []
  var rows = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (!item || !item.uri) continue
    var album = item.album || {}
    rows.push({
      id: String(item.id || ""),
      uri: String(item.uri),
      name: String(item.name || ""),
      artists: joinArtists(item.artists),
      albumName: String(album.name || ""),
      albumUri: String(album.uri || ""),
      durationText: formatDuration(item.duration_ms),
      artworkUrl: pickArtwork(album.images, 64)
    })
  }
  return dedupe(rows)
}
```

- [ ] **Step 5: Run the tests and make sure they pass**

Run: `./run-tests.sh`
Expected: PASS — all 8 `Search` tests green.

- [ ] **Step 6: Commit and push**

```bash
git add Search.js tests/tst_search.qml tests/fixtures/search-tracks.json
git commit -m "feat: add search response transformation and dedupe"
git push origin main
```

---

### Task 5: `Recent.js` — search history

**Files:**
- Create: `Recent.js`
- Test: `tests/tst_recent.qml`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `Recent.sanitize(rawText) -> array of string`
  - `Recent.insert(list, query, cap) -> array of string`
  - `Recent.serialize(list) -> string`
  - `Recent.CAP -> int`

- [ ] **Step 1: Write the failing test**

Create `tests/tst_recent.qml`:

```qml
import QtQuick
import QtTest

import "../Recent.js" as Recent

TestCase {
  name: "Recent"

  function test_insertPutsNewestFirst() {
    var list = Recent.insert([], "one", 10)
    list = Recent.insert(list, "two", 10)
    compare(list.length, 2)
    compare(list[0], "two")
    compare(list[1], "one")
  }

  function test_insertMovesRepeatedQueryToFrontWithoutDuplicating() {
    var list = Recent.insert(Recent.insert(Recent.insert([], "a", 10), "b", 10), "a", 10)
    compare(list.length, 2)
    compare(list[0], "a")
    compare(list[1], "b")
  }

  function test_insertTrimsWhitespaceAndIgnoresEmpty() {
    compare(Recent.insert([], "  spaced  ", 10)[0], "spaced")
    compare(Recent.insert([], "   ", 10).length, 0)
    compare(Recent.insert([], "", 10).length, 0)
  }

  function test_insertRespectsCap() {
    var list = []
    for (var i = 0; i < 15; i++) list = Recent.insert(list, "q" + i, 10)
    compare(list.length, 10)
    compare(list[0], "q14")
    compare(list[9], "q5")
  }

  function test_insertTreatsDifferentCaseAsDifferentQueries() {
    var list = Recent.insert(Recent.insert([], "M83", 10), "m83", 10)
    compare(list.length, 2)
  }

  function test_sanitizeAcceptsWellFormedJson() {
    compare(Recent.sanitize(JSON.stringify(["a", "b"])).length, 2)
  }

  function test_sanitizeDropsNonStringsAndGarbage() {
    compare(Recent.sanitize(JSON.stringify(["a", 3, null, "b"])).length, 2)
    compare(Recent.sanitize("not json").length, 0)
    compare(Recent.sanitize("").length, 0)
    compare(Recent.sanitize(JSON.stringify({ not: "a list" })).length, 0)
  }

  function test_sanitizeEnforcesCap() {
    var many = []
    for (var i = 0; i < 40; i++) many.push("q" + i)
    compare(Recent.sanitize(JSON.stringify(many)).length, Recent.CAP)
  }

  function test_serializeRoundTrips() {
    compare(Recent.sanitize(Recent.serialize(["a", "b"])).length, 2)
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./run-tests.sh`
Expected: FAIL — `../Recent.js` cannot be resolved.

- [ ] **Step 3: Write `Recent.js`**

Create `Recent.js`:

```javascript
.pragma library

var CAP = 10

function insert(list, query, cap) {
  var limit = parseInt(cap, 10)
  if (isNaN(limit) || limit < 1) limit = CAP

  var trimmed = String(query || "").trim()
  if (trimmed.length === 0) return (list || []).slice(0, limit)

  var out = [trimmed]
  var source = list || []
  for (var i = 0; i < source.length; i++) {
    if (source[i] === trimmed) continue
    out.push(source[i])
    if (out.length === limit) break
  }
  return out
}

function sanitize(rawText) {
  var parsed
  try {
    parsed = JSON.parse(String(rawText || ""))
  } catch (e) {
    return []
  }
  if (!Array.isArray(parsed)) return []

  var out = []
  for (var i = 0; i < parsed.length && out.length < CAP; i++)
    if (typeof parsed[i] === "string" && parsed[i].length > 0) out.push(parsed[i])
  return out
}

function serialize(list) {
  return JSON.stringify((list || []).slice(0, CAP))
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `./run-tests.sh`
Expected: PASS — all 9 `Recent` tests green. The suite now holds 40 assertions across four test cases.

- [ ] **Step 5: Commit and push**

```bash
git add Recent.js tests/tst_recent.qml
git commit -m "feat: add search history list operations"
git push origin main
```

---

### Task 6: `Service.qml` — auth lifecycle

Wires the tested string logic to real processes, files, and the network. This task has no headless test: it needs a running shell and a browser. Verification is manual, and the steps say exactly what to look for.

**Files:**
- Modify: `Service.qml` (replaces the Task 1 stub entirely)

**Interfaces:**
- Consumes: `Auth.js` from Task 2; `scripts/pkce.sh` from Task 2.
- Produces, on the service root:
  - `property var shell` — injected by the shell at mount time
  - `readonly property var settings` — derived from `shell.shellConfig.plugins`
  - `readonly property string clientId`
  - `readonly property bool authorized`
  - `property string authError`
  - `property bool loginBusy`
  - `function beginLogin()`
  - `function withToken(callback)` — invokes `callback(accessToken, errorString)`, refreshing first when needed
  - `function setClientId(value)` — persists to `shell.json`
  - `function clearAuth(message)`

- [ ] **Step 1: Replace `Service.qml`**

```qml
import QtQuick
import Quickshell
import Quickshell.Io

import "Auth.js" as Auth

QtObject {
  id: root

  // Injected by the shell when the service is mounted (shell.qml:306).
  property var shell: null

  // Settings are the plugin's entry in shell.json's top-level plugins[] array.
  // Derived rather than assigned, so an external edit to shell.json is picked
  // up without a restart.
  readonly property var settings: {
    var plugins = (shell && shell.shellConfig && shell.shellConfig.plugins) || []
    for (var i = 0; i < plugins.length; i++)
      if (plugins[i] && plugins[i].id === "io.github.rhyscole.quickspot") return plugins[i]
    return ({})
  }
  readonly property string clientId: String(settings.clientId || "")
  readonly property int redirectPort: Auth.normalizedPort(settings.redirectPort)
  readonly property string redirectUri: "http://127.0.0.1:" + redirectPort + "/callback"

  property string accessToken: ""
  property double accessTokenExpiresAt: 0
  property string refreshToken: ""
  property string authError: ""
  property bool loginBusy: false

  readonly property bool authorized: refreshToken !== ""
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/quickspot"

  property string pkceVerifier: ""
  property string oauthState: ""
  property var tokenWaiters: []

  function tokenValid() {
    return accessToken !== "" && Date.now() + 60000 < accessTokenExpiresAt
  }

  function withToken(callback) {
    if (tokenValid()) { callback(accessToken, ""); return }
    if (refreshToken === "") { callback("", "Not signed in to Spotify"); return }
    tokenWaiters.push(callback)
    if (!refreshRequest.active) refreshRequest.start()
  }

  function finishWaiters(token, error) {
    var waiters = tokenWaiters
    tokenWaiters = []
    for (var i = 0; i < waiters.length; i++) waiters[i](token, error)
  }

  // `settings` is read-only, so this writes through the shell, which persists
  // shell.json and republishes shellConfig. The derived property then updates.
  function setClientId(value) {
    if (!shell) return
    authError = ""
    var next = { id: "io.github.rhyscole.quickspot" }
    for (var key in settings) if (key !== "id") next[key] = settings[key]
    next.clientId = String(value).trim()
    shell.updateEntryInline("io.github.rhyscole.quickspot", next)
  }

  function beginLogin() {
    if (loginBusy) return
    if (clientId === "") { authError = "Enter your Spotify client ID first"; return }
    authError = ""
    loginBusy = true
    pkceVerifier = ""
    pkceGenerator.command = [Qt.resolvedUrl("scripts/pkce.sh").toString().replace("file://", "")]
    pkceGenerator.running = true
  }

  function failLogin(message) {
    loginBusy = false
    pkceVerifier = ""
    authError = message
    callbackListener.running = false
    finishWaiters("", message)
  }

  function onPkceLine(line) {
    if (!loginBusy || pkceVerifier !== "") return
    var pkce = Auth.parsePkceOutput(line)
    if (!pkce.ok) { failLogin(pkce.error); return }

    pkceVerifier = pkce.verifier
    oauthState = pkce.state
    callbackListener.command = [
      "socat", "-T", "180",
      "TCP4-LISTEN:" + redirectPort + ",bind=127.0.0.1,reuseaddr",
      "SYSTEM:cat"
    ]
    callbackListener.running = true
    Qt.openUrlExternally(Auth.authorizeUrl(clientId, redirectUri, pkce.challenge, pkce.state))
  }

  function onCallbackLine(line) {
    var callback = Auth.parseCallbackRequestLine(line)
    if (!callback.ok) {
      if (callback.error) failLogin("Spotify sign-in was declined")
      return
    }
    if (callback.state !== oauthState) { failLogin("OAuth state mismatch"); return }

    callbackListener.write(Auth.successResponse())
    callbackListener.running = false
    exchangeCode(callback.code)
  }

  function exchangeCode(code) {
    var verifier = pkceVerifier
    pkceVerifier = ""

    var request = new XMLHttpRequest()
    request.open("POST", "https://accounts.spotify.com/api/token")
    request.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
    request.onreadystatechange = function() {
      if (request.readyState !== XMLHttpRequest.DONE) return
      root.loginBusy = false
      var parsed = Auth.parseTokenResponse(request.responseText, Date.now())
      if (!parsed.ok) { root.failLogin(parsed.error); return }
      root.applyToken(parsed)
    }
    request.send("grant_type=authorization_code"
      + "&code=" + encodeURIComponent(code)
      + "&redirect_uri=" + encodeURIComponent(redirectUri)
      + "&client_id=" + encodeURIComponent(clientId)
      + "&code_verifier=" + encodeURIComponent(verifier))
  }

  function applyToken(parsed) {
    accessToken = parsed.accessToken
    accessTokenExpiresAt = parsed.expiresAt
    if (parsed.refreshToken !== "") {
      refreshToken = parsed.refreshToken
      tokenStore.setText(JSON.stringify({ refresh_token: refreshToken }))
    }
    authError = ""
    finishWaiters(accessToken, "")
  }

  function clearAuth(message) {
    accessToken = ""
    accessTokenExpiresAt = 0
    refreshToken = ""
    tokenStore.setText(JSON.stringify({}))
    authError = message
    finishWaiters("", message)
  }

  property Process pkceGenerator: Process {
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.onPkceLine(line) }
    }
    onExited: function(exitCode) {
      if (root.loginBusy && root.pkceVerifier === "" && exitCode !== 0)
        root.failLogin("Could not start Spotify sign-in")
    }
  }

  property Process callbackListener: Process {
    stdinEnabled: true
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) { root.onCallbackLine(line) }
    }
  }

  property FileView tokenStore: FileView {
    path: root.statePath + "/oauth.json"
    onLoaded: {
      try {
        var stored = JSON.parse(text())
        if (stored && stored.refresh_token) root.refreshToken = String(stored.refresh_token)
      } catch (e) {}
    }
  }

  property QtObject refreshRequest: QtObject {
    id: refresher
    property bool active: false

    function start() {
      active = true
      var request = new XMLHttpRequest()
      request.open("POST", "https://accounts.spotify.com/api/token")
      request.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
      request.onreadystatechange = function() {
        if (request.readyState !== XMLHttpRequest.DONE) return
        refresher.active = false
        var parsed = Auth.parseTokenResponse(request.responseText, Date.now())
        if (!parsed.ok) { root.clearAuth("Spotify sign-in expired, sign in again"); return }
        root.applyToken(parsed)
      }
      request.send("grant_type=refresh_token"
        + "&refresh_token=" + encodeURIComponent(root.refreshToken)
        + "&client_id=" + encodeURIComponent(root.clientId))
    }
  }

  property Timer refreshTimer: Timer {
    interval: 30000
    repeat: true
    running: root.refreshToken !== ""
    onTriggered: {
      if (root.refreshToken !== "" && !root.tokenValid() && !root.refreshRequest.active)
        root.refreshRequest.start()
    }
  }
}
```

- [ ] **Step 2: Create the state directory with restrictive permissions**

```bash
mkdir -p ~/.local/state/quickspot
chmod 700 ~/.local/state/quickspot
```

`FileView.setText` creates `oauth.json` inside a `0700` directory, so the refresh token is unreadable by other users regardless of the file's own mode.

- [ ] **Step 3: Enable the plugin and confirm the service loads**

```bash
omarchy plugin validate .
omarchy plugin enable io.github.rhyscole.quickspot
omarchy-shell shell rescanPlugins
omarchy plugin list | grep quickspot
```

Expected: the plugin lists as `enabled` with kinds `service, overlay`, and no QML errors appear on the shell console.

- [ ] **Step 4: Register a Spotify application and set the client ID**

Create an app at `https://developer.spotify.com/dashboard` with the redirect URI set to exactly `http://127.0.0.1:8788/callback`. Then:

```bash
jq '.plugins += [{"id":"io.github.rhyscole.quickspot","clientId":"YOUR_CLIENT_ID"}]' \
  ~/.config/omarchy/shell.json > /tmp/quickspot-shell.json \
  && mv /tmp/quickspot-shell.json ~/.config/omarchy/shell.json
```

Later tasks replace this manual step with the overlay's first-run screen; it is needed now because no UI exists yet.

- [ ] **Step 5: Verify the login round trip**

Trigger `beginLogin()` from the shell console, complete the Spotify consent page, and confirm all three:

```bash
test -s ~/.local/state/quickspot/oauth.json && echo "token file written"
jq -e '.refresh_token | length > 0' ~/.local/state/quickspot/oauth.json
ls -ld ~/.local/state/quickspot
```

Expected: the browser tab reads "QuickSpot is connected", the token file contains a non-empty `refresh_token`, and the directory mode is `drwx------`.

If Spotify shows an `INVALID_CLIENT: Invalid redirect URI` error, the dashboard entry and `redirectPort` disagree.

- [ ] **Step 6: Commit and push**

```bash
git add Service.qml
git commit -m "feat: add OAuth PKCE login and token refresh to the service"
git push origin main
```

---

### Task 7: `Service.qml` — search, device resolution, and playback

**Files:**
- Modify: `Service.qml` (add imports at the top, append functions before the final closing brace)

**Interfaces:**
- Consumes: `withToken(callback)` and `clearAuth(message)` from Task 6; `Api.js` from Task 3; `Search.js` from Task 4.
- Produces, on the service root:
  - `function search(query, callback)` — invokes `callback(rows, errorString)`
  - `function cancelSearch()`
  - `function playTrack(row, callback)` — invokes `callback(errorString)`
  - `function queueTrack(row, callback)` — invokes `callback(errorString)`
  - `function playAlbum(row, callback)` — invokes `callback(errorString)`

- [ ] **Step 1: Add the three new imports**

At the top of `Service.qml`, below the existing `import "Auth.js" as Auth`:

```qml
import Quickshell.Services.Mpris

import "Api.js" as Api
import "Search.js" as Search
```

- [ ] **Step 2: Append the search and playback functions**

Insert before the closing brace of the `QtObject`:

```qml
  property int searchSerial: 0

  function cancelSearch() { searchSerial++ }

  function search(query, callback) {
    searchSerial++
    var serial = searchSerial
    if (String(query).trim() === "") { callback([], ""); return }

    withToken(function(token, error) {
      if (error) { callback([], error); return }
      if (serial !== root.searchSerial) return

      var request = new XMLHttpRequest()
      request.open("GET", Api.searchUrl(query, 20))
      request.setRequestHeader("Authorization", "Bearer " + token)
      request.onreadystatechange = function() {
        if (request.readyState !== XMLHttpRequest.DONE) return
        if (serial !== root.searchSerial) return
        if (request.status === 200) { callback(Search.toRows(request.responseText), ""); return }
        var classified = Api.classifyError(request.status, request.responseText)
        if (classified.kind === "unauthorized") root.clearAuth("Spotify sign-in expired, sign in again")
        callback([], classified.message)
      }
      request.send()
    })
  }

  // Resolves the active Connect device and hands it to `action(token, deviceId)`.
  // An empty device id means nothing is active, and each caller decides whether
  // an MPRIS fallback applies to its verb.
  function withDevice(action, onError) {
    withToken(function(token, error) {
      if (error) { onError(error); return }
      var request = new XMLHttpRequest()
      request.open("GET", Api.devicesUrl())
      request.setRequestHeader("Authorization", "Bearer " + token)
      request.onreadystatechange = function() {
        if (request.readyState !== XMLHttpRequest.DONE) return
        if (request.status !== 200) {
          var classified = Api.classifyError(request.status, request.responseText)
          if (classified.kind === "unauthorized") root.clearAuth("Spotify sign-in expired, sign in again")
          onError(classified.message)
          return
        }
        action(token, Api.activeDeviceId(request.responseText))
      }
      request.send()
    })
  }

  function sendPlayback(method, url, body, token, callback) {
    var request = new XMLHttpRequest()
    request.open(method, url)
    request.setRequestHeader("Authorization", "Bearer " + token)
    request.setRequestHeader("Content-Type", "application/json")
    request.onreadystatechange = function() {
      if (request.readyState !== XMLHttpRequest.DONE) return
      if (request.status >= 200 && request.status < 300) { callback(""); return }
      var classified = Api.classifyError(request.status, request.responseText)
      if (classified.kind === "unauthorized") root.clearAuth("Spotify sign-in expired, sign in again")
      callback(classified.message)
    }
    request.send(body === "" ? undefined : body)
  }

  // The local librespot daemon, when it is running.
  function localPlayer() {
    var players = Mpris.players.values
    for (var i = 0; i < players.length; i++)
      if (String(players[i].dbusName || "").indexOf("OmarchySpotify") !== -1) return players[i]
    return null
  }

  function playTrack(row, callback) {
    withDevice(function(token, deviceId) {
      if (deviceId === "") {
        var player = root.localPlayer()
        if (player) { player.openUri(row.uri); callback(""); return }
        callback("No Spotify device available. Open Omarchy Spotify or start playback somewhere.")
        return
      }
      root.sendPlayback("PUT", Api.playUrl(deviceId), Api.playTrackBody(row.uri), token, callback)
    }, callback)
  }

  function queueTrack(row, callback) {
    withDevice(function(token, deviceId) {
      if (deviceId === "") { callback("Queueing needs an active Spotify device"); return }
      root.sendPlayback("POST", Api.queueUrl(row.uri, deviceId), "", token, callback)
    }, callback)
  }

  function playAlbum(row, callback) {
    if (!row.albumUri) { callback("This track has no album"); return }
    withDevice(function(token, deviceId) {
      if (deviceId === "") { callback("Playing an album needs an active Spotify device"); return }
      root.sendPlayback("PUT", Api.playUrl(deviceId),
        Api.playAlbumBody(row.albumUri, row.uri), token, callback)
    }, callback)
  }
```

- [ ] **Step 3: Run the test suite to confirm nothing regressed**

Run: `./run-tests.sh`
Expected: PASS — still 40 assertions. The pure modules are untouched; this confirms the QML edit did not break their imports.

- [ ] **Step 4: Verify search returns real results**

Save the file so the shell hot-reloads, then call `search("m83", function(rows, err) { console.log(err, JSON.stringify(rows)) })` from the shell console.

Expected: no error, and rows carrying populated `name`, `artists`, and `durationText`. Expect fewer than 20 rows, because dedupe removes regional duplicates.

- [ ] **Step 5: Verify playback against a live device**

With something already playing in Spotify so a device is active, call `playTrack` on a row and confirm the track changes.

- [ ] **Step 6: Verify the MPRIS fallback**

Stop all Spotify playback so no device is active, confirm the librespot daemon is still running (`busctl --user list | grep -i omarchyspotify`), then call `playTrack` again.

Expected: the local daemon starts playing the track.

This is the risk the spec flagged: `Mpris.openUri` is verified as present in Quickshell 0.3.1, but its effect on this daemon is asserted rather than observed. If nothing plays, replace `player.openUri(row.uri)` with a `Process` running:

```bash
busctl --user call <bus-name> /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player OpenUri s <uri>
```

and record the change in the spec's Playback section before moving on.

- [ ] **Step 7: Verify the no-device message**

Stop the librespot daemon so its bus name disappears, with nothing else playing, then call `playTrack`.

Expected: the callback receives "No Spotify device available. Open Omarchy Spotify or start playback somewhere." rather than silence.

- [ ] **Step 8: Commit and push**

```bash
git add Service.qml
git commit -m "feat: add search, device resolution, and playback dispatch"
git push origin main
```

---
### Task 8: `Overlay.qml` — window, entrance animation, and first-run screen

The visible half. After this task the overlay drops in on a keybind, follows the theme, and can capture a client ID, but does not yet search.

**Files:**
- Modify: `Overlay.qml` (replaces the Task 1 stub entirely)

**Interfaces:**
- Consumes: `Service.qml` from Tasks 6 and 7, reached through `shell.ensureService("io.github.rhyscole.quickspot")`.
- Produces, on the overlay root — this is the contract `shell.summon()` requires, matching `omarchy.emojis`:
  - `property bool opened`
  - `function open(payloadJson)`
  - `function close()`
  - `function toggle()`

- [ ] **Step 1: Replace `Overlay.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs.Commons
import qs.Ui

Item {
  id: root

  // Injected by the shell when the overlay is loaded (shell.qml:630).
  property var shell: null
  readonly property var service: shell ? shell.ensureService("io.github.rhyscole.quickspot") : null

  property bool opened: false
  readonly property bool needsClientId: service ? service.clientId === "" : true
  readonly property bool needsLogin: service ? (!service.authorized && !needsClientId) : false

  // Gap below the bar. 0 means derive it from the shell's own bar tokens; any
  // other value wins, which matters on third-party bars of a different height.
  readonly property int configuredTopMargin: service && service.settings
    ? (parseInt(service.settings.topMargin, 10) || 0) : 0
  readonly property int cardTopMargin: configuredTopMargin > 0
    ? configuredTopMargin
    : Style.bar.sizeHorizontal + Style.space(10)

  function open(payloadJson) {
    if (opened) return
    opened = true
    field.text = ""
    field.forceActiveFocus()
  }

  function close() {
    if (!opened) return
    opened = false
    if (service) service.cancelSearch()
  }

  function toggle() {
    if (opened) close()
    else open("")
  }

  PanelWindow {
    id: window

    // Stays mapped through the exit animation so the card can slide back out.
    visible: root.opened || card.y > -card.height

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "quickspot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: scrim
      anchors.fill: parent
      color: Color.menu.scrim
      opacity: root.opened ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: root.opened ? 200 : 150; easing.type: Easing.OutCubic }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }
    }

    Rectangle {
      id: card

      width: Math.min(640, window.width - Style.space(40))
      height: content.implicitHeight + Style.space(24)
      anchors.horizontalCenter: parent.horizontalCenter

      // The entrance: the card travels from fully above the screen edge down to
      // its resting position under the clock. Because the window is fullscreen,
      // this is ordinary QML translation and needs no layer-shell margin work.
      y: root.opened ? root.cardTopMargin : -height

      color: Color.menu.background
      radius: Style.cornerRadius
      border.color: Color.menu.border
      border.width: 1

      Behavior on y {
        NumberAnimation { duration: root.opened ? 200 : 150; easing.type: Easing.OutCubic }
      }

      // Height changes as results arrive. Animating it separately keeps the
      // list growing from reading as a second entrance.
      Behavior on height {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }

      // Swallows clicks so they do not reach the scrim's dismiss handler.
      MouseArea { anchors.fill: parent }

      ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        TextField {
          id: field
          Layout.fillWidth: true
          visible: !root.needsClientId
          placeholderText: root.needsLogin
            ? "Press Enter to sign in to Spotify"
            : "Search Spotify"

          Keys.onEscapePressed: root.close()
          onAccepted: {
            if (root.needsLogin && root.service) root.service.beginLogin()
          }
        }

        // First-run: capture the client ID here rather than in Omarchy's
        // settings panel, which is unavailable to a plugin with no bar widget.
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.needsClientId
          spacing: Style.space(6)

          Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Color.menu.text
            font.pixelSize: Style.font.body
            text: "QuickSpot needs a Spotify client ID. Create an app at "
              + "developer.spotify.com/dashboard with the redirect URI "
              + (root.service ? root.service.redirectUri : "") + " and paste the ID below."
          }

          TextField {
            id: clientIdField
            Layout.fillWidth: true
            placeholderText: "Spotify client ID"
            Keys.onEscapePressed: root.close()
            onAccepted: {
              if (text.trim() === "" || !root.service) return
              root.service.setClientId(text)
              text = ""
              field.forceActiveFocus()
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.service && root.service.authError !== ""
          wrapMode: Text.WordWrap
          color: Color.urgent
          font.pixelSize: Style.font.bodySmall
          text: root.service ? root.service.authError : ""
        }
      }
    }
  }
}
```

- [ ] **Step 2: Confirm the shell reloads the overlay without errors**

Save the file, then:

```bash
omarchy-shell shell rescanPlugins
```

Expected: no QML errors on the shell console. An unresolved `qs.Ui` or `qs.Commons` import here means the plugin directory is not on the shell's import path; check that the plugin is enabled before debugging the QML itself.

- [ ] **Step 3: Add a temporary keybind and verify the animation**

Append to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER SHIFT", "S", "Search Spotify",
  "omarchy-shell shell summon io.github.rhyscole.quickspot")
```

Then `hyprctl reload` and `hyprctl configerrors`.

Press `Super+Shift+S`. Expected: the card slides down from the top edge, settles just below the bar, horizontally centred under the clock, with the background dimmed. `Escape` and a click on the dimmed area both send it back up.

`Super+Shift+M` is already taken by `quickshell.spotify`, which is why this uses `S`.

- [ ] **Step 4: Verify theme following**

```bash
omarchy theme set catppuccin
```

Summon the overlay again and confirm its background, border, text, and scrim all changed with the theme. Then switch to a light theme and confirm the text stays legible. Any colour that does not move is a hardcoded value that must be replaced with a `Color.menu.*` token.

- [ ] **Step 5: Verify the first-run screen**

Temporarily remove the client ID:

```bash
jq '(.plugins[] | select(.id == "io.github.rhyscole.quickspot") | .clientId) = ""' \
  ~/.config/omarchy/shell.json > /tmp/quickspot-shell.json \
  && mv /tmp/quickspot-shell.json ~/.config/omarchy/shell.json
```

Summon the overlay. Expected: the explanation and paste field appear instead of the search field, and the redirect URI shown matches what the Spotify dashboard expects. Paste the client ID, press Enter, and confirm the search field replaces it and `shell.json` now carries the value:

```bash
jq '.plugins[] | select(.id == "io.github.rhyscole.quickspot")' ~/.config/omarchy/shell.json
```

- [ ] **Step 6: Commit and push**

```bash
git add Overlay.qml
git commit -m "feat: add drop-in overlay window, animation, and first-run screen"
git push origin main
```

---

### Task 9: `TrackRow.qml` and the result list

Adds the searching, the rows, the keyboard actions, and the history empty state. This completes the feature.

**Files:**
- Create: `TrackRow.qml`
- Modify: `Overlay.qml`

**Interfaces:**
- Consumes: `service.search`, `service.playTrack`, `service.queueTrack`, `service.playAlbum` from Task 7; `Recent.js` from Task 5.
- Produces: no new external interface. This is the last task that changes behaviour.

- [ ] **Step 1: Create `TrackRow.qml`**

```qml
import QtQuick
import QtQuick.Layouts

import qs.Commons

Rectangle {
  id: root

  property var row: null
  property bool selected: false

  implicitHeight: 52
  color: selected ? Color.menu.selectedBackground : "transparent"
  radius: Style.cornerRadius

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(10)

    Rectangle {
      Layout.preferredWidth: 40
      Layout.preferredHeight: 40
      radius: Style.cornerRadius
      color: Color.menu.selectedBackground
      clip: true

      Image {
        anchors.fill: parent
        source: root.row ? root.row.artworkUrl : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        color: root.selected ? Color.menu.selectedText : Color.menu.text
        font.pixelSize: Style.font.body
        text: root.row ? root.row.name : ""
      }

      Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        opacity: 0.7
        color: Color.menu.text
        font.pixelSize: Style.font.bodySmall
        text: root.row ? (root.row.artists + " · " + root.row.albumName) : ""
      }
    }

    Text {
      opacity: 0.7
      color: Color.menu.text
      font.pixelSize: Style.font.bodySmall
      text: root.row ? root.row.durationText : ""
    }
  }
}
```

- [ ] **Step 2: Add search state and history to `Overlay.qml`**

Add `import "Recent.js" as Recent` at the top, and these properties and functions to the root `Item`, below `needsLogin`:

```qml
  property var rows: []
  property var history: []
  property int selectedIndex: 0
  property string statusText: ""
  readonly property bool showingHistory: field.text.trim() === "" && rows.length === 0

  function runSearch(query) {
    if (!service) return
    if (query.trim() === "") { rows = []; statusText = ""; service.cancelSearch(); return }
    service.search(query, function(results, error) {
      root.rows = results
      root.selectedIndex = 0
      root.statusText = error !== "" ? error : (results.length === 0 ? "No results" : "")
    })
  }

  function rememberQuery(query) {
    history = Recent.insert(history, query, Recent.CAP)
    historyStore.setText(Recent.serialize(history))
  }

  function submit(modifiers) {
    if (needsLogin) { service.beginLogin(); return }

    if (showingHistory) {
      if (history.length > 0) field.text = history[selectedIndex] || history[0]
      return
    }
    if (modifiers & Qt.ControlModifier) act(function(row, done) { root.service.queueTrack(row, done) })
    else if (modifiers & Qt.ShiftModifier) act(function(row, done) { root.service.playAlbum(row, done) })
    else act(function(row, done) { root.service.playTrack(row, done) })
  }

  function act(handler) {
    if (!service || selectedIndex < 0 || selectedIndex >= rows.length) return
    var row = rows[selectedIndex]
    rememberQuery(field.text)
    handler(row, function(error) {
      if (error === "") root.close()
      else root.statusText = error
    })
  }
```

Add the debounce timer and the history file inside the root `Item`:

```qml
  Timer {
    id: debounce
    interval: 180
    onTriggered: root.runSearch(field.text)
  }

  FileView {
    id: historyStore
    path: Quickshell.env("HOME") + "/.local/state/quickspot/history.json"
    onLoaded: root.history = Recent.sanitize(text())
  }
```

This requires `import Quickshell.Io` at the top of `Overlay.qml`.

- [ ] **Step 3: Wire the field to the debounce and the action keys**

Replace the `TextField` block from Task 8 with:

```qml
        TextField {
          id: field
          Layout.fillWidth: true
          visible: !root.needsClientId
          placeholderText: root.needsLogin
            ? "Press Enter to sign in to Spotify"
            : "Search Spotify"

          onTextChanged: {
            if (root.needsLogin) return
            root.statusText = ""
            debounce.restart()
          }

          Keys.onEscapePressed: root.close()
          Keys.onUpPressed: root.selectedIndex = Math.max(0, root.selectedIndex - 1)
          Keys.onDownPressed: root.selectedIndex = Math.min(root.rows.length - 1, root.selectedIndex + 1)
          Keys.onTabPressed: root.selectedIndex = root.rows.length === 0
            ? 0
            : (root.selectedIndex + 1) % root.rows.length

          // Both handlers delegate to root.submit(): an attached signal handler
          // cannot be invoked as a function, so the shared body lives on the root.
          Keys.onReturnPressed: function(event) { root.submit(event.modifiers) }
          Keys.onEnterPressed: function(event) { root.submit(event.modifiers) }
        }
```

- [ ] **Step 4: Add the list, status row, and hint row**

Insert into the `ColumnLayout` after the error `Text` from Task 8:

```qml
        ListView {
          id: list
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(contentHeight, 320)
          visible: root.rows.length > 0
          clip: true
          interactive: contentHeight > height
          currentIndex: root.selectedIndex
          model: root.rows

          delegate: TrackRow {
            required property int index
            required property var modelData
            width: list.width
            row: modelData
            selected: index === root.selectedIndex

            MouseArea {
              anchors.fill: parent
              onClicked: {
                root.selectedIndex = index
                root.act(function(row, done) { root.service.playTrack(row, done) })
              }
            }
          }
        }

        ListView {
          Layout.fillWidth: true
          Layout.preferredHeight: Math.min(contentHeight, 240)
          visible: root.showingHistory && root.history.length > 0 && !root.needsClientId && !root.needsLogin
          clip: true
          model: root.history

          delegate: Text {
            required property int index
            required property string modelData
            width: parent ? parent.width : 0
            height: 28
            verticalAlignment: Text.AlignVCenter
            leftPadding: Style.space(8)
            elide: Text.ElideRight
            opacity: 0.7
            color: Color.menu.text
            font.pixelSize: Style.font.body
            text: modelData

            MouseArea {
              anchors.fill: parent
              onClicked: field.text = modelData
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.statusText !== ""
          wrapMode: Text.WordWrap
          opacity: 0.8
          color: Color.menu.text
          font.pixelSize: Style.font.bodySmall
          text: root.statusText
        }

        Text {
          Layout.fillWidth: true
          visible: root.rows.length > 0
          horizontalAlignment: Text.AlignRight
          opacity: 0.5
          color: Color.menu.text
          font.pixelSize: Style.font.bodySmall
          text: "↵ play    Ctrl+↵ queue    Shift+↵ album"
        }
```

- [ ] **Step 5: Reset transient state when the overlay opens**

Replace the `open` function from Task 8 with:

```qml
  function open(payloadJson) {
    if (opened) return
    opened = true
    field.text = ""
    rows = []
    selectedIndex = 0
    statusText = ""
    field.forceActiveFocus()
  }
```

- [ ] **Step 6: Run the test suite**

Run: `./run-tests.sh`
Expected: PASS — still 40 assertions. No pure module changed; this confirms `Recent.js` still imports cleanly.

- [ ] **Step 7: Verify searching and playing**

Summon the overlay and type `midnight city`. Expected: results appear after roughly a fifth of a second, the first row is highlighted using the theme's selection colour, and the hint row shows the three bindings.

- Press `Enter`: the track plays and the overlay closes.
- Summon again, arrow down one row, press `Ctrl+Enter`: that track is appended to the queue and the overlay closes.
- Summon again and press `Shift+Enter`: the track's album starts from that track.

- [ ] **Step 8: Verify history**

Summon the overlay with an empty field. Expected: the queries just run are listed, newest first, capped at 10. Click one, or press Enter on it, and the field refills and searches.

```bash
jq . ~/.local/state/quickspot/history.json
```

Expected: a JSON array of at most 10 strings.

- [ ] **Step 9: Verify failure messages surface**

Disconnect from the network and search. Expected: the status row reads "Could not reach Spotify" rather than showing an empty list with no explanation.

- [ ] **Step 10: Commit and push**

```bash
git add TrackRow.qml Overlay.qml
git commit -m "feat: add result list, keyboard actions, and search history"
git push origin main
```

---

### Task 10: README, keybind documentation, and release check

**Files:**
- Create: `README.md`
- Modify: `manifest.json` (version bump)
- Modify: `docs/superpowers/specs/2026-09-05-quickspot-design.md` (only if Task 7 Step 6 forced a change)

**Interfaces:**
- Consumes: everything.
- Produces: an installable, documented plugin.

- [ ] **Step 1: Write `README.md`**

```markdown
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

With the field empty, your recent searches are listed. Enter refills the field.

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

## What it stores

`~/.local/state/quickspot/` holds `oauth.json` (your refresh token) and
`history.json` (your recent searches). Nothing else is written and nothing
leaves your machine except requests to Spotify.

## Development

```bash
./run-tests.sh          # headless unit tests, no compositor or network needed
omarchy plugin validate .
```

The four `.js` modules are pure functions covered by `qmltestrunner`. The QML
files hold only presentation and I/O.

## Licence

MIT
```

- [ ] **Step 2: Bump the version**

In `manifest.json`, change `"version": "0.1.0"` to `"version": "1.0.0"`.

- [ ] **Step 3: Verify a clean install from the repository**

```bash
cd /tmp && rm -rf quickspot-check
git clone https://github.com/RhysCole/quickspot.git quickspot-check
omarchy plugin validate /tmp/quickspot-check
cd /tmp/quickspot-check && ./run-tests.sh
```

Expected: validation exits 0 and the suite passes from a clean checkout. This catches any file that works locally but was never committed.

- [ ] **Step 4: Confirm no secret was ever committed**

```bash
cd ~/.config/omarchy/plugins/io.github.rhyscole.quickspot
git log -p | grep -inE "refresh_token|access_token|client_id.*[A-Za-z0-9]{20}" || echo "clean"
```

Expected: `clean`. If anything matches, the history must be rewritten before the repository stays public.

- [ ] **Step 5: Reconcile the spec if the MPRIS fallback changed**

If Task 7 Step 6 required replacing `Mpris.openUri` with a `busctl` subprocess, update the Playback and Subprocesses sections of
`docs/superpowers/specs/2026-09-05-quickspot-design.md` to match, and remove the open risk from the final section. If `openUri` worked, change that risk entry to record that it was verified.

- [ ] **Step 6: Commit and push**

```bash
git add README.md manifest.json docs/
git commit -m "docs: add README and release QuickSpot 1.0.0"
git push origin main
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task: Architecture and the module table to Task 1; Auth, per-user client ID, the flow, scopes, and token storage to Tasks 2 and 6; Subprocesses to Task 2; Search, history, and failure states to Tasks 4, 5, 7 and 9; Playback, the no-device fallback and error handling to Task 7; the Overlay window, position, animation, theming and keys to Tasks 8 and 9; Settings to Tasks 6, 8 and 10; Testing to Tasks 1 through 5; Repository layout and the constraints list to Tasks 1 and 10.

**Type consistency.** `Search.toRows` produces rows with `uri`, `name`, `artists`, `albumName`, `albumUri`, `durationText`, `artworkUrl`; `TrackRow.qml` reads exactly those names, and `playTrack`, `queueTrack` and `playAlbum` read `row.uri` and `row.albumUri` only. `withToken(callback)` is defined in Task 6 and consumed under that name in Task 7. `clearAuth(message)` is defined in Task 6 and called in Task 7. `Recent.CAP` is defined in Task 5 and used in Task 9. `service.cancelSearch()` is defined in Task 7 and called in Task 8's `close()`, which is why Task 7 precedes Task 8.

**Placeholder scan.** No `TBD`, `TODO`, or "handle errors appropriately" steps remain. Every code step carries the code; every verification step carries the command and the expected output.

**Token names verified.** `Style.font.body`, `Style.font.bodySmall`, `Style.cornerRadius`, `Style.space(n)`, `Style.bar.sizeHorizontal` and the `Color.menu.*` group were each checked against `Commons/Style.qml` and `Commons/Color.qml` rather than assumed. `Color.urgent` is a top-level token, not part of the `menu` group, which is why Task 8 uses it unqualified for the auth error.

**One correction folded in during review.** An earlier draft of Task 9 had `Keys.onEnterPressed` calling `Keys.returnPressed(event)`. Attached signal handlers cannot be invoked as functions in QML, so both handlers now delegate to a `root.submit(modifiers)` function that holds the shared body. Task 8's `TextField.onAccepted` becomes redundant once Task 9 lands and should be dropped when that block is replaced.
