#!/bin/bash

# OpenKeyboard iOS/Core Test Runner
# Usage: ./scripts/ios/test.sh {core|build|deterministic-ui|ui|live-ui|live-gateway-smoke|live-model-differential|real-keyboard-live|screenshots|all|coverage}

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$REPO_ROOT/OpenKeyboard.xcodeproj"
SCHEME="OpenKeyboard"
BUILD_DESTINATION="generic/platform=iOS Simulator"
DESTINATION="platform=iOS Simulator,name=iPhone 16"
SE_DESTINATION="platform=iOS Simulator,name=iPhone SE (3rd generation)"
CORE_PACKAGE="$REPO_ROOT/OpenKeyboardCore"
DETERMINISTIC_UI_DERIVED_DATA="$REPO_ROOT/.build/deterministic-ui/DerivedData"
DEFAULT_SIMULATOR_GATEWAY_SEED_FILE=".agent/local-seeds/openkeyboard-gateway.env"
DEFAULT_REAL_KEYBOARD_SIMULATOR="${OPEN_KEYBOARD_REAL_KEYBOARD_SIMULATOR:-iPhone 17 Pro}"
source "$REPO_ROOT/scripts/ios/live-test-safety.sh"

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

simulator_destination() {
  local simulator="$1"
  if [[ "$simulator" =~ ^[0-9A-Fa-f-]{8}-[0-9A-Fa-f-]{4}-[0-9A-Fa-f-]{4}-[0-9A-Fa-f-]{4}-[0-9A-Fa-f-]{12}$ ]]; then
    printf 'platform=iOS Simulator,id=%s' "$simulator"
  else
    printf 'platform=iOS Simulator,name=%s' "$simulator"
  fi
}

plist_set_or_add_string() {
  local plist="$1"
  local path="$2"
  local value="$3"

  if /usr/libexec/PlistBuddy -c "Print $path" "$plist" >/dev/null 2>&1; then
    printf 'Set %s %s\nSave\n' "$path" "$value" | /usr/libexec/PlistBuddy "$plist" >/dev/null
  else
    printf 'Add %s string %s\nSave\n' "$path" "$value" | /usr/libexec/PlistBuddy "$plist" >/dev/null
  fi
}

plist_set_or_add_exact_string() {
  local plist="$1"
  local path="$2"
  local value="$3"
  local plist_path="${path#:}"
  plist_path="${plist_path//:/.}"

  if ! /usr/libexec/PlistBuddy -c "Print $path" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Add $path string placeholder" "$plist" >/dev/null
  fi
  /usr/bin/plutil -replace "$plist_path" -string "$value" "$plist"
}

inject_xctestrun_gateway_env() {
  local xctestrun="$1"
  local roots=(
    ":TestConfigurations:0:TestTargets:0:EnvironmentVariables"
    ":TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables"
    ":TestConfigurations:0:TestTargets:0:UITargetAppEnvironmentVariables"
  )
  local root

  for root in "${roots[@]}"; do
    plist_set_or_add_string "$xctestrun" "$root:OPEN_KEYBOARD_TEST_GATEWAY_URL" "$OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL"
    plist_set_or_add_string "$xctestrun" "$root:OPEN_KEYBOARD_TEST_API_KEY" "$OPEN_KEYBOARD_SIMULATOR_API_KEY"
    plist_set_or_add_string "$xctestrun" "$root:OPEN_KEYBOARD_TEST_MODEL" "$OPEN_KEYBOARD_SIMULATOR_MODEL"
    if [[ -n "${OPEN_KEYBOARD_REAL_SCREENSHOT_DIR:-}" ]]; then
      plist_set_or_add_string "$xctestrun" "$root:OPEN_KEYBOARD_REAL_SCREENSHOT_DIR" "$OPEN_KEYBOARD_REAL_SCREENSHOT_DIR"
    fi
    if [[ -n "${OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE:-}" ]]; then
      plist_set_or_add_exact_string "$xctestrun" "$root:OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE" "$OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE"
    fi
  done
}

inject_xctestrun_live_smoke_env() {
  local xctestrun="$1"
  local gateway_url_hex api_key_hex
  local roots=(
    ":TestConfigurations:0:TestTargets:0:EnvironmentVariables"
    ":TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables"
    ":TestConfigurations:0:TestTargets:0:UITargetAppEnvironmentVariables"
  )
  local root

  gateway_url_hex="$(printf '%s' "$OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL" | od -An -tx1 | tr -d ' \n')"
  api_key_hex="$(printf '%s' "$OPEN_KEYBOARD_SIMULATOR_API_KEY" | od -An -tx1 | tr -d ' \n')"
  for root in "${roots[@]}"; do
    plist_set_or_add_string "$xctestrun" "$root:OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX" "$gateway_url_hex"
    plist_set_or_add_string "$xctestrun" "$root:OPEN_KEYBOARD_TEST_API_KEY_HEX" "$api_key_hex"
    plist_set_or_add_string "$xctestrun" "$root:OPEN_KEYBOARD_TEST_MODEL" "$OPEN_KEYBOARD_SIMULATOR_MODEL"
    if [[ -n "${OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE:-}" ]]; then
      plist_set_or_add_string "$xctestrun" "$root:OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE" "$OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE"
    fi
  done
}

SENSITIVE_LIVE_WORKSPACE=""
SENSITIVE_LIVE_SIMULATOR=""
SENSITIVE_LIVE_SOURCE_SIMULATOR=""
SENSITIVE_LIVE_SOURCE_WAS_BOOTED="false"
SENSITIVE_LIVE_CLOSE_SIMULATOR_APP="true"
SENSITIVE_LIVE_SIMULATOR_WAS_CREATED="false"

restore_sensitive_live_source_simulator() {
  if [[ "$SENSITIVE_LIVE_SOURCE_WAS_BOOTED" != "true" || -z "$SENSITIVE_LIVE_SOURCE_SIMULATOR" ]]; then
    return 0
  fi

  if ! openkeyboard_restore_booted_simulator "$SENSITIVE_LIVE_SOURCE_SIMULATOR"; then
    return 1
  fi
  SENSITIVE_LIVE_SOURCE_SIMULATOR=""
  SENSITIVE_LIVE_SOURCE_WAS_BOOTED="false"
  return 0
}

cleanup_sensitive_live_artifacts() {
  local original_status=$?
  local cleanup_status=0

  if ! delete_sensitive_live_simulator; then
    cleanup_status=1
  fi

  if ! restore_sensitive_live_source_simulator; then
    echo -e "${RED}✗ Failed to restore the source simulator after cloning.${NC}" >&2
    cleanup_status=1
  fi

  if [[ "$SENSITIVE_LIVE_SIMULATOR_WAS_CREATED" == "true" && \
        "$SENSITIVE_LIVE_CLOSE_SIMULATOR_APP" == "true" ]] && \
      ! openkeyboard_stop_simulator_app; then
    cleanup_status=1
  fi

  openkeyboard_unset_simulator_gateway_profiles
  unset \
    OPEN_KEYBOARD_TEST_GATEWAY_URL \
    OPEN_KEYBOARD_TEST_API_KEY \
    OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX \
    OPEN_KEYBOARD_TEST_API_KEY_HEX \
    OPEN_KEYBOARD_TEST_MODEL \
    OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE

  if [[ -n "$SENSITIVE_LIVE_WORKSPACE" ]]; then
    if ! rm -rf -- "$SENSITIVE_LIVE_WORKSPACE"; then
      echo -e "${RED}✗ Failed to remove the sensitive live-test workspace.${NC}" >&2
      cleanup_status=1
    fi
    SENSITIVE_LIVE_WORKSPACE=""
  fi

  if [[ "$original_status" -ne 0 ]]; then
    return "$original_status"
  fi
  if [[ "$cleanup_status" -ne 0 ]]; then
    trap - EXIT
    exit "$cleanup_status"
  fi
  return "$cleanup_status"
}

delete_sensitive_live_simulator() {
  if [[ -z "$SENSITIVE_LIVE_SIMULATOR" ]]; then
    return 0
  fi

  xcrun simctl shutdown "$SENSITIVE_LIVE_SIMULATOR" >/dev/null 2>&1 || true
  if ! xcrun simctl delete "$SENSITIVE_LIVE_SIMULATOR" >/dev/null 2>&1; then
    echo -e "${RED}✗ Failed to delete the disposable live-test simulator.${NC}" >&2
    return 1
  fi
  SENSITIVE_LIVE_SIMULATOR=""
}

select_loaded_live_profile() {
  local requested_profile="${1:-reference}"

  case "$requested_profile" in
    reference)
      openkeyboard_select_reference_simulator_gateway_profile
      ;;
    legacy|low|high)
      openkeyboard_select_simulator_gateway_profile "$requested_profile"
      ;;
    *)
      echo -e "${RED}✗ Live profile must be reference, legacy, low, or high.${NC}" >&2
      return 2
      ;;
  esac
}

monotonic_seconds() {
  ruby -e 'printf "%.6f", Process.clock_gettime(Process::CLOCK_MONOTONIC)'
}

elapsed_seconds() {
  ruby -e 'printf "%.3f", Float(ARGV.fetch(1)) - Float(ARGV.fetch(0))' "$1" "$2"
}

begin_sensitive_live_workspace() {
  local label="$1"

  case "${OPEN_KEYBOARD_KEEP_SIMULATOR_APP_OPEN:-false}" in
    false) SENSITIVE_LIVE_CLOSE_SIMULATOR_APP="true" ;;
    true) SENSITIVE_LIVE_CLOSE_SIMULATOR_APP="false" ;;
    *)
      echo -e "${RED}✗ OPEN_KEYBOARD_KEEP_SIMULATOR_APP_OPEN must be true or false.${NC}" >&2
      exit 2
      ;;
  esac

  SENSITIVE_LIVE_WORKSPACE="$(
    mktemp -d "${TMPDIR:-/tmp}/openkeyboard-$label.XXXXXX"
  )"
  trap cleanup_sensitive_live_artifacts EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  chmod 700 "$SENSITIVE_LIVE_WORKSPACE"
}

create_sensitive_live_simulator() {
  local selector="$1"
  local descriptor source_simulator source_state simulator_name

  descriptor="$(
    xcrun simctl list devices available -j |
      ruby -rjson -e '
        selector = ARGV.fetch(0)
        devices = JSON.parse(STDIN.read).fetch("devices")
        matches = devices.flat_map do |runtime, entries|
          entries.map do |device|
            next unless device["udid"] == selector || device["name"] == selector
            [device.fetch("udid"), device.fetch("state")]
          end.compact
        end
        abort "Simulator selector must resolve to exactly one available device." unless matches.one?
        puts matches.first.join("\t")
      ' "$selector"
  )"
  source_simulator="${descriptor%%$'\t'*}"
  source_state="${descriptor#*$'\t'}"
  case "$source_state" in
    Booted)
      SENSITIVE_LIVE_SOURCE_SIMULATOR="$source_simulator"
      SENSITIVE_LIVE_SOURCE_WAS_BOOTED="true"
      xcrun simctl shutdown "$source_simulator"
      ;;
    Shutdown) ;;
    *)
      echo -e "${RED}✗ Source simulator must be booted or shut down before cloning.${NC}" >&2
      exit 1
      ;;
  esac

  simulator_name="OpenKeyboard Live Test $$ $(date +%s)"
  SENSITIVE_LIVE_SIMULATOR="$(
    xcrun simctl clone "$source_simulator" "$simulator_name"
  )"
  if [[ ! "$SENSITIVE_LIVE_SIMULATOR" =~ ^[0-9A-Fa-f-]{36}$ ]]; then
    echo -e "${RED}✗ Failed to create a disposable live-test simulator.${NC}" >&2
    exit 1
  fi
  SENSITIVE_LIVE_SIMULATOR_WAS_CREATED="true"
  if ! restore_sensitive_live_source_simulator; then
    echo -e "${RED}✗ Failed to restore the source simulator after cloning.${NC}" >&2
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
      -destination "$BUILD_DESTINATION" \
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

  deterministic-ui)
    echo -e "${YELLOW}Running deterministic OpenKeyboard UI-target tests on iPhone 16...${NC}"
    require_xcodebuild
    run_xcodebuild xcodebuild test \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -configuration Debug \
      -derivedDataPath "$DETERMINISTIC_UI_DERIVED_DATA" \
      -parallel-testing-enabled NO \
      -only-testing:OpenKeyboardUITests \
      -skip-testing:OpenKeyboardUITests/KeyboardExtensionConfiguredUITests \
      -skip-testing:OpenKeyboardUITests/LiveGatewayAIUITests \
      -skip-testing:OpenKeyboardUITests/LiveGatewaySmokeTests \
      -skip-testing:OpenKeyboardUITests/LiveModelDifferentialTests \
      -skip-testing:OpenKeyboardUITests/OnboardingScreenshotUITests \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO
    run_xcodebuild xcodebuild test \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION" \
      -configuration Debug \
      -derivedDataPath "$DETERMINISTIC_UI_DERIVED_DATA" \
      -parallel-testing-enabled NO \
      -only-testing:OpenKeyboardUITests/OnboardingScreenshotUITests/testWelcomePageContentIsVisibleAndNonOverlapping \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO
    echo -e "${GREEN}✓ Deterministic UI-target tests complete${NC}"
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

  live-gateway-smoke)
    echo -e "${YELLOW}Running opt-in live gateway Test Connection smoke on iPhone 16...${NC}"
    require_xcodebuild
    begin_sensitive_live_workspace live-gateway-smoke
    seed_file="$(
      openkeyboard_require_local_seed_file \
        "$REPO_ROOT" \
        "${OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE:-$DEFAULT_SIMULATOR_GATEWAY_SEED_FILE}"
    )" || exit 2
    create_sensitive_live_simulator "iPhone 16"
    destination="$(simulator_destination "$SENSITIVE_LIVE_SIMULATOR")"
    derived_data="$SENSITIVE_LIVE_WORKSPACE/DerivedData"
    result_bundle="$SENSITIVE_LIVE_WORKSPACE/live-gateway-smoke.xcresult"

    openkeyboard_load_simulator_gateway_seed "$seed_file"
    select_loaded_live_profile "${OPEN_KEYBOARD_LIVE_PROFILE:-reference}"
    echo "Loaded live gateway smoke configuration from ignored local seed file. Values are not printed."
    echo "Credential profile: $OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE"
    run_xcodebuild xcodebuild build-for-testing \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$destination" \
      -configuration Debug \
      -derivedDataPath "$derived_data" \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO

    xctestrun="$(find "$derived_data/Build/Products" -name '*.xctestrun' -print -quit)"
    if [[ -z "$xctestrun" ]]; then
      echo -e "${RED}✗ .xctestrun file was not produced under $derived_data/Build/Products${NC}"
      exit 1
    fi

    inject_xctestrun_live_smoke_env "$xctestrun"
    openkeyboard_unset_simulator_gateway_profiles
    run_xcodebuild xcodebuild test-without-building \
      -xctestrun "$xctestrun" \
      -destination "$destination" \
      -only-testing:OpenKeyboardUITests/LiveGatewaySmokeTests/testLiveGatewayTestConnectionServicePathWhenSeeded \
      -resultBundlePath "$result_bundle"
    openkeyboard_assert_single_passing_xcresult "$result_bundle"
    echo -e "${GREEN}✓ Live gateway Test Connection smoke complete${NC}"
    echo "Sensitive live-test artifacts will be removed before exit."
    ;;

  live-model-differential)
    echo -e "${YELLOW}Running targeted two-profile live-model differential verification...${NC}"
    require_xcodebuild
    begin_sensitive_live_workspace live-model-differential
    seed_file="$(
      openkeyboard_require_local_seed_file \
        "$REPO_ROOT" \
        "${OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE:-$DEFAULT_SIMULATOR_GATEWAY_SEED_FILE}"
    )" || exit 2
    openkeyboard_load_simulator_gateway_seed "$seed_file"
    openkeyboard_require_two_profile_gateway_seed
    low_model="$OPEN_KEYBOARD_SIMULATOR_LOW_MODEL"
    high_model="$OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL"
    derived_data="$SENSITIVE_LIVE_WORKSPACE/DerivedData"

    create_sensitive_live_simulator "iPhone 16"
    destination="$(simulator_destination "$SENSITIVE_LIVE_SIMULATOR")"
    echo "Building the targeted live-test artifacts once."
    run_xcodebuild xcodebuild build-for-testing \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$destination" \
      -configuration Debug \
      -derivedDataPath "$derived_data" \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO

    xctestrun="$(find "$derived_data/Build/Products" -name '*.xctestrun' -print -quit)"
    if [[ -z "$xctestrun" ]]; then
      echo -e "${RED}✗ .xctestrun file was not produced under $derived_data/Build/Products${NC}"
      exit 1
    fi

    contract_result_bundle="$SENSITIVE_LIVE_WORKSPACE/live-model-contracts.xcresult"
    echo "Running deterministic operation-scoped warning prerequisites once."
    run_xcodebuild xcodebuild test-without-building \
      -xctestrun "$xctestrun" \
      -destination "$destination" \
      -only-testing:OpenKeyboardUITests/GatewayClientArchitectureTests/testKeyboardAIServiceClassifiesMalformedStructuredJSONAsModelCapabilityFailure \
      -only-testing:OpenKeyboardUITests/GatewayClientArchitectureTests/testKeyboardAIServiceRetriesGenericTranslationCapabilityFailureThenScopesWarning \
      -only-testing:OpenKeyboardUITests/KeyboardViewModelActionErrorTests/testModelCapabilityFailureIsShownForRewriteActionPanelAndPreservesText \
      -only-testing:OpenKeyboardUITests/KeyboardViewModelActionErrorTests/testAutomaticGrammarCapabilityFailureShowsTypedStateAndPreservesText \
      -only-testing:OpenKeyboardUITests/KeyboardViewModelActionErrorTests/testTypingAfterAutomaticGrammarCapabilityFailureRetriesUpdatedText \
      -only-testing:OpenKeyboardUITests/KeyboardViewModelActionErrorTests/testTranslationModelCapabilityFailureStaysWarningScopedAndDoesNotAffectRewrite \
      -resultBundlePath "$contract_result_bundle"
    openkeyboard_assert_passing_xcresult_count "$contract_result_bundle" 6

    low_latency=""
    high_latency=""
    low_differential_outcome=""
    low_baseline_outcome="unverified"
    low_follow_up_outcome="unverified"
    high_baseline_outcome="unverified"
    high_differential_outcome="unverified"
    high_follow_up_outcome="unverified"
    for profile_role in low high; do
      if [[ "$profile_role" == "high" ]]; then
        delete_sensitive_live_simulator
        create_sensitive_live_simulator "iPhone 16"
        destination="$(simulator_destination "$SENSITIVE_LIVE_SIMULATOR")"
      fi

      openkeyboard_load_simulator_gateway_seed "$seed_file"
      openkeyboard_select_simulator_gateway_profile "$profile_role"
      OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE="$profile_role"
      inject_xctestrun_live_smoke_env "$xctestrun"
      openkeyboard_unset_simulator_gateway_profiles
      profile_result_bundle="$SENSITIVE_LIVE_WORKSPACE/live-model-$profile_role.xcresult"
      profile_started_at="$(monotonic_seconds)"
      echo "Running isolated $profile_role profile baseline, boundary, and follow-up scenarios."
      profile_command_passed="true"
      if ! run_xcodebuild xcodebuild test-without-building \
          -xctestrun "$xctestrun" \
          -destination "$destination" \
          -only-testing:OpenKeyboardUITests/LiveModelDifferentialTests/testConfiguredProfileDifferentialContract \
          -resultBundlePath "$profile_result_bundle"; then
        profile_command_passed="false"
      fi
      profile_finished_at="$(monotonic_seconds)"
      if [[ "$profile_role" == "low" ]]; then
        if [[ "$profile_command_passed" == "true" ]]; then
          if low_differential_outcome="$(
              openkeyboard_classify_low_differential_xcresult "$profile_result_bundle"
            )"; then
            low_baseline_outcome="passed"
            low_follow_up_outcome="passed"
          else
            low_differential_outcome="unverified"
          fi
        else
          low_differential_outcome="unverified"
        fi
      else
        if [[ "$profile_command_passed" == "true" ]] && \
            openkeyboard_assert_single_passing_xcresult "$profile_result_bundle"; then
          high_baseline_outcome="passed"
          high_differential_outcome="passed"
          high_follow_up_outcome="passed"
        fi
      fi
      profile_latency="$(elapsed_seconds "$profile_started_at" "$profile_finished_at")"
      case "$profile_role" in
        low) low_latency="$profile_latency" ;;
        high) high_latency="$profile_latency" ;;
      esac
    done

    evidence_lines="$(printf '%s\n' \
      "models=low=$low_model, high=$high_model" \
      "baseline_outcomes=low=$low_baseline_outcome, high=$high_baseline_outcome" \
      "differential_outcomes=low=$low_differential_outcome, high=$high_differential_outcome" \
      "follow_up_outcomes=low=$low_follow_up_outcome, high=$high_follow_up_outcome" \
      'operation_scoped_warning_contracts=verified' \
      "profile_latencies=low=${low_latency}s, high=${high_latency}s")"
    printf '%s\n' "$evidence_lines"
    if [[ -n "${OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT:-}" ]]; then
      umask 077
      printf '%s\n' "$evidence_lines" > "$OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT"
      chmod 600 "$OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT"
    fi
    echo -e "${GREEN}✓ Targeted two-profile live-model differential verification complete${NC}"
    echo "Sensitive per-profile test state and artifacts will be removed before exit."
    ;;

  real-keyboard-live)
    echo -e "${YELLOW}Running seeded real keyboard extension live test...${NC}"
    require_xcodebuild
    live_test_identifier="${OPEN_KEYBOARD_REAL_KEYBOARD_LIVE_TEST:-OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardImproveReplacesTextWhenGatewayConfigured}"
    case "$live_test_identifier" in
      OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardImproveReplacesTextWhenGatewayConfigured|\
      OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardTranslateReplacesTextWhenGatewayConfigured|\
      OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardAutomaticAnalysisWorkflowScreenshotsWhenExplicitlyRequested)
        ;;
      *)
        echo -e "${RED}✗ OPEN_KEYBOARD_REAL_KEYBOARD_LIVE_TEST must select an approved real keyboard live test.${NC}"
        exit 2
        ;;
    esac
    begin_sensitive_live_workspace real-keyboard-live
    seed_file="$(
      openkeyboard_require_local_seed_file \
        "$REPO_ROOT" \
        "${OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE:-$DEFAULT_SIMULATOR_GATEWAY_SEED_FILE}"
    )" || exit 2
    simulator_template="${OPEN_KEYBOARD_REAL_KEYBOARD_SIMULATOR:-$DEFAULT_REAL_KEYBOARD_SIMULATOR}"
    create_sensitive_live_simulator "$simulator_template"
    simulator="$SENSITIVE_LIVE_SIMULATOR"
    destination="$(simulator_destination "$simulator")"
    derived_data="$SENSITIVE_LIVE_WORKSPACE/DerivedData"
    result_bundle="$SENSITIVE_LIVE_WORKSPACE/real-keyboard-live.xcresult"
    openkeyboard_load_simulator_gateway_seed "$seed_file"
    select_loaded_live_profile "${OPEN_KEYBOARD_LIVE_PROFILE:-reference}"

    xcrun simctl boot "$simulator" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$simulator" -b >/dev/null

    run_xcodebuild xcodebuild build-for-testing \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$destination" \
      -configuration Debug \
      -derivedDataPath "$derived_data" \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO

    app_path="$derived_data/Build/Products/Debug-iphonesimulator/OpenKeyboard.app"
    if [[ ! -d "$app_path" ]]; then
      echo -e "${RED}✗ Built app not found: $app_path${NC}"
      exit 1
    fi

    xcrun simctl install "$simulator" "$app_path"
    "$REPO_ROOT/scripts/ios/enable-openkeyboard-simulator-keyboard.sh" "$simulator" >/dev/null
    xcrun simctl shutdown "$simulator"
    xcrun simctl boot "$simulator"
    xcrun simctl bootstatus "$simulator" -b >/dev/null
    "$REPO_ROOT/scripts/ios/seed-simulator-gateway-config.sh" \
      --seed-file "$seed_file" \
      --profile "$OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE" \
      --simulator "$simulator" \
      --replace-existing-config

    xctestrun="$(find "$derived_data/Build/Products" -name '*.xctestrun' -print -quit)"
    if [[ -z "$xctestrun" ]]; then
      echo -e "${RED}✗ .xctestrun file was not produced under $derived_data/Build/Products${NC}"
      exit 1
    fi

    inject_xctestrun_gateway_env "$xctestrun"
    openkeyboard_unset_simulator_gateway_profiles
    run_xcodebuild xcodebuild test-without-building \
      -xctestrun "$xctestrun" \
      -destination "$destination" \
      -only-testing:"$live_test_identifier" \
      -resultBundlePath "$result_bundle"
    openkeyboard_assert_single_passing_xcresult "$result_bundle"
    echo -e "${GREEN}✓ Seeded real keyboard extension live test complete${NC}"
    echo "Sensitive live-test artifacts will be removed before exit."
    ;;

  screenshots)
    echo -e "${YELLOW}Running onboarding screenshot UI tests on iPhone 16 and iPhone SE...${NC}"
    require_xcodebuild
    for destination in "$DESTINATION" "$SE_DESTINATION"; do
      echo -e "${YELLOW}Destination: $destination${NC}"
      run_xcodebuild xcodebuild test \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "$destination" \
        -configuration Debug \
        -only-testing:OpenKeyboardUITests/OnboardingScreenshotUITests \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO
    done
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
    echo -e "${YELLOW}Usage: ./scripts/ios/test.sh {core|build|deterministic-ui|ui|live-ui|live-gateway-smoke|live-model-differential|real-keyboard-live|screenshots|all|coverage}${NC}"
    echo "  core        - Run Swift package tests for OpenKeyboardCore"
    echo "  build       - Build the iOS app/keyboard extension"
    echo "  deterministic-ui - Run UI-target tests without credential/state-dependent suites"
    echo "  ui          - Run OpenKeyboardUITests on iPhone 16"
    echo "  live-ui     - Run opt-in live gateway AI UI tests on iPhone 16"
    echo "  live-gateway-smoke - Run opt-in Test Connection smoke using the ignored local gateway seed"
    echo "  live-model-differential - Build once and run the targeted low/high live-model matrix"
    echo "  real-keyboard-live - Seed ignored local gateway credentials, then run real keyboard extension live test"
    echo "  screenshots - Run onboarding screenshot UI tests on iPhone 16 and iPhone SE"
    echo "  all         - Run core tests, iOS build, then UI tests"
    echo "  coverage    - Run core package tests with coverage"
    exit 1
    ;;
esac
