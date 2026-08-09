#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---hygiene}"

usage() {
  cat <<'EOF'
Usage: ./scripts/check-environment.sh [--hygiene|--quick|--full]

  --hygiene  Check the standard shell, Git, YAML, and secret-scan tools.
  --quick    Check hygiene tools plus Swift and the iOS build toolchain.
  --full     Check quick tools plus the required iPhone 16 simulator.
EOF
}

case "$MODE" in
  --hygiene|hygiene)
    MODE="--hygiene"
    ;;
  --quick|quick)
    MODE="--quick"
    ;;
  --full|full)
    MODE="--full"
    ;;
  --help|-h|help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown environment-check mode: $MODE" >&2
    usage >&2
    exit 2
    ;;
esac

require_command() {
  local command_name="$1"
  local explanation="$2"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Contributor environment is missing '$command_name': $explanation" >&2
    return 1
  fi
}

require_standard_env() {
  local env_path
  local probe_output
  local probe_status

  env_path="$(command -v env || true)"
  if [[ -z "$env_path" ]]; then
    echo "Contributor environment is missing the standard 'env' command." >&2
    return 1
  fi

  probe_status=0
  probe_output="$(
    env OPEN_KEYBOARD_ENV_COMMAND_PROBE=works \
      /bin/sh -c 'printf "%s" "$OPEN_KEYBOARD_ENV_COMMAND_PROBE"'
  )" || probe_status=$?

  if [[ "$probe_status" -ne 0 || "$probe_output" != "works" ]]; then
    echo "Contributor environment has a non-standard 'env' command: $env_path" >&2
    echo "The project requires 'env NAME=value command' to execute that command." >&2
    return 1
  fi
}

require_apple_toolchain() {
  local simulator_sdk_path
  local simulator_sdk_status

  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "OpenKeyboard quick and full checks require macOS." >&2
    return 1
  fi

  require_command swift "Install and select Xcode with the Swift toolchain." || return 1
  require_command xcodebuild "Install and select Xcode." || return 1
  require_command xcrun "Install and select Xcode command-line tools." || return 1

  if ! xcodebuild -version >/dev/null 2>&1; then
    echo "Contributor environment could not execute the selected Xcode." >&2
    return 1
  fi

  simulator_sdk_status=0
  simulator_sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)" ||
    simulator_sdk_status=$?
  if [[ "$simulator_sdk_status" -ne 0 || -z "$simulator_sdk_path" ]]; then
    echo "Contributor environment could not resolve the iOS Simulator SDK." >&2
    return 1
  fi
}

require_iphone_16_simulator() {
  local available_devices

  available_devices="$(xcrun simctl list devices available)"
  if ! rg --quiet 'iPhone 16 \(' <<< "$available_devices"; then
    echo "OpenKeyboard full checks require an available iPhone 16 simulator." >&2
    return 1
  fi
}

require_standard_env
require_command bash "Bash runs the committed repository scripts."
require_command git "Git provides source and exact-head checks."
require_command realpath "realpath enforces canonical local-seed containment."
require_command rg "Ripgrep performs fail-closed policy and secret scanning."
require_command ruby "Ruby validates committed YAML syntax."

if [[ "$MODE" == "--quick" || "$MODE" == "--full" ]]; then
  require_apple_toolchain
fi

if [[ "$MODE" == "--full" ]]; then
  require_iphone_16_simulator
fi

echo "Contributor environment preflight passed for $MODE."
