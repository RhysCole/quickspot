#!/usr/bin/env bash
# Starts a Spotify client if one is not already running, so the launcher has
# somewhere to send music. Exits 0 when something is already there, which is
# the common case and must stay cheap.
set -uo pipefail

if busctl --user list --no-legend 2>/dev/null | grep -qi 'org\.mpris\.MediaPlayer2\.[a-z]*spotify'; then
  exit 0
fi

# Detached from the shell that spawned it, so restarting the shell does not
# take the music player down with it. systemd-run is how Omarchy's own
# launchers do this; setsid covers a system without a user manager.
launch() {
  if command -v systemd-run >/dev/null 2>&1 &&
     systemd-run --user --quiet --collect \
       --unit="quickspot-spotify-$(date +%s%N)" "$@" 2>/dev/null; then
    return 0
  fi
  setsid "$@" >/dev/null 2>&1 &
  return 0
}

# Native package, then Arch's spotify-launcher, then Flatpak.
if command -v spotify >/dev/null 2>&1; then
  launch spotify
  exit 0
fi

if command -v spotify-launcher >/dev/null 2>&1; then
  launch spotify-launcher
  exit 0
fi

if command -v flatpak >/dev/null 2>&1 && flatpak info com.spotify.Client >/dev/null 2>&1; then
  launch flatpak run com.spotify.Client
  exit 0
fi

# No desktop client installed. The librespot daemon the Omarchy Spotify plugin
# ships is headless but plays just as well, so it is worth trying before giving
# up — QuickSpot's whole premise is not needing a window open.
if systemctl --user list-unit-files omarchy-spotify.service >/dev/null 2>&1; then
  systemctl --user start omarchy-spotify >/dev/null 2>&1 && exit 0
fi

echo "quickspot: no Spotify client found (tried spotify, spotify-launcher, flatpak, omarchy-spotify)" >&2
exit 1
