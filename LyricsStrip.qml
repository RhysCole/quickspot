import QtQuick

import qs.Commons

import "Lyrics.js" as Lyrics

// One line of lyric at a time, in the gap between the transport controls and
// the record. Deliberately quiet: it holds no space when there is nothing to
// show, and a line crossfades into the next rather than snapping, so it reads
// as part of the background rather than as a caption demanding attention.
Item {
  id: root

  property var lines: []
  property double positionMs: 0
  property color accent: Color.menu.text

  readonly property string current: Lyrics.textAt(lines, positionMs)
  readonly property bool active: current !== ""

  // A timestamped blank is an instrumental gap: the strip empties rather than
  // holding the previous line, so the fade out is the interlude.
  opacity: active ? 1 : 0

  Behavior on opacity {
    NumberAnimation { duration: 500; easing.type: Easing.InOutQuad }
  }

  Text {
    id: label
    anchors.centerIn: parent
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    maximumLineCount: 2
    wrapMode: Text.WordWrap
    color: root.accent
    opacity: 0.7
    font.pixelSize: Style.font.bodySmall
    font.italic: true
    text: root.current

    // Each new line arrives by fading up rather than replacing the last one
    // mid-frame, which is what keeps a fast passage from flickering.
    onTextChanged: {
      if (text !== "") lineIn.restart()
    }

    NumberAnimation {
      id: lineIn
      target: label
      property: "opacity"
      from: 0
      to: 0.7
      duration: 320
      easing.type: Easing.OutCubic
    }
  }
}
