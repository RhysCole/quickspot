.pragma library

// Lyrics come from LRCLIB, which is keyless, free, and what most open-source
// players use. Spotify's own lyrics are not in the Web API at all — the client
// reads them from a private endpoint that needs a different token — so there is
// nothing to use there even with an account.
var BASE = "https://lrclib.net/api/get"
var SEARCH = "https://lrclib.net/api/search"

// How far a candidate's length may sit from the track's before it is treated
// as a different recording. Three seconds absorbs the usual disagreement
// between what a player reports and what was submitted, without letting an
// extended mix through.
var DURATION_TOLERANCE_SEC = 3

// Only synced lyrics are shown. A wall of unsynced text is not what a one-line
// strip under the transport controls is for, and showing the wrong line is
// worse than showing none.
function lookupUrl(trackName, artistName, albumName, durationSec) {
  var query = ["track_name=" + encodeURIComponent(String(trackName || "")),
               "artist_name=" + encodeURIComponent(String(artistName || ""))]
  if (albumName) query.push("album_name=" + encodeURIComponent(String(albumName)))
  // Duration narrows the match to the right recording, but a live or remastered
  // cut whose length differs by more than a couple of seconds misses entirely,
  // which is why the caller retries without it.
  var duration = Math.round(Number(durationSec) || 0)
  if (duration > 0) query.push("duration=" + duration)
  return BASE + "?" + query.join("&")
}

// /api/get returns exactly one record, chosen by exact match, and that record
// frequently has plain lyrics only while other records of the same song carry
// timed ones. Searching returns all of them, so a miss is recoverable.
function searchUrl(trackName, artistName) {
  return SEARCH + "?track_name=" + encodeURIComponent(String(trackName || ""))
    + "&artist_name=" + encodeURIComponent(String(artistName || ""))
}

// The best search result that actually has timed lyrics. Length is the only
// signal worth ranking on: album strings vary wildly between submissions of
// the same recording, but a track that is 40 seconds longer is a different cut.
function pickSynced(results, durationSec) {
  var list = results || []
  var target = Number(durationSec) || 0
  var fallback = null

  for (var i = 0; i < list.length; i++) {
    var candidate = list[i]
    if (!candidate || !candidate.syncedLyrics) continue
    if (candidate.instrumental === true) continue
    if (fallback === null) fallback = candidate
    if (target <= 0) return candidate
    if (Math.abs((Number(candidate.duration) || 0) - target) <= DURATION_TOLERANCE_SEC)
      return candidate
  }
  // Nothing matched on length. A timed sheet for the wrong cut drifts, so it is
  // only worth using when the track's own length is unknown.
  return target > 0 ? null : fallback
}

function parseSearch(bodyText, durationSec) {
  var payload
  try {
    payload = JSON.parse(String(bodyText || ""))
  } catch (e) {
    return { ok: false, instrumental: false, lines: [] }
  }
  if (!Array.isArray(payload)) return { ok: false, instrumental: false, lines: [] }

  var best = pickSynced(payload, durationSec)
  if (!best) return { ok: false, instrumental: false, lines: [] }

  var lines = parseSynced(best.syncedLyrics)
  return { ok: lines.length > 0, instrumental: false, lines: lines }
}

// "[mm:ss.xx] text" per line. Lines without a timestamp are dropped rather than
// guessed at, and the result is sorted because a file is not required to be.
function parseSynced(text) {
  var lines = String(text || "").split("\n")
  var out = []

  for (var i = 0; i < lines.length; i++) {
    var match = /^\s*\[(\d+):(\d+(?:[.:]\d+)?)\]\s*(.*)$/.exec(lines[i])
    if (!match) continue

    var minutes = parseInt(match[1], 10)
    var seconds = parseFloat(String(match[2]).replace(":", "."))
    if (isNaN(minutes) || isNaN(seconds)) continue

    out.push({
      timeMs: Math.round((minutes * 60 + seconds) * 1000),
      text: String(match[3]).trim()
    })
  }

  out.sort(function(a, b) { return a.timeMs - b.timeMs })
  return out
}

function parseResponse(bodyText) {
  var payload
  try {
    payload = JSON.parse(String(bodyText || ""))
  } catch (e) {
    return { ok: false, instrumental: false, lines: [] }
  }
  if (typeof payload !== "object" || payload === null)
    return { ok: false, instrumental: false, lines: [] }

  if (payload.instrumental === true)
    return { ok: false, instrumental: true, lines: [] }

  var lines = parseSynced(payload.syncedLyrics)
  return { ok: lines.length > 0, instrumental: false, lines: lines }
}

// Index of the line that should be showing at `positionMs`, or -1 before the
// first one starts. Walks forward rather than binary-searching: a lyric sheet
// is a few dozen lines and this runs four times a second.
function lineAt(lines, positionMs) {
  var list = lines || []
  var position = Number(positionMs) || 0
  var found = -1
  for (var i = 0; i < list.length; i++) {
    if (list[i].timeMs > position) break
    found = i
  }
  return found
}

function textAt(lines, positionMs) {
  var index = lineAt(lines, positionMs)
  return index < 0 ? "" : lines[index].text
}

// --- word sweep --------------------------------------------------------

// How long the last line of a sheet is assumed to run for, since nothing
// follows it to measure against.
var TRAILING_LINE_MS = 4000

// LRCLIB's lyrics are timed per line, never per word: enhanced LRC with inline
// <mm:ss.xx> tags does not appear in its data at all. So the sweep across a
// line is interpolated from the line's own span, weighting each word by its
// length. It tracks a sung line closely enough to read along with, but it is an
// approximation, not the real vocal timing Spotify has.
function splitWords(text) {
  var raw = String(text || "").split(/\s+/)
  var words = []
  var total = 0

  for (var i = 0; i < raw.length; i++) {
    if (raw[i] === "") continue
    // The +1 stands in for the space that follows, so a run of short words does
    // not sweep faster than the singer says them.
    var weight = raw[i].length + 1
    words.push({ text: raw[i], weight: weight })
    total += weight
  }
  if (total === 0) return []

  var elapsed = 0
  for (var j = 0; j < words.length; j++) {
    words[j].start = elapsed / total
    elapsed += words[j].weight
    words[j].end = elapsed / total
  }
  return words
}

// How far through line `index` the track has got, 0 to 1.
function lineProgress(lines, index, positionMs) {
  var list = lines || []
  if (index < 0 || index >= list.length) return 0

  var start = list[index].timeMs
  var end = index + 1 < list.length ? list[index + 1].timeMs : start + TRAILING_LINE_MS
  var span = end - start
  if (span <= 0) return 1

  var fraction = ((Number(positionMs) || 0) - start) / span
  if (fraction < 0) return 0
  if (fraction > 1) return 1
  return fraction
}

// The line before and after the current one, for the faded context above and
// below. Empty strings where there is nothing to show.
function neighbours(lines, index) {
  var list = lines || []
  return {
    previous: index > 0 ? list[index - 1].text : "",
    next: index >= -1 && index + 1 < list.length ? list[index + 1].text : ""
  }
}
