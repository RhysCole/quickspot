pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.Commons

import "Lyrics.js" as Lyrics

// Three lines of lyric in the gap between the transport controls and the
// record: the line just gone, the line being sung, and the one coming. The
// current line lights word by word as the line plays.
//
// The sweep is interpolated from the line's own span — LRCLIB times lyrics per
// line and never per word — so it follows the singing closely without being
// the real vocal timing.
Item {
  id: root

  property var lines: []
  property double positionMs: 0
  property color accent: Color.menu.text

  readonly property int index: Lyrics.lineAt(lines, positionMs)
  readonly property var words: index >= 0 ? Lyrics.splitWords(lines[index].text) : []
  readonly property real progress: Lyrics.lineProgress(lines, index, positionMs)
  readonly property var context: Lyrics.neighbours(lines, index)
  readonly property bool active: lines.length > 0

  implicitHeight: column.implicitHeight

  opacity: active ? 1 : 0

  Behavior on opacity {
    NumberAnimation { duration: 500; easing.type: Easing.InOutQuad }
  }

  ColumnLayout {
    id: column
    anchors.centerIn: parent
    width: parent.width
    spacing: Style.space(2)

    // Context lines are dim and small enough to read as surroundings rather
    // than as something competing with the line being sung.
    Text {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      color: Color.menu.text
      opacity: 0.4
      font.pixelSize: Style.font.bodySmall
      text: root.context.previous

      Behavior on opacity {
        NumberAnimation { duration: 350 }
      }
    }

    // Flow rather than a Row so a long line wraps instead of eliding — the
    // strip is narrow, and half a lyric is worse than two lines of it.
    Flow {
      id: currentLine
      Layout.fillWidth: true
      spacing: 0

      // Animated instead of `y`, which the layout owns: driving a
      // layout-managed property means fighting the layout for it, and reading
      // it back as the animation's own target is circular.
      transform: Translate { id: lineShift }

      Repeater {
        model: root.words

        Text {
          required property int index
          required property var modelData

          // Lights once the sweep reaches this word. The behaviour below turns
          // the step into a soft cascade across the line.
          readonly property bool lit: root.progress >= modelData.start

          text: modelData.text + (index < root.words.length - 1 ? " " : "")
          color: root.accent
          opacity: lit ? 1.0 : 0.45
          font.pixelSize: Style.font.subtitle
          font.weight: Font.Medium

          Behavior on opacity {
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      color: Color.menu.text
      opacity: 0.4
      font.pixelSize: Style.font.bodySmall
      text: root.context.next

      Behavior on opacity {
        NumberAnimation { duration: 350 }
      }
    }
  }

  // Each new line arrives by rising slightly and fading up, so the change
  // reads as movement through the song rather than as text being swapped.
  onIndexChanged: lineIn.restart()

  ParallelAnimation {
    id: lineIn
    NumberAnimation {
      target: currentLine; property: "opacity"
      from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: lineShift; property: "y"
      from: 7; to: 0; duration: 340; easing.type: Easing.OutCubic
    }
  }
}
