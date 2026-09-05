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
