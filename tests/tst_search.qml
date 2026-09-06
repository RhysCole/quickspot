import QtQuick
import QtTest

import "../Search.js" as Search

TestCase {
  name: "Search"

  property string fixture: ""

  function initTestCase() {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("fixtures/search-tracks.json"), false)
    request.send(null)
    fixture = request.responseText
    verify(fixture.length > 0)
  }

  function test_formatDurationPadsSeconds() {
    compare(Search.formatDuration(243000), "4:03")
    compare(Search.formatDuration(381000), "6:21")
    compare(Search.formatDuration(59000), "0:59")
    compare(Search.formatDuration(0), "0:00")
    compare(Search.formatDuration(-5), "0:00")
  }

  function test_joinArtistsUsesCommas() {
    compare(Search.joinArtists([{ name: "M83" }]), "M83")
    compare(Search.joinArtists([{ name: "M83" }, { name: "Eric Prydz" }]), "M83, Eric Prydz")
    compare(Search.joinArtists([]), "")
  }

  function test_pickArtworkChoosesSmallestAboveMinimum() {
    var images = [
      { url: "large", height: 640 },
      { url: "medium", height: 300 },
      { url: "small", height: 64 }
    ]
    compare(Search.pickArtwork(images, 64), "small")
    compare(Search.pickArtwork(images, 100), "medium")
    compare(Search.pickArtwork(images, 700), "large")
    compare(Search.pickArtwork([], 64), "")
  }

  function test_toRowsMapsEveryField() {
    var rows = Search.toRows(fixture)
    compare(rows[0].id, "trk1")
    compare(rows[0].uri, "spotify:track:trk1")
    compare(rows[0].name, "Midnight City")
    compare(rows[0].artists, "M83")
    compare(rows[0].albumName, "Hurry Up, We're Dreaming")
    compare(rows[0].albumUri, "spotify:album:alb1")
    compare(rows[0].kind, "track")
    compare(rows[0].trailing, "4:03")
    compare(rows[0].artworkUrl, "https://example.invalid/small.jpg")
  }

  function test_toRowsDedupesSameNameAndArtists() {
    var rows = Search.toRows(fixture)
    compare(rows.length, 2)
    compare(rows[0].id, "trk1")
    compare(rows[1].id, "trk3")
  }

  function test_dedupeKeepsDistinctArtistSets() {
    var rows = Search.dedupe([
      { name: "Song", artists: "A" },
      { name: "Song", artists: "B" },
      { name: "Song", artists: "A" }
    ])
    compare(rows.length, 2)
  }

  function test_dedupeKeepsTheFirstOccurrence() {
    var rows = Search.dedupe([
      { name: "Song", artists: "A", id: "first" },
      { name: "Song", artists: "A", id: "second" }
    ])
    compare(rows.length, 1)
    compare(rows[0].id, "first")
  }

  function test_toRowsReturnsEmptyOnGarbage() {
    compare(Search.toRows("not json").length, 0)
    compare(Search.toRows("").length, 0)
    compare(Search.toRows(JSON.stringify({})).length, 0)
    compare(Search.toRows("null").length, 0)
    compare(Search.toRows("42").length, 0)
  }

  function test_toRowsReadsAlbumsAndPlaylists() {
    var body = JSON.stringify({
      albums: { items: [{
        uri: "spotify:album:a1", id: "a1", name: "Skinty Fia",
        artists: [{ name: "Fontaines D.C." }],
        images: [{ url: "http://art/a1", height: 300 }]
      }]},
      playlists: { items: [{
        uri: "spotify:playlist:p1", id: "p1", name: "Post Punk",
        owner: { display_name: "Rhys" },
        images: [{ url: "http://art/p1", height: 300 }]
      }]}
    })
    var rows = Search.toRows(body)
    compare(rows.length, 2)
    compare(rows[0].kind, "album")
    compare(rows[0].artists, "Fontaines D.C.")
    compare(rows[0].trailing, "Album")
    compare(rows[1].kind, "playlist")
    compare(rows[1].artists, "Rhys")
    compare(rows[1].trailing, "Playlist")
    compare(rows[1].artworkUrl, "http://art/p1")
  }

  function test_toRowsInterleavesTheThreeKinds() {
    function items(prefix, count) {
      var out = []
      for (var i = 0; i < count; i++)
        out.push({ uri: "spotify:x:" + prefix + i, id: prefix + i, name: prefix + i,
                   artists: [{ name: "A" }], album: { name: "Al", uri: "spotify:album:z", images: [] },
                   owner: { display_name: "O" }, images: [] })
      return out
    }
    var body = JSON.stringify({
      tracks: { items: items("t", 2) },
      albums: { items: items("a", 2) },
      playlists: { items: items("p", 2) }
    })
    var rows = Search.toRows(body)
    // One of each kind lands in the three visible rows.
    compare(rows[0].kind, "track")
    compare(rows[1].kind, "album")
    compare(rows[2].kind, "playlist")
    compare(rows.length, 6)
  }

  function test_toRowsSkipsNullPlaylistItems() {
    // Spotify's search really does return nulls among playlist items.
    var body = JSON.stringify({ playlists: { items: [null, { uri: "spotify:playlist:p", name: "P" }] } })
    var rows = Search.toRows(body)
    compare(rows.length, 1)
    compare(rows[0].name, "P")
  }

  function test_dedupeKeepsATrackAndAnAlbumOfTheSameName() {
    var body = JSON.stringify({
      tracks: { items: [{ uri: "spotify:track:1", name: "Roman Holiday",
                          artists: [{ name: "Fontaines D.C." }],
                          album: { name: "A Hero's Death", uri: "spotify:album:h", images: [] } }] },
      albums: { items: [{ uri: "spotify:album:2", name: "Roman Holiday",
                          artists: [{ name: "Fontaines D.C." }], images: [] }] }
    })
    compare(Search.toRows(body).length, 2)
  }
}
