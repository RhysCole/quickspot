import QtQuick
import QtQuick.Layouts

import qs.Commons

Rectangle {
  id: root

  property var row: null
  property bool selected: false
  // The album's own colour, so the selection matches the background instead of
  // being the one thing on the card still wearing the theme's.
  property color accent: Color.menu.selectedText

  implicitHeight: 52
  color: selected ? Color.menu.selectedBackground : "transparent"
  radius: Style.cornerRadius

  Behavior on color {
    ColorAnimation { duration: 120 }
  }

  // A bar down the leading edge of the selected row. The tinted fill alone is
  // easy to lose against a background that is itself coloured and moving.
  Rectangle {
    width: 2
    height: parent.height * 0.55
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    radius: width / 2
    color: root.accent
    opacity: root.selected ? 1 : 0

    Behavior on opacity {
      NumberAnimation { duration: 140 }
    }
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(10)

    Rectangle {
      Layout.preferredWidth: 40
      Layout.preferredHeight: 40
      radius: Style.cornerRadius
      color: Color.menu.selectedBackground
      clip: true

      Image {
        anchors.fill: parent
        source: root.row ? root.row.artworkUrl : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: status === Image.Ready
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        color: root.selected ? root.accent : Color.menu.text
        font.pixelSize: Style.font.body
        text: root.row ? root.row.name : ""
      }

      Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        opacity: 0.7
        color: Color.menu.text
        font.pixelSize: Style.font.bodySmall
        // An album or playlist row has no album line of its own, so the
        // separator would leave a dangling middle dot.
        text: root.row
          ? (root.row.albumName !== ""
             ? root.row.artists + " · " + root.row.albumName
             : root.row.artists)
          : ""
      }
    }

    // A duration for tracks, the kind for everything else — the two never
    // apply at once, so they share the slot.
    Text {
      opacity: 0.7
      color: Color.menu.text
      font.pixelSize: Style.font.bodySmall
      text: root.row ? root.row.trailing : ""
    }
  }
}
