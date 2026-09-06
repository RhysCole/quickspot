pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

// Slow-moving blobs of colour, blurred into each other and masked to the card's
// rounded rectangle: a lava lamp tinted by whatever is playing. The blobs are
// drawn off-screen and composited once, so the blur cost does not scale with
// how many of them there are.
Item {
  id: root

  property var colors: []
  // Animations stop with the overlay so a closed card is not repainting every
  // frame behind a hidden surface.
  property bool active: false
  property real cornerRadius: 0
  property real intensity: 0.34

  // Sized off the card's height, not its width: a blob scaled to a 640px-wide
  // card washes the whole surface in one colour.
  readonly property real blobSize: Math.max(80, height * 0.75)

  Item {
    id: blobs
    anchors.fill: parent
    visible: false
    layer.enabled: true

    Repeater {
      model: root.colors.length

      Rectangle {
        id: blob
        required property int index

        readonly property real phase: index / Math.max(1, root.colors.length)
        // Prime-ish periods so the blobs never settle into a visible loop.
        readonly property int driftX: 11000 + index * 2600
        readonly property int driftY: 14000 + index * 1900
        readonly property int pulse: 6000 + index * 1300

        width: root.blobSize
        height: root.blobSize
        radius: width / 2
        color: root.colors[index]
        opacity: 0.75

        Behavior on color {
          ColorAnimation { duration: 1200; easing.type: Easing.InOutQuad }
        }

        // Each blob starts somewhere different along its own path, so they do
        // not sweep the card in formation.
        x: root.width * (0.15 + 0.7 * blob.phase) - width / 2
        y: root.height * (0.2 + 0.6 * blob.phase) - height / 2

        SequentialAnimation on x {
          running: root.active
          loops: Animation.Infinite
          NumberAnimation {
            to: root.width * 0.85 - blob.width / 2
            duration: blob.driftX
            easing.type: Easing.InOutSine
          }
          NumberAnimation {
            to: root.width * 0.15 - blob.width / 2
            duration: blob.driftX
            easing.type: Easing.InOutSine
          }
        }

        SequentialAnimation on y {
          running: root.active
          loops: Animation.Infinite
          NumberAnimation {
            to: root.height * 0.8 - blob.height / 2
            duration: blob.driftY
            easing.type: Easing.InOutSine
          }
          NumberAnimation {
            to: root.height * 0.2 - blob.height / 2
            duration: blob.driftY
            easing.type: Easing.InOutSine
          }
        }

        SequentialAnimation on scale {
          running: root.active
          loops: Animation.Infinite
          NumberAnimation { to: 1.25; duration: blob.pulse; easing.type: Easing.InOutSine }
          NumberAnimation { to: 0.8; duration: blob.pulse; easing.type: Easing.InOutSine }
        }
      }
    }
  }

  Rectangle {
    id: mask
    anchors.fill: parent
    radius: root.cornerRadius
    color: "black"
    visible: false
    layer.enabled: true
  }

  // MultiEffect grows its painted area beyond its own geometry to fit the blur
  // unless told not to. Inside a fullscreen layer surface that spills the tint
  // across the entire screen, so padding is off and the result is clipped as
  // well. The shell's own LockView does the same thing for the same reason.
  Item {
    anchors.fill: parent
    clip: true

  MultiEffect {
    anchors.fill: parent
    autoPaddingEnabled: false
    source: blobs
    // A blur wide enough that the blobs read as one flowing field rather than
    // as four circles.
    blurEnabled: true
    blur: 1.0
    blurMax: 48
    blurMultiplier: 1.0
    maskEnabled: true
    maskSource: mask
    opacity: root.colors.length > 0 ? root.intensity : 0

    Behavior on opacity {
      NumberAnimation { duration: 400 }
    }
  }
  }
}
