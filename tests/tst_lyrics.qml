import QtQuick
import QtTest

import "../Lyrics.js" as Lyrics

TestCase {
  name: "Lyrics"

  function test_lookupUrlEncodesAndOmitsWhatIsMissing() {
    var url = Lyrics.lookupUrl("I Love You", "Fontaines D.C.", "Skinty Fia", 305.4)
    verify(url.indexOf("https://lrclib.net/api/get?") === 0)
    verify(url.indexOf("track_name=I%20Love%20You") !== -1)
    verify(url.indexOf("artist_name=Fontaines%20D.C.") !== -1)
    verify(url.indexOf("duration=305") !== -1)

    var bare = Lyrics.lookupUrl("A", "B", "", 0)
    verify(bare.indexOf("album_name") === -1)
    verify(bare.indexOf("duration") === -1)
  }

  function test_parseSyncedReadsTimestamps() {
    var lines = Lyrics.parseSynced("[00:26.75] I love you\n[01:05.00] Second line\n")
    compare(lines.length, 2)
    compare(lines[0].timeMs, 26750)
    compare(lines[0].text, "I love you")
    compare(lines[1].timeMs, 65000)
  }

  function test_parseSyncedSortsAndDropsUntimedLines() {
    var lines = Lyrics.parseSynced("[00:10.00] second\nno timestamp here\n[00:05.00] first\n")
    compare(lines.length, 2)
    compare(lines[0].text, "first")
    compare(lines[1].text, "second")
  }

  function test_parseSyncedAcceptsAColonBeforeHundredths() {
    // Some LRC files use mm:ss:xx rather than mm:ss.xx.
    compare(Lyrics.parseSynced("[00:05:50] x")[0].timeMs, 5500)
  }

  function test_parseSyncedKeepsEmptyLines() {
    // A timestamped blank is an instrumental gap, and showing nothing there is
    // the correct behaviour rather than holding the previous line.
    var lines = Lyrics.parseSynced("[00:01.00] a\n[00:09.00]\n")
    compare(lines.length, 2)
    compare(lines[1].text, "")
  }

  function test_parseResponseRequiresSyncedLyrics() {
    var plainOnly = JSON.stringify({ plainLyrics: "words\nmore words", syncedLyrics: null })
    verify(!Lyrics.parseResponse(plainOnly).ok)

    var synced = JSON.stringify({ syncedLyrics: "[00:01.00] hello" })
    verify(Lyrics.parseResponse(synced).ok)
    compare(Lyrics.parseResponse(synced).lines.length, 1)
  }

  function test_parseResponseFlagsInstrumentals() {
    var body = JSON.stringify({ instrumental: true, syncedLyrics: null })
    var out = Lyrics.parseResponse(body)
    verify(!out.ok)
    verify(out.instrumental)
  }

  function test_parseResponseSurvivesGarbage() {
    verify(!Lyrics.parseResponse("").ok)
    verify(!Lyrics.parseResponse("not json").ok)
    verify(!Lyrics.parseResponse("null").ok)
  }

  function test_lineAtIsMinusOneBeforeTheFirstLine() {
    var lines = Lyrics.parseSynced("[00:10.00] a\n[00:20.00] b\n")
    compare(Lyrics.lineAt(lines, 0), -1)
    compare(Lyrics.lineAt(lines, 9999), -1)
    compare(Lyrics.lineAt(lines, 10000), 0)
    compare(Lyrics.lineAt(lines, 19999), 0)
    compare(Lyrics.lineAt(lines, 20000), 1)
    compare(Lyrics.lineAt(lines, 999999), 1)
  }

  function test_textAtReturnsEmptyOutsideTheSheet() {
    var lines = Lyrics.parseSynced("[00:10.00] a\n")
    compare(Lyrics.textAt(lines, 0), "")
    compare(Lyrics.textAt(lines, 10000), "a")
    compare(Lyrics.textAt([], 5000), "")
  }
}
