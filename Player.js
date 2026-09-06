.pragma library

.import "Search.js" as Search

// How often the overlay asks Spotify what is playing. Progress is interpolated
// locally between polls, so this only has to be frequent enough to notice a
// track change or a pause made from another device.
var POLL_MS = 5000

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

// The next few tracks Spotify will play. Only the fields the column shows are
// kept; `id` is absent from some queue entries, so the index is what makes a
// row unique — a queue legitimately repeats the same track.
function parseQueue(bodyText, limit) {
  var payload
  try {
    payload = JSON.parse(String(bodyText || ""))
  } catch (e) {
    return []
  }
  if (typeof payload !== "object" || payload === null) return []

  var items = payload.queue || []
  var max = Math.max(0, Number(limit) || 0)
  var out = []
  for (var i = 0; i < items.length && out.length < max; i++) {
    var item = items[i]
    if (!item || !item.name) continue
    out.push({
      name: String(item.name),
      artists: Search.joinArtists(item.artists)
    })
  }
  return out
}
