pragma ComponentBehavior: Bound

import QtQuick

// Three bars that bounce while something is playing and settle flat when it
// stops. Purely decorative — it is not driven by the audio, which no media
// player exposes over MPRIS. It answers "is anything playing" at a glance,
// which is the question a bar icon should answer.
Item {
  id: root

  property bool playing: false
  property color color: "white"
  property real barWidth: 2
  property real spacing: 2

  implicitWidth: barWidth * 3 + spacing * 2
  implicitHeight: 12

  Row {
    anchors.centerIn: parent
    spacing: root.spacing

    Repeater {
      model: 3

      Rectangle {
        id: bar
        required property int index

        // Staggered periods so the three never march in step, which is what
        // separates this from a loading indicator.
        readonly property int period: 420 + index * 130
        readonly property real restHeight: root.height * 0.22

        width: root.barWidth
        height: root.height * 0.35
        radius: width / 2
        color: root.color
        anchors.verticalCenter: parent.verticalCenter

        SequentialAnimation on height {
          running: root.playing
          loops: Animation.Infinite

          NumberAnimation {
            to: root.height
            duration: bar.period
            easing.type: Easing.InOutSine
          }
          NumberAnimation {
            to: root.height * 0.28
            duration: bar.period
            easing.type: Easing.InOutSine
          }
        }

        // Settling is its own animation rather than a State: the bouncing
        // above is a value source and owns `height` while it runs, so a State
        // declaring a different height for the same property would be two
        // things writing one value.
        NumberAnimation {
          id: settle
          target: bar
          property: "height"
          to: bar.restHeight
          duration: 260
          easing.type: Easing.OutCubic
        }

        Connections {
          target: root
          function onPlayingChanged() {
            if (!root.playing) settle.restart()
          }
        }
      }
    }
  }
}
