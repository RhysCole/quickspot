import QtQuick
import QtQuick.Layouts

import qs.Commons

Rectangle {
  id: root

  property var row: null
  property bool selected: false

  implicitHeight: 52
  color: selected ? Color.menu.selectedBackground : "transparent"
  radius: Style.cornerRadius

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
        color: root.selected ? Color.menu.selectedText : Color.menu.text
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
