.pragma library

// Lyrics come from LRCLIB, which is keyless, free, and what most open-source
// players use. Spotify's own lyrics are not in the Web API at all — the client
// reads them from a private endpoint that needs a different token — so there is
// nothing to use there even with an account.
var BASE = "https://lrclib.net/api/get"

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
