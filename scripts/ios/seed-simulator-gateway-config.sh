#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/ios/seed-simulator-gateway-config.sh --seed-file <path> [--simulator <name-or-udid>] [--replace-existing-config]

Explicitly seeds a booted iOS Simulator OpenKeyboard install with real gateway
configuration for local actual-keyboard testing. This is a developer-only flow;
unit/core tests must keep using DummyGatewayServer.

By default, existing real simulator gateway config is preserved and the app only
uses the seed when no complete config is available. Pass
--replace-existing-config only for disposable simulators where clearing first is
intended.

Required seed file variables:
  OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL=https://your-gateway.example
  OPEN_KEYBOARD_SIMULATOR_API_KEY=your-real-key
  OPEN_KEYBOARD_SIMULATOR_MODEL=your-model

The real seed file must live in an ignored local path such as:
  .agent/local-seeds/openkeyboard-gateway.env

The script intentionally redacts API key values in logs.
USAGE
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_allowed_seed_key() {
  case "$1" in
    OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL|OPEN_KEYBOARD_SIMULATOR_API_KEY|OPEN_KEYBOARD_SIMULATOR_MODEL)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

load_seed_file() {
  local line line_number key value
  line_number=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="$(trim "$line")"

    if [[ -z "$line" || "$line" == \#* ]]; then
      continue
    fi

    if [[ "$line" == export[[:space:]]* ]]; then
      line="$(trim "${line#export}")"
    fi

    if [[ "$line" != *=* ]]; then
      echo "Invalid seed file line $line_number: expected KEY=value" >&2
      exit 2
    fi

    key="$(trim "${line%%=*}")"
    value="$(trim "${line#*=}")"

    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "Invalid seed variable name on line $line_number" >&2
      exit 2
    fi

    if ! is_allowed_seed_key "$key"; then
      echo "Unsupported seed variable on line $line_number: $key" >&2
      exit 2
    fi

    if [[ ${#value} -ge 2 && "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ ${#value} -ge 2 && "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi

    printf -v "$key" '%s' "$value"
  done < "$seed_file"
}

seed_file=""
simulator="booted"
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

if [[ ! -f "$seed_file" ]]; then
  echo "Seed file not found: $seed_file" >&2
  exit 2
fi

case "$seed_file" in
  .agent/local-seeds/*|*/.agent/local-seeds/*) ;;
  *)
    echo "Refusing seed file outside ignored .agent/local-seeds/: $seed_file" >&2
    echo "Move the real seed file to .agent/local-seeds/openkeyboard-gateway.env" >&2
    exit 2
    ;;
esac

load_seed_file

required=(
  OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL
  OPEN_KEYBOARD_SIMULATOR_API_KEY
  OPEN_KEYBOARD_SIMULATOR_MODEL
)
for key in "${required[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    echo "Missing required seed variable: $key" >&2
    exit 2
  fi
done

api_key_length=${#OPEN_KEYBOARD_SIMULATOR_API_KEY}
if [[ "$api_key_length" -lt 8 ]]; then
  echo "Refusing suspiciously short API key; length=$api_key_length" >&2
  exit 2
fi

bundle_id="com.maneesh.openkeyboard"

echo "Seeding OpenKeyboard simulator gateway config explicitly."
echo "Simulator: $simulator"
echo "Gateway URL: $OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL"
echo "Model: $OPEN_KEYBOARD_SIMULATOR_MODEL"
echo "API key: <redacted length=$api_key_length>"
if [[ "$replace_existing_config" == true ]]; then
  echo "Existing simulator config: replace requested; app will clear before seeding."
else
  echo "Existing simulator config: preserve; seed is used only when config is unavailable."
fi

launch_arguments=(
  --uitesting
  --seed-functional-gateway-config
  --skip-onboarding
)
if [[ "$replace_existing_config" == true ]]; then
  launch_arguments=(
    --uitesting
    --clear-gateway-config
    --seed-functional-gateway-config
    --skip-onboarding
  )
fi

OPEN_KEYBOARD_TEST_GATEWAY_URL="$OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL" \
OPEN_KEYBOARD_TEST_API_KEY="$OPEN_KEYBOARD_SIMULATOR_API_KEY" \
OPEN_KEYBOARD_TEST_MODEL="$OPEN_KEYBOARD_SIMULATOR_MODEL" \
OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG="$([[ "$replace_existing_config" == true ]] && printf '1' || printf '0')" \
xcrun simctl launch \
  "$simulator" \
  "$bundle_id" \
  "${launch_arguments[@]}" \
  >/tmp/openkeyboard-simulator-seed.log

echo "Seed launch completed. Simulator launch output: /tmp/openkeyboard-simulator-seed.log"
echo "No API key value was printed by this script."
