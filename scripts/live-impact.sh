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
  --no-renames \
  --name-only \
  --diff-filter=ACDMRT \
  -z \
  "$BASE_SHA...$HEAD_SHA" > "$changed_paths_file"

live_required="false"
while IFS= read -r -d '' changed_path; do
  case "$changed_path" in
    .github/pull_request_template.md | \
      .github/workflows/live.yml | \
      .gitmodules | \
      .githooks/pre-push | \
      scripts/check-live.sh | \
      scripts/check.sh | \
      scripts/check-semantic-prompt-contract.sh | \
      scripts/live-impact.sh | \
      scripts/ios/enable-openkeyboard-simulator-keyboard.sh | \
      scripts/ios/live-test-safety.sh | \
      scripts/ios/openkeyboard-gateway.seed.env.example | \
      scripts/ios/seed-simulator-gateway-config.sh | \
      scripts/ios/test.sh | \
      Vendor/semantic-prompt-contract | \
      OpenKeyboard/* | \
      OpenKeyboardCore/Package.swift | \
      OpenKeyboardCore/Sources/* | \
      OpenKeyboardExtension/* | \
      OpenKeyboardUITests/GatewayClientArchitectureTests.swift | \
      OpenKeyboardUITests/KeyboardExtensionConfiguredUITests.swift | \
      OpenKeyboard.xcodeproj/project.pbxproj)
      live_required="true"
      ;;
  esac
done < "$changed_paths_file"

if [[ "$live_required" == "true" ]]; then
  echo "gateway"
else
  echo "none"
fi
