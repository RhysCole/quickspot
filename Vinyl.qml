pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

import qs.Commons

// A record: black disc, concentric grooves, circular album label at the centre,
// spindle hole through the middle. Spins clockwise while `spinning` is true and
// holds its angle when it is not, so pausing does not snap the artwork back to
// the top.
Item {
  id: root

  property real size: 120
  property string artworkUrl: ""
  property bool spinning: false
  // Punched through to whatever sits behind the record, so the hole reads as a
  // hole rather than as a dot painted on the label.
  property color holeColor: Color.menu.background

  implicitWidth: size
  implicitHeight: size

  property real angle: 0

  // Runs continuously and pauses in place: `from`/`to` are evaluated once, so
  // resuming picks up mid-revolution instead of restarting from zero.
  NumberAnimation on angle {
    running: true
    paused: !root.spinning
    loops: Animation.Infinite
    from: 0
    to: 360
    duration: 8000
  }

  Item {
    id: disc
    anchors.fill: parent
    rotation: root.angle

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "#0d0d0f"
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.08)
    }

    // Grooves, confined to the rim the label leaves visible. Spacing widens
    // slightly outward, which is what makes a still frame read as vinyl rather
    // than as a dark circle.
    Repeater {
      model: 5

      Rectangle {
        required property int index
        readonly property real inset: root.size * (0.028 + index * 0.013)

        anchors.centerIn: parent
        width: root.size - inset * 2
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.05)
      }
    }

    // The album label. Masked to a circle rather than clipped, because `clip`
    // on a rounded Rectangle still clips to its bounding box.
    Item {
      id: label
      anchors.centerIn: parent
      // Nearly fills the record: the sleeve is the point, the vinyl is framing.
      width: root.size * 0.82
      height: width

      Image {
        id: artwork
        anchors.fill: parent
        source: root.artworkUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
        sourceSize.width: Math.round(root.size)
        sourceSize.height: Math.round(root.size)
      }

      Rectangle {
        id: labelMask
        anchors.fill: parent
        radius: width / 2
        color: "black"
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: parent
        source: artwork
        maskEnabled: true
        maskSource: labelMask
        visible: root.artworkUrl !== "" && artwork.status === Image.Ready
      }

      // Stands in for the label until artwork arrives, and for tracks that
      // have none at all.
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        visible: root.artworkUrl === "" || artwork.status !== Image.Ready
        color: Color.menu.selectedBackground
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
      }
    }

    Rectangle {
      anchors.centerIn: parent
      width: root.size * 0.06
      height: width
      radius: width / 2
      color: root.holeColor
    }
  }
}
