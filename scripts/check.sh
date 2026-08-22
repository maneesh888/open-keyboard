#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---full}"

usage() {
  cat <<'EOF'
Usage: ./scripts/check.sh [--hygiene|--quick|--full]

  --hygiene  Validate shell/YAML syntax, policies, secrets, and whitespace.
  --quick    Run hygiene, OpenKeyboardCore tests, and the app/extension build.
  --full     Run quick coverage plus deterministic UI-target tests.
             This is the default.
EOF
}

validate_yaml() {
  local yaml_file

  while IFS= read -r -d '' yaml_file; do
    if [[ ! -f "$ROOT/$yaml_file" ]]; then
      continue
    fi
    ruby -e 'require "yaml"; YAML.parse_file(ARGV.fetch(0))' "$ROOT/$yaml_file"
  done < <(
    git -C "$ROOT" ls-files --cached --others --exclude-standard -z -- \
      '*.yml' '*.yaml'
  )
}

validate_all_whitespace() {
  local temp_index_directory
  local temp_index
  local temp_object_directory
  local repository_object_directory

  git -C "$ROOT" diff --check
  git -C "$ROOT" diff --cached --check

  temp_index_directory="$(mktemp -d)"
  temp_index="$temp_index_directory/index"
  temp_object_directory="$temp_index_directory/objects"
  repository_object_directory="$(git -C "$ROOT" rev-parse --git-path objects)"
  mkdir -p "$temp_object_directory"

  cleanup_temp_index() {
    rm -rf -- "$temp_index_directory"
  }
  trap cleanup_temp_index EXIT

  GIT_INDEX_FILE="$temp_index" \
    GIT_OBJECT_DIRECTORY="$temp_object_directory" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$repository_object_directory" \
    git -C "$ROOT" read-tree HEAD
  GIT_INDEX_FILE="$temp_index" \
    GIT_OBJECT_DIRECTORY="$temp_object_directory" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$repository_object_directory" \
    git -C "$ROOT" add --intent-to-add .
  GIT_INDEX_FILE="$temp_index" \
    GIT_OBJECT_DIRECTORY="$temp_object_directory" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$repository_object_directory" \
    git -C "$ROOT" diff --check

  cleanup_temp_index
  trap - EXIT
}

run_script_policy_tests() {
  "$ROOT/scripts/tests/environment-preflight-test.sh"
  "$ROOT/scripts/tests/secret-scan-test.sh"
  "$ROOT/scripts/tests/live-impact-test.sh"
  "$ROOT/scripts/tests/live-policy-bootstrap-test.sh"
  "$ROOT/scripts/tests/live-test-safety-test.sh"
  "$ROOT/scripts/tests/live-evidence-policy-test.sh"
  "$ROOT/scripts/tests/pr-requirements-policy-test.sh"
  "$ROOT/scripts/tests/pr-review-record-policy-test.sh"
  "$ROOT/scripts/tests/review-workflow-snapshot-test.sh"
  "$ROOT/scripts/tests/deploy-source-policy-test.sh"
  "$ROOT/scripts/tests/workflow-policy-test.sh"
}

run_hygiene() {
  local preflight_mode="${1:---hygiene}"
  local shell_file

  "$ROOT/scripts/check-environment.sh" "$preflight_mode"

  while IFS= read -r -d '' shell_file; do
    if [[ ! -f "$ROOT/$shell_file" ]]; then
      continue
    fi
    bash -n "$ROOT/$shell_file"
  done < <(
    git -C "$ROOT" ls-files --cached --others --exclude-standard -z -- \
      '*.sh' '.githooks/*'
  )

  validate_yaml
  "$ROOT/scripts/secret-scan.sh"
  run_script_policy_tests
  validate_all_whitespace
  echo "OpenKeyboard hygiene checks passed."
}

run_quick() {
  run_hygiene --quick
  "$ROOT/scripts/check-semantic-prompt-contract.sh"
  "$ROOT/scripts/local-ci.sh" --quick
  echo "OpenKeyboard quick checks passed."
}

run_full() {
  run_hygiene --full
  "$ROOT/scripts/check-semantic-prompt-contract.sh"
  "$ROOT/scripts/local-ci.sh" --quick
  "$ROOT/scripts/ios/test.sh" deterministic-ui
  echo "OpenKeyboard full deterministic checks passed."
}

case "$MODE" in
  --hygiene|hygiene)
    run_hygiene --hygiene
    ;;
  --quick|quick)
    run_quick
    ;;
  --full|full)
    run_full
    ;;
  --help|-h|help)
    usage
    ;;
  *)
    echo "Unknown check mode: $MODE" >&2
    usage >&2
    exit 2
    ;;
esac
