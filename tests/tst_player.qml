import QtQuick
import QtTest

import "../Player.js" as Player

TestCase {
  name: "Player"

  readonly property string osRelease:
    'NAME="Omarchy"\n' +
    'ID=omarchy\n' +
    'ID_LIKE=arch\n' +
    '# a comment\n' +
    'LOGO=omarchy\n'

  function test_parseOsReleaseStripsQuotesAndComments() {
    var fields = Player.parseOsRelease(osRelease)
    compare(fields.NAME, "Omarchy")
    compare(fields.ID, "omarchy")
    compare(fields.ID_LIKE, "arch")
    compare(fields.LOGO, "omarchy")
  }

  function test_parseOsReleaseTakesFirstIdLike() {
    // ID_LIKE is a space-separated list; only the first entry is usable as a
    // logo basename.
    var fields = Player.parseOsRelease("ID_LIKE=\"arch debian\"\n")
    compare(fields.ID_LIKE, "arch")
  }

  function test_parseOsReleaseSurvivesGarbage() {
    var fields = Player.parseOsRelease("no-equals-sign\n=leading\n\n")
    compare(Object.keys(fields).length, 0)
  }

  function test_logoCandidatesPrefersOverrideThenDerivative() {
    var candidates = Player.logoCandidates(osRelease, "/tmp/mine.svg")
    compare(candidates[0], "/tmp/mine.svg")
    compare(candidates[1], "/usr/share/pixmaps/archlinux-logo.svg")
    verify(candidates.indexOf("/usr/share/pixmaps/omarchy-logo.svg") !== -1)
  }

  function test_logoCandidatesAlwaysEndInAShippedPath() {
    var candidates = Player.logoCandidates("", "")
    compare(candidates[candidates.length - 1], "/usr/share/omarchy/logo.svg")
  }

  function test_parseStateReadsATrack() {
    var body = JSON.stringify({
      is_playing: true,
      progress_ms: 30000,
      device: { id: "dev-1" },
      item: {
        uri: "spotify:track:1",
        name: "Bad Apple!!",
        duration_ms: 317000,
        artists: [{ name: "nomico" }, { name: "Alstroemeria" }],
        album: { name: "THE GAME", images: [{ url: "http://a/640", height: 640 }] }
      }
    })
    var state = Player.parseState(body)
    verify(state.ok)
    verify(state.playing)
    compare(state.trackName, "Bad Apple!!")
    compare(state.artists, "nomico, Alstroemeria")
    compare(state.albumName, "THE GAME")
    compare(state.artworkUrl, "http://a/640")
    compare(state.durationMs, 317000)
    compare(state.progressMs, 30000)
    compare(state.deviceId, "dev-1")
  }

  function test_parseStateTreatsMissingItemAsNothingPlaying() {
    verify(!Player.parseState(JSON.stringify({ is_playing: true })).ok)
    // 204 No Content is what a silent account returns, so the body is empty.
    verify(!Player.parseState("").ok)
    verify(!Player.parseState("not json").ok)
    verify(!Player.parseState("null").ok)
  }

  function test_progressFractionClamps() {
    compare(Player.progressFraction(0, 1000), 0)
    compare(Player.progressFraction(500, 1000), 0.5)
    compare(Player.progressFraction(2000, 1000), 1)
    compare(Player.progressFraction(-5, 1000), 0)
    // A zero-length track must not divide by zero.
    compare(Player.progressFraction(100, 0), 0)
  }

  function test_seekMsClamps() {
    compare(Player.seekMs(0.5, 1000), 500)
    compare(Player.seekMs(-1, 1000), 0)
    compare(Player.seekMs(2, 1000), 1000)
    compare(Player.seekMs(0.5, 0), 0)
    compare(Player.seekMs(NaN, 1000), 0)
  }

  function test_advanceStopsAtTheEndOfTheTrack() {
    compare(Player.advance(1000, 250, 5000), 1250)
    compare(Player.advance(4900, 250, 5000), 5000)
    compare(Player.advance(0, -50, 5000), 0)
    // An unknown duration must not clamp the position to zero.
    compare(Player.advance(1000, 250, 0), 1250)
  }

  function test_formatTimeMatchesSearchFormatting() {
    compare(Player.formatTime(0), "0:00")
    compare(Player.formatTime(65000), "1:05")
    compare(Player.formatTime(317000), "5:17")
  }
}
