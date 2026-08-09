#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/check-environment.sh"

"$SCRIPT" --help >/dev/null

set +e
"$SCRIPT" --not-a-mode >/dev/null 2>&1
status=$?
set -e

if [[ "$status" -ne 2 ]]; then
  echo "Environment preflight must reject unknown modes with exit 2." >&2
  exit 1
fi

echo "Environment preflight policy tests passed."
