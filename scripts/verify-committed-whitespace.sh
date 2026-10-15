#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPEN_KEYBOARD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BASE_REF="${OPEN_KEYBOARD_CHECK_BASE_REF:-origin/main}"

if ! git -C "$ROOT" cat-file -e "$BASE_REF^{commit}" 2>/dev/null; then
  echo "Committed-whitespace validation cannot resolve base $BASE_REF." >&2
  exit 1
fi
if ! git -C "$ROOT" merge-base "$BASE_REF" HEAD >/dev/null 2>&1; then
  echo "Committed-whitespace validation requires a common base." >&2
  exit 1
fi

git -C "$ROOT" diff --check "$BASE_REF...HEAD" --
