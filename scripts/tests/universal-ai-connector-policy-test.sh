#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$ROOT/OpenKeyboard.xcodeproj/project.pbxproj"
ADAPTER="$ROOT/OpenKeyboard/Services/UniversalAIConnectorAdapter.swift"

if ! git -C "$ROOT" config --file .gitmodules --get-regexp '^submodule\.Vendor/universal-ai-connector\.path$' |
  grep -q 'Vendor/universal-ai-connector$'; then
  echo "Universal AI Connector must be recorded as a Git submodule." >&2
  exit 1
fi

if [[ "$(grep -c 'productName = UniversalAiConnector;' "$PROJECT")" -ne 3 ]]; then
  echo "The app, keyboard extension, and UI-test target must link the public connector product." >&2
  exit 1
fi
if ! grep -q 'relativePath = "Vendor/universal-ai-connector/swift-package";' "$PROJECT"; then
  echo "The Xcode project must consume the pinned connector Swift package." >&2
  exit 1
fi
if [[ "$(grep -c 'APPLICATION_EXTENSION_API_ONLY = YES;' "$PROJECT")" -ne 2 ]]; then
  echo "The keyboard extension must enforce extension-safe APIs." >&2
  exit 1
fi

if ! grep -q '^import UniversalAiConnector$' "$ADAPTER"; then
  echo "The production adapter must import the public connector product." >&2
  exit 1
fi
if rg --quiet '^import UniversalAiConnectorBridge$' \
  "$ROOT/OpenKeyboard" "$ROOT/OpenKeyboardExtension" "$ROOT/OpenKeyboardUITests"; then
  echo "OpenKeyboard must not import the connector's private bridge." >&2
  exit 1
fi
if rg --quiet '\bURLSession\b|\bURLRequest\b' \
  "$ROOT/OpenKeyboard" "$ROOT/OpenKeyboardExtension" "$ROOT/OpenKeyboardCore/Sources"; then
  echo "Direct HTTP transport re-entered an active OpenKeyboard production target." >&2
  exit 1
fi

if ! grep -q 'bootstrap-universal-ai-connector.sh' "$ROOT/scripts/ios/test.sh"; then
  echo "iOS build and test routes must bootstrap the pinned connector artifact." >&2
  exit 1
fi
if ! grep -q './scripts/build-xcframework.sh' "$ROOT/scripts/bootstrap-universal-ai-connector.sh"; then
  echo "The bootstrap must use the connector repository's canonical build entry point." >&2
  exit 1
fi
if ! grep -q 'rev-parse --local-env-vars' "$ROOT/scripts/bootstrap-universal-ai-connector.sh"; then
  echo "The bootstrap must clear parent Git hook variables before inspecting the connector repository." >&2
  exit 1
fi

echo "Universal AI Connector consumption policy tests passed."
