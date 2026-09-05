#!/usr/bin/env bash
set -euo pipefail

runner=/usr/lib/qt6/bin/qmltestrunner
if [[ ! -x $runner ]]; then
  echo "run-tests.sh: Qt 6 qmltestrunner not found at $runner" >&2
  exit 1
fi

root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "$runner" -input "$root/tests"
