#!/bin/bash

# Opt-in live routes handle private provider values. Disable inherited tracing and automatic
# export before reading any environment or seed so `bash -ax` cannot disclose those values or
# pass seed-derived shell state to unrelated child tools.
case "$-" in
  *x*) set +x ;;
esac
case "$-" in
  *a*) set +a ;;
esac

# OpenKeyboard iOS/Core Test Runner
# Usage: ./scripts/ios/test.sh {core|build|release-exclusion|deterministic-ui|ui|live-ui|live-gateway-smoke|live-provider-matrix|live-model-differential [--diagnostic]|real-keyboard-live|screenshots|all|coverage}

set -euo pipefail

MODE="${1:-}"

# Capture non-exported route controls before the pre-child scrub removes their ambient names.
# Credential values are never captured here; seed files remain the only source of live secrets.
initial_seed_file="${OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE:-}"
initial_live_profile="${OPEN_KEYBOARD_LIVE_PROFILE:-}"
initial_uac_checkout="${OPEN_KEYBOARD_UAC_LIVE_CHECKOUT:-}"
initial_provider_evidence_output="${OPEN_KEYBOARD_LIVE_PROVIDER_EVIDENCE_OUTPUT:-}"
initial_differential_evidence_output="${OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT:-}"
initial_live_test_identifier="${OPEN_KEYBOARD_REAL_KEYBOARD_LIVE_TEST:-}"
initial_simulator_template="${OPEN_KEYBOARD_REAL_KEYBOARD_SIMULATOR:-}"
initial_screenshot_dir="${OPEN_KEYBOARD_REAL_SCREENSHOT_DIR:-}"
initial_screenshot_phrase="${OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE:-}"
export -n \
  initial_seed_file \
  initial_live_profile \
  initial_uac_checkout \
  initial_provider_evidence_output \
  initial_differential_evidence_output \
  initial_live_test_identifier \
  initial_simulator_template \
  initial_screenshot_dir \
  initial_screenshot_phrase

openkeyboard_unset_initial_route_controls() {
  unset \
    initial_seed_file \
    initial_live_profile \
    initial_uac_checkout \
    initial_provider_evidence_output \
    initial_differential_evidence_output \
    initial_live_test_identifier \
    initial_simulator_template \
    initial_screenshot_dir \
    initial_screenshot_phrase
}

openkeyboard_unset_ambient_private_live_values() {
  unset \
    OPENAI_API_KEY \
    OPENAI_LIVE_MODEL \
    ANTHROPIC_API_KEY \
    ANTHROPIC_LIVE_MODEL \
    OPENROUTER_API_KEY \
    OPENROUTER_LIVE_MODEL \
    GATEWAY_LIVE_BASE_URL \
    GATEWAY_API_KEY \
    GATEWAY_LIVE_MODEL \
    GATEWAY_LIVE_STRUCTURED_OUTPUT \
    OPEN_KEYBOARD_LIVE_GATEWAY_URL \
    OPEN_KEYBOARD_LIVE_API_KEY \
    OPEN_KEYBOARD_LIVE_MODEL \
    OPEN_KEYBOARD_LIVE_REQUIRED_MODEL \
    OPEN_KEYBOARD_LIVE_REQUIRED_MODELS \
    OPEN_KEYBOARD_TEST_GATEWAY_URL \
    OPEN_KEYBOARD_TEST_API_KEY \
    OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX \
    OPEN_KEYBOARD_TEST_API_KEY_HEX \
    OPEN_KEYBOARD_TEST_MODEL \
    OPEN_KEYBOARD_TEST_PROVIDER \
    OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE \
    OPEN_KEYBOARD_SIMULATOR_PROVIDER \
    OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL \
    OPEN_KEYBOARD_SIMULATOR_API_KEY \
    OPEN_KEYBOARD_SIMULATOR_MODEL \
    OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL \
    OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY \
    OPEN_KEYBOARD_SIMULATOR_LOW_MODEL \
    OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL \
    OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY \
    OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL \
    OPEN_KEYBOARD_SIMULATOR_LEGACY_GATEWAY_URL \
    OPEN_KEYBOARD_SIMULATOR_LEGACY_API_KEY \
    OPEN_KEYBOARD_SIMULATOR_LEGACY_MODEL \
    OPEN_KEYBOARD_SIMULATOR_LEGACY_PROFILE_STATE \
    OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE \
    OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_DIR \
    OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_PHRASE \
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_GATEWAY_URL \
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_API_KEY \
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_MODEL \
    SIMCTL_CHILD_OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG \
    line \
    value \
    base_url \
    key_value \
    model_value \
    model_id \
    tested_model \
    required_model \
    low_model \
    high_model \
    expected_profile_model \
    gateway_url_hex \
    api_key_hex \
    requested_seed_file \
    requested_live_profile \
    requested_uac_checkout \
    requested_provider_evidence_output \
    requested_differential_evidence_output \
    requested_live_test_identifier \
    requested_simulator_template \
    requested_screenshot_dir \
    requested_screenshot_phrase
}

case "$MODE" in
  live-gateway-smoke|live-provider-matrix|live-model-differential|real-keyboard-live)
    # Scrub raw ambient values before repository-root resolution and simulator-lock acquisition can
    # spawn a child. Explicit seed/profile/evidence/control knobs survive until each mode caches
    # them privately and performs its complete preflight scrub.
    openkeyboard_unset_ambient_private_live_values
    ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$REPO_ROOT/OpenKeyboard.xcodeproj"
SCHEME="OpenKeyboard"
BUILD_DESTINATION="generic/platform=iOS Simulator"
DESTINATION="platform=iOS Simulator,name=iPhone 16"
SE_DESTINATION="platform=iOS Simulator,name=iPhone SE (3rd generation)"
CORE_PACKAGE="$REPO_ROOT/OpenKeyboardCore"
DETERMINISTIC_UI_DERIVED_DATA="$REPO_ROOT/.build/deterministic-ui/DerivedData"
DEFAULT_SIMULATOR_GATEWAY_SEED_FILE=".agent/local-seeds/openkeyboard-gateway.env"
DEFAULT_REAL_KEYBOARD_SIMULATOR="iPhone 17 Pro"
source "$REPO_ROOT/scripts/ios/live-test-safety.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LIVE_DIFFERENTIAL_EXECUTION_MODE="verification"
if [[ "$MODE" == "live-model-differential" ]]; then
  case "$#" in
    1) ;;
    2)
      if [[ "$2" != "--diagnostic" ]]; then
        echo "live-model-differential accepts only the optional --diagnostic flag." >&2
        exit 2
      fi
      LIVE_DIFFERENTIAL_EXECUTION_MODE="diagnostic"
      ;;
    *)
      echo "live-model-differential accepts only the optional --diagnostic flag." >&2
      exit 2
      ;;
  esac
elif [[ "$#" -gt 1 ]]; then
  echo "$MODE does not accept additional arguments." >&2
  exit 2
fi

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
  "$REPO_ROOT/scripts/bootstrap-universal-ai-connector.sh"
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
  export -n plist path value

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
  export -n plist path value plist_path
  plist_path="${plist_path//:/.}"

  if ! /usr/libexec/PlistBuddy -c "Print $path" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Add $path string placeholder" "$plist" >/dev/null
  fi
  /usr/bin/plutil -replace "$plist_path" -string "$value" "$plist"
}

inject_xctestrun_gateway_env() {
  local xctestrun="$1"
  export -n xctestrun
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
    if [[ -n "${OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_DIR:-}" ]]; then
      plist_set_or_add_string "$xctestrun" "$root:OPEN_KEYBOARD_REAL_SCREENSHOT_DIR" "$OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_DIR"
    fi
    if [[ -n "${OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_PHRASE:-}" ]]; then
      plist_set_or_add_exact_string "$xctestrun" "$root:OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE" "$OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_PHRASE"
    fi
  done
}

inject_xctestrun_live_smoke_env() {
  local xctestrun="$1"
  local gateway_url_hex api_key_hex
  export -n xctestrun gateway_url_hex api_key_hex
  local roots=(
    ":TestConfigurations:0:TestTargets:0:EnvironmentVariables"
    ":TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables"
    ":TestConfigurations:0:TestTargets:0:UITargetAppEnvironmentVariables"
  )
  local root

  if [[ -z "${OPEN_KEYBOARD_SIMULATOR_PROVIDER:-}" ]]; then
    echo -e "${RED}✗ Live smoke provider identity is required.${NC}" >&2
    return 2
  fi

  gateway_url_hex="$(printf '%s' "$OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL" | od -An -tx1 | tr -d ' \n')"
  api_key_hex="$(printf '%s' "$OPEN_KEYBOARD_SIMULATOR_API_KEY" | od -An -tx1 | tr -d ' \n')"
  for root in "${roots[@]}"; do
    plist_set_or_add_string "$xctestrun" "$root:OPEN_KEYBOARD_TEST_PROVIDER" "$OPEN_KEYBOARD_SIMULATOR_PROVIDER"
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
SENSITIVE_LIVE_SIMULATOR_OWNED="false"

cleanup_sensitive_live_artifacts() {
  local original_status=$?
  local cleanup_status=0

  # Clear every credential-bearing variable before cleanup invokes xcrun or rm. This also covers
  # failures that occur while a seed-backed provider loader still has private values in memory.
  openkeyboard_unset_ambient_private_live_values
  openkeyboard_unset_simulator_gateway_profiles
  openkeyboard_unset_uac_live_provider_inputs
  unset \
    OPEN_KEYBOARD_TEST_GATEWAY_URL \
    OPEN_KEYBOARD_TEST_API_KEY \
    OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX \
    OPEN_KEYBOARD_TEST_API_KEY_HEX \
    OPEN_KEYBOARD_TEST_MODEL \
    OPEN_KEYBOARD_TEST_PROVIDER \
    OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE \
    OPEN_KEYBOARD_SIMULATOR_PROVIDER \
    OPENAI_API_KEY \
    OPENAI_LIVE_MODEL \
    ANTHROPIC_API_KEY \
    ANTHROPIC_LIVE_MODEL \
    OPENROUTER_API_KEY \
    OPENROUTER_LIVE_MODEL \
    GATEWAY_LIVE_BASE_URL \
    GATEWAY_API_KEY \
    GATEWAY_LIVE_MODEL \
    GATEWAY_LIVE_STRUCTURED_OUTPUT \
    OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_DIR \
    OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_PHRASE \
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_GATEWAY_URL \
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_API_KEY \
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_MODEL \
    SIMCTL_CHILD_OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG

  if ! openkeyboard_delete_sensitive_live_simulator; then
    cleanup_status=1
  fi

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
  OPEN_KEYBOARD_SIMULATOR_PROVIDER="openai-compatible"
}

openkeyboard_unset_uac_live_provider_inputs() {
  unset \
    OPENAI_API_KEY \
    OPENAI_LIVE_MODEL \
    ANTHROPIC_API_KEY \
    ANTHROPIC_LIVE_MODEL \
    OPENROUTER_API_KEY \
    OPENROUTER_LIVE_MODEL \
    GATEWAY_LIVE_BASE_URL \
    GATEWAY_API_KEY \
    GATEWAY_LIVE_MODEL \
    GATEWAY_LIVE_STRUCTURED_OUTPUT
}

openkeyboard_unset_seed_backed_live_ambient_inputs() {
  openkeyboard_unset_ambient_private_live_values
  openkeyboard_unset_uac_live_provider_inputs
  openkeyboard_unset_simulator_gateway_profiles
  unset \
    UAC_LIVE_ENV_FILE \
    OPEN_KEYBOARD_UAC_LIVE_CHECKOUT \
    OPEN_KEYBOARD_LIVE_BASE_REF \
    OPEN_KEYBOARD_LIVE_EXPECTED_SHA \
    OPEN_KEYBOARD_LIVE_REQUIRE_DIFFERENTIAL \
    OPEN_KEYBOARD_LIVE_REQUIRED_MODEL \
    OPEN_KEYBOARD_LIVE_REQUIRED_MODELS \
    OPEN_KEYBOARD_LIVE_GATEWAY_URL \
    OPEN_KEYBOARD_LIVE_API_KEY \
    OPEN_KEYBOARD_LIVE_MODEL \
    OPEN_KEYBOARD_LIVE_PROFILE \
    OPEN_KEYBOARD_LIVE_PROVIDER_EVIDENCE_OUTPUT \
    OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT \
    OPEN_KEYBOARD_TEST_GATEWAY_URL \
    OPEN_KEYBOARD_TEST_API_KEY \
    OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX \
    OPEN_KEYBOARD_TEST_API_KEY_HEX \
    OPEN_KEYBOARD_TEST_MODEL \
    OPEN_KEYBOARD_TEST_PROVIDER \
    OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG \
    OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE \
    OPEN_KEYBOARD_SIMULATOR_PROVIDER \
    OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE \
    OPEN_KEYBOARD_SIMULATOR_LOCK_HELD \
    OPEN_KEYBOARD_REAL_KEYBOARD_LIVE_TEST \
    OPEN_KEYBOARD_REAL_KEYBOARD_SIMULATOR \
    OPEN_KEYBOARD_REAL_SCREENSHOT_DIR \
    OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE \
    OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_DIR \
    OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_PHRASE \
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_GATEWAY_URL \
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_API_KEY \
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_MODEL \
    SIMCTL_CHILD_OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG
}

openkeyboard_is_safe_live_gateway_base_url() {
  local value="$1"
  local canonical_ipv4_octet='(0|[1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])'
  local canonical_loopback_ipv4

  canonical_loopback_ipv4="127[.]${canonical_ipv4_octet}[.]${canonical_ipv4_octet}[.]${canonical_ipv4_octet}"

  if [[ -z "$value" ||
        "${#value}" -gt 2048 ||
        "$value" == *$'\n'* ||
        "$value" == *$'\r'* ||
        "$value" == *$'\t'* ||
        "$value" == *' '* ||
        "$value" == *'@'* ||
        "$value" == *'?'* ||
        "$value" == *'#'* ]]; then
    return 1
  fi
  if [[ "$value" != https://* &&
        ! "$value" =~ ^http://(localhost|${canonical_loopback_ipv4}|\[::1\])(:[0-9]{1,5})?(/.*)?$ ]]; then
    return 1
  fi
  [[ "$value" == */v1 || "$value" == */v1/ ]]
}

openkeyboard_is_safe_uac_provider_model_id() {
  local provider="$1"
  local model_id="$2"

  case "$provider" in
    openai|anthropic)
      [[ ${#model_id} -le 128 && "$model_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
      ;;
    openrouter|gateway)
      [[ ${#model_id} -le 256 && "$model_id" =~ ^[A-Za-z0-9][A-Za-z0-9._:/@+-]*$ ]]
      ;;
    *)
      return 1
      ;;
  esac
}

openkeyboard_load_uac_live_provider_profile() {
  local provider="$1"
  local uac_checkout="$2"
  local key_name model_name base_url key_value model_value simulator_provider
  export -n provider uac_checkout key_name model_name base_url key_value model_value simulator_provider

  # This proof route is seed-bound: ambient provider credentials or model IDs must never
  # override the ignored file, including on the first provider row.
  openkeyboard_unset_uac_live_provider_inputs

  case "$provider" in
    openai)
      key_name="OPENAI_API_KEY"
      model_name="OPENAI_LIVE_MODEL"
      base_url="https://api.openai.com/v1"
      uac_load_live_environment "$uac_checkout" "$key_name" "$model_name"
      ;;
    anthropic)
      key_name="ANTHROPIC_API_KEY"
      model_name="ANTHROPIC_LIVE_MODEL"
      base_url="https://api.anthropic.com/v1"
      uac_load_live_environment "$uac_checkout" "$key_name" "$model_name"
      ;;
    openrouter)
      key_name="OPENROUTER_API_KEY"
      model_name="OPENROUTER_LIVE_MODEL"
      base_url="https://openrouter.ai/api/v1"
      uac_load_live_environment "$uac_checkout" "$key_name" "$model_name"
      ;;
    gateway)
      key_name="GATEWAY_API_KEY"
      model_name="GATEWAY_LIVE_MODEL"
      uac_load_live_environment \
        "$uac_checkout" \
        GATEWAY_LIVE_BASE_URL \
        "$key_name" \
        "$model_name" \
        GATEWAY_LIVE_STRUCTURED_OUTPUT
      base_url="${GATEWAY_LIVE_BASE_URL:-}"
      ;;
    *)
      echo -e "${RED}✗ Unsupported live provider matrix row.${NC}" >&2
      return 2
      ;;
  esac

  if [[ -z "${!key_name:-}" || -z "${!model_name:-}" || -z "$base_url" ]]; then
    echo -e "${RED}✗ The ignored Universal AI Connector seed is incomplete for $provider.${NC}" >&2
    return 2
  fi
  key_value="${!key_name}"
  model_value="${!model_name}"
  if [[ "${#key_value}" -gt 8192 || "$key_value" == *$'\n'* || "$key_value" == *$'\r'* ]]; then
    echo -e "${RED}✗ The ignored Universal AI Connector seed has an unsafe API key shape for $provider.${NC}" >&2
    return 2
  fi
  if ! openkeyboard_is_safe_uac_provider_model_id "$provider" "$model_value"; then
    echo -e "${RED}✗ The ignored Universal AI Connector seed has an unsafe model ID for $provider.${NC}" >&2
    return 2
  fi
  if [[ "$provider" == "gateway" ]]; then
    if ! openkeyboard_is_safe_live_gateway_base_url "$base_url"; then
      echo -e "${RED}✗ The ignored Universal AI Connector seed has an unsafe gateway base URL.${NC}" >&2
      return 2
    fi
    if [[ "${GATEWAY_LIVE_STRUCTURED_OUTPUT:-}" != "true" &&
          "${GATEWAY_LIVE_STRUCTURED_OUTPUT:-}" != "false" ]]; then
      echo -e "${RED}✗ The ignored Universal AI Connector seed has an invalid gateway structured-output flag.${NC}" >&2
      return 2
    fi
  fi

  if [[ "$provider" == "gateway" ]]; then
    simulator_provider="openai-compatible"
  else
    simulator_provider="$provider"
  fi
  OPEN_KEYBOARD_SIMULATOR_PROVIDER="$simulator_provider"
  OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL="$base_url"
  OPEN_KEYBOARD_SIMULATOR_API_KEY="$key_value"
  OPEN_KEYBOARD_SIMULATOR_MODEL="$model_value"
  OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE="$provider"
  openkeyboard_unexport_simulator_gateway_profiles
  # The pinned loader exports the requested UAC names. The copied simulator variables are
  # intentionally non-exported, so remove the exported seed values before od, PlistBuddy, xcrun,
  # or any other external tool can inherit them.
  openkeyboard_unset_uac_live_provider_inputs
}

begin_sensitive_live_workspace() {
  local label="$1"

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
  local created_simulator descriptor device_type runtime simulator_name

  if [[ -n "$SENSITIVE_LIVE_SIMULATOR" || "$SENSITIVE_LIVE_SIMULATOR_OWNED" != "false" ]]; then
    echo -e "${RED}✗ Refusing to replace a disposable simulator still owned by this live workflow.${NC}" >&2
    exit 1
  fi

  descriptor="$(
    xcrun simctl list devices available -j |
      ruby -rjson -e '
        selector = ARGV.fetch(0)
        devices = JSON.parse(STDIN.read).fetch("devices")
        matches = devices.flat_map do |runtime, entries|
          entries.map do |device|
            next unless device["udid"] == selector || device["name"] == selector
            [device.fetch("deviceTypeIdentifier"), runtime]
          end.compact
        end
        abort "Simulator selector must resolve to exactly one available device." unless matches.one?
        puts matches.first.join("\t")
      ' "$selector"
  )"
  device_type="${descriptor%%$'\t'*}"
  runtime="${descriptor#*$'\t'}"

  simulator_name="OpenKeyboard Live Test $$ $(date +%s)"
  created_simulator="$(
    xcrun simctl create "$simulator_name" "$device_type" "$runtime"
  )"
  if [[ ! "$created_simulator" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
    echo -e "${RED}✗ Failed to create a disposable live-test simulator.${NC}" >&2
    exit 1
  fi
  SENSITIVE_LIVE_SIMULATOR="$created_simulator"
  SENSITIVE_LIVE_SIMULATOR_OWNED="true"
}

simulator_mode_requires_lock() {
  case "${1:-}" in
    ui|deterministic-ui|live-ui|live-gateway-smoke|live-provider-matrix|live-model-differential|real-keyboard-live|screenshots)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if simulator_mode_requires_lock "$MODE"; then
  openkeyboard_relaunch_with_simulator_lock "$REPO_ROOT" "$0" "$@"
fi

case "$MODE" in
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

  release-exclusion)
    echo -e "${YELLOW}Building an unsigned generic-iOS Release product and checking credential-hook exclusion...${NC}"
    require_xcodebuild
    release_workspace="$(mktemp -d "${TMPDIR:-/tmp}/openkeyboard-release-exclusion.XXXXXX")"
    cleanup_release_workspace() {
      rm -rf -- "$release_workspace"
    }
    trap cleanup_release_workspace EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    release_derived_data="$release_workspace/DerivedData"
    run_xcodebuild xcodebuild build \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination 'generic/platform=iOS' \
      -configuration Release \
      -derivedDataPath "$release_derived_data" \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO

    release_app="$release_derived_data/Build/Products/Release-iphoneos/OpenKeyboard.app"
    release_extension="$release_app/PlugIns/OpenKeyboardExtension.appex"
    release_binaries=(
      "$release_app/OpenKeyboard"
      "$release_extension/OpenKeyboardExtension"
    )
    forbidden_release_tokens=(
      OPEN_KEYBOARD_TEST_API_KEY
      OPEN_KEYBOARD_TEST_GATEWAY_URL
      OPEN_KEYBOARD_TEST_MODEL
      OPEN_KEYBOARD_LIVE_API_KEY
      OPEN_KEYBOARD_LIVE_GATEWAY_URL
      OPEN_KEYBOARD_LIVE_MODEL
      OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG
      SimulatorLiveAIConfiguration
      LiveAITestHarnessView
      captureUITestGatewayEnvironment
      seedUITestGatewayConfigAtLaunchIfNeeded
      saveTestSeed
      KeyboardUITestConfigProcessAuthorization
      keyboardUITestConfigAuthorization
      hasFreshKeyboardExtensionUITestConfigSeed
    )
    for release_binary in "${release_binaries[@]}"; do
      if [[ ! -f "$release_binary" ]]; then
        echo -e "${RED}✗ Release binary was not produced at the expected app/extension path.${NC}" >&2
        exit 1
      fi
      strings_file="$release_workspace/$(basename "$release_binary").strings"
      symbols_file="$release_workspace/$(basename "$release_binary").symbols"
      strings -a "$release_binary" > "$strings_file"
      nm -j "$release_binary" > "$symbols_file"
      for token in "${forbidden_release_tokens[@]}"; do
        if rg --fixed-strings --quiet -- "$token" "$strings_file" "$symbols_file"; then
          echo -e "${RED}✗ Release product retained a simulator-only credential hook token.${NC}" >&2
          exit 1
        fi
      done
    done
    cleanup_release_workspace
    trap - EXIT HUP INT TERM
    echo -e "${GREEN}✓ Release app and extension exclude simulator-only credential bootstrap/harness hooks${NC}"
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
    openkeyboard_unset_seed_backed_live_ambient_inputs
    requested_seed_file="${initial_seed_file:-$DEFAULT_SIMULATOR_GATEWAY_SEED_FILE}"
    requested_live_profile="${initial_live_profile:-reference}"
    requested_differential_evidence_output="$initial_differential_evidence_output"
    export -n requested_seed_file requested_live_profile requested_differential_evidence_output
    openkeyboard_unset_initial_route_controls
    echo -e "${YELLOW}Running opt-in live gateway Test Connection smoke on iPhone 16...${NC}"
    require_xcodebuild
    begin_sensitive_live_workspace live-gateway-smoke
    seed_file="$(
      openkeyboard_require_local_seed_file \
        "$REPO_ROOT" \
        "$requested_seed_file"
    )" || exit 2
    create_sensitive_live_simulator "iPhone 16"
    destination="$(simulator_destination "$SENSITIVE_LIVE_SIMULATOR")"
    derived_data="$SENSITIVE_LIVE_WORKSPACE/DerivedData"
    result_bundle="$SENSITIVE_LIVE_WORKSPACE/live-gateway-smoke.xcresult"

    openkeyboard_load_simulator_gateway_seed "$seed_file"
    select_loaded_live_profile "$requested_live_profile"
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
    chmod 600 "$xctestrun"

    reference_model="$OPEN_KEYBOARD_SIMULATOR_MODEL"
    export -n reference_model
    inject_xctestrun_live_smoke_env "$xctestrun"
    openkeyboard_unset_simulator_gateway_profiles
    run_xcodebuild xcodebuild test-without-building \
      -xctestrun "$xctestrun" \
      -destination "$destination" \
      -only-testing:OpenKeyboardUITests/LiveGatewaySmokeTests/testLiveGatewayTestConnectionServicePathWhenSeeded \
      -resultBundlePath "$result_bundle"
    openkeyboard_assert_single_passing_xcresult "$result_bundle"
    if [[ -n "$requested_differential_evidence_output" ]]; then
      (umask 077; printf 'model=%s\n' "$reference_model" > "$requested_differential_evidence_output")
      chmod 600 "$requested_differential_evidence_output"
    fi
    unset reference_model
    echo -e "${GREEN}✓ Live gateway Test Connection smoke complete${NC}"
    echo "Sensitive live-test artifacts will be removed before exit."
    ;;

  live-provider-matrix)
    # This route is seed-only. Remove every ambient provider/test credential before even the
    # toolchain preflight or build can inherit it; each row reloads only its guarded seed values.
    openkeyboard_unset_seed_backed_live_ambient_inputs
    requested_uac_checkout="$initial_uac_checkout"
    requested_provider_evidence_output="$initial_provider_evidence_output"
    export -n requested_uac_checkout requested_provider_evidence_output
    openkeyboard_unset_initial_route_controls
    echo -e "${YELLOW}Running the opt-in four-provider Settings/connector live matrix...${NC}"
    require_xcodebuild
    begin_sensitive_live_workspace live-provider-matrix
    pinned_uac_helper="$REPO_ROOT/Vendor/universal-ai-connector/scripts/local-config.sh"
    if [[ ! -r "$pinned_uac_helper" ]]; then
      echo -e "${RED}✗ The pinned Universal AI Connector local-config helper is unavailable.${NC}" >&2
      exit 2
    fi
    # shellcheck source=/dev/null
    source "$pinned_uac_helper"
    primary_checkout="$(openkeyboard_primary_checkout_root "$REPO_ROOT")"
    uac_checkout="${requested_uac_checkout:-$(dirname "$primary_checkout")/universal-ai-connector}"
    uac_checkout="$(uac_primary_checkout "$uac_checkout")" || exit $?
    uac_seed_file="$(uac_live_env_path "$uac_checkout")" || exit $?
    uac_validate_live_env_file "$uac_checkout" "$uac_seed_file" || exit $?
    openkeyboard_require_private_seed_permissions "$uac_seed_file" || exit $?
    openkeyboard_require_trusted_seed_directory "$uac_checkout" || exit $?

    create_sensitive_live_simulator "iPhone 16"
    destination="$(simulator_destination "$SENSITIVE_LIVE_SIMULATOR")"
    derived_data="$SENSITIVE_LIVE_WORKSPACE/DerivedData"
    echo "Building the four-provider live-test artifacts once."
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
      echo -e "${RED}✗ .xctestrun file was not produced under the sensitive workspace.${NC}" >&2
      exit 1
    fi
    chmod 600 "$xctestrun"

    openai_exact_binding="false"
    anthropic_exact_binding="false"
    openrouter_exact_binding="false"
    gateway_exact_binding="false"
    openai_test_connection="unverified"
    anthropic_test_connection="unverified"
    openrouter_test_connection="unverified"
    gateway_test_connection="unverified"
    openai_diagnostics="unverified"
    anthropic_diagnostics="unverified"
    openrouter_diagnostics="unverified"
    gateway_diagnostics="unverified"
    for provider in openai anthropic openrouter gateway; do
      openkeyboard_load_uac_live_provider_profile "$provider" "$uac_checkout"
      expected_provider="$provider"
      if [[ "$provider" == "gateway" ]]; then
        expected_provider="openai-compatible"
      fi
      if [[ "$OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE" != "$provider" ||
            "$OPEN_KEYBOARD_SIMULATOR_PROVIDER" != "$expected_provider" ]]; then
        echo -e "${RED}✗ The four-provider live row did not preserve its canonical provider binding.${NC}" >&2
        exit 1
      fi
      inject_xctestrun_live_smoke_env "$xctestrun"
      openkeyboard_unset_simulator_gateway_profiles
      unset OPEN_KEYBOARD_SIMULATOR_PROVIDER

      result_bundle="$SENSITIVE_LIVE_WORKSPACE/live-provider-$provider.xcresult"
      echo "Running isolated $provider Settings discovery, exact-model validation, and diagnostics."
      run_xcodebuild xcodebuild test-without-building \
        -xctestrun "$xctestrun" \
        -destination "$destination" \
        -only-testing:OpenKeyboardUITests/LiveGatewaySmokeTests/testLiveGatewayTestConnectionServicePathWhenSeeded \
        -resultBundlePath "$result_bundle"
      openkeyboard_assert_single_passing_xcresult "$result_bundle"
      case "$provider" in
        openai)
          openai_exact_binding="true"
          openai_test_connection="passed"
          openai_diagnostics="passed"
          ;;
        anthropic)
          anthropic_exact_binding="true"
          anthropic_test_connection="passed"
          anthropic_diagnostics="passed"
          ;;
        openrouter)
          openrouter_exact_binding="true"
          openrouter_test_connection="passed"
          openrouter_diagnostics="passed"
          ;;
        gateway)
          gateway_exact_binding="true"
          gateway_test_connection="passed"
          gateway_diagnostics="passed"
          ;;
      esac
      echo -e "${GREEN}✓ $provider live provider row passed${NC}"
    done
    provider_evidence_lines="$(printf '%s\n' \
      "provider_exact_bindings=openai=$openai_exact_binding, anthropic=$anthropic_exact_binding, openrouter=$openrouter_exact_binding, gateway=$gateway_exact_binding" \
      "provider_test_connection_outcomes=openai=$openai_test_connection, anthropic=$anthropic_test_connection, openrouter=$openrouter_test_connection, gateway=$gateway_test_connection" \
      "provider_diagnostic_outcomes=openai=$openai_diagnostics, anthropic=$anthropic_diagnostics, openrouter=$openrouter_diagnostics, gateway=$gateway_diagnostics")"
    printf '%s\n' "$provider_evidence_lines"
    if [[ -n "$requested_provider_evidence_output" ]]; then
      umask 077
      printf '%s\n' "$provider_evidence_lines" > "$requested_provider_evidence_output"
      chmod 600 "$requested_provider_evidence_output"
    fi
    echo -e "${GREEN}✓ Four-provider Settings/connector live matrix complete${NC}"
    echo "Sensitive live-test artifacts will be removed before exit."
    ;;

  live-model-differential)
    openkeyboard_unset_seed_backed_live_ambient_inputs
    requested_seed_file="${initial_seed_file:-$DEFAULT_SIMULATOR_GATEWAY_SEED_FILE}"
    requested_differential_evidence_output="$initial_differential_evidence_output"
    export -n requested_seed_file requested_differential_evidence_output
    openkeyboard_unset_initial_route_controls
    echo -e "${YELLOW}Running targeted two-profile live-model differential ${LIVE_DIFFERENTIAL_EXECUTION_MODE}...${NC}"
    require_xcodebuild
    begin_sensitive_live_workspace live-model-differential
    seed_file="$(
      openkeyboard_require_local_seed_file \
        "$REPO_ROOT" \
        "$requested_seed_file"
    )" || exit 2
    openkeyboard_load_simulator_gateway_seed "$seed_file"
    openkeyboard_require_two_profile_gateway_seed
    low_model="$OPEN_KEYBOARD_SIMULATOR_LOW_MODEL"
    high_model="$OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL"
    export -n low_model high_model
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
    chmod 600 "$xctestrun"

    contract_result_bundle="$SENSITIVE_LIVE_WORKSPACE/live-model-contracts.xcresult"
    echo "Running deterministic operation-scoped warning prerequisites once."
    run_xcodebuild xcodebuild test-without-building \
      -xctestrun "$xctestrun" \
      -destination "$destination" \
      -only-testing:OpenKeyboardUITests/GatewayClientArchitectureTests/testKeyboardAIServiceRejectsLegacyJSONGrammarEnvelopeAsRetryableInvalidResponse \
      -only-testing:OpenKeyboardUITests/GatewayClientArchitectureTests/testKeyboardAIServiceRetriesGenericTranslationCapabilityFailureThenScopesWarning \
      -only-testing:OpenKeyboardUITests/KeyboardViewModelActionErrorTests/testModelCapabilityFailureIsShownForRewriteActionPanelAndPreservesText \
      -only-testing:OpenKeyboardUITests/KeyboardViewModelActionErrorTests/testAutomaticGrammarCapabilityFailureShowsTypedStateAndPreservesText \
      -only-testing:OpenKeyboardUITests/KeyboardViewModelActionErrorTests/testTypingAfterAutomaticGrammarCapabilityFailureRetriesUpdatedText \
      -only-testing:OpenKeyboardUITests/KeyboardViewModelActionErrorTests/testTranslationModelCapabilityFailureStaysWarningScopedAndDoesNotAffectRewrite \
      -resultBundlePath "$contract_result_bundle"
    openkeyboard_assert_passing_xcresult_count "$contract_result_bundle" 6

    low_differential_outcome=""
    low_baseline_outcome="unverified"
    low_follow_up_outcome="unverified"
    high_baseline_outcome="unverified"
    high_differential_outcome="unverified"
    high_follow_up_outcome="unverified"
    low_summarize_outcome="unverified"
    high_summarize_outcome="unverified"
    low_continue_writing_outcome="unverified"
    high_continue_writing_outcome="unverified"
    low_diagnostic_outcomes=""
    high_diagnostic_outcomes=""
    low_profile_model_bound="false"
    high_profile_model_bound="false"
    for profile_role in low high; do
      if [[ "$profile_role" == "high" ]]; then
        openkeyboard_delete_sensitive_live_simulator
        create_sensitive_live_simulator "iPhone 16"
        destination="$(simulator_destination "$SENSITIVE_LIVE_SIMULATOR")"
      fi

      openkeyboard_load_simulator_gateway_seed "$seed_file"
      openkeyboard_select_simulator_gateway_profile "$profile_role"
      case "$profile_role" in
        low) expected_profile_model="$low_model" ;;
        high) expected_profile_model="$high_model" ;;
      esac
      export -n expected_profile_model
      if [[ "$OPEN_KEYBOARD_SIMULATOR_MODEL" != "$expected_profile_model" ]]; then
        echo -e "${RED}✗ Live differential profile selection did not preserve the requested role identity.${NC}" >&2
        exit 1
      fi
      case "$profile_role" in
        low) low_profile_model_bound="true" ;;
        high) high_profile_model_bound="true" ;;
      esac
      OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE="$profile_role"
      OPEN_KEYBOARD_SIMULATOR_PROVIDER="openai-compatible"
      inject_xctestrun_live_smoke_env "$xctestrun"
      openkeyboard_unset_simulator_gateway_profiles
      profile_result_bundle="$SENSITIVE_LIVE_WORKSPACE/live-model-$profile_role.xcresult"
      echo "Running isolated $profile_role profile baseline, boundary, and follow-up scenarios."
      profile_command_passed="true"
      if ! run_xcodebuild xcodebuild test-without-building \
          -xctestrun "$xctestrun" \
          -destination "$destination" \
          -only-testing:OpenKeyboardUITests/LiveModelDifferentialTests/testConfiguredProfileDifferentialContract \
          -resultBundlePath "$profile_result_bundle"; then
        profile_command_passed="false"
      fi
      if [[ "$profile_role" == "low" ]]; then
        if [[ "$profile_command_passed" == "true" ]]; then
          if low_differential_outcome="$(
              openkeyboard_classify_low_differential_xcresult "$profile_result_bundle"
            )"; then
            low_baseline_outcome="passed"
            low_follow_up_outcome="passed"
            low_summarize_outcome="passed"
            low_continue_writing_outcome="passed"
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
          high_summarize_outcome="passed"
          high_continue_writing_outcome="passed"
        fi
      fi
      profile_diagnostic_evidence="$(
        openkeyboard_extract_live_diagnostic_evidence "$profile_result_bundle" "$profile_role"
      )"
      case "$profile_role" in
        low)
          low_diagnostic_outcomes="$(printf '%s\n' "$profile_diagnostic_evidence" | grep -E '^diagnostic_outcomes_low=')"
          ;;
        high)
          high_diagnostic_outcomes="$(printf '%s\n' "$profile_diagnostic_evidence" | grep -E '^diagnostic_outcomes_high=')"
          ;;
      esac
    done

    evidence_lines="$(printf '%s\n' \
      "profile_model_bindings=low=$low_profile_model_bound, high=$high_profile_model_bound" \
      'profile_models_distinct=true' \
      "baseline_outcomes=low=$low_baseline_outcome, high=$high_baseline_outcome" \
      "differential_outcomes=low=$low_differential_outcome, high=$high_differential_outcome" \
      "follow_up_outcomes=low=$low_follow_up_outcome, high=$high_follow_up_outcome" \
      "summarize_outcomes=low=$low_summarize_outcome, high=$high_summarize_outcome" \
      "continue_writing_outcomes=low=$low_continue_writing_outcome, high=$high_continue_writing_outcome" \
      'operation_scoped_warning_contracts=verified' \
      "$low_diagnostic_outcomes" \
      "$high_diagnostic_outcomes")"
    printf '%s\n' "$evidence_lines"
    if [[ -n "$requested_differential_evidence_output" ]]; then
      umask 077
      # Exact identities are private IPC to the parent gate, never public stdout.
      printf 'models=low=%s, high=%s\n%s\n' "$low_model" "$high_model" "$evidence_lines" > "$requested_differential_evidence_output"
      chmod 600 "$requested_differential_evidence_output"
    fi
    completion_status=0
    openkeyboard_finish_live_differential_run \
      "$LIVE_DIFFERENTIAL_EXECUTION_MODE" \
      "$low_baseline_outcome" \
      "$high_baseline_outcome" \
      "$low_differential_outcome" \
      "$high_differential_outcome" \
      "$low_follow_up_outcome" \
      "$high_follow_up_outcome" \
      verified || completion_status=$?
    echo "Sensitive per-profile test state and artifacts will be removed before exit."
    if [[ "$completion_status" -ne 0 ]]; then
      exit "$completion_status"
    fi
    ;;

  real-keyboard-live)
    openkeyboard_unset_seed_backed_live_ambient_inputs
    requested_seed_file="${initial_seed_file:-$DEFAULT_SIMULATOR_GATEWAY_SEED_FILE}"
    requested_live_profile="${initial_live_profile:-reference}"
    requested_live_test_identifier="${initial_live_test_identifier:-OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardImproveReplacesTextWhenGatewayConfigured}"
    requested_simulator_template="${initial_simulator_template:-$DEFAULT_REAL_KEYBOARD_SIMULATOR}"
    requested_screenshot_dir="$initial_screenshot_dir"
    requested_screenshot_phrase="$initial_screenshot_phrase"
    export -n \
      requested_seed_file \
      requested_live_profile \
      requested_live_test_identifier \
      requested_simulator_template \
      requested_screenshot_dir \
      requested_screenshot_phrase
    openkeyboard_unset_initial_route_controls
    echo -e "${YELLOW}Running automated real-extension regression test with seeded live gateway configuration...${NC}"
    echo "Evidence boundary: XCTest/XCUITest regression only; not normal simulator or device proof."
    require_xcodebuild
    live_test_identifier="$requested_live_test_identifier"
    case "$live_test_identifier" in
      OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardExtensionMatchesNativeTouchGeometry|\
      OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardImproveReplacesTextWhenGatewayConfigured|\
      OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardTranslateReplacesTextWhenGatewayConfigured|\
      OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardAutomaticAnalysisWorkflowScreenshotsWhenExplicitlyRequested)
        ;;
      *)
        echo -e "${RED}✗ OPEN_KEYBOARD_REAL_KEYBOARD_LIVE_TEST must select an approved automated real-extension regression test.${NC}"
        exit 2
        ;;
    esac
    begin_sensitive_live_workspace real-keyboard-live
    seed_file="$(
      openkeyboard_require_local_seed_file \
        "$REPO_ROOT" \
        "$requested_seed_file"
    )" || exit 2
    simulator_template="$requested_simulator_template"
    create_sensitive_live_simulator "$simulator_template"
    simulator="$SENSITIVE_LIVE_SIMULATOR"
    openkeyboard_require_sensitive_live_simulator_ownership "$simulator"
    destination="$(simulator_destination "$simulator")"
    derived_data="$SENSITIVE_LIVE_WORKSPACE/DerivedData"
    result_bundle="$SENSITIVE_LIVE_WORKSPACE/real-keyboard-live.xcresult"
    openkeyboard_load_simulator_gateway_seed "$seed_file"
    select_loaded_live_profile "$requested_live_profile"

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

    chmod 600 "$xctestrun"
    OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_DIR="$requested_screenshot_dir"
    OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_PHRASE="$requested_screenshot_phrase"
    inject_xctestrun_gateway_env "$xctestrun"
    openkeyboard_unset_simulator_gateway_profiles
    run_xcodebuild xcodebuild test-without-building \
      -xctestrun "$xctestrun" \
      -destination "$destination" \
      -only-testing:"$live_test_identifier" \
      -resultBundlePath "$result_bundle"
    openkeyboard_assert_single_passing_xcresult "$result_bundle"
    echo -e "${GREEN}✓ Automated real-extension regression test complete${NC}"
    echo "This result does not replace normal simulator runtime or physical-device proof."
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
    echo -e "${YELLOW}Usage: ./scripts/ios/test.sh {core|build|release-exclusion|deterministic-ui|ui|live-ui|live-gateway-smoke|live-provider-matrix|live-model-differential [--diagnostic]|real-keyboard-live|screenshots|all|coverage}${NC}"
    echo "  core        - Run Swift package tests for OpenKeyboardCore"
    echo "  build       - Build the iOS app/keyboard extension"
    echo "  release-exclusion - Build unsigned generic-iOS Release products and prove simulator credential hooks are absent"
    echo "  deterministic-ui - Run UI-target tests without credential/state-dependent suites"
    echo "  ui          - Run OpenKeyboardUITests on iPhone 16"
    echo "  live-ui     - Run opt-in live gateway AI UI tests on iPhone 16"
    echo "  live-gateway-smoke - Run opt-in Test Connection smoke using the ignored local gateway seed"
    echo "  live-provider-matrix - Run Settings discovery, exact-model validation, and diagnostics for all four providers"
    echo "  live-model-differential - Strict targeted low/high verification; add --diagnostic for exploratory collection"
    echo "  real-keyboard-live - Run credentialed automated real-extension regression (not final runtime proof)"
    echo "  screenshots - Run onboarding screenshot UI tests on iPhone 16 and iPhone SE"
    echo "  all         - Run core tests, iOS build, then UI tests"
    echo "  coverage    - Run core package tests with coverage"
    exit 1
    ;;
esac
