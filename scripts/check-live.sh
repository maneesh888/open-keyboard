#!/usr/bin/env bash

# Live inputs include private endpoints, credentials, and model identities. Disable inherited
# tracing and automatic export before any input is read so `bash -ax`/SHELLOPTS cannot disclose
# them or pass seed-derived shell state to unrelated child tools.
case "$-" in
  *x*) set +x ;;
esac
case "$-" in
  *a*) set +a ;;
esac
set -euo pipefail

TARGET="${1:-}"
REQUIRED_MODEL_INPUT_SET="false"
REQUIRED_MODEL_INPUT=""
REQUIRED_MODELS_INPUT_SET="false"
REQUIRED_MODELS_INPUT=""
if [[ "${OPEN_KEYBOARD_LIVE_REQUIRED_MODEL+x}" == "x" ]]; then
  REQUIRED_MODEL_INPUT_SET="true"
  REQUIRED_MODEL_INPUT="$OPEN_KEYBOARD_LIVE_REQUIRED_MODEL"
fi
if [[ "${OPEN_KEYBOARD_LIVE_REQUIRED_MODELS+x}" == "x" ]]; then
  REQUIRED_MODELS_INPUT_SET="true"
  REQUIRED_MODELS_INPUT="$OPEN_KEYBOARD_LIVE_REQUIRED_MODELS"
fi
export -n TARGET REQUIRED_MODEL_INPUT_SET REQUIRED_MODEL_INPUT \
  REQUIRED_MODELS_INPUT_SET REQUIRED_MODELS_INPUT

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
    REQUIRED_MODEL \
    REQUIRED_MODELS \
    REQUIRED_LOW_MODEL \
    REQUIRED_HIGH_MODEL \
    TESTED_MODEL \
    TESTED_MODELS \
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

# Scrub raw ambient values before even resolving the repository root in a child shell. Explicit
# non-secret controls (seed path, target, expected SHA, profile, and base ref) remain available.
openkeyboard_unset_ambient_private_live_values

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_SEED_FILE=".agent/local-seeds/openkeyboard-gateway.env"
source "$ROOT/scripts/ios/live-test-safety.sh"

provider_evidence_file=""
differential_evidence_file=""

usage() {
  cat <<'EOF'
Usage: ./scripts/check-live.sh {gateway|gateway-differential}

The gateway check reads the persistent ignored seed in the primary checkout:
  <primary-checkout>/.agent/local-seeds/openkeyboard-gateway.env

Optional:
  OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE  Alternate ignored seed beneath the
                                             primary checkout's local-seeds directory.
  OPEN_KEYBOARD_LIVE_EXPECTED_SHA            Exact 40-character expected HEAD.
  OPEN_KEYBOARD_LIVE_REQUIRED_MODEL          Exact model ID required by this task.
                                             Omit only for model-agnostic gateway work.
                                             Every run must verify the production plain-text
                                             grammar flow for the seeded model.
  OPEN_KEYBOARD_LIVE_REQUIRED_MODELS         Canonical low/high requirement mapping for the
                                             differential target: low=<id>, high=<id>.
  OPEN_KEYBOARD_LIVE_BASE_REF                Trusted comparison ref used to auto-select the
                                             differential matrix. Defaults to origin/main.
EOF
}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

remove_live_evidence_files() {
  openkeyboard_cleanup_live_evidence_file "${provider_evidence_file:-}"
  openkeyboard_cleanup_live_evidence_file "${differential_evidence_file:-}"
}

clear_private_live_state() {
  openkeyboard_unset_ambient_private_live_values
  openkeyboard_unset_simulator_gateway_profiles
  unset \
    OPEN_KEYBOARD_LIVE_REQUIRED_MODEL \
    OPEN_KEYBOARD_LIVE_REQUIRED_MODELS \
    REQUIRED_MODEL \
    REQUIRED_MODELS \
    REQUIRED_LOW_MODEL \
    REQUIRED_HIGH_MODEL \
    TESTED_MODEL \
    TESTED_MODELS \
    REQUIRED_MODEL_INPUT \
    REQUIRED_MODELS_INPUT
  # BASH_REMATCH is readonly on the supported macOS Bash. Replace its exact-model captures with a
  # fixed non-sensitive match instead of attempting an unset that would abort successful cleanup.
  [[ "cleared" =~ ^(cleared)$ ]]
}

cleanup_live_gate() {
  local original_status=$?

  trap - EXIT HUP INT TERM
  remove_live_evidence_files
  clear_private_live_state
  exit "$original_status"
}

exit_live_gate_after_signal() {
  local signal_status="$1"

  trap - EXIT HUP INT TERM
  remove_live_evidence_files
  clear_private_live_state
  exit "$signal_status"
}

require_clean_checkout() {
  local checkout_status_file
  checkout_status_file="$(mktemp)"
  trap 'rm -f "$checkout_status_file"' RETURN

  git -C "$ROOT" status \
    --porcelain=v1 \
    -z \
    --untracked-files=all > "$checkout_status_file"
  if [[ -s "$checkout_status_file" ]]; then
    fail "Live verification requires a clean checkout bound to committed HEAD."
  fi

  rm -f "$checkout_status_file"
  trap - RETURN
}

require_private_evidence_shape() {
  local evidence_file="$1"
  local expected_line_count="$2"
  local description="$3"
  local actual_line_count

  actual_line_count="$(wc -l < "$evidence_file")"
  actual_line_count="${actual_line_count//[[:space:]]/}"
  if [[ "$actual_line_count" != "$expected_line_count" ]]; then
    fail "$description did not contain the exact canonical field count."
  fi
  if grep -Eiq 'latenc(y|ies)|duration|timing' "$evidence_file"; then
    fail "$description contained a prohibited timing field."
  fi
}

if [[ "$#" -ne 1 || ( "$TARGET" != "gateway" && "$TARGET" != "gateway-differential" ) ]]; then
  usage >&2
  exit 2
fi

command -v git >/dev/null 2>&1 || fail "git is required for live verification."

HEAD_SHA="$(git -C "$ROOT" rev-parse --verify HEAD 2>/dev/null)" ||
  fail "Live verification requires a Git checkout with a committed HEAD."
if [[ ! "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  fail "Live verification could not resolve an exact 40-character HEAD SHA."
fi

require_clean_checkout

EXPECTED_SHA="${OPEN_KEYBOARD_LIVE_EXPECTED_SHA:-$HEAD_SHA}"
if [[ ! "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ || "$EXPECTED_SHA" != "$HEAD_SHA" ]]; then
  fail "Live verification HEAD does not match OPEN_KEYBOARD_LIVE_EXPECTED_SHA."
fi

SEED_FILE="$(
  openkeyboard_require_local_seed_file \
    "$ROOT" \
    "${OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE:-$DEFAULT_SEED_FILE}"
)" || fail "Live gateway seed validation failed."

openkeyboard_load_simulator_gateway_seed "$SEED_FILE" ||
  fail "Live gateway seed parsing failed."
trap cleanup_live_gate EXIT
trap 'exit_live_gate_after_signal 129' HUP
trap 'exit_live_gate_after_signal 130' INT
trap 'exit_live_gate_after_signal 143' TERM

LIVE_MODE="$TARGET"
if [[ "$LIVE_MODE" == "gateway" ]]; then
  LIVE_BASE_REF="${OPEN_KEYBOARD_LIVE_BASE_REF:-origin/main}"
  if git -C "$ROOT" rev-parse --verify "$LIVE_BASE_REF^{commit}" >/dev/null 2>&1; then
    LIVE_IMPACT="$($ROOT/scripts/live-impact.sh "$LIVE_BASE_REF" "$HEAD_SHA")" ||
      fail "Live-impact classification failed."
    if [[ "$LIVE_IMPACT" == "gateway-differential" ]]; then
      LIVE_MODE="gateway-differential"
      echo "The exact-head impact classifier requires the targeted two-profile matrix."
    fi
  elif [[ "${OPEN_KEYBOARD_LIVE_REQUIRE_DIFFERENTIAL:-}" == "true" ]]; then
    LIVE_MODE="gateway-differential"
  else
    fail "Live verification could not resolve OPEN_KEYBOARD_LIVE_BASE_REF."
  fi
fi

if [[ "${OPEN_KEYBOARD_LIVE_REQUIRE_DIFFERENTIAL:-}" == "true" ]]; then
  LIVE_MODE="gateway-differential"
fi

openkeyboard_require_compatible_live_model_inputs \
  "$LIVE_MODE" \
  "$REQUIRED_MODEL_INPUT_SET" \
  "$REQUIRED_MODELS_INPUT_SET" ||
  fail "Live model requirement inputs do not match the selected live target."

if [[ "$LIVE_MODE" == "gateway-differential" ]]; then
  openkeyboard_require_two_profile_gateway_seed ||
    fail "Two-profile live model coverage validation failed."
  if [[ "$REQUIRED_MODELS_INPUT_SET" == "true" ]]; then
    REQUIRED_MODELS="$REQUIRED_MODELS_INPUT"
  else
    REQUIRED_MODELS="low=$OPEN_KEYBOARD_SIMULATOR_LOW_MODEL, high=$OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL"
  fi
  if [[ ! "$REQUIRED_MODELS" =~ ^low=([A-Za-z0-9][A-Za-z0-9._:/+-]*),\ high=([A-Za-z0-9][A-Za-z0-9._:/+-]*)$ ]]; then
    fail "Differential live-model requirements must use canonical low=<id>, high=<id> order."
  fi
  REQUIRED_LOW_MODEL="${BASH_REMATCH[1]}"
  REQUIRED_HIGH_MODEL="${BASH_REMATCH[2]}"
  openkeyboard_require_exact_live_model "$OPEN_KEYBOARD_SIMULATOR_LOW_MODEL" "$REQUIRED_LOW_MODEL" ||
    fail "The low live-model profile does not match the exact requirement."
  openkeyboard_require_exact_live_model "$OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL" "$REQUIRED_HIGH_MODEL" ||
    fail "The high live-model profile does not match the exact requirement."
  MODEL_REQUIREMENT="exact"
  MODEL_IDENTITY_MATCHES="low=true, high=true"
  MODEL_ROLES_DISTINCT="true"
else
  openkeyboard_select_reference_simulator_gateway_profile ||
    fail "Reference live-model profile selection failed."
  TESTED_MODEL="$OPEN_KEYBOARD_SIMULATOR_MODEL"
  if [[ "$REQUIRED_MODEL_INPUT_SET" == "true" ]]; then
    REQUIRED_MODEL="$REQUIRED_MODEL_INPUT"
    MODEL_REQUIREMENT="exact"
  else
    REQUIRED_MODEL="model-agnostic"
    MODEL_REQUIREMENT="model-agnostic"
  fi
  MODEL_IDENTITY_MATCHES="reference=true"
  MODEL_ROLES_DISTINCT="not required"
  if [[ "$MODEL_REQUIREMENT" == "model-agnostic" ]]; then
    openkeyboard_require_exact_live_model "$TESTED_MODEL" "$REQUIRED_MODEL" true ||
      fail "Live model coverage validation failed."
  else
    openkeyboard_require_exact_live_model "$TESTED_MODEL" "$REQUIRED_MODEL" ||
      fail "Live model coverage validation failed."
  fi
fi

# Bash assignment preserves an inherited export attribute. Ensure exact identities derived from
# the guarded seed and task requirement can never reach even the defensive `/usr/bin/env` wrapper.
export -n \
  REQUIRED_MODEL \
  REQUIRED_MODELS \
  REQUIRED_LOW_MODEL \
  REQUIRED_HIGH_MODEL \
  TESTED_MODEL \
  TESTED_MODELS \
  REQUIRED_MODEL_INPUT \
  REQUIRED_MODELS_INPUT

echo "Running deterministic gateway prerequisites for exact HEAD."
env \
  -u UAC_LIVE_ENV_FILE \
  -u REQUIRED_MODEL \
  -u REQUIRED_MODELS \
  -u REQUIRED_LOW_MODEL \
  -u REQUIRED_HIGH_MODEL \
  -u TESTED_MODEL \
  -u TESTED_MODELS \
  -u REQUIRED_MODEL_INPUT \
  -u REQUIRED_MODELS_INPUT \
  -u OPEN_KEYBOARD_LIVE_BASE_REF \
  -u OPEN_KEYBOARD_LIVE_EXPECTED_SHA \
  -u OPEN_KEYBOARD_LIVE_REQUIRE_DIFFERENTIAL \
  -u OPENAI_API_KEY \
  -u OPENAI_LIVE_MODEL \
  -u ANTHROPIC_API_KEY \
  -u ANTHROPIC_LIVE_MODEL \
  -u OPENROUTER_API_KEY \
  -u OPENROUTER_LIVE_MODEL \
  -u GATEWAY_LIVE_BASE_URL \
  -u GATEWAY_API_KEY \
  -u GATEWAY_LIVE_MODEL \
  -u GATEWAY_LIVE_STRUCTURED_OUTPUT \
  -u OPEN_KEYBOARD_UAC_LIVE_CHECKOUT \
  -u OPEN_KEYBOARD_LIVE_GATEWAY_URL \
  -u OPEN_KEYBOARD_LIVE_API_KEY \
  -u OPEN_KEYBOARD_LIVE_MODEL \
  -u OPEN_KEYBOARD_LIVE_REQUIRED_MODEL \
  -u OPEN_KEYBOARD_LIVE_REQUIRED_MODELS \
  -u OPEN_KEYBOARD_LIVE_PROFILE \
  -u OPEN_KEYBOARD_LIVE_PROVIDER_EVIDENCE_OUTPUT \
  -u OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT \
  -u OPEN_KEYBOARD_TEST_GATEWAY_URL \
  -u OPEN_KEYBOARD_TEST_API_KEY \
  -u OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX \
  -u OPEN_KEYBOARD_TEST_API_KEY_HEX \
  -u OPEN_KEYBOARD_TEST_MODEL \
  -u OPEN_KEYBOARD_TEST_PROVIDER \
  -u OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG \
  -u OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE \
  -u OPEN_KEYBOARD_SIMULATOR_PROVIDER \
  -u OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE \
  -u OPEN_KEYBOARD_SIMULATOR_LOCK_HELD \
  -u OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL \
  -u OPEN_KEYBOARD_SIMULATOR_API_KEY \
  -u OPEN_KEYBOARD_SIMULATOR_MODEL \
  -u OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL \
  -u OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY \
  -u OPEN_KEYBOARD_SIMULATOR_LOW_MODEL \
  -u OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL \
  -u OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY \
  -u OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL \
  -u OPEN_KEYBOARD_SIMULATOR_LEGACY_GATEWAY_URL \
  -u OPEN_KEYBOARD_SIMULATOR_LEGACY_API_KEY \
  -u OPEN_KEYBOARD_SIMULATOR_LEGACY_MODEL \
  -u OPEN_KEYBOARD_SIMULATOR_LEGACY_PROFILE_STATE \
  -u OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE \
  -u OPEN_KEYBOARD_REAL_KEYBOARD_LIVE_TEST \
  -u OPEN_KEYBOARD_REAL_KEYBOARD_SIMULATOR \
  -u OPEN_KEYBOARD_REAL_SCREENSHOT_DIR \
  -u OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE \
  -u OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_DIR \
  -u OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_PHRASE \
  -u SIMCTL_CHILD_OPEN_KEYBOARD_TEST_GATEWAY_URL \
  -u SIMCTL_CHILD_OPEN_KEYBOARD_TEST_API_KEY \
  -u SIMCTL_CHILD_OPEN_KEYBOARD_TEST_MODEL \
  -u SIMCTL_CHILD_OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG \
  "$ROOT/scripts/ios/test.sh" core

POST_DETERMINISTIC_SHA="$(git -C "$ROOT" rev-parse --verify HEAD)"
if [[ "$POST_DETERMINISTIC_SHA" != "$HEAD_SHA" ]]; then
  fail "Live verification HEAD changed during deterministic tests."
fi
require_clean_checkout

provider_evidence_file="$(mktemp "${TMPDIR:-/tmp}/openkeyboard-live-provider-evidence.XXXXXX")"
chmod 600 "$provider_evidence_file"
echo "Running the exact-head four-provider Settings and connector matrix."
env \
  -u UAC_LIVE_ENV_FILE \
  -u REQUIRED_MODEL \
  -u REQUIRED_MODELS \
  -u REQUIRED_LOW_MODEL \
  -u REQUIRED_HIGH_MODEL \
  -u TESTED_MODEL \
  -u TESTED_MODELS \
  -u REQUIRED_MODEL_INPUT \
  -u REQUIRED_MODELS_INPUT \
  -u OPEN_KEYBOARD_LIVE_BASE_REF \
  -u OPEN_KEYBOARD_LIVE_EXPECTED_SHA \
  -u OPEN_KEYBOARD_LIVE_REQUIRE_DIFFERENTIAL \
  -u OPENAI_API_KEY \
  -u OPENAI_LIVE_MODEL \
  -u ANTHROPIC_API_KEY \
  -u ANTHROPIC_LIVE_MODEL \
  -u OPENROUTER_API_KEY \
  -u OPENROUTER_LIVE_MODEL \
  -u GATEWAY_LIVE_BASE_URL \
  -u GATEWAY_API_KEY \
  -u GATEWAY_LIVE_MODEL \
  -u GATEWAY_LIVE_STRUCTURED_OUTPUT \
  -u OPEN_KEYBOARD_UAC_LIVE_CHECKOUT \
  -u OPEN_KEYBOARD_LIVE_REQUIRED_MODEL \
  -u OPEN_KEYBOARD_LIVE_REQUIRED_MODELS \
  -u OPEN_KEYBOARD_LIVE_GATEWAY_URL \
  -u OPEN_KEYBOARD_LIVE_API_KEY \
  -u OPEN_KEYBOARD_LIVE_MODEL \
  -u OPEN_KEYBOARD_LIVE_PROFILE \
  -u OPEN_KEYBOARD_LIVE_PROVIDER_EVIDENCE_OUTPUT \
  -u OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT \
  -u OPEN_KEYBOARD_TEST_GATEWAY_URL \
  -u OPEN_KEYBOARD_TEST_API_KEY \
  -u OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX \
  -u OPEN_KEYBOARD_TEST_API_KEY_HEX \
  -u OPEN_KEYBOARD_TEST_MODEL \
  -u OPEN_KEYBOARD_TEST_PROVIDER \
  -u OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG \
  -u OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE \
  -u OPEN_KEYBOARD_SIMULATOR_PROVIDER \
  -u OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE \
  -u OPEN_KEYBOARD_SIMULATOR_LOCK_HELD \
  -u OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL \
  -u OPEN_KEYBOARD_SIMULATOR_API_KEY \
  -u OPEN_KEYBOARD_SIMULATOR_MODEL \
  -u OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL \
  -u OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY \
  -u OPEN_KEYBOARD_SIMULATOR_LOW_MODEL \
  -u OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL \
  -u OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY \
  -u OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL \
  -u OPEN_KEYBOARD_SIMULATOR_LEGACY_GATEWAY_URL \
  -u OPEN_KEYBOARD_SIMULATOR_LEGACY_API_KEY \
  -u OPEN_KEYBOARD_SIMULATOR_LEGACY_MODEL \
  -u OPEN_KEYBOARD_SIMULATOR_LEGACY_PROFILE_STATE \
  -u OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE \
  -u OPEN_KEYBOARD_REAL_KEYBOARD_LIVE_TEST \
  -u OPEN_KEYBOARD_REAL_KEYBOARD_SIMULATOR \
  -u OPEN_KEYBOARD_REAL_SCREENSHOT_DIR \
  -u OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE \
  -u OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_DIR \
  -u OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_PHRASE \
  -u SIMCTL_CHILD_OPEN_KEYBOARD_TEST_GATEWAY_URL \
  -u SIMCTL_CHILD_OPEN_KEYBOARD_TEST_API_KEY \
  -u SIMCTL_CHILD_OPEN_KEYBOARD_TEST_MODEL \
  -u SIMCTL_CHILD_OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG \
  OPEN_KEYBOARD_LIVE_PROVIDER_EVIDENCE_OUTPUT="$provider_evidence_file" \
    "$ROOT/scripts/ios/test.sh" live-provider-matrix
[[ -s "$provider_evidence_file" ]] || fail "Four-provider live evidence output was not produced."
require_private_evidence_shape "$provider_evidence_file" 3 "Four-provider live evidence"
PROVIDER_BINDINGS_LINE="$(grep -E '^provider_exact_bindings=' "$provider_evidence_file")"
PROVIDER_TEST_CONNECTION_LINE="$(grep -E '^provider_test_connection_outcomes=' "$provider_evidence_file")"
PROVIDER_DIAGNOSTICS_LINE="$(grep -E '^provider_diagnostic_outcomes=' "$provider_evidence_file")"
[[ "$PROVIDER_BINDINGS_LINE" == "provider_exact_bindings=openai=true, anthropic=true, openrouter=true, gateway=true" ]] ||
  fail "Four-provider live evidence did not preserve every exact provider/model binding."
[[ "$PROVIDER_TEST_CONNECTION_LINE" == "provider_test_connection_outcomes=openai=passed, anthropic=passed, openrouter=passed, gateway=passed" ]] ||
  fail "Four-provider Test Connection outcomes were not verified."
[[ "$PROVIDER_DIAGNOSTICS_LINE" == "provider_diagnostic_outcomes=openai=passed, anthropic=passed, openrouter=passed, gateway=passed" ]] ||
  fail "Four-provider diagnostic outcomes were not verified."

POST_PROVIDER_SHA="$(git -C "$ROOT" rev-parse --verify HEAD)"
if [[ "$POST_PROVIDER_SHA" != "$HEAD_SHA" ]]; then
  fail "Live verification HEAD changed during the four-provider matrix."
fi
require_clean_checkout

if [[ "$LIVE_MODE" == "gateway-differential" ]]; then
  differential_evidence_file="$(mktemp "${TMPDIR:-/tmp}/openkeyboard-live-differential-evidence.XXXXXX")"
  chmod 600 "$differential_evidence_file"
  echo "Running the targeted two-profile live-model matrix for exact HEAD."
  env \
    -u UAC_LIVE_ENV_FILE \
    -u REQUIRED_MODEL \
    -u REQUIRED_MODELS \
    -u REQUIRED_LOW_MODEL \
    -u REQUIRED_HIGH_MODEL \
    -u TESTED_MODEL \
    -u TESTED_MODELS \
    -u REQUIRED_MODEL_INPUT \
    -u REQUIRED_MODELS_INPUT \
    -u OPEN_KEYBOARD_LIVE_BASE_REF \
    -u OPEN_KEYBOARD_LIVE_EXPECTED_SHA \
    -u OPEN_KEYBOARD_LIVE_REQUIRE_DIFFERENTIAL \
    -u OPENAI_API_KEY \
    -u OPENAI_LIVE_MODEL \
    -u ANTHROPIC_API_KEY \
    -u ANTHROPIC_LIVE_MODEL \
    -u OPENROUTER_API_KEY \
    -u OPENROUTER_LIVE_MODEL \
    -u GATEWAY_LIVE_BASE_URL \
    -u GATEWAY_API_KEY \
    -u GATEWAY_LIVE_MODEL \
    -u GATEWAY_LIVE_STRUCTURED_OUTPUT \
    -u OPEN_KEYBOARD_UAC_LIVE_CHECKOUT \
    -u OPEN_KEYBOARD_LIVE_GATEWAY_URL \
    -u OPEN_KEYBOARD_LIVE_API_KEY \
    -u OPEN_KEYBOARD_LIVE_MODEL \
    -u OPEN_KEYBOARD_LIVE_REQUIRED_MODEL \
    -u OPEN_KEYBOARD_LIVE_REQUIRED_MODELS \
    -u OPEN_KEYBOARD_LIVE_PROFILE \
    -u OPEN_KEYBOARD_LIVE_PROVIDER_EVIDENCE_OUTPUT \
    -u OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT \
    -u OPEN_KEYBOARD_TEST_GATEWAY_URL \
    -u OPEN_KEYBOARD_TEST_API_KEY \
    -u OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX \
    -u OPEN_KEYBOARD_TEST_API_KEY_HEX \
    -u OPEN_KEYBOARD_TEST_MODEL \
    -u OPEN_KEYBOARD_TEST_PROVIDER \
    -u OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG \
    -u OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE \
    -u OPEN_KEYBOARD_SIMULATOR_PROVIDER \
    -u OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE \
    -u OPEN_KEYBOARD_SIMULATOR_LOCK_HELD \
    -u OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL \
    -u OPEN_KEYBOARD_SIMULATOR_API_KEY \
    -u OPEN_KEYBOARD_SIMULATOR_MODEL \
    -u OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL \
    -u OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY \
    -u OPEN_KEYBOARD_SIMULATOR_LOW_MODEL \
    -u OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL \
    -u OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY \
    -u OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL \
    -u OPEN_KEYBOARD_SIMULATOR_LEGACY_GATEWAY_URL \
    -u OPEN_KEYBOARD_SIMULATOR_LEGACY_API_KEY \
    -u OPEN_KEYBOARD_SIMULATOR_LEGACY_MODEL \
    -u OPEN_KEYBOARD_SIMULATOR_LEGACY_PROFILE_STATE \
    -u OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE \
    -u OPEN_KEYBOARD_REAL_KEYBOARD_LIVE_TEST \
    -u OPEN_KEYBOARD_REAL_KEYBOARD_SIMULATOR \
    -u OPEN_KEYBOARD_REAL_SCREENSHOT_DIR \
    -u OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE \
    -u OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_DIR \
    -u OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_PHRASE \
    -u SIMCTL_CHILD_OPEN_KEYBOARD_TEST_GATEWAY_URL \
    -u SIMCTL_CHILD_OPEN_KEYBOARD_TEST_API_KEY \
    -u SIMCTL_CHILD_OPEN_KEYBOARD_TEST_MODEL \
    -u SIMCTL_CHILD_OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG \
    OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE="$SEED_FILE" \
    OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT="$differential_evidence_file" \
      "$ROOT/scripts/ios/test.sh" live-model-differential
  [[ -s "$differential_evidence_file" ]] || fail "Targeted live-model evidence output was not produced."
  require_private_evidence_shape "$differential_evidence_file" 10 "Targeted live-model evidence"
  PROFILE_MODEL_BINDINGS_LINE="$(grep -E '^profile_model_bindings=' "$differential_evidence_file")"
  PROFILE_MODELS_DISTINCT_LINE="$(grep -E '^profile_models_distinct=' "$differential_evidence_file")"
  BASELINE_LINE="$(grep -E '^baseline_outcomes=' "$differential_evidence_file")"
  DIFFERENTIAL_LINE="$(grep -E '^differential_outcomes=' "$differential_evidence_file")"
  FOLLOW_UP_LINE="$(grep -E '^follow_up_outcomes=' "$differential_evidence_file")"
  SUMMARIZE_LINE="$(grep -E '^summarize_outcomes=' "$differential_evidence_file")"
  CONTINUE_WRITING_LINE="$(grep -E '^continue_writing_outcomes=' "$differential_evidence_file")"
  WARNING_LINE="$(grep -E '^operation_scoped_warning_contracts=' "$differential_evidence_file")"
  DIAGNOSTIC_OUTCOMES_LOW_LINE="$(grep -E '^diagnostic_outcomes_low=' "$differential_evidence_file")"
  DIAGNOSTIC_OUTCOMES_HIGH_LINE="$(grep -E '^diagnostic_outcomes_high=' "$differential_evidence_file")"
  [[ "$PROFILE_MODEL_BINDINGS_LINE" == "profile_model_bindings=low=true, high=true" ]] || fail "Targeted live-model evidence did not preserve both profile bindings."
  [[ "$PROFILE_MODELS_DISTINCT_LINE" == "profile_models_distinct=true" ]] || fail "Targeted live-model evidence did not preserve distinct profile roles."
  [[ "$BASELINE_LINE" == "baseline_outcomes=low=passed, high=passed" ]] || fail "Targeted baseline outcomes were not verified."
  [[ "$DIFFERENTIAL_LINE" == "differential_outcomes=low=expected-model-capability, high=passed" ]] || fail "Targeted capability-boundary outcomes were not verified."
  [[ "$FOLLOW_UP_LINE" == "follow_up_outcomes=low=passed, high=passed" ]] || fail "Targeted follow-up outcomes were not verified."
  [[ "$SUMMARIZE_LINE" == "summarize_outcomes=low=passed, high=passed" ]] || fail "Targeted Summarize outcomes were not verified."
  [[ "$CONTINUE_WRITING_LINE" == "continue_writing_outcomes=low=passed, high=passed" ]] || fail "Targeted Continue Writing outcomes were not verified."
  [[ "$WARNING_LINE" == "operation_scoped_warning_contracts=verified" ]] || fail "Operation-scoped warning contracts were not verified."
  [[ "$DIAGNOSTIC_OUTCOMES_LOW_LINE" =~ ^diagnostic_outcomes_low=transport=passed,\ grammar=(passed|failed),\ rewrite=(passed|failed),\ translation=(passed|failed)$ ]] || fail "Low-profile diagnostic capability outcomes are malformed."
  [[ "$DIAGNOSTIC_OUTCOMES_HIGH_LINE" =~ ^diagnostic_outcomes_high=transport=passed,\ grammar=(passed|failed),\ rewrite=(passed|failed),\ translation=(passed|failed)$ ]] || fail "High-profile diagnostic capability outcomes are malformed."
else
  echo "Running local live gateway smoke for exact HEAD."
  env \
    -u UAC_LIVE_ENV_FILE \
    -u REQUIRED_MODEL \
    -u REQUIRED_MODELS \
    -u REQUIRED_LOW_MODEL \
    -u REQUIRED_HIGH_MODEL \
    -u TESTED_MODEL \
    -u TESTED_MODELS \
    -u REQUIRED_MODEL_INPUT \
    -u REQUIRED_MODELS_INPUT \
    -u OPEN_KEYBOARD_LIVE_BASE_REF \
    -u OPEN_KEYBOARD_LIVE_EXPECTED_SHA \
    -u OPEN_KEYBOARD_LIVE_REQUIRE_DIFFERENTIAL \
    -u OPENAI_API_KEY \
    -u OPENAI_LIVE_MODEL \
    -u ANTHROPIC_API_KEY \
    -u ANTHROPIC_LIVE_MODEL \
    -u OPENROUTER_API_KEY \
    -u OPENROUTER_LIVE_MODEL \
    -u GATEWAY_LIVE_BASE_URL \
    -u GATEWAY_API_KEY \
    -u GATEWAY_LIVE_MODEL \
    -u GATEWAY_LIVE_STRUCTURED_OUTPUT \
    -u OPEN_KEYBOARD_UAC_LIVE_CHECKOUT \
    -u OPEN_KEYBOARD_LIVE_GATEWAY_URL \
    -u OPEN_KEYBOARD_LIVE_API_KEY \
    -u OPEN_KEYBOARD_LIVE_MODEL \
    -u OPEN_KEYBOARD_LIVE_REQUIRED_MODEL \
    -u OPEN_KEYBOARD_LIVE_REQUIRED_MODELS \
    -u OPEN_KEYBOARD_LIVE_PROFILE \
    -u OPEN_KEYBOARD_LIVE_PROVIDER_EVIDENCE_OUTPUT \
    -u OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT \
    -u OPEN_KEYBOARD_TEST_GATEWAY_URL \
    -u OPEN_KEYBOARD_TEST_API_KEY \
    -u OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX \
    -u OPEN_KEYBOARD_TEST_API_KEY_HEX \
    -u OPEN_KEYBOARD_TEST_MODEL \
    -u OPEN_KEYBOARD_TEST_PROVIDER \
    -u OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG \
    -u OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE \
    -u OPEN_KEYBOARD_SIMULATOR_PROVIDER \
    -u OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE \
    -u OPEN_KEYBOARD_SIMULATOR_LOCK_HELD \
    -u OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL \
    -u OPEN_KEYBOARD_SIMULATOR_API_KEY \
    -u OPEN_KEYBOARD_SIMULATOR_MODEL \
    -u OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL \
    -u OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY \
    -u OPEN_KEYBOARD_SIMULATOR_LOW_MODEL \
    -u OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL \
    -u OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY \
    -u OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL \
    -u OPEN_KEYBOARD_SIMULATOR_LEGACY_GATEWAY_URL \
    -u OPEN_KEYBOARD_SIMULATOR_LEGACY_API_KEY \
    -u OPEN_KEYBOARD_SIMULATOR_LEGACY_MODEL \
    -u OPEN_KEYBOARD_SIMULATOR_LEGACY_PROFILE_STATE \
    -u OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE \
    -u OPEN_KEYBOARD_REAL_KEYBOARD_LIVE_TEST \
    -u OPEN_KEYBOARD_REAL_KEYBOARD_SIMULATOR \
    -u OPEN_KEYBOARD_REAL_SCREENSHOT_DIR \
    -u OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE \
    -u OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_DIR \
    -u OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_PHRASE \
    -u SIMCTL_CHILD_OPEN_KEYBOARD_TEST_GATEWAY_URL \
    -u SIMCTL_CHILD_OPEN_KEYBOARD_TEST_API_KEY \
    -u SIMCTL_CHILD_OPEN_KEYBOARD_TEST_MODEL \
    -u SIMCTL_CHILD_OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG \
    OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE="$SEED_FILE" \
    OPEN_KEYBOARD_LIVE_PROFILE="$OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE" \
      "$ROOT/scripts/ios/test.sh" live-gateway-smoke
fi

POST_LIVE_SHA="$(git -C "$ROOT" rev-parse --verify HEAD)"
if [[ "$POST_LIVE_SHA" != "$HEAD_SHA" ]]; then
  fail "Live verification HEAD changed during the gateway smoke."
fi
require_clean_checkout

# Exact model/provider identities have already been compared in this process against the guarded
# seed and exercised by the live tests. Drop the private values before emitting retained evidence.
clear_private_live_state

echo "OpenKeyboard live gateway verification passed."
echo "target=$LIVE_MODE"
echo "head_sha=$HEAD_SHA"
echo "${PROVIDER_BINDINGS_LINE}"
echo "${PROVIDER_TEST_CONNECTION_LINE}"
echo "${PROVIDER_DIAGNOSTICS_LINE}"
if [[ "$LIVE_MODE" == "gateway-differential" ]]; then
  echo "model_requirement=$MODEL_REQUIREMENT"
  echo "model_identity_matches=$MODEL_IDENTITY_MATCHES"
  echo "model_roles_distinct=$MODEL_ROLES_DISTINCT"
  echo "${BASELINE_LINE}"
  echo "${DIFFERENTIAL_LINE}"
  echo "${FOLLOW_UP_LINE}"
  echo "${SUMMARIZE_LINE}"
  echo "${CONTINUE_WRITING_LINE}"
  echo "${WARNING_LINE}"
  echo "${DIAGNOSTIC_OUTCOMES_LOW_LINE}"
  echo "${DIAGNOSTIC_OUTCOMES_HIGH_LINE}"
else
  echo "model_requirement=$MODEL_REQUIREMENT"
  echo "model_identity_matches=$MODEL_IDENTITY_MATCHES"
  echo "model_roles_distinct=$MODEL_ROLES_DISTINCT"
fi
echo "model_substitutions=none"
echo "plain_text_grammar_verified=true"
