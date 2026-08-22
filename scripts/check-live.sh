#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"
DEFAULT_SEED_FILE=".agent/local-seeds/openkeyboard-gateway.env"
source "$ROOT/scripts/ios/live-test-safety.sh"

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

if [[ "$LIVE_MODE" == "gateway-differential" ]]; then
  openkeyboard_require_two_profile_gateway_seed ||
    fail "Two-profile live model coverage validation failed."
  TESTED_MODELS="low=$OPEN_KEYBOARD_SIMULATOR_LOW_MODEL, high=$OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL"
  REQUIRED_MODELS="${OPEN_KEYBOARD_LIVE_REQUIRED_MODELS:-$TESTED_MODELS}"
  if [[ ! "$REQUIRED_MODELS" =~ ^low=([A-Za-z0-9][A-Za-z0-9._:/+-]*),\ high=([A-Za-z0-9][A-Za-z0-9._:/+-]*)$ ]]; then
    fail "Differential live-model requirements must use canonical low=<id>, high=<id> order."
  fi
  REQUIRED_LOW_MODEL="${BASH_REMATCH[1]}"
  REQUIRED_HIGH_MODEL="${BASH_REMATCH[2]}"
  openkeyboard_require_exact_live_model "$OPEN_KEYBOARD_SIMULATOR_LOW_MODEL" "$REQUIRED_LOW_MODEL" ||
    fail "The low live-model profile does not match the exact requirement."
  openkeyboard_require_exact_live_model "$OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL" "$REQUIRED_HIGH_MODEL" ||
    fail "The high live-model profile does not match the exact requirement."
  if [[ "$REQUIRED_MODELS" != "$TESTED_MODELS" ]]; then
    fail "Differential live-model substitution or role reversal is not allowed."
  fi
else
  openkeyboard_select_reference_simulator_gateway_profile ||
    fail "Reference live-model profile selection failed."
  TESTED_MODEL="$OPEN_KEYBOARD_SIMULATOR_MODEL"
  REQUIRED_MODEL="${OPEN_KEYBOARD_LIVE_REQUIRED_MODEL:-model-agnostic}"
  openkeyboard_require_exact_live_model "$TESTED_MODEL" "$REQUIRED_MODEL" ||
    fail "Live model coverage validation failed."
fi

echo "Running deterministic gateway prerequisites for exact HEAD."
env \
  -u OPEN_KEYBOARD_LIVE_GATEWAY_URL \
  -u OPEN_KEYBOARD_LIVE_API_KEY \
  -u OPEN_KEYBOARD_LIVE_MODEL \
  -u OPEN_KEYBOARD_TEST_GATEWAY_URL \
  -u OPEN_KEYBOARD_TEST_API_KEY \
  -u OPEN_KEYBOARD_TEST_MODEL \
  -u OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL \
  -u OPEN_KEYBOARD_SIMULATOR_API_KEY \
  -u OPEN_KEYBOARD_SIMULATOR_MODEL \
  -u OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL \
  -u OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY \
  -u OPEN_KEYBOARD_SIMULATOR_LOW_MODEL \
  -u OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL \
  -u OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY \
  -u OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL \
  "$ROOT/scripts/ios/test.sh" core

POST_DETERMINISTIC_SHA="$(git -C "$ROOT" rev-parse --verify HEAD)"
if [[ "$POST_DETERMINISTIC_SHA" != "$HEAD_SHA" ]]; then
  fail "Live verification HEAD changed during deterministic tests."
fi
require_clean_checkout

if [[ "$LIVE_MODE" == "gateway-differential" ]]; then
  evidence_file="$(mktemp "${TMPDIR:-/tmp}/openkeyboard-live-evidence.XXXXXX")"
  chmod 600 "$evidence_file"
  trap 'openkeyboard_cleanup_live_evidence_file "$evidence_file"' EXIT
  trap 'openkeyboard_exit_after_live_evidence_signal 129 "$evidence_file"' HUP
  trap 'openkeyboard_exit_after_live_evidence_signal 130 "$evidence_file"' INT
  trap 'openkeyboard_exit_after_live_evidence_signal 143 "$evidence_file"' TERM
  echo "Running the targeted two-profile live-model matrix for exact HEAD."
  OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE="$SEED_FILE" \
  OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT="$evidence_file" \
    "$ROOT/scripts/ios/test.sh" live-model-differential
  [[ -s "$evidence_file" ]] || fail "Targeted live-model evidence output was not produced."
  MODELS_LINE="$(grep -E '^models=' "$evidence_file")"
  BASELINE_LINE="$(grep -E '^baseline_outcomes=' "$evidence_file")"
  DIFFERENTIAL_LINE="$(grep -E '^differential_outcomes=' "$evidence_file")"
  FOLLOW_UP_LINE="$(grep -E '^follow_up_outcomes=' "$evidence_file")"
  WARNING_LINE="$(grep -E '^operation_scoped_warning_contracts=' "$evidence_file")"
  LATENCY_LINE="$(grep -E '^profile_latencies=' "$evidence_file")"
  [[ "$MODELS_LINE" == "models=$TESTED_MODELS" ]] || fail "Targeted live-model evidence used an unexpected profile mapping."
  [[ "$BASELINE_LINE" == "baseline_outcomes=low=passed, high=passed" ]] || fail "Targeted baseline outcomes were not verified."
  [[ "$DIFFERENTIAL_LINE" == "differential_outcomes=low=expected-model-capability, high=passed" ]] || fail "Targeted capability-boundary outcomes were not verified."
  [[ "$FOLLOW_UP_LINE" == "follow_up_outcomes=low=passed, high=passed" ]] || fail "Targeted follow-up outcomes were not verified."
  [[ "$WARNING_LINE" == "operation_scoped_warning_contracts=verified" ]] || fail "Operation-scoped warning contracts were not verified."
  [[ "$LATENCY_LINE" =~ ^profile_latencies=low=[0-9]+([.][0-9]{3})?s,\ high=[0-9]+([.][0-9]{3})?s$ ]] || fail "Per-profile live latency evidence is malformed."
else
  echo "Running local live gateway smoke for exact HEAD."
  OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE="$SEED_FILE" \
  OPEN_KEYBOARD_LIVE_PROFILE="$OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE" \
    "$ROOT/scripts/ios/test.sh" live-gateway-smoke
fi

POST_LIVE_SHA="$(git -C "$ROOT" rev-parse --verify HEAD)"
if [[ "$POST_LIVE_SHA" != "$HEAD_SHA" ]]; then
  fail "Live verification HEAD changed during the gateway smoke."
fi
require_clean_checkout

echo "OpenKeyboard live gateway verification passed."
echo "target=$LIVE_MODE"
echo "head_sha=$HEAD_SHA"
if [[ "$LIVE_MODE" == "gateway-differential" ]]; then
  echo "required_models=$REQUIRED_MODELS"
  echo "tested_models=$TESTED_MODELS"
  echo "${BASELINE_LINE}"
  echo "${DIFFERENTIAL_LINE}"
  echo "${FOLLOW_UP_LINE}"
  echo "${WARNING_LINE}"
  echo "${LATENCY_LINE}"
  echo "model_substitutions=none"
else
  echo "required_model=$REQUIRED_MODEL"
  echo "tested_model=$TESTED_MODEL"
fi
echo "plain_text_grammar_verified=true"
