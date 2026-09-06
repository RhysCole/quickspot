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
  // The shell assigns this at shell.qml:637 via serviceFor(), which returns
  // null when the service singleton has not been instantiated yet. It must
  // therefore be a plain property, not a binding: a readonly binding makes the
  // shell's assignment throw before it can call registerPanelLoader(), which
  // leaves the overlay unregistered and the keybind inert.
  property var service: null

  // serviceFor() can hand us null on a cold start. ensureService() creates the
  // singleton on demand, so resolve lazily the first time the overlay opens.
  function resolveService() {
    if (service) return service
    if (shell && shell.ensureService)
      service = shell.ensureService("io.github.rhyscole.quickspot")
    return service
  }

  property bool opened: false
  readonly property bool needsClientId: service ? service.clientId === "" : true
  readonly property bool needsLogin: service ? (!service.authorized && !needsClientId) : false
  readonly property bool ready: !needsClientId && !needsLogin

  property var rows: []
  property int selectedIndex: 0
  property string statusText: ""

  // TrackRow's own implicitHeight. The results area is sized in whole rows so
  // it never shows a half-cut one.
  readonly property int rowHeight: 52
  readonly property int maxVisibleRows: 3
  // Starts at nothing and grows a row at a time as results arrive, up to three.
  // The rest stay reachable by scrolling.
  readonly property int resultsHeight:
    Math.min(rows.length, maxVisibleRows) * rowHeight

  function runSearch(query) {
    // A response for a stale query must not write state after the overlay
    // has closed: close() stops the debounce timer, but a search already
    // in flight when close() ran can still resolve afterwards.
    if (!service || !opened) return
    if (query.trim() === "") { rows = []; selectedIndex = 0; statusText = ""; service.cancelSearch(); return }
    service.search(query, function(results, error) {
      if (!root.opened) return
      root.rows = results
      root.selectedIndex = 0
      root.statusText = error !== "" ? error : (results.length === 0 ? "No results" : "")
    })
  }

  function submit(modifiers) {
    if (needsLogin) { service.beginLogin(); return }
    if (modifiers & Qt.ControlModifier) act(function(row, done) { root.service.queueTrack(row, done) })
    else if (modifiers & Qt.ShiftModifier) act(function(row, done) { root.service.playAlbum(row, done) })
    else act(function(row, done) { root.service.playTrack(row, done) })
  }

  function act(handler) {
    if (!service || selectedIndex < 0 || selectedIndex >= rows.length) return
    var row = rows[selectedIndex]
    handler(row, function(error) {
      if (error === "") root.close()
      else root.statusText = error
    })
  }

  // Drives window.visible. Unlike `opened`, this is never derived from
  // animated geometry (card.y / card.height), so a background event that
  // changes the card's height while closed cannot make the surface flash
  // visible. Set true synchronously on open; cleared only after the exit
  // animation has had time to finish (see hideTimer below).
  property bool surfaceVisible: false

  // Gap below the bar. 0 means derive it from the shell's own bar tokens; any
  // other value wins, which matters on third-party bars of a different height.
  readonly property int configuredTopMargin: service && service.settings
    ? (parseInt(service.settings.topMargin, 10) || 0) : 0
  readonly property int cardTopMargin: configuredTopMargin > 0
    ? configuredTopMargin
    : Style.bar.sizeHorizontal + Style.space(10)

  function open(payloadJson) {
    if (opened) return
    resolveService()
    surfaceVisible = true
    opened = true
    field.text = ""
    rows = []
    selectedIndex = 0
    statusText = ""
    // Polling runs only while the overlay is on screen, so a closed overlay
    // costs no API quota.
    if (service) service.watchPlayback()
    // Wayland layer-surface mapping is asynchronous: forcing focus in the
    // same tick as flipping `opened` would target a child of a window that
    // is not mapped yet. Defer to the next event loop turn, and focus
    // whichever field is actually visible on this run.
    Qt.callLater(function() {
      if (root.needsClientId) {
        if (clientIdField) clientIdField.forceActiveFocus()
      } else {
        if (field) field.forceActiveFocus()
      }
    })
  }

  function close() {
    if (!opened) return
    opened = false
    // Stop any pending debounced search: without this, a search typed then
    // dismissed inside the 180ms debounce window still fires after `opened`
    // goes false. `runSearch`'s own `opened` guard is a second line of
    // defence for a request already in flight when close() runs.
    debounce.stop()
    if (service) {
      service.cancelSearch()
      service.unwatchPlayback()
    }
    // Keep the surface mapped so the exit animation is visible, then hide it
    // shortly after the 150ms exit animation would have finished. Guarded so
    // a re-open during the exit cancels the pending hide.
    hideTimer.restart()
  }

  function toggle() {
    if (opened) close()
    else open("")
  }

  ArtPalette {
    id: palette
    artworkUrl: root.service && root.service.playback.ok
      ? root.service.playback.artworkUrl
      : ""
  }

  Timer {
    id: hideTimer
    interval: 180
    repeat: false
    onTriggered: {
      if (!root.opened) root.surfaceVisible = false
    }
  }

  Timer {
    id: debounce
    interval: 180
    onTriggered: root.runSearch(field.text)
  }

  PanelWindow {
    id: window

    // Bound only to explicit open/close state (via surfaceVisible), never to
    // animated geometry, so it cannot be affected by card.height changing
    // while closed (e.g. an auth-error message appearing from a background
    // token refresh).
    visible: root.surfaceVisible

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

      // Single dismiss path for Escape regardless of which field (if either)
      // currently holds focus: an unhandled key event at the focused
      // descendant bubbles up to this ancestor. The per-field handlers were
      // removed so there is exactly one path, not two that could both fire.
      Keys.onEscapePressed: root.close()

      Behavior on y {
        NumberAnimation { duration: root.opened ? 200 : 150; easing.type: Easing.OutCubic }
      }

      // The card grows and shrinks as results arrive and clear, so this runs on
      // nearly every search.
      Behavior on height {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }

      LavaBackground {
        anchors.fill: parent
        cornerRadius: card.radius
        colors: palette.colors
        // Nothing to animate behind a card that is not on screen.
        active: root.opened
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

          onTextChanged: {
            if (root.needsLogin) return
            root.statusText = ""
            debounce.restart()
          }

          Keys.onUpPressed: root.selectedIndex = Math.max(0, root.selectedIndex - 1)
          Keys.onDownPressed: root.selectedIndex = root.rows.length === 0
            ? 0
            : Math.min(root.rows.length - 1, root.selectedIndex + 1)
          Keys.onTabPressed: root.selectedIndex = root.rows.length === 0
            ? 0
            : (root.selectedIndex + 1) % root.rows.length

          // Both handlers delegate to root.submit(): an attached signal handler
          // cannot be invoked as a function, so the shared body lives on the root.
          Keys.onReturnPressed: function(event) { root.submit(event.modifiers) }
          Keys.onEnterPressed: function(event) { root.submit(event.modifiers) }
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

        ListView {
          id: list
          Layout.fillWidth: true
          Layout.preferredHeight: root.resultsHeight
          visible: root.rows.length > 0
          clip: true
          interactive: contentHeight > height
          currentIndex: root.selectedIndex
          model: root.rows

          // Keeps the keyboard selection on screen once the list is longer
          // than the visible area.
          highlightFollowsCurrentItem: true
          highlightMoveDuration: 120
          preferredHighlightBegin: 0
          preferredHighlightEnd: height

          delegate: TrackRow {
            required property int index
            required property var modelData
            width: list.width
            row: modelData
            selected: index === root.selectedIndex

            MouseArea {
              anchors.fill: parent
              onClicked: {
                root.selectedIndex = index
                root.act(function(row, done) { root.service.playTrack(row, done) })
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.statusText !== ""
          wrapMode: Text.WordWrap
          opacity: 0.8
          color: Color.menu.text
          font.pixelSize: Style.font.bodySmall
          text: root.statusText
        }

        Text {
          Layout.fillWidth: true
          visible: root.rows.length > 0
          horizontalAlignment: Text.AlignRight
          opacity: 0.5
          color: Color.menu.text
          font.pixelSize: Style.font.bodySmall
          text: "↵ play    Ctrl+↵ queue    Shift+↵ album"
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(4)
          visible: root.ready
          implicitHeight: 1
          color: Color.menu.border
          opacity: 0.4
        }

        PlayerPanel {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(4)
          visible: root.ready
          service: root.service
          onFailed: function(message) { root.statusText = message }
        }
      }
    }
  }
}
