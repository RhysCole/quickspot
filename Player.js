.pragma library

.import "Search.js" as Search

// How often the overlay asks Spotify what is playing. Progress is interpolated
// locally between polls, so this only has to be frequent enough to notice a
// track change or a pause made from another device.
var POLL_MS = 5000

// Candidate logo paths, most specific first. The Image that renders these falls
// through to the next entry whenever one fails to load, so a path that does not
// exist on this machine costs nothing. `LOGO` is the freedesktop os-release key;
// `ID_LIKE` comes before `ID` because a derivative distribution usually ships no
// logo of its own but sits on top of one that does.
function logoCandidates(osReleaseText, override) {
  var out = []
  if (override) out.push(String(override))

  var fields = parseOsRelease(osReleaseText)
  var pixmaps = "/usr/share/pixmaps/"
  if (fields.ID_LIKE) out.push(pixmaps + fields.ID_LIKE + "linux-logo.svg")
  if (fields.ID) out.push(pixmaps + fields.ID + "-logo.svg")
  if (fields.LOGO) {
    out.push(pixmaps + fields.LOGO + ".svg")
    out.push(pixmaps + fields.LOGO + ".png")
  }
  out.push("/usr/share/omarchy/logo.svg")
  return out
}

function parseOsRelease(text) {
  var fields = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "" || line.charAt(0) === "#") continue
    var split = line.indexOf("=")
    if (split <= 0) continue
    var key = line.substring(0, split).trim()
    var value = line.substring(split + 1).trim()
    // os-release values may be quoted, and ID_LIKE may list several ids.
    value = value.replace(/^["']|["']$/g, "").split(" ")[0]
    if (value !== "") fields[key] = value
  }
  return fields
}

// An empty state is what the overlay shows when nothing is playing anywhere.
// `ok` false means "no playback", not "an error occurred" — the API answers a
// silent account with 204 No Content and an empty body.
function emptyState() {
  return {
    ok: false,
    playing: false,
    trackName: "",
    artists: "",
    albumName: "",
    artworkUrl: "",
    durationMs: 0,
    progressMs: 0,
    deviceId: ""
  }
}

function parseState(bodyText) {
  var payload
  try {
    payload = JSON.parse(String(bodyText || ""))
  } catch (e) {
    return emptyState()
  }
  if (typeof payload !== "object" || payload === null) return emptyState()

  var item = payload.item
  if (!item || !item.uri) return emptyState()

  var album = item.album || {}
  var device = payload.device || {}
  return {
    ok: true,
    playing: payload.is_playing === true,
    trackName: String(item.name || ""),
    artists: Search.joinArtists(item.artists),
    albumName: String(album.name || ""),
    artworkUrl: Search.pickArtwork(album.images, 300),
    durationMs: Math.max(0, Number(item.duration_ms) || 0),
    progressMs: Math.max(0, Number(payload.progress_ms) || 0),
    deviceId: String(device.id || "")
  }
}

function formatTime(ms) {
  return Search.formatDuration(ms)
}

function progressFraction(progressMs, durationMs) {
  var duration = Number(durationMs) || 0
  if (duration <= 0) return 0
  var fraction = (Number(progressMs) || 0) / duration
  if (fraction < 0) return 0
  if (fraction > 1) return 1
  return fraction
}

// Turns a click or drag position on the seek bar into a millisecond offset.
function seekMs(fraction, durationMs) {
  var duration = Number(durationMs) || 0
  if (duration <= 0) return 0
  var clamped = Number(fraction)
  if (isNaN(clamped) || clamped < 0) clamped = 0
  if (clamped > 1) clamped = 1
  return Math.round(clamped * duration)
}

// Local interpolation between polls. Never runs past the track length, so the
// bar parks at the end rather than overshooting while a poll is in flight.
function advance(progressMs, elapsedMs, durationMs) {
  var next = (Number(progressMs) || 0) + (Number(elapsedMs) || 0)
  var duration = Number(durationMs) || 0
  if (next < 0) return 0
  if (duration > 0 && next > duration) return duration
  return next
}
