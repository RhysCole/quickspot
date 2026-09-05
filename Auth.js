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
