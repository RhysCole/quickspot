pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.Commons

import "Player.js" as Player

// The now-playing strip along the bottom of the overlay: metadata and transport
// on the left, the spinning record on the right. Purely a view — every action
// is delegated back to the service.
Item {
  id: root

  property var service: null
  // The album's own colour, already checked for legibility by ArtPalette.
  property color accent: Color.menu.selectedText
  readonly property var playback: service ? service.playback : Player.emptyState()
  readonly property double progressMs: service ? service.playbackProgressMs : 0
  readonly property real discSize: 170

  signal failed(string message)

  implicitHeight: Math.max(discSize, layout.implicitHeight)

  function act(handler) {
    if (!service) return
    handler(function(error) {
      if (error !== "") root.failed(error)
    })
  }

  RowLayout {
    id: layout
    anchors.fill: parent
    spacing: Style.space(12)

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: Style.space(4)

      Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        color: root.accent
        font.pixelSize: Style.font.heading
        text: root.playback.ok ? root.playback.trackName : "Nothing playing"
      }

      Text {
        Layout.fillWidth: true
        visible: root.playback.ok
        elide: Text.ElideRight
        opacity: 0.85
        color: Qt.tint(Color.menu.text, Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35))
        font.pixelSize: Style.font.subtitle
        text: root.playback.artists
      }

      Text {
        Layout.fillWidth: true
        visible: root.playback.ok && text !== ""
        elide: Text.ElideRight
        opacity: 0.5
        color: Color.menu.text
        font.pixelSize: Style.font.body
        // Says which app is being controlled when it is not Spotify, so a
        // browser tab holding the media keys is visible rather than puzzling.
        text: {
          var album = root.playback.albumName
          var source = root.service && root.service.localIdentity !== ""
            && root.service.localIdentity.toLowerCase().indexOf("spotify") === -1
            ? root.service.localIdentity : ""
          if (album !== "" && source !== "") return album + " · " + source
          return album !== "" ? album : source
        }
      }

      RowLayout {
        Layout.topMargin: Style.space(4)
        spacing: Style.space(10)

        TransportButton {
          accent: root.accent
          glyph: "󰒮"      // nf-md-skip_previous
          enabled: root.service ? root.service.canGoPrevious : false
          onActivated: root.act(function(done) { root.service.previousTrack(done) })
        }

        TransportButton {
          accent: root.accent
          glyph: root.playback.playing ? "󰏤" : "󰐊"  // nf-md-pause / nf-md-play
          primary: true
          enabled: root.service ? root.service.canTogglePlay : false
          onActivated: root.act(function(done) { root.service.togglePlay(done) })
        }

        TransportButton {
          accent: root.accent
          glyph: "󰒭"      // nf-md-skip_next
          enabled: root.service ? root.service.canGoNext : false
          onActivated: root.act(function(done) { root.service.nextTrack(done) })
        }

        // Sits between the controls and the record, which is the only empty
        // space on the panel and reads as the natural place for it.
        LyricsStrip {
          Layout.fillWidth: true
          Layout.leftMargin: Style.space(6)
          Layout.alignment: Qt.AlignVCenter
          lines: root.service ? root.service.lyrics : []
          positionMs: root.progressMs
          accent: root.accent
        }
      }

      SeekBar {
        Layout.fillWidth: true
        Layout.topMargin: Style.space(6)
        accent: root.accent
        enabled: root.service ? root.service.canSeek : false
        positionMs: root.progressMs
        durationMs: root.playback.durationMs
        onSeeked: function(ms) { root.act(function(done) { root.service.seekTo(ms, done) }) }
      }
    }

    Vinyl {
      Layout.alignment: Qt.AlignVCenter
      size: root.discSize
      artworkUrl: root.playback.artworkUrl
      spinning: root.playback.ok && root.playback.playing
    }
  }
}
