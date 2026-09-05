#!/usr/bin/env bash
# Emits one line: "<verifier> <challenge> <state>".
#
# QML's JavaScript engine has neither a CSPRNG nor SHA-256, so PKCE material
# cannot be generated in the shell process. openssl is part of the Arch base
# system.
set -euo pipefail

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

verifier=$(openssl rand 32 | b64url)
challenge=$(printf '%s' "$verifier" | openssl dgst -sha256 -binary | b64url)
state=$(openssl rand 16 | b64url)

printf '%s %s %s\n' "$verifier" "$challenge" "$state"
