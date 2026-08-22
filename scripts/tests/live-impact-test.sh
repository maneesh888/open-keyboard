#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASSIFIER="$ROOT/scripts/live-impact.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

# Git exports repository-local variables to hooks. Clear them before operating on a fixture repo.
while IFS= read -r git_environment_name; do
  unset "$git_environment_name"
done < <(git -C "$ROOT" rev-parse --local-env-vars)

git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.name "OpenKeyboard Policy Test"
git -C "$FIXTURE" config user.email "policy-test@example.invalid"

printf 'base\n' > "$FIXTURE/README.md"
git -C "$FIXTURE" add README.md
git -C "$FIXTURE" commit -q -m base
base_sha="$(git -C "$FIXTURE" rev-parse HEAD)"

mkdir -p "$FIXTURE/docs"
printf 'documentation\n' > "$FIXTURE/docs/workflow.md"
git -C "$FIXTURE" add docs/workflow.md
git -C "$FIXTURE" commit -q -m docs
docs_sha="$(git -C "$FIXTURE" rev-parse HEAD)"

if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" "$base_sha" "$docs_sha")" != "none" ]]; then
  echo "Documentation-only changes must not require live verification." >&2
  exit 1
fi

assert_impact_path() {
  local relative_path="$1"
  local expected_impact="$2"
  local fixture_content="${3:-gateway-sensitive change}"
  local path_sha

  git -C "$FIXTURE" checkout -q -B impact-case "$docs_sha"
  mkdir -p "$(dirname "$FIXTURE/$relative_path")"
  printf '%s\n' "$fixture_content" > "$FIXTURE/$relative_path"
  git -C "$FIXTURE" add -- "$relative_path"
  git -C "$FIXTURE" commit -q -m "impact $relative_path"
  path_sha="$(git -C "$FIXTURE" rev-parse HEAD)"

  if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" "$docs_sha" "$path_sha")" != "$expected_impact" ]]; then
    echo "Path did not receive expected live-impact classification $expected_impact: $relative_path" >&2
    exit 1
  fi
}

gateway_sensitive_paths=(
  .github/pull_request_template.md
  .githooks/pre-push
  scripts/check.sh
  scripts/ios/enable-openkeyboard-simulator-keyboard.sh
  OpenKeyboard/Info.plist
  OpenKeyboard/Views/PlaygroundView.swift
  OpenKeyboard/Views/LiveAITestHarnessView.swift
  OpenKeyboard/Services/Nested/AnyGatewayRuntime.swift
  OpenKeyboard/Resources/Nested/GatewayPolicy.json
  OpenKeyboardCore/Package.swift
  OpenKeyboardCore/Sources/OpenKeyboardCore/GatewayClient.swift
  OpenKeyboardCore/Sources/AnotherModule/NestedGatewayRuntime.swift
  OpenKeyboardCore/Sources/AnotherModule/RuntimeContract.json
  OpenKeyboardExtension/Info.plist
  OpenKeyboardExtension/KeyboardAIService.swift
  OpenKeyboardExtension/Nested/AnyExtensionRuntime.swift
  OpenKeyboardExtension/Resources/RuntimeConfiguration.plist.template
  OpenKeyboardUITests/GatewayClientArchitectureTests.swift
  OpenKeyboardUITests/KeyboardExtensionConfiguredUITests.swift
  OpenKeyboard.xcodeproj/project.pbxproj
  OpenKeyboard/OpenKeyboard.entitlements
  OpenKeyboardExtension/OpenKeyboardExtension.entitlements
)

for gateway_sensitive_path in "${gateway_sensitive_paths[@]}"; do
  assert_impact_path "$gateway_sensitive_path" gateway
done


differential_workflow_paths=(
  .github/workflows/live.yml
  scripts/check-live.sh
  scripts/live-impact.sh
  scripts/validate-pr-live-evidence.sh
  scripts/ios/live-test-safety.sh
  scripts/ios/openkeyboard-gateway.seed.env.example
  scripts/ios/seed-simulator-gateway-config.sh
  scripts/ios/test.sh
)

for differential_workflow_path in "${differential_workflow_paths[@]}"; do
  assert_impact_path "$differential_workflow_path" gateway-differential
done

assert_impact_path \
  OpenKeyboardExtension/KeyboardViewModel.swift \
  gateway-differential \
  'automaticAnalysisWarning retry modelCapability'
assert_impact_path \
  OpenKeyboardExtension/KeyboardViewModel.swift \
  gateway-differential \
  'selectedActionErrorState translationWarning'
assert_impact_path \
  OpenKeyboard/Services/CanonicalGatewayClient.swift \
  gateway-differential \
  'decode structured response parser'
assert_impact_path \
  OpenKeyboardExtension/KeyboardAIService.swift \
  gateway-differential \
  'chunk long input boundary'
assert_impact_path \
  OpenKeyboardExtension/KeyboardViewModel.swift \
  gateway \
  'unrelated keyboard layout adjustment'

gateway_sha="$(git -C "$FIXTURE" rev-parse HEAD)"

git -C "$FIXTURE" checkout -q -B rename-base "$docs_sha"
mkdir -p "$FIXTURE/OpenKeyboard/Resources" "$FIXTURE/docs"
printf 'runtime configuration\n' > "$FIXTURE/OpenKeyboard/Resources/runtime-policy.json"
git -C "$FIXTURE" add OpenKeyboard/Resources/runtime-policy.json
git -C "$FIXTURE" commit -q -m runtime-base
rename_base_sha="$(git -C "$FIXTURE" rev-parse HEAD)"
git -C "$FIXTURE" mv \
  OpenKeyboard/Resources/runtime-policy.json \
  docs/runtime-policy.json
git -C "$FIXTURE" commit -q -m rename-runtime-out
rename_out_sha="$(git -C "$FIXTURE" rev-parse HEAD)"

if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" "$rename_base_sha" "$rename_out_sha")" != "gateway" ]]; then
  echo "Renaming a runtime file out of a sensitive directory bypassed live verification." >&2
  exit 1
fi

if OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" invalid "$gateway_sha" >/dev/null 2>&1; then
  echo "Live-impact classification accepted an invalid revision." >&2
  exit 1
fi

echo "Live-impact regression tests passed."
