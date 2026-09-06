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
    // Must not skip the fetch when a file is already there: a stale entry from
    // an earlier track is indistinguishable from a fresh one.
    verify(command[2].indexOf("-s ") === -1)
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

  function test_buildGivesAMonochromeSleeveWhiteNotTheTheme() {
    // A black cover quantizes to colours that are all unusable. Falling through
    // to the theme there made it come up in whatever hue the theme happens to
    // use, which looks like a bug because nothing on screen explains it.
    var themed = Qt.rgba(0.2, 0.9, 0.3, 1)
    var out = Palette.build([Qt.rgba(0, 0, 0, 1), Qt.rgba(0.02, 0.02, 0.02, 1)], [themed], 2)
    compare(out.length, 2)
    verify(out[0] !== themed)
    verify(out[0].r > 0.6 && out[0].g > 0.6 && out[0].b > 0.6)
  }

  function test_buildUsesTheThemeOnlyWhenThereIsNoArtworkAtAll() {
    var themed = Qt.rgba(0.2, 0.6, 0.9, 1)
    var out = Palette.build([], [themed], 2)
    compare(out[0], themed)
    compare(out[1], themed)
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

  function test_readableFallsBackOnlyWithNoArtworkAtAll() {
    var fallback = Qt.rgba(0.9, 0.9, 0.2, 1)
    compare(Palette.readable([], Qt.rgba(0, 0, 0, 1), fallback, 4.5), fallback)
  }

  function test_readableGivesAMonochromeSleeveWhite() {
    var fallback = Qt.rgba(0.9, 0.9, 0.2, 1)
    var out = Palette.readable([Qt.rgba(0, 0, 0, 1)], Qt.rgba(0.05, 0.05, 0.05, 1), fallback, 4.5)
    verify(out !== fallback)
    verify(out.r > 0.9 && out.g > 0.9 && out.b > 0.9)
  }

  function test_readablePrefersTheMostSaturatedCandidate() {
    var background = Qt.rgba(0.06, 0.07, 0.08, 1)
    // The pale one has far more contrast; the saturated one is what reads as
    // belonging to the album, so it wins and gets lifted instead.
    var pale = Qt.hsla(0.15, 0.10, 0.85, 1)
    var vivid = Qt.hsla(0.02, 0.90, 0.35, 1)
    var out = Palette.readable([pale, vivid], background, Qt.rgba(0, 1, 0, 1), 4.5)
    verify(Math.abs(out.hslHue - vivid.hslHue) < 0.02)
    verify(Palette.contrastRatio(out, background) >= 4.5)
  }

  function test_readableSkipsAnUnliftableCandidateForTheNextOne() {
    var background = Qt.rgba(1, 1, 1, 1)
    // Saturated but on a white card: lifting darkens it, and it gets there.
    var vivid = Qt.hsla(0.6, 0.95, 0.45, 1)
    var out = Palette.readable([vivid], background, Qt.rgba(0, 0, 0, 1), 4.5)
    verify(Palette.contrastRatio(out, background) >= 4.5)
  }

  function test_capBrightnessLeavesADarkColourAlone() {
    var dark = Qt.hsla(0.02, 0.9, 0.25, 1)
    compare(Palette.capBrightness(dark, 0.34), dark)
  }

  function test_capBrightnessDarkensAndKeepsTheHue() {
    var pale = Qt.hsla(0.55, 0.8, 0.9, 1)
    var out = Palette.capBrightness(pale, 0.34)
    verify(Palette.relativeLuminance(out) <= 0.34)
    verify(Math.abs(out.hslHue - pale.hslHue) < 0.02)
    verify(out.hslSaturation > 0.5)
  }

  function test_capBrightnessHandlesWhite() {
    var out = Palette.capBrightness(Qt.rgba(1, 1, 1, 1), 0.34)
    verify(Palette.relativeLuminance(out) <= 0.34)
  }

  function test_buildCapsEveryBlobItReturns() {
    // The monochrome fallback is near-white, so this is the case that would
    // otherwise wash out the text.
    var out = Palette.build([Qt.rgba(0, 0, 0, 1)], [], 4)
    compare(out.length, 4)
    for (var i = 0; i < out.length; i++)
      verify(Palette.relativeLuminance(out[i]) <= Palette.MAX_BLOB_LUMINANCE)
  }

  function test_theTextAccentIsNotCappedLikeTheBlobs() {
    // The same colour goes two ways: capped when it is a blob, left bright
    // when it is text. Dimming the text to the blob ceiling would cost it the
    // contrast it was chosen for.
    var background = Qt.rgba(0.06, 0.07, 0.08, 1)
    var pale = Qt.hsla(0.15, 0.8, 0.75, 1)

    var text = Palette.readable([pale], background, Qt.rgba(0, 1, 0, 1), 4.5)
    verify(Palette.contrastRatio(text, background) >= 4.5)
    verify(Palette.relativeLuminance(text) > Palette.MAX_BLOB_LUMINANCE)

    var blob = Palette.build([pale], [], 1)[0]
    verify(Palette.relativeLuminance(blob) <= Palette.MAX_BLOB_LUMINANCE)
  }
}
