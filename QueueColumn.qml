pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.Commons

// The next few tracks, filling the space to the right of the results. Sized to
// match the results area exactly, so the card's height never depends on which
// of the two happens to have more in it.
Item {
  id: root

  property var tracks: []
  property color accent: Color.menu.text
  property int rowHeight: 28

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    Text {
      Layout.fillWidth: true
      Layout.bottomMargin: Style.space(2)
      opacity: 0.45
      color: Color.menu.text
      font.pixelSize: Style.font.caption
      text: "Up next"
    }

    Repeater {
      model: root.tracks

      Item {
        id: entry
        required property int index
        required property var modelData

        Layout.fillWidth: true
        Layout.preferredHeight: root.rowHeight

        Text {
          id: name
          width: parent.width
          elide: Text.ElideRight
          opacity: 0.85
          color: Color.menu.text
          font.pixelSize: Style.font.bodySmall
          text: entry.modelData.name
        }

        Text {
          anchors.top: name.bottom
          width: parent.width
          elide: Text.ElideRight
          opacity: 0.45
          color: Color.menu.text
          font.pixelSize: Style.font.caption
          text: entry.modelData.artists
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: root.tracks.length === 0
      opacity: 0.35
      color: Color.menu.text
      font.pixelSize: Style.font.bodySmall
      text: "Queue is empty"
    }

    Item { Layout.fillHeight: true }
  }
}
