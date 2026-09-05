#!/usr/bin/env bash
set -euo pipefail

runner=/usr/lib/qt6/bin/qmltestrunner
if [[ ! -x $runner ]]; then
  echo "run-tests.sh: Qt 6 qmltestrunner not found at $runner" >&2
  exit 1
fi

root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Qt 6 refuses XMLHttpRequest reads of local files unless this is set. Task 4's
# tests load a JSON fixture that way, and without it they fail in initTestCase
# with "Using GET on a local file is disabled by default."
export QML_XHR_ALLOW_FILE_READ=1
exec "$runner" -input "$root/tests"
