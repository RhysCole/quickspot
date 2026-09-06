import QtQuick

import qs.Commons

// A round transport control. `primary` is the play/pause button, which sits
// larger and filled so the eye lands on it first.
Rectangle {
  id: root

  property string glyph: ""
  property bool primary: false

  signal activated()

  implicitWidth: primary ? 44 : 32
  implicitHeight: implicitWidth
  radius: width / 2

  color: primary
    ? Color.menu.selectedText
    : (mouse.containsMouse ? Color.menu.selectedBackground : "transparent")
  opacity: enabled ? (mouse.containsMouse || primary ? 1.0 : 0.75) : 0.3

  Behavior on opacity {
    NumberAnimation { duration: 100 }
  }

  scale: mouse.pressed ? 0.92 : 1.0

  Behavior on scale {
    NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
  }

  Text {
    anchors.centerIn: parent
    text: root.glyph
    color: root.primary ? Color.menu.background : Color.menu.text
    // The glyphs are Nerd Font media icons, which the default UI family does
    // not carry; naming the family explicitly keeps them from falling back to
    // tofu on a theme that sets a different font.
    font.family: Style.fontFamily
    font.pixelSize: root.primary ? Style.font.heading : Style.font.subtitle
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
