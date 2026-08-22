#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/scripts/ios/live-test-safety.sh"

usage() {
  cat <<'USAGE'
Usage: scripts/ios/seed-simulator-gateway-config.sh --seed-file <path> [--profile <reference|legacy|low|high>] [--simulator <name-or-udid>] [--replace-existing-config]

Explicitly seeds a booted iOS Simulator OpenKeyboard install with real gateway
configuration for local actual-keyboard testing. This is a developer-only flow;
unit/core tests must keep using DummyGatewayServer.

By default, existing real simulator gateway config is preserved and the app only
uses the seed when no complete config is available. Pass
--replace-existing-config only for disposable simulators where clearing first is
intended.

Legacy fallback seed variables:
  OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL=https://your-gateway.example
  OPEN_KEYBOARD_SIMULATOR_API_KEY=your-real-key
  OPEN_KEYBOARD_SIMULATOR_MODEL=your-model

Two-profile live verification instead defines complete LOW and HIGH triples.
The default reference selection uses HIGH when present, otherwise the legacy
fallback. It never silently selects LOW.

The real seed file must live in the primary checkout's ignored local path:
  <primary-checkout>/.agent/local-seeds/openkeyboard-gateway.env

The script intentionally redacts API key values in logs.
USAGE
}

seed_file=""
simulator="booted"
profile="reference"
replace_existing_config=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seed-file)
      seed_file="${2:-}"
      shift 2
      ;;
    --simulator)
      simulator="${2:-}"
      shift 2
      ;;
    --profile)
      profile="${2:-}"
      shift 2
      ;;
    --replace-existing-config|--clear-existing-config)
      replace_existing_config=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$seed_file" ]]; then
  echo "Missing --seed-file" >&2
  usage >&2
  exit 2
fi

seed_file="$(openkeyboard_require_local_seed_file "$REPO_ROOT" "$seed_file")" || exit 2

openkeyboard_load_simulator_gateway_seed "$seed_file"
case "$profile" in
  reference)
    openkeyboard_select_reference_simulator_gateway_profile
    ;;
  legacy|low|high)
    openkeyboard_select_simulator_gateway_profile "$profile"
    ;;
  *)
    echo "--profile must be reference, legacy, low, or high." >&2
    exit 2
    ;;
esac

api_key_length=${#OPEN_KEYBOARD_SIMULATOR_API_KEY}
if [[ "$api_key_length" -lt 8 ]]; then
  echo "Refusing suspiciously short API key." >&2
  exit 2
fi

bundle_id="com.maneesh.openkeyboard"

echo "Seeding OpenKeyboard simulator gateway config explicitly."
echo "Simulator: $simulator"
echo "Credential profile: $OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE"
echo "Gateway URL: <configured>"
echo "Model: <configured>"
echo "API key: <configured>"
if [[ "$replace_existing_config" == true ]]; then
  echo "Existing simulator config: replace requested; app will clear before seeding."
else
  echo "Existing simulator config: preserve; seed is used only when config is unavailable."
fi

launch_arguments=(
  --uitesting
  --seed-functional-gateway-config
  --keyboard-host-test
  --skip-onboarding
)
if [[ "$replace_existing_config" == true ]]; then
  launch_arguments=(
    --uitesting
    --clear-gateway-config
    --seed-functional-gateway-config
    --keyboard-host-test
    --skip-onboarding
  )
fi

SIMCTL_CHILD_OPEN_KEYBOARD_TEST_GATEWAY_URL="$OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL" \
SIMCTL_CHILD_OPEN_KEYBOARD_TEST_API_KEY="$OPEN_KEYBOARD_SIMULATOR_API_KEY" \
SIMCTL_CHILD_OPEN_KEYBOARD_TEST_MODEL="$OPEN_KEYBOARD_SIMULATOR_MODEL" \
SIMCTL_CHILD_OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG="$([[ "$replace_existing_config" == true ]] && printf '1' || printf '0')" \
xcrun simctl launch \
  "$simulator" \
  "$bundle_id" \
  "${launch_arguments[@]}" \
  >/dev/null

echo "Seed launch completed."
echo "No API key value was printed by this script."
