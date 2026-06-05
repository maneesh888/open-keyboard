#!/bin/bash

# OpenKeyboard local CI runner.
# Usage: ./scripts/local-ci.sh [--quick|--all|--core|--ios-build|--ui|--live-ui|--screenshots]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="$REPO_ROOT/.ci-results"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
LOG_FILE="$RESULTS_DIR/local-ci_$TIMESTAMP.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MODE="${1:---quick}"
mkdir -p "$RESULTS_DIR"

run_step() {
  local name="$1"
  shift
  echo -e "${CYAN}⏳ $name${NC}" | tee -a "$LOG_FILE"
  if "$@" 2>&1 | tee -a "$LOG_FILE"; then
    echo -e "${GREEN}✅ $name passed${NC}" | tee -a "$LOG_FILE"
  else
    echo -e "${RED}❌ $name failed${NC}" | tee -a "$LOG_FILE"
    echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
    exit 1
  fi
}

case "$MODE" in
  --quick|--all)
    run_step "Core package tests" "$SCRIPT_DIR/ios/test.sh" core
    run_step "iOS app build" "$SCRIPT_DIR/ios/test.sh" build
    ;;

  --core)
    run_step "Core package tests" "$SCRIPT_DIR/ios/test.sh" core
    ;;

  --ios-build)
    run_step "iOS app build" "$SCRIPT_DIR/ios/test.sh" build
    ;;

  --ui)
    run_step "OpenKeyboard UI tests" "$SCRIPT_DIR/ios/test.sh" ui
    ;;

  --live-ui)
    run_step "OpenKeyboard live gateway AI UI tests" "$SCRIPT_DIR/ios/test.sh" live-ui
    ;;

  --screenshots)
    run_step "OpenKeyboard screenshot UI tests" "$SCRIPT_DIR/ios/test.sh" screenshots
    ;;

  --help|-h)
    echo "Usage: ./scripts/local-ci.sh [--quick|--all|--core|--ios-build|--ui|--live-ui|--screenshots]"
    echo "  --quick       Run core tests + iOS build (default)"
    echo "  --all         Run core tests + iOS build (UI tests are available via --ui)"
    echo "  --core        Run OpenKeyboardCore Swift package tests only"
    echo "  --ios-build   Build OpenKeyboard app/extension only"
    echo "  --ui          Run OpenKeyboardUITests on iPhone 16"
    echo "  --live-ui     Run opt-in live gateway AI UI tests on iPhone 16"
    echo "  --screenshots Run onboarding screenshot UI tests on iPhone 16 and iPhone SE"
    ;;

  *)
    echo -e "${YELLOW}Unknown option: $MODE${NC}"
    echo "Use --help"
    exit 1
    ;;
esac

echo -e "${GREEN}✅ OpenKeyboard local CI complete${NC}"
echo "Log: $LOG_FILE"
