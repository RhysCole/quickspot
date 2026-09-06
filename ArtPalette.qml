import QtQuick
import Quickshell
import Quickshell.Io

import qs.Commons

import "Palette.js" as Palette

// Turns the current album artwork into a handful of colours for the background
// to animate. ColorQuantizer reads a local file, so the artwork is fetched to a
// cache directory first; until that lands (and for artwork that quantizes to
// nothing usable) the theme's own colours stand in, so the background is never
// blank and never has to be waited for.
QtObject {
  id: root

  property string artworkUrl: ""
  property int count: Palette.BLOB_COUNT

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/quickspot/art"
  readonly property string localPath: Palette.cachePath(cacheDir, artworkUrl)

  readonly property var themeColors: [Color.accent, Color.menu.selectedText, Color.foreground]
  readonly property var colors: Palette.build(quantizer.colors, themeColors, count)

  property Process fetch: Process {
    command: root.artworkUrl !== "" && root.localPath !== ""
      ? Palette.downloadCommand(root.artworkUrl, root.localPath)
      : []
    running: false
    onExited: function(exitCode) {
      // Point the quantizer at the file only once it exists. Setting the
      // source before the download finishes leaves `colors` empty with no
      // second attempt, because the source URL would not have changed.
      if (exitCode === 0) quantizer.source = "file://" + root.localPath
    }
  }

  property ColorQuantizer quantizer: ColorQuantizer {
    // 2^depth colours. Four is enough for the blobs and keeps the median cut
    // cheap enough to run on every track change.
    depth: 2
    // The quantizer downscales before cutting; artwork detail past this adds
    // work without changing which colours dominate.
    rescaleSize: 64
  }

  // Re-fetch and re-quantize whenever the track changes. Clearing the source
  // first matters: the same album coming back around would otherwise leave the
  // quantizer's source unchanged and produce no new colours.
  onArtworkUrlChanged: {
    quantizer.source = ""
    if (artworkUrl === "" || localPath === "") return
    fetch.running = false
    fetch.running = true
  }
}
