#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"
DEFAULT_SEED_FILE=".agent/local-seeds/openkeyboard-gateway.env"
source "$ROOT/scripts/ios/live-test-safety.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/check-live.sh gateway

The gateway check reads the persistent ignored seed in the primary checkout:
  <primary-checkout>/.agent/local-seeds/openkeyboard-gateway.env

Optional:
  OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE  Alternate ignored seed beneath the
                                             primary checkout's local-seeds directory.
  OPEN_KEYBOARD_LIVE_EXPECTED_SHA            Exact 40-character expected HEAD.
  OPEN_KEYBOARD_LIVE_REQUIRED_MODEL          Exact model ID required by this task.
                                             Omit only for model-agnostic gateway work.
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

if [[ "$#" -ne 1 || "$TARGET" != "gateway" ]]; then
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
TESTED_MODEL="${OPEN_KEYBOARD_SIMULATOR_MODEL:-}"
REQUIRED_MODEL="${OPEN_KEYBOARD_LIVE_REQUIRED_MODEL:-model-agnostic}"
openkeyboard_require_exact_live_model "$TESTED_MODEL" "$REQUIRED_MODEL" ||
  fail "Live model coverage validation failed."

echo "Running deterministic gateway prerequisites for exact HEAD."
env \
  -u OPEN_KEYBOARD_LIVE_GATEWAY_URL \
  -u OPEN_KEYBOARD_LIVE_API_KEY \
  -u OPEN_KEYBOARD_LIVE_MODEL \
  -u OPEN_KEYBOARD_TEST_GATEWAY_URL \
  -u OPEN_KEYBOARD_TEST_API_KEY \
  -u OPEN_KEYBOARD_TEST_MODEL \
  "$ROOT/scripts/ios/test.sh" core

POST_DETERMINISTIC_SHA="$(git -C "$ROOT" rev-parse --verify HEAD)"
if [[ "$POST_DETERMINISTIC_SHA" != "$HEAD_SHA" ]]; then
  fail "Live verification HEAD changed during deterministic tests."
fi
require_clean_checkout

echo "Running local live gateway smoke for exact HEAD."
OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE="$SEED_FILE" \
  "$ROOT/scripts/ios/test.sh" live-gateway-smoke

POST_LIVE_SHA="$(git -C "$ROOT" rev-parse --verify HEAD)"
if [[ "$POST_LIVE_SHA" != "$HEAD_SHA" ]]; then
  fail "Live verification HEAD changed during the gateway smoke."
fi
require_clean_checkout

echo "OpenKeyboard live gateway verification passed."
echo "target=gateway"
echo "head_sha=$HEAD_SHA"
echo "required_model=$REQUIRED_MODEL"
echo "tested_model=$TESTED_MODEL"
