import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs.Commons
import qs.Ui

Item {
  id: root

  // Injected by the shell when the overlay is loaded (shell.qml:630).
  property var shell: null
  readonly property var service: shell ? shell.ensureService("io.github.rhyscole.quickspot") : null

  property bool opened: false
  readonly property bool needsClientId: service ? service.clientId === "" : true
  readonly property bool needsLogin: service ? (!service.authorized && !needsClientId) : false

  // Gap below the bar. 0 means derive it from the shell's own bar tokens; any
  // other value wins, which matters on third-party bars of a different height.
  readonly property int configuredTopMargin: service && service.settings
    ? (parseInt(service.settings.topMargin, 10) || 0) : 0
  readonly property int cardTopMargin: configuredTopMargin > 0
    ? configuredTopMargin
    : Style.bar.sizeHorizontal + Style.space(10)

  function open(payloadJson) {
    if (opened) return
    opened = true
    field.text = ""
    field.forceActiveFocus()
  }

  function close() {
    if (!opened) return
    opened = false
    if (service) service.cancelSearch()
  }

  function toggle() {
    if (opened) close()
    else open("")
  }

  PanelWindow {
    id: window

    // Stays mapped through the exit animation so the card can slide back out.
    visible: root.opened || card.y > -card.height

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "quickspot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      id: scrim
      anchors.fill: parent
      color: Color.menu.scrim
      opacity: root.opened ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: root.opened ? 200 : 150; easing.type: Easing.OutCubic }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }
    }

    Rectangle {
      id: card

      width: Math.min(640, window.width - Style.space(40))
      height: content.implicitHeight + Style.space(24)
      anchors.horizontalCenter: parent.horizontalCenter

      // The entrance: the card travels from fully above the screen edge down to
      // its resting position under the clock. Because the window is fullscreen,
      // this is ordinary QML translation and needs no layer-shell margin work.
      y: root.opened ? root.cardTopMargin : -height

      color: Color.menu.background
      radius: Style.cornerRadius
      border.color: Color.menu.border
      border.width: 1

      Behavior on y {
        NumberAnimation { duration: root.opened ? 200 : 150; easing.type: Easing.OutCubic }
      }

      // Height changes as results arrive. Animating it separately keeps the
      // list growing from reading as a second entrance.
      Behavior on height {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }

      // Swallows clicks so they do not reach the scrim's dismiss handler.
      MouseArea { anchors.fill: parent }

      ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        TextField {
          id: field
          Layout.fillWidth: true
          visible: !root.needsClientId
          placeholderText: root.needsLogin
            ? "Press Enter to sign in to Spotify"
            : "Search Spotify"

          Keys.onEscapePressed: root.close()
          onAccepted: {
            if (root.needsLogin && root.service) root.service.beginLogin()
          }
        }

        // First-run: capture the client ID here rather than in Omarchy's
        // settings panel, which is unavailable to a plugin with no bar widget.
        ColumnLayout {
          Layout.fillWidth: true
          visible: root.needsClientId
          spacing: Style.space(6)

          Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Color.menu.text
            font.pixelSize: Style.font.body
            text: "QuickSpot needs a Spotify client ID. Create an app at "
              + "developer.spotify.com/dashboard with the redirect URI "
              + (root.service ? root.service.redirectUri : "") + " and paste the ID below."
          }

          TextField {
            id: clientIdField
            Layout.fillWidth: true
            placeholderText: "Spotify client ID"
            Keys.onEscapePressed: root.close()
            onAccepted: {
              if (text.trim() === "" || !root.service) return
              root.service.setClientId(text)
              text = ""
              field.forceActiveFocus()
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.service && root.service.authError !== ""
          wrapMode: Text.WordWrap
          color: Color.urgent
          font.pixelSize: Style.font.bodySmall
          text: root.service ? root.service.authError : ""
        }
      }
    }
  }
}
