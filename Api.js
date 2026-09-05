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
