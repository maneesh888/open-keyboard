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

assert_gateway_path() {
  local relative_path="$1"
  local path_sha

  git -C "$FIXTURE" checkout -q -B impact-case "$docs_sha"
  mkdir -p "$(dirname "$FIXTURE/$relative_path")"
  printf 'gateway-sensitive change\n' > "$FIXTURE/$relative_path"
  git -C "$FIXTURE" add -- "$relative_path"
  git -C "$FIXTURE" commit -q -m "impact $relative_path"
  path_sha="$(git -C "$FIXTURE" rev-parse HEAD)"

  if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" "$docs_sha" "$path_sha")" != "gateway" ]]; then
    echo "Gateway-sensitive path was not classified for live verification: $relative_path" >&2
    exit 1
  fi
}

gateway_sensitive_paths=(
  .github/pull_request_template.md
  .github/workflows/live.yml
  .githooks/pre-push
  scripts/check-live.sh
  scripts/check.sh
  scripts/live-impact.sh
  scripts/ios/enable-openkeyboard-simulator-keyboard.sh
  scripts/ios/live-test-safety.sh
  scripts/ios/openkeyboard-gateway.seed.env.example
  scripts/ios/seed-simulator-gateway-config.sh
  scripts/ios/test.sh
  OpenKeyboard/Info.plist
  OpenKeyboard/Views/PlaygroundView.swift
  OpenKeyboard/Views/LiveAITestHarnessView.swift
  OpenKeyboard/Services/Nested/AnyGatewayRuntime.swift
  OpenKeyboardCore/Package.swift
  OpenKeyboardCore/Sources/OpenKeyboardCore/GatewayClient.swift
  OpenKeyboardCore/Sources/AnotherModule/NestedGatewayRuntime.swift
  OpenKeyboardExtension/Info.plist
  OpenKeyboardExtension/KeyboardAIService.swift
  OpenKeyboardExtension/Nested/AnyExtensionRuntime.swift
  OpenKeyboardUITests/GatewayClientArchitectureTests.swift
  OpenKeyboardUITests/KeyboardExtensionConfiguredUITests.swift
  OpenKeyboard.xcodeproj/project.pbxproj
  OpenKeyboard/OpenKeyboard.entitlements
  OpenKeyboardExtension/OpenKeyboardExtension.entitlements
)

for gateway_sensitive_path in "${gateway_sensitive_paths[@]}"; do
  assert_gateway_path "$gateway_sensitive_path"
done

gateway_sha="$(git -C "$FIXTURE" rev-parse HEAD)"

if OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" invalid "$gateway_sha" >/dev/null 2>&1; then
  echo "Live-impact classification accepted an invalid revision." >&2
  exit 1
fi

echo "Live-impact regression tests passed."
