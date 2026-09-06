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
    // Scoped by kind: a single and the album named after it are different
    // results, and collapsing them would drop the one the user wanted.
    var key = rows[i].kind + " " + rows[i].name + " " + rows[i].artists
    if (seen[key]) continue
    seen[key] = true
    out.push(rows[i])
  }
  return out
}

// The three result kinds share one row shape so the list has a single delegate
// and one keyboard path. `kind` is what the action handler branches on.
function trackRow(item) {
  var album = item.album || {}
  return {
    kind: "track",
    id: String(item.id || ""),
    uri: String(item.uri),
    name: String(item.name || ""),
    artists: joinArtists(item.artists),
    albumName: String(album.name || ""),
    albumUri: String(album.uri || ""),
    trailing: formatDuration(item.duration_ms),
    artworkUrl: pickArtwork(album.images, 64)
  }
}

function albumRow(item) {
  return {
    kind: "album",
    id: String(item.id || ""),
    uri: String(item.uri),
    name: String(item.name || ""),
    artists: joinArtists(item.artists),
    albumName: "",
    albumUri: String(item.uri),
    trailing: "Album",
    artworkUrl: pickArtwork(item.images, 64)
  }
}

function playlistRow(item) {
  var owner = item.owner || {}
  return {
    kind: "playlist",
    id: String(item.id || ""),
    uri: String(item.uri),
    name: String(item.name || ""),
    artists: String(owner.display_name || ""),
    albumName: "",
    albumUri: "",
    trailing: "Playlist",
    artworkUrl: pickArtwork(item.images, 64)
  }
}

// Round-robin rather than one kind after another. Only three rows are visible
// at a time, so appending albums after every track would put them out of sight
// on every search; taking one of each in turn means the top result of all three
// kinds is on screen without scrolling.
function interleave(lists) {
  var out = []
  var longest = 0
  for (var i = 0; i < lists.length; i++)
    longest = Math.max(longest, lists[i].length)

  for (var rank = 0; rank < longest; rank++)
    for (var list = 0; list < lists.length; list++)
      if (rank < lists[list].length) out.push(lists[list][rank])
  return out
}

function mapItems(items, build) {
  var out = []
  var list = items || []
  for (var i = 0; i < list.length; i++) {
    // Spotify's search returns nulls among playlist items, which is not
    // documented but happens often enough to crash on.
    if (!list[i] || !list[i].uri) continue
    out.push(build(list[i]))
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
  if (typeof payload !== "object" || payload === null) return []

  var tracks = mapItems(payload.tracks && payload.tracks.items, trackRow)
  var albums = mapItems(payload.albums && payload.albums.items, albumRow)
  var playlists = mapItems(payload.playlists && payload.playlists.items, playlistRow)

  return dedupe(interleave([tracks, albums, playlists]))
}
