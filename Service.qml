import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

import "Auth.js" as Auth
import "Api.js" as Api
import "Search.js" as Search

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
}
