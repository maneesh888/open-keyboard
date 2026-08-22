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
differential_required="false"
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
      scripts/validate-pr-live-evidence.sh | \
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

  case "$changed_path" in
    .github/workflows/live.yml | \
      scripts/check-live.sh | \
      scripts/live-impact.sh | \
      scripts/validate-pr-live-evidence.sh | \
      scripts/ios/live-test-safety.sh | \
      scripts/ios/openkeyboard-gateway.seed.env.example | \
      scripts/ios/seed-simulator-gateway-config.sh | \
      scripts/ios/test.sh)
      differential_required="true"
      ;;
    OpenKeyboard/Models/KeyboardSuggestionModels.swift | \
      OpenKeyboard/Services/CanonicalGatewayClient.swift | \
      OpenKeyboard/Services/NetworkManager.swift | \
      OpenKeyboardCore/Sources/OpenKeyboardCore/GatewayClient.swift | \
      OpenKeyboardExtension/KeyboardAIService.swift | \
      OpenKeyboardExtension/KeyboardViewModel.swift | \
      OpenKeyboardUITests/GatewayClientArchitectureTests.swift | \
      OpenKeyboardUITests/KeyboardViewModelActionErrorTests.swift)
      if git -C "$ROOT" diff --no-ext-diff --unified=0 "$BASE_SHA...$HEAD_SHA" -- "$changed_path" |
          grep -E '^[+-][^+-].*(modelCapability|translationCapability|translationWarning|Translate warning|unusableCorrection|invalidResponse|longCapability|GrammarTextChunker|chunk|long input|automaticAnalysisWarning|automatic analysis|retry|parser|parse|decode|structured|selectedActionError|actionErrorState|manual action|LiveModelDifferential)' >/dev/null; then
        differential_required="true"
      fi
      ;;
  esac
done < "$changed_paths_file"

if [[ "$differential_required" == "true" ]]; then
  echo "gateway-differential"
elif [[ "$live_required" == "true" ]]; then
  echo "gateway"
else
  echo "none"
fi
