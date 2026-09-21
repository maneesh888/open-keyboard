#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONNECTOR_ROOT="$REPO_ROOT/Vendor/universal-ai-connector"
ARTIFACT="$CONNECTOR_ROOT/swift-package/Artifacts/UniversalAiConnectorBridge.xcframework"
STAMP_ROOT="$REPO_ROOT/.build/universal-ai-connector"

# Git exports the parent repository's local environment variables to hooks. Clear them before
# invoking Git or build scripts in the connector repository so pre-commit and pre-push validation
# inspect the connector's own HEAD and index instead of the parent worktree.
clear_outer_git_environment() {
  local variable
  while IFS= read -r variable; do
    [[ -n "$variable" ]] && unset "$variable"
  done <<< "$(git -C "$REPO_ROOT" rev-parse --local-env-vars)"
}

connector_git() (
  clear_outer_git_environment
  git -C "$CONNECTOR_ROOT" "$@"
)

artifact_is_usable() {
  local first_identifier second_identifier identifiers
  [[ -f "$ARTIFACT/Info.plist" ]] || return 1
  first_identifier="$(
    /usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:0:LibraryIdentifier' \
      "$ARTIFACT/Info.plist" 2>/dev/null
  )" || return 1
  second_identifier="$(
    /usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:1:LibraryIdentifier' \
      "$ARTIFACT/Info.plist" 2>/dev/null
  )" || return 1
  if /usr/libexec/PlistBuddy -c 'Print :AvailableLibraries:2:LibraryIdentifier' \
    "$ARTIFACT/Info.plist" >/dev/null 2>&1; then
    return 1
  fi
  identifiers="$(printf '%s\n%s\n' "$first_identifier" "$second_identifier" | LC_ALL=C sort)"
  [[ "$identifiers" == $'ios-arm64\nios-arm64-simulator' ]] || return 1
  [[ -f "$ARTIFACT/ios-arm64/UniversalAiConnectorBridge.framework/UniversalAiConnectorBridge" ]] || return 1
  [[ -f "$ARTIFACT/ios-arm64-simulator/UniversalAiConnectorBridge.framework/UniversalAiConnectorBridge" ]] || return 1
}

if ! connector_git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Universal AI Connector is not initialized. Run: git submodule update --init Vendor/universal-ai-connector" >&2
  exit 1
fi

connector_sha="$(connector_git rev-parse HEAD)"
recorded_sha="$(
  git -C "$REPO_ROOT" ls-files --stage Vendor/universal-ai-connector |
    awk '$1 == "160000" { print $2 }'
)"
if [[ -z "$recorded_sha" ]]; then
  recorded_sha="$(git -C "$REPO_ROOT" ls-tree HEAD Vendor/universal-ai-connector | awk '{print $3}')"
fi
if [[ -n "$recorded_sha" && "$recorded_sha" != "$connector_sha" ]]; then
  echo "Universal AI Connector checkout does not match the recorded gitlink." >&2
  exit 1
fi

if [[ -n "$(connector_git status --porcelain --untracked-files=no)" ]]; then
  echo "Universal AI Connector has tracked local changes; refusing to build an uncommitted API." >&2
  exit 1
fi

stamp="$STAMP_ROOT/$connector_sha.ready"
if [[ -f "$stamp" ]] && artifact_is_usable; then
  exit 0
fi

echo "Bootstrapping pinned Universal AI Connector Apple artifact..."
(
  clear_outer_git_environment
  cd "$CONNECTOR_ROOT"
  ./scripts/build-xcframework.sh
)

if ! artifact_is_usable; then
  echo "Universal AI Connector bootstrap did not produce the expected XCFramework." >&2
  exit 1
fi
if [[ -n "$(connector_git status --porcelain --untracked-files=no)" ]]; then
  echo "Universal AI Connector build changed tracked files; refusing the result." >&2
  exit 1
fi

mkdir -p "$STAMP_ROOT"
touch "$stamp"
