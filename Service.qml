import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

import "Auth.js" as Auth
import "Api.js" as Api
import "Search.js" as Search
import "Player.js" as Player

QtObject {
  id: root

  // Injected by the shell when the service is mounted (shell.qml:306).
  property var shell: null

  // Settings live in one of two places in shell.json, and which one depends on
  // whether the plugin has been given a place on the bar. updateEntryInline()
  // writes into bar.layout when it finds the id there and falls back to the
  // top-level plugins[] array otherwise, so reading only plugins[] loses the
  // settings of a bar-placed plugin entirely — including the client ID, which
  // then looks like the first-run screen refusing to accept it.
  //
  // Derived rather than assigned, so an external edit to shell.json is picked
  // up without a restart.
  readonly property var settings: {
    var config = (shell && shell.shellConfig) || {}

    var layout = (config.bar && config.bar.layout) || {}
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var entries = layout[sections[s]] || []
      for (var i = 0; i < entries.length; i++)
        if (entries[i] && entries[i].id === "io.github.rhyscole.quickspot") return entries[i]
    }

    var plugins = config.plugins || []
    for (var j = 0; j < plugins.length; j++)
      if (plugins[j] && plugins[j].id === "io.github.rhyscole.quickspot") return plugins[j]

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

  // What Spotify's Web API last said was playing. Only used when there is no
  // local media player to read instead.
  property var apiPlayback: Player.emptyState()

  // The MPRIS player transport commands go to: whichever one is actually
  // playing, else any that can be controlled. Deliberately not restricted to
  // Spotify — a browser playing YouTube exports the same interface, and the
  // controls should work on it for the same reason the keyboard's media keys
  // do.
  readonly property var mprisPlayer: {
    var players = Mpris.players.values
    var controllable = null
    for (var i = 0; i < players.length; i++) {
      var candidate = players[i]
      if (!candidate || !candidate.canControl) continue
      if (candidate.isPlaying) return candidate
      if (controllable === null) controllable = candidate
    }
    return controllable
  }

  readonly property bool localControl: mprisPlayer !== null

  // What the current player will actually accept. A browser playing a video
  // often has no previous track, and a live stream cannot be seeked; greying
  // those out beats a button that silently does nothing.
  readonly property bool canGoNext: localControl
    ? mprisPlayer.canGoNext : apiPlayback.ok
  readonly property bool canGoPrevious: localControl
    ? mprisPlayer.canGoPrevious : apiPlayback.ok
  readonly property bool canSeek: localControl
    ? (mprisPlayer.canSeek && mprisPlayer.positionSupported && mprisPlayer.lengthSupported)
    : (apiPlayback.ok && apiPlayback.durationMs > 0)
  readonly property bool canTogglePlay: localControl
    ? mprisPlayer.canTogglePlaying : apiPlayback.ok

  // Which app the controls are pointed at, for the panel to name when it is
  // something other than Spotify.
  readonly property string localIdentity: localControl
    ? String(mprisPlayer.identity || "") : ""

  // What is playing right now. A local player is preferred over the Web API:
  // its state arrives on D-Bus property changes rather than a five-second
  // poll, and it is correct for players Spotify knows nothing about.
  readonly property var playback: localControl ? mprisPlayback : apiPlayback

  readonly property var mprisPlayback: {
    var player = mprisPlayer
    if (!player) return Player.emptyState()
    return {
      ok: String(player.trackTitle || "") !== "",
      playing: player.isPlaying === true,
      trackName: String(player.trackTitle || ""),
      artists: String(player.trackArtist || ""),
      albumName: String(player.trackAlbum || ""),
      artworkUrl: String(player.trackArtUrl || ""),
      durationMs: Math.max(0, (Number(player.length) || 0) * 1000),
      progressMs: Math.max(0, (Number(player.position) || 0) * 1000),
      deviceId: ""
    }
  }
  // Interpolated locally between polls so the seek bar moves at frame rate
  // instead of stepping once every POLL_MS.
  property double playbackProgressMs: 0
  property int playbackWatchers: 0
  // The next few tracks Spotify will play, read on the same cycle as playback.
  property var queue: []
  readonly property int queueLength: 5
  property string pkceVerifier: ""
  property string oauthState: ""
  property var tokenWaiters: []
  property bool callbackHandled: false

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
    callbackHandled = false
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
      "STDIO"
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

    callbackHandled = true
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
    onExited: function(exitCode) {
      if (root.loginBusy && !root.callbackHandled)
        root.failLogin("Spotify sign-in did not complete")
    }
  }

  property FileView tokenStore: FileView {
    path: root.statePath + "/oauth.json"
    onLoaded: {
      try {
        var stored = JSON.parse(text())
        if (stored && stored.refresh_token) {
          root.refreshToken = String(stored.refresh_token)
          // Read the player once at startup so the first time the overlay is
          // opened it already knows the track — and the background already has
          // the album's colours — instead of showing the previous state until
          // the first poll lands.
          primePoll.start()
        }
      } catch (e) {}
    }
  }

  // Delayed so the request does not compete with the rest of the shell coming
  // up. One call per shell start; polling proper only runs with the overlay open.
  property Timer primePoll: Timer {
    interval: 2000
    repeat: false
    onTriggered: root.pollPlayback()
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

  property int searchSerial: 0

  function cancelSearch() { searchSerial++ }

  function search(query, callback) {
    searchSerial++
    var serial = searchSerial
    if (String(query).trim() === "") { callback([], ""); return }

    withToken(function(token, error) {
      if (serial !== root.searchSerial) return
      if (error) { callback([], error); return }

      var request = new XMLHttpRequest()
      request.open("GET", Api.searchUrl(query, Api.MAX_SEARCH_LIMIT))
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

  // A local Spotify specifically — the desktop client or the librespot daemon.
  // Distinct from `mprisPlayer`: handing a Spotify track URI to whatever
  // happens to be playing would mean asking a browser to open it.
  function localPlayer() {
    var players = Mpris.players.values
    for (var i = 0; i < players.length; i++) {
      var name = String(players[i].dbusName || "").toLowerCase()
      if (name.indexOf("spotify") !== -1) return players[i]
    }
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
    if (row.kind !== "track") { callback("Only tracks can be queued"); return }
    withDevice(function(token, deviceId) {
      if (deviceId === "") { callback("Queueing needs an active Spotify device"); return }
      root.sendPlayback("POST", Api.queueUrl(row.uri, deviceId), "", token, callback)
    }, callback)
  }

  // Albums and playlists are both "contexts" to Spotify, and a track played in
  // the context of its album is the same call with an offset. One verb, three
  // callers.
  function playContext(contextUri, offsetUri, callback) {
    if (!contextUri) { callback("Nothing to play"); return }
    withDevice(function(token, deviceId) {
      if (deviceId === "") { callback("Playing this needs an active Spotify device"); return }
      root.sendPlayback("PUT", Api.playUrl(deviceId),
        Api.playContextBody(contextUri, offsetUri), token, callback)
    }, callback)
  }

  // The action for a result row, chosen by what kind of thing it is: a track
  // plays on its own, an album or playlist plays as a context.
  function playRow(row, callback) {
    if (row.kind === "track") { playTrack(row, callback); return }
    playContext(row.uri, "", callback)
  }

  function playAlbumOf(row, callback) {
    if (row.kind !== "track") { playContext(row.uri, "", callback); return }
    if (!row.albumUri) { callback("This track has no album"); return }
    playContext(row.albumUri, row.uri, callback)
  }

  // ---------------------------------------------------------- playback

  // The overlay calls these on open/close. Polling only runs while something
  // is watching, so a closed overlay costs no API quota and no wakeups.
  function watchPlayback() {
    playbackWatchers++
    if (playbackWatchers === 1) {
      pollPlayback()
      pollQueue()
      playbackPoll.start()
      progressTick.start()
    }
  }

  function unwatchPlayback() {
    playbackWatchers = Math.max(0, playbackWatchers - 1)
    if (playbackWatchers === 0) {
      playbackPoll.stop()
      progressTick.stop()
    }
  }

  // Asks for the player state shortly from now. Used after an action that
  // changes what is playing: Spotify applies those asynchronously, so polling
  // in the same instant returns the state from before the command.
  function refreshPlayback() {
    transportSettle.restart()
  }

  function pollPlayback() {
    if (refreshToken === "") return
    // A local player is already the source of truth, so this would be a
    // request every five seconds whose answer is discarded.
    if (localControl) return
    withToken(function(token, error) {
      if (error) return
      var request = new XMLHttpRequest()
      request.open("GET", Api.playerUrl())
      request.setRequestHeader("Authorization", "Bearer " + token)
      request.onreadystatechange = function() {
        if (request.readyState !== XMLHttpRequest.DONE) return
        // 204 is the documented answer when nothing is playing anywhere.
        if (request.status === 204) { root.applyPlayback(Player.emptyState()); return }
        if (request.status !== 200) {
          var classified = Api.classifyError(request.status, request.responseText)
          if (classified.kind === "unauthorized") root.clearAuth("Spotify sign-in expired, sign in again")
          return
        }
        root.applyPlayback(Player.parseState(request.responseText))
      }
      request.send()
    })
  }

  function pollQueue() {
    if (refreshToken === "") return
    withToken(function(token, error) {
      if (error) return
      var request = new XMLHttpRequest()
      request.open("GET", Api.queueListUrl())
      request.setRequestHeader("Authorization", "Bearer " + token)
      request.onreadystatechange = function() {
        if (request.readyState !== XMLHttpRequest.DONE) return
        // 204 is the answer when nothing is playing, and there is no queue
        // without something to queue behind.
        if (request.status === 204) { root.queue = []; return }
        if (request.status !== 200) return
        root.queue = Player.parseQueue(request.responseText, root.queueLength)
      }
      request.send()
    })
  }

  function applyPlayback(state) {
    apiPlayback = state
    if (!localControl) playbackProgressMs = state.progressMs
  }

  // Transport verbs share a shape: act on the device Spotify already considers
  // active, then re-poll straight away so the UI reflects the change without
  // waiting out the poll interval.
  function sendTransport(method, url, callback) {
    withToken(function(token, error) {
      if (error) { callback(error); return }
      root.sendPlayback(method, url, "", token, function(sendError) {
        callback(sendError)
        if (sendError === "") transportSettle.restart()
      })
    })
  }

  // Every transport verb goes over D-Bus when a local player exists: it is a
  // call to a process on this machine rather than a network round trip, it
  // needs no token, and it cannot fail the way the Web API does when Spotify
  // has quietly deactivated the device that was playing a moment ago. The Web
  // API path stays for controlling a device that is not local, such as a phone.
  function togglePlay(callback) {
    if (localControl) { mprisPlayer.togglePlaying(); callback(""); return }
    var verb = apiPlayback.playing ? "pause" : "play"
    sendTransport("PUT", Api.transportUrl(verb, apiPlayback.deviceId, ""), callback)
  }

  function nextTrack(callback) {
    if (localControl) { mprisPlayer.next(); callback(""); return }
    sendTransport("POST", Api.transportUrl("next", apiPlayback.deviceId, ""), callback)
  }

  function previousTrack(callback) {
    if (localControl) { mprisPlayer.previous(); callback(""); return }
    sendTransport("POST", Api.transportUrl("previous", apiPlayback.deviceId, ""), callback)
  }

  function seekTo(positionMs, callback) {
    playbackProgressMs = positionMs
    if (localControl) {
      // MprisPlayer.position is writable and in seconds; seek() is relative.
      mprisPlayer.position = positionMs / 1000
      callback("")
      return
    }
    sendTransport("PUT", Api.seekUrl(positionMs, apiPlayback.deviceId), callback)
  }

  property Timer playbackPoll: Timer {
    interval: Player.POLL_MS
    repeat: true
    onTriggered: {
      root.pollPlayback()
      root.pollQueue()
    }
  }

  // Spotify applies a transport command asynchronously: polling in the same
  // instant usually returns the pre-command state. A short delay makes the
  // confirming poll land after the change has taken effect.
  property Timer transportSettle: Timer {
    interval: 400
    repeat: false
    onTriggered: {
      root.pollPlayback()
      root.pollQueue()
    }
  }

  property Timer progressTick: Timer {
    interval: 250
    repeat: true
    onTriggered: {
      if (!root.playback.ok || !root.playback.playing) return
      // MPRIS exposes a real position, so read it rather than guessing. The
      // property does not reliably signal on its own, which is why this is
      // still a timer rather than a binding.
      if (root.localControl) {
        root.playbackProgressMs = Math.max(0, (Number(root.mprisPlayer.position) || 0) * 1000)
        return
      }
      root.playbackProgressMs = Player.advance(root.playbackProgressMs, interval,
                                               root.playback.durationMs)
    }
  }

}
