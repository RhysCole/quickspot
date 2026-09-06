import QtQuick
import Quickshell
import Quickshell.Io

import qs.Commons

import "Palette.js" as Palette

// Turns the current album artwork into colours for the background and for the
// player's text. ColorQuantizer reads a local file, so the artwork is fetched
// to a cache directory first; until that lands (and for artwork that quantizes
// to nothing usable) the theme's own colours stand in, so the background is
// never blank and never has to be waited for.
QtObject {
  id: root

  property string artworkUrl: ""
  property int count: Palette.BLOB_COUNT

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/quickspot/art"

  // What the palette currently describes. Compared against `artworkUrl` on
  // every process exit so a download that finished after the track already
  // moved on is discarded rather than painting the previous album's colours.
  property string resolvedUrl: ""
  property string pendingUrl: ""
  property string pendingPath: ""

  readonly property var themeColors: [Color.accent, Color.menu.selectedText, Color.foreground]
  readonly property var colors: Palette.build(quantizer.colors, themeColors, count)

  // The album colour for text and controls, guaranteed legible against the
  // card. Falls back to the theme's accent when the sleeve offers nothing that
  // can be made readable.
  readonly property color accent:
    Palette.readable(quantizer.colors, Color.menu.background, Color.menu.selectedText, 4.5)

  function refresh() {
    if (artworkUrl === "") {
      pendingUrl = ""
      resolvedUrl = ""
      quantizer.source = ""
      return
    }
    if (artworkUrl === resolvedUrl && quantizer.colors.length > 0) return
    if (artworkUrl === pendingUrl && fetch.running) return

    pendingUrl = artworkUrl
    pendingPath = Palette.cachePath(cacheDir, artworkUrl)
    // Toggling `running` off and on in one tick is not a restart, so a fetch
    // still in flight for a previous track is stopped and the new one started
    // on the next turn.
    fetch.running = false
    Qt.callLater(function() {
      if (root.pendingUrl === "") return
      root.fetch.running = true
    })
  }

  onArtworkUrlChanged: refresh()

  property Process fetch: Process {
    command: root.pendingUrl !== "" && root.pendingPath !== ""
      ? Palette.downloadCommand(root.pendingUrl, root.pendingPath)
      : []

    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("quickspot: artwork fetch failed for", root.pendingUrl, "exit", exitCode)
        return
      }
      // The track may have changed while curl was running.
      if (root.pendingUrl !== root.artworkUrl) { root.refresh(); return }
      root.resolvedUrl = root.pendingUrl
      // Cleared first: re-pointing at the same path would not change the URL,
      // so the quantizer would never re-read a file whose contents are new.
      quantizer.source = ""
      quantizer.source = "file://" + root.pendingPath
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
}
