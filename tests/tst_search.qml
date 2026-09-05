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
    compare(rows[0].durationText, "4:03")
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
}
