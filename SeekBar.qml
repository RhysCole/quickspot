import QtQuick
import QtQuick.Layouts

import qs.Commons

import "Player.js" as Player

// Progress bar and elapsed/remaining times. Dragging shows the position under
// the cursor immediately and commits it on release, so the bar does not fight
// the interpolated position while the pointer is down.
Item {
  id: root

  property color accent: Color.menu.selectedText
  property double positionMs: 0
  property double durationMs: 0

  signal seeked(int ms)

  property bool dragging: false
  property real dragFraction: 0

  readonly property real shownFraction: dragging
    ? dragFraction
    : Player.progressFraction(positionMs, durationMs)

  implicitHeight: column.implicitHeight

  ColumnLayout {
    id: column
    anchors.fill: parent
    spacing: Style.space(4)

    Item {
      Layout.fillWidth: true
      implicitHeight: 14

      Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: height / 2
        color: Color.menu.selectedBackground

        Rectangle {
          width: Math.max(0, Math.min(parent.width, parent.width * root.shownFraction))
          height: parent.height
          radius: parent.radius
          color: root.accent
        }
      }

      Rectangle {
        id: handle
        width: 10
        height: 10
        radius: width / 2
        color: root.accent
        visible: root.enabled
        opacity: seekArea.containsMouse || root.dragging ? 1 : 0
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(track.width, track.width * root.shownFraction)) - width / 2

        Behavior on opacity {
          NumberAnimation { duration: 120 }
        }
      }

      MouseArea {
        id: seekArea
        anchors.fill: parent
        anchors.margins: -4
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        function fractionAt(mouseX) {
          if (track.width <= 0) return 0
          var fraction = mouseX / track.width
          return fraction < 0 ? 0 : (fraction > 1 ? 1 : fraction)
        }

        onPressed: function(event) {
          root.dragging = true
          root.dragFraction = fractionAt(event.x)
        }
        onPositionChanged: function(event) {
          if (root.dragging) root.dragFraction = fractionAt(event.x)
        }
        onReleased: function(event) {
          if (!root.dragging) return
          root.dragging = false
          root.seeked(Player.seekMs(fractionAt(event.x), root.durationMs))
        }
        onCanceled: root.dragging = false
      }
    }

    RowLayout {
      Layout.fillWidth: true

      Text {
        opacity: 0.6
        color: Color.menu.text
        font.pixelSize: Style.font.bodySmall
        text: Player.formatTime(root.shownFraction * root.durationMs)
      }

      Item { Layout.fillWidth: true }

      Text {
        opacity: 0.6
        color: Color.menu.text
        font.pixelSize: Style.font.bodySmall
        text: Player.formatTime(root.durationMs)
      }
    }
  }
}
