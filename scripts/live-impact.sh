#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPEN_KEYBOARD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BASE_SHA="${1:-}"
HEAD_SHA="${2:-}"

usage() {
  echo "Usage: ./scripts/live-impact.sh <base-sha> <head-sha>" >&2
}

if [[ "$#" -ne 2 ]]; then
  usage
  exit 2
fi

for revision in "$BASE_SHA" "$HEAD_SHA"; do
  if ! git -C "$ROOT" cat-file -e "$revision^{commit}" 2>/dev/null; then
    echo "Live-impact classification requires two valid commit SHAs." >&2
    exit 2
  fi
done

if ! git -C "$ROOT" merge-base "$BASE_SHA" "$HEAD_SHA" >/dev/null 2>&1; then
  echo "Live-impact classification requires commits with a common ancestor." >&2
  exit 2
fi

changed_paths_file="$(mktemp)"
trap 'rm -f "$changed_paths_file"' EXIT

git -C "$ROOT" diff \
  --name-only \
  --diff-filter=ACDMRT \
  -z \
  "$BASE_SHA...$HEAD_SHA" > "$changed_paths_file"

live_required="false"
while IFS= read -r -d '' changed_path; do
  case "$changed_path" in
    OpenKeyboard/Models/AppConfig.swift | \
      OpenKeyboard/Services/CanonicalGatewayClient.swift | \
      OpenKeyboard/Services/NetworkManager.swift | \
      OpenKeyboardCore/Package.swift | \
      OpenKeyboardCore/Sources/OpenKeyboardCore/Gateway*.swift | \
      OpenKeyboardExtension/KeyboardAIService.swift | \
      OpenKeyboardExtension/KeyboardViewModel.swift | \
      OpenKeyboard.xcodeproj/project.pbxproj | \
      OpenKeyboard/*.entitlements | \
      OpenKeyboardExtension/*.entitlements)
      live_required="true"
      ;;
  esac
done < "$changed_paths_file"

if [[ "$live_required" == "true" ]]; then
  echo "gateway"
else
  echo "none"
fi
