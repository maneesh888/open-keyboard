#!/bin/bash

# OpenKeyboard iOS/Core Test Runner
# Usage: ./scripts/ios/test.sh {core|build|ui|live-ui|screenshots|all|coverage}

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$REPO_ROOT/OpenKeyboard.xcodeproj"
SCHEME="OpenKeyboard"
DESTINATION="platform=iOS Simulator,name=iPhone 16"
SE_DESTINATION="platform=iOS Simulator,name=iPhone SE (3rd generation)"
CORE_PACKAGE="$REPO_ROOT/OpenKeyboardCore"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

run_xcodebuild() {
  if command -v xcpretty >/dev/null 2>&1; then
    "$@" | xcpretty
  else
    "$@"
  fi
}

require_xcodebuild() {
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo -e "${RED}✗ xcodebuild not found. Run this on the Mac host with Xcode installed.${NC}"
    exit 1
  fi
}

require_swift() {
  if ! command -v swift >/dev/null 2>&1; then
    echo -e "${RED}✗ swift not found. Run this on the Mac host with Xcode/Swift installed.${NC}"
    exit 1
  fi
}

case "${1:-}" in
  core)
    echo -e "${YELLOW}Running OpenKeyboardCore package tests...${NC}"
    require_swift
    swift test --package-path "$CORE_PACKAGE"
    echo -e "${GREEN}✓ Core tests complete${NC}"
    ;;

  build)
    echo -e "${YELLOW}Building OpenKeyboard iOS app...${NC}"
    require_xcodebuild
    run_xcodebuild xcodebuild build \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -configuration Debug \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO
    echo -e "${GREEN}✓ Build complete${NC}"
    ;;

  ui)
    echo -e "${YELLOW}Running OpenKeyboard UI tests on iPhone 16...${NC}"
    require_xcodebuild
    run_xcodebuild xcodebuild test \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -configuration Debug \
      -only-testing:OpenKeyboardUITests \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO
    echo -e "${GREEN}✓ UI tests complete${NC}"
    ;;

  live-ui)
    echo -e "${YELLOW}Running live gateway AI UI tests on iPhone 16...${NC}"
    require_xcodebuild
    if [[ -z "${OPEN_KEYBOARD_LIVE_GATEWAY_URL:-}" || -z "${OPEN_KEYBOARD_LIVE_API_KEY:-}" || -z "${OPEN_KEYBOARD_LIVE_MODEL:-}" ]]; then
      echo -e "${RED}✗ OPEN_KEYBOARD_LIVE_GATEWAY_URL, OPEN_KEYBOARD_LIVE_API_KEY, and OPEN_KEYBOARD_LIVE_MODEL are required for live-ui.${NC}"
      exit 1
    fi
    run_xcodebuild xcodebuild test \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -configuration Debug \
      -only-testing:OpenKeyboardUITests/LiveGatewayAIUITests \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO
    echo -e "${GREEN}✓ Live gateway AI UI tests complete${NC}"
    ;;

  screenshots)
    echo -e "${YELLOW}Running acceptance screenshot UI tests on iPhone 16 and home screenshots on iPhone SE...${NC}"
    require_xcodebuild
    echo -e "${YELLOW}Destination: $DESTINATION${NC}"
    run_xcodebuild xcodebuild test \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -configuration Debug \
      -resultBundlePath "$REPO_ROOT/.ci-results/acceptance-screenshots-iPhone16.xcresult" \
      -only-testing:OpenKeyboardUITests/AcceptanceScreenshotUITests \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO

    echo -e "${YELLOW}Destination: $SE_DESTINATION (home screenshots only)${NC}"
    run_xcodebuild xcodebuild test \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$SE_DESTINATION" \
      -configuration Debug \
      -resultBundlePath "$REPO_ROOT/.ci-results/acceptance-screenshots-iPhoneSE.xcresult" \
      -only-testing:OpenKeyboardUITests/AcceptanceScreenshotUITests/testHomeLaunchLightScreenshotHasNoPreviewOrDebugCopy \
      -only-testing:OpenKeyboardUITests/AcceptanceScreenshotUITests/testHomeLaunchDarkScreenshotHasNoPreviewOrDebugCopy \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO
    echo -e "${GREEN}✓ Screenshot UI tests complete${NC}"
    ;;

  all)
    "$0" core
    "$0" build
    "$0" ui
    ;;

  coverage)
    echo -e "${YELLOW}Running OpenKeyboardCore tests with coverage...${NC}"
    require_swift
    swift test --package-path "$CORE_PACKAGE" --enable-code-coverage
    echo -e "${GREEN}✓ Core coverage test run complete${NC}"
    ;;

  *)
    echo -e "${YELLOW}Usage: ./scripts/ios/test.sh {core|build|ui|live-ui|screenshots|all|coverage}${NC}"
    echo "  core        - Run Swift package tests for OpenKeyboardCore"
    echo "  build       - Build the iOS app/keyboard extension"
    echo "  ui          - Run OpenKeyboardUITests on iPhone 16"
    echo "  live-ui     - Run opt-in live gateway AI UI tests on iPhone 16"
    echo "  screenshots - Run acceptance screenshot UI tests with named XCTAttachments; real extension blockers fail explicitly"
    echo "  all         - Run core tests, iOS build, then UI tests"
    echo "  coverage    - Run core package tests with coverage"
    exit 1
    ;;
esac
