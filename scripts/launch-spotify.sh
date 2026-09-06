#!/usr/bin/env bash
# Starts a Spotify client if one is not already running, so the launcher has
# somewhere to send music. Exits 0 when something is already there, which is
# the common case and must stay cheap.
#
# Under Hyprland the window is placed on the first empty workspace and left
# there unfocused, so starting music does not take over whatever you were
# doing.
set -uo pipefail

if busctl --user list --no-legend 2>/dev/null | grep -qi 'org\.mpris\.MediaPlayer2\.[a-z]*spotify'; then
  exit 0
fi

# The first empty workspace at or after the active one, wrapping to the lower
# ones if every higher workspace is occupied. Prints nothing when Hyprland is
# not answering, which is the signal to launch without placement.
empty_workspace() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local active occupied
  active=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty') || return 0
  [[ -n $active ]] || return 0

  # A workspace Hyprland does not list has no windows: it destroys empty ones.
  occupied=$(hyprctl workspaces -j 2>/dev/null | jq -r '.[] | select(.windows > 0) | .id') || return 0

  local candidate
  for candidate in $(seq $((active + 1)) 10) $(seq 1 "$active"); do
    if ! grep -qx "$candidate" <<<"$occupied"; then
      echo "$candidate"
      return 0
    fi
  done
}

WORKSPACE=$(empty_workspace)

# Detached from the shell that spawned it, so restarting the shell does not
# take the music player down with it. Under Hyprland the rule in brackets
# applies to the first window this exec produces and to nothing afterwards —
# `silent` places it without following it, and being one-shot means no rule is
# left behind to misplace a window later.
launch() {
  if [[ -n ${WORKSPACE:-} ]]; then
    # Hyprland 0.56 moved dispatch to a Lua API and no longer accepts the old
    # `dispatch exec "<rules> cmd"` form; the bracket rules still work inside
    # exec_cmd. The legacy form is kept as a fallback for older releases.
    if hyprctl dispatch "hl.dsp.exec_cmd(\"[workspace $WORKSPACE silent] $*\")" \
         >/dev/null 2>&1; then
      return 0
    fi
    if hyprctl dispatch exec "[workspace $WORKSPACE silent] $*" >/dev/null 2>&1; then
      return 0
    fi
  fi

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
# up — QuickSpot's whole premise is not needing a window open. No workspace
# placement applies: it has no window to place.
if systemctl --user list-unit-files omarchy-spotify.service >/dev/null 2>&1; then
  systemctl --user start omarchy-spotify >/dev/null 2>&1 && exit 0
fi

echo "quickspot: no Spotify client found (tried spotify, spotify-launcher, flatpak, omarchy-spotify)" >&2
exit 1
