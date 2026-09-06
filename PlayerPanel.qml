pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.Commons

import "Player.js" as Player

// The now-playing strip along the bottom of the overlay: metadata and transport
// on the left, the spinning record on the right, the distribution's logo tucked
// under it. Purely a view — every action is delegated back to the service.
Item {
  id: root

  property var service: null
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
        color: Color.menu.selectedText
        font.pixelSize: Style.font.subtitle
        text: root.playback.ok ? root.playback.trackName : "Nothing playing"
      }

      Text {
        Layout.fillWidth: true
        visible: root.playback.ok
        elide: Text.ElideRight
        opacity: 0.75
        color: Color.menu.text
        font.pixelSize: Style.font.bodySmall
        text: root.playback.artists
      }

      Text {
        Layout.fillWidth: true
        visible: root.playback.ok && root.playback.albumName !== ""
        elide: Text.ElideRight
        opacity: 0.5
        color: Color.menu.text
        font.pixelSize: Style.font.bodySmall
        text: root.playback.albumName
      }

      RowLayout {
        Layout.topMargin: Style.space(4)
        spacing: Style.space(10)

        TransportButton {
          glyph: "󰒮"      // nf-md-skip_previous
          enabled: root.playback.ok
          onActivated: root.act(function(done) { root.service.previousTrack(done) })
        }

        TransportButton {
          glyph: root.playback.playing ? "󰏤" : "󰐊"  // nf-md-pause / nf-md-play
          primary: true
          enabled: root.playback.ok
          onActivated: root.act(function(done) { root.service.togglePlay(done) })
        }

        TransportButton {
          glyph: "󰒭"      // nf-md-skip_next
          enabled: root.playback.ok
          onActivated: root.act(function(done) { root.service.nextTrack(done) })
        }

        Item { Layout.fillWidth: true }

        Image {
          id: logo
          property int candidate: 0

          Layout.alignment: Qt.AlignVCenter
          source: root.service && root.service.logoCandidates.length > candidate
            ? "file://" + root.service.logoCandidates[candidate]
            : ""
          sourceSize.height: 22
          fillMode: Image.PreserveAspectFit
          opacity: 0.65
          // Walk the candidate list until one of them actually exists on this
          // machine; Player.logoCandidates ends in a path Omarchy always ships.
          onStatusChanged: {
            if (status === Image.Error && root.service
                && candidate < root.service.logoCandidates.length - 1) candidate++
          }
        }
      }

      SeekBar {
        Layout.fillWidth: true
        Layout.topMargin: Style.space(6)
        enabled: root.playback.ok && root.playback.durationMs > 0
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
