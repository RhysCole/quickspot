#!/usr/bin/env bash
# Writes the OAuth refresh token to disk with the permissions it deserves, and
# repairs those permissions on a file written by an earlier version.
#
# The token is read from stdin and never passed as an argument: argv is visible
# to every process on the machine through /proc, which would defeat the point of
# the file mode entirely.
#
#   store-token.sh write  <path>   read stdin, replace <path> atomically, 0600
#   store-token.sh secure <path>   fix the modes of an existing dir and file
set -euo pipefail

# Belt and braces with the explicit chmods below: anything created here is
# private from the moment it exists, so there is no window in which a wider
# mode is on disk.
umask 077

mode=${1:?usage: store-token.sh <write|secure> <path>}
target=${2:?usage: store-token.sh <write|secure> <path>}
dir=$(dirname -- "$target")

mkdir -p -- "$dir"
chmod 700 -- "$dir"

case $mode in
  secure)
    # Only the mode is corrected; the contents are left alone.
    [[ -e $target ]] && chmod 600 -- "$target"
    exit 0
    ;;
  write) ;;
  *)
    echo "store-token.sh: unknown mode: $mode" >&2
    exit 2
    ;;
esac

# Written to a temporary file in the same directory and renamed over the target,
# so a crash mid-write leaves the previous token intact rather than a truncated
# file that reads as "not signed in".
tmp=$(mktemp -- "$dir/.oauth.XXXXXXXX")
trap 'rm -f -- "$tmp"' EXIT

cat >"$tmp"
chmod 600 -- "$tmp"
mv -f -- "$tmp" "$target"

trap - EXIT
