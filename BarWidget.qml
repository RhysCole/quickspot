pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.Commons
import qs.Ui

// Bar widget: dancing bars, the current track, and transport controls.
//
// It reads whatever media player is active rather than Spotify specifically, so
// a browser playing a video drives it exactly the same way — and it works with
// no Spotify account configured at all, because nothing it shows or does needs
// one. Search is the only part of QuickSpot that does.
//
// Clicking the bars or the title opens the overlay; the transport buttons act
// in place without opening anything.
BarWidget {
  id: root

  moduleName: "io.github.rhyscole.quickspot"

  // `bar.shell` is how a third-party widget reaches the shell; the widget is
  // only ever handed `bar`.
  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("io.github.rhyscole.quickspot") : null

  readonly property var playback: service && service.playback
    ? service.playback : ({ ok: false, playing: false, trackName: "", artists: "" })
  readonly property bool hasMedia: playback.ok === true
  readonly property bool playing: playback.playing === true

  readonly property string trackLabel: {
    if (!hasMedia) return ""
    var name = String(playback.trackName || "")
    var artists = String(playback.artists || "")
    return artists !== "" ? name + "  ·  " + artists : name
  }

  // A vertical bar has no room for a title or a control strip, and neither has
  // anything to say with nothing playing. Both fall back to the plain icon;
  // everything remains reachable through the overlay.
  readonly property bool compact: vertical || !hasMedia

  // How much width the title may take before eliding: long enough to be worth
  // reading, short enough not to shove the rest of the bar around on every
  // track change.
  readonly property int titleWidth: Math.max(40, parseInt(setting("titleWidth", 190), 10) || 190)

  readonly property color ink: bar ? bar.foreground : Color.bar.text

  function open() {
    if (bar && bar.shell) bar.shell.toggle("io.github.rhyscole.quickspot", "{}")
  }

  function transport(verb) {
    if (!service) return
    // Errors surface in the overlay, which is where there is room to read them.
    var done = function(error) {}
    if (verb === "toggle") service.togglePlay(done)
    else if (verb === "next") service.nextTrack(done)
    else if (verb === "previous") service.previousTrack(done)
  }

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  RowLayout {
    id: layout
    anchors.centerIn: parent
    spacing: 0

    // Icon only: nothing playing, or a vertical bar with no room for more.
    BarIconButton {
      bar: root.bar
      visible: root.compact
      // A music note rather than the Spotify mark: with nothing playing the
      // widget is a launcher for music generally, and the transport controls
      // it grows into drive any media player, not only Spotify.
      text: "󰎉"      // nf-md-music_note
      tooltipText: root.hasMedia ? root.trackLabel : "Search Spotify"
      active: root.playing
      onPressed: function(mouseButton) { root.open() }
    }

    // Bars and title are one press target, because a title that opens the
    // launcher is the obvious behaviour and splitting them would make half of
    // it dead.
    Item {
      id: launcher
      visible: !root.compact
      Layout.preferredWidth: launcherRow.implicitWidth + Style.space(14)
      Layout.preferredHeight: root.barSize
      Layout.alignment: Qt.AlignVCenter

      RowLayout {
        id: launcherRow
        anchors.centerIn: parent
        spacing: Style.space(7)

        DancingBars {
          Layout.alignment: Qt.AlignVCenter
          Layout.preferredHeight: Math.round(root.barSize * 0.44)
          playing: root.playing
          color: root.playing && root.bar ? root.bar.urgent : root.ink
        }

        Text {
          Layout.alignment: Qt.AlignVCenter
          Layout.maximumWidth: root.titleWidth
          elide: Text.ElideRight
          color: root.ink
          opacity: launcherHover.containsMouse ? 1.0 : 0.9
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          text: root.trackLabel

          Behavior on opacity {
            NumberAnimation { duration: 120 }
          }
        }
      }

      MouseArea {
        id: launcherHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.open()
      }
    }

    BarIconButton {
      bar: root.bar
      visible: !root.compact
      text: "󰒮"      // nf-md-skip_previous
      tooltipText: "Previous"
      enabled: root.service ? root.service.canGoPrevious : false
      onPressed: function(mouseButton) { root.transport("previous") }
    }

    BarIconButton {
      bar: root.bar
      visible: !root.compact
      text: root.playing ? "󰏤" : "󰐊"  // nf-md-pause / nf-md-play
      tooltipText: root.playing ? "Pause" : "Play"
      enabled: root.service ? root.service.canTogglePlay : false
      onPressed: function(mouseButton) { root.transport("toggle") }
    }

    BarIconButton {
      bar: root.bar
      visible: !root.compact
      text: "󰒭"      // nf-md-skip_next
      tooltipText: "Next"
      enabled: root.service ? root.service.canGoNext : false
      onPressed: function(mouseButton) { root.transport("next") }
    }
  }
}
