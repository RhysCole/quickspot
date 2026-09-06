import QtQuick
import QtTest

import "../Palette.js" as Palette

TestCase {
  name: "Palette"

  function test_cacheKeyIsStableAndUrlSpecific() {
    compare(Palette.cacheKey("https://i.scdn.co/image/ab1"),
            Palette.cacheKey("https://i.scdn.co/image/ab1"))
    verify(Palette.cacheKey("https://i.scdn.co/image/ab1")
           !== Palette.cacheKey("https://i.scdn.co/image/ab2"))
    // Must be usable as a filename.
    verify(/^[0-9a-f]+$/.test(Palette.cacheKey("https://i.scdn.co/image/ab1")))
  }

  function test_cachePathIsEmptyWithoutAUrl() {
    compare(Palette.cachePath("/tmp/art", ""), "")
    compare(Palette.cachePath("/tmp/art", "u"), "/tmp/art/" + Palette.cacheKey("u"))
  }

  function test_downloadCommandPassesUrlAndPathAsArguments() {
    var command = Palette.downloadCommand("https://x/y", "/tmp/art/1")
    compare(command[0], "sh")
    // The URL and path are positional arguments, never interpolated into the
    // script, so a hostile filename cannot become shell syntax.
    compare(command[command.length - 2], "https://x/y")
    compare(command[command.length - 1], "/tmp/art/1")
  }

  function test_usableRejectsExtremesAndGreys() {
    verify(!Palette.usable(Qt.rgba(0, 0, 0, 1)))
    verify(!Palette.usable(Qt.rgba(1, 1, 1, 1)))
    verify(!Palette.usable(Qt.rgba(0.5, 0.5, 0.5, 1)))
    verify(Palette.usable(Qt.rgba(0.8, 0.2, 0.4, 1)))
  }

  function test_buildAlwaysReturnsTheRequestedCount() {
    var one = [Qt.rgba(0.8, 0.2, 0.4, 1)]
    compare(Palette.build(one, [], 4).length, 4)
    compare(Palette.build([], [Qt.rgba(0.2, 0.6, 0.9, 1)], 3).length, 3)
  }

  function test_buildCyclesTheColoursItKept() {
    var a = Qt.rgba(0.8, 0.2, 0.4, 1)
    var b = Qt.rgba(0.2, 0.6, 0.9, 1)
    var out = Palette.build([a, b], [], 4)
    compare(out[0], out[2])
    compare(out[1], out[3])
    verify(out[0] !== out[1])
  }

  function test_buildFallsBackWhenNothingIsUsable() {
    var fallback = Qt.rgba(0.2, 0.6, 0.9, 1)
    var out = Palette.build([Qt.rgba(0, 0, 0, 1), Qt.rgba(1, 1, 1, 1)], [fallback], 2)
    compare(out[0], fallback)
    compare(out[1], fallback)
  }

  function test_buildReturnsNothingWithNoColoursAtAll() {
    compare(Palette.build([], [], 4).length, 0)
  }

  function test_contrastRatioIsSymmetricAndBounded() {
    var black = Qt.rgba(0, 0, 0, 1)
    var white = Qt.rgba(1, 1, 1, 1)
    compare(Math.round(Palette.contrastRatio(black, white)), 21)
    compare(Palette.contrastRatio(black, white), Palette.contrastRatio(white, black))
    compare(Palette.contrastRatio(white, white), 1)
  }

  function test_readableLiftsALowContrastAlbumColour() {
    var background = Qt.rgba(0.06, 0.07, 0.08, 1)
    // A dark blue that would be unreadable on a dark card.
    var dim = Qt.hsla(0.6, 0.7, 0.18, 1)
    var out = Palette.readable([dim], background, Qt.rgba(1, 0, 0, 1), 4.5)
    verify(Palette.contrastRatio(out, background) >= 4.5)
    // Hue is preserved, so the result still belongs to the album.
    verify(Math.abs(out.hslHue - dim.hslHue) < 0.02)
  }

  function test_readableFallsBackWhenNothingWorks() {
    var fallback = Qt.rgba(0.9, 0.9, 0.2, 1)
    compare(Palette.readable([], Qt.rgba(0, 0, 0, 1), fallback, 4.5), fallback)
  }

  function test_readablePrefersTheHighestContrastCandidate() {
    var background = Qt.rgba(0, 0, 0, 1)
    var dim = Qt.hsla(0.6, 0.7, 0.12, 1)
    var bright = Qt.hsla(0.1, 0.8, 0.7, 1)
    var out = Palette.readable([dim, bright], background, Qt.rgba(1, 0, 0, 1), 4.5)
    verify(Math.abs(out.hslHue - bright.hslHue) < 0.02)
  }
}
