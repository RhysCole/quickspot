import QtQuick

import qs.Commons
import qs.Ui

// Optional bar icon: click to drop the overlay in, exactly as the keybind does.
// The plugin works without ever being placed on the bar — this is a second door,
// not the only one.
BarWidget {
  id: root

  moduleName: "io.github.rhyscole.quickspot"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // `bar.shell` is how a third-party widget reaches the shell; the widget
  // itself is only handed `bar`. Reading the service is what lets the icon
  // light up while something is playing.
  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("io.github.rhyscole.quickspot") : null

  readonly property bool playing: service && service.playback ? service.playback.playing === true : false

  BarIconButton {
    id: button

    bar: root.bar
    text: "󰷇"      // nf-md-spotify
    tooltipText: root.playing && root.service
      ? root.service.playback.trackName
      : "Search Spotify"

    // Lit while something is playing, so the bar doubles as an at-a-glance
    // indicator without taking the space a full widget would.
    active: root.playing

    // The shell routes this to the overlay rather than to this widget:
    // isBarWidgetPanelPlugin() returns false for a plugin that also declares an
    // overlay kind, deliberately leaving those to the panel loader.
    onPressed: function(mouseButton) {
      if (!root.bar || !root.bar.shell) return
      root.bar.shell.toggle("io.github.rhyscole.quickspot", "{}")
    }
  }
}
