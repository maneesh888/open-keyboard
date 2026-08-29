#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/ios/live-test-safety.sh"

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/openkeyboard-live-safety.XXXXXX")"
TEST_CHILD_PIDS=()

cleanup_fixture() {
  local child_pid

  if [[ "${#TEST_CHILD_PIDS[@]}" -gt 0 ]]; then
    for child_pid in "${TEST_CHILD_PIDS[@]}"; do
      kill -TERM "$child_pid" >/dev/null 2>&1 || true
      wait "$child_pid" >/dev/null 2>&1 || true
    done
  fi
  rm -rf -- "$FIXTURE"
}
trap cleanup_fixture EXIT

forget_test_child_pid() {
  local completed_pid="$1"
  local child_pid
  local remaining_pids=()

  for child_pid in "${TEST_CHILD_PIDS[@]}"; do
    if [[ "$child_pid" != "$completed_pid" ]]; then
      remaining_pids+=("$child_pid")
    fi
  done
  if [[ "${#remaining_pids[@]}" -eq 0 ]]; then
    TEST_CHILD_PIDS=()
  else
    TEST_CHILD_PIDS=("${remaining_pids[@]}")
  fi
}

# Git exports repository-local variables to hooks. Clear them before operating on fixture repos.
while IFS= read -r git_environment_name; do
  unset "$git_environment_name"
done < <(git -C "$ROOT" rev-parse --local-env-vars)

initialize_repository() {
  local repository="$1"

  mkdir -p "$repository/.agent/local-seeds"
  chmod 700 "$repository/.agent/local-seeds"
  git -C "$repository" init -q
  git -C "$repository" config user.name "OpenKeyboard Policy Test"
  git -C "$repository" config user.email "policy-test@example.invalid"
  printf '.agent/local-seeds/\n' > "$repository/.gitignore"
  printf 'base\n' > "$repository/README.md"
  git -C "$repository" add .gitignore README.md
  git -C "$repository" commit -q -m base
}

SECRET_SENTINEL='test-only-secret-value-that-must-never-be-logged'

write_valid_seed() {
  local seed_file="$1"

  printf '%s\n' \
    'OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL=https://gateway.example.invalid' \
    "OPEN_KEYBOARD_SIMULATOR_API_KEY=$SECRET_SENTINEL" \
    'OPEN_KEYBOARD_SIMULATOR_MODEL=test-model' \
    > "$seed_file"
  chmod 600 "$seed_file"
}

write_dual_profile_seed() {
  local seed_file="$1"

  printf '%s\n' \
    'OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL=https://low-gateway.example.invalid' \
    "OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY=$SECRET_SENTINEL-low" \
    'OPEN_KEYBOARD_SIMULATOR_LOW_MODEL=low-model:2b' \
    'OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL=https://high-gateway.example.invalid' \
    "OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY=$SECRET_SENTINEL-high" \
    'OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL=high-model:120b' \
    > "$seed_file"
  chmod 600 "$seed_file"
}

assert_output_excludes_secret() {
  local output_file="$1"
  local context="$2"

  if grep -Fq -- "$SECRET_SENTINEL" "$output_file"; then
    echo "$context emitted a secret value." >&2
    exit 1
  fi
}

assert_simulator_profiles_unset() {
  local variable_name

  for variable_name in \
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
    OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE; do
    if [[ -n "${!variable_name+x}" ]]; then
      echo "Sensitive simulator profile variable was retained after cleanup: $variable_name" >&2
      exit 1
    fi
  done
}

PRIMARY_CHECKOUT="$FIXTURE/machine one/Open Keyboard"
LINKED_WORKTREE="$FIXTURE/temporary linked worktree"
VALID_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/openkeyboard-gateway.env"
initialize_repository "$PRIMARY_CHECKOUT"
write_valid_seed "$VALID_SEED"
mkdir -p "$PRIMARY_CHECKOUT/scripts/ios"
cp "$ROOT/scripts/ios/live-test-safety.sh" "$PRIMARY_CHECKOUT/scripts/ios/live-test-safety.sh"
chmod 700 "$PRIMARY_CHECKOUT/scripts/ios/live-test-safety.sh"
git -C "$PRIMARY_CHECKOUT" add scripts/ios/live-test-safety.sh
git -C "$PRIMARY_CHECKOUT" commit -q -m workflow-cleanup-fixture
git -C "$PRIMARY_CHECKOUT" worktree add -q -b linked-worktree-test "$LINKED_WORKTREE"

LOCK_PROBE="$FIXTURE/simulator-lock-probe.sh"
LOCK_OUTPUT="$FIXTURE/simulator-lock-order.log"
LOCK_WAIT_OUTPUT="$FIXTURE/simulator-lock-wait.log"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'source "$1"' \
  'repository_root="$2"' \
  'output_file="$3"' \
  'label="$4"' \
  'hold_seconds="$5"' \
  'openkeyboard_relaunch_with_simulator_lock "$repository_root" "$0" "$@"' \
  'printf "%s-start\n" "$label" >> "$output_file"' \
  'sleep "$hold_seconds"' \
  'printf "%s-end\n" "$label" >> "$output_file"' \
  > "$LOCK_PROBE"
chmod +x "$LOCK_PROBE"

"$LOCK_PROBE" "$ROOT/scripts/ios/live-test-safety.sh" "$PRIMARY_CHECKOUT" "$LOCK_OUTPUT" first 1 &
first_lock_probe=$!
for _ in {1..50}; do
  if [[ -s "$LOCK_OUTPUT" ]]; then
    break
  fi
  sleep 0.02
done
if [[ ! -s "$LOCK_OUTPUT" ]]; then
  echo "The first Simulator lock probe did not start." >&2
  exit 1
fi
"$LOCK_PROBE" "$ROOT/scripts/ios/live-test-safety.sh" "$LINKED_WORKTREE" "$LOCK_OUTPUT" second 0 \
  2> "$LOCK_WAIT_OUTPUT" &
second_lock_probe=$!
wait "$first_lock_probe"
wait "$second_lock_probe"
if [[ "$(<"$LOCK_OUTPUT")" != $'first-start\nfirst-end\nsecond-start\nsecond-end' ]]; then
  echo "Simulator-backed routes from separate worktrees were not serialized by the repository lock." >&2
  exit 1
fi
if ! grep -Fq 'Another OpenKeyboard Simulator route is active; waiting for it to finish.' "$LOCK_WAIT_OUTPUT"; then
  echo "The serialized Simulator route did not report that it was waiting." >&2
  exit 1
fi

CLEANUP_MOCK_BIN="$FIXTURE/owned-cleanup-mock-bin"
mkdir -p "$CLEANUP_MOCK_BIN"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ "$#" -ne 3 || "$1" != "simctl" ]]; then' \
  '  echo "Owned cleanup used an unexpected xcrun command." >&2' \
  '  exit 64' \
  'fi' \
  'action="$2"' \
  'simulator="$3"' \
  'case "$action" in' \
  '  shutdown|delete) ;;' \
  '  *)' \
  '    echo "Owned cleanup used a broad or unexpected simctl action." >&2' \
  '    exit 64' \
  '    ;;' \
  'esac' \
  'if [[ ! "$simulator" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] ||' \
  '    ! grep -Fxq "$simulator" "$OPEN_KEYBOARD_POLICY_TEST_SIMULATOR_STATE"; then' \
  '  echo "Owned cleanup targeted a simulator absent from its bounded fixture." >&2' \
  '  exit 64' \
  'fi' \
  'printf "%s %s %s\n" "$OPEN_KEYBOARD_POLICY_TEST_LABEL" "$action" "$simulator" >> "$OPEN_KEYBOARD_POLICY_TEST_LOG"' \
  'if [[ "$action" == "delete" ]]; then' \
  '  temporary_state="$OPEN_KEYBOARD_POLICY_TEST_SIMULATOR_STATE.$$"' \
  '  grep -Fvx "$simulator" "$OPEN_KEYBOARD_POLICY_TEST_SIMULATOR_STATE" > "$temporary_state" || true' \
  '  mv "$temporary_state" "$OPEN_KEYBOARD_POLICY_TEST_SIMULATOR_STATE"' \
  'fi' \
  > "$CLEANUP_MOCK_BIN/xcrun"
chmod 700 "$CLEANUP_MOCK_BIN/xcrun"

OWNED_CLEANUP_PROBE="$FIXTURE/owned-cleanup-probe.sh"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'source "$1"' \
  'simulator="$2"' \
  'scenario="$3"' \
  'scenario_root="$4"' \
  'label="$5"' \
  'mock_xcrun="$6"' \
  'xcrun() {' \
  '  "$mock_xcrun" "$@"' \
  '}' \
  'SENSITIVE_LIVE_SIMULATOR="$simulator"' \
  'if [[ "$scenario" == "unowned" ]]; then' \
  '  SENSITIVE_LIVE_SIMULATOR_OWNED="false"' \
  'else' \
  '  SENSITIVE_LIVE_SIMULATOR_OWNED="true"' \
  'fi' \
  'cleanup_owned_simulator() {' \
  '  local original_status=$?' \
  '  local cleanup_status=0' \
  '  trap - EXIT HUP INT TERM' \
  '  openkeyboard_delete_sensitive_live_simulator || cleanup_status=$?' \
  '  if [[ "$original_status" -ne 0 ]]; then' \
  '    exit "$original_status"' \
  '  fi' \
  '  exit "$cleanup_status"' \
  '}' \
  'trap cleanup_owned_simulator EXIT' \
  'trap '\''exit 143'\'' TERM' \
  ': > "$scenario_root/$label.ready"' \
  'for _ in {1..500}; do' \
  '  [[ -f "$scenario_root/$label.release" ]] && break' \
  '  sleep 0.01' \
  'done' \
  'if [[ ! -f "$scenario_root/$label.release" ]]; then' \
  '  exit 124' \
  'fi' \
  'case "$scenario" in' \
  '  normal|unowned) exit 0 ;;' \
  '  term) kill -TERM "$$" ;;' \
  '  *) exit 64 ;;' \
  'esac' \
  > "$OWNED_CLEANUP_PROBE"
chmod 700 "$OWNED_CLEANUP_PROBE"

wait_for_cleanup_marker() {
  local marker="$1"
  local description="$2"

  for _ in {1..500}; do
    [[ -f "$marker" ]] && return 0
    sleep 0.01
  done
  echo "Timed out waiting for $description." >&2
  return 1
}

assert_concurrent_worktree_cleanup_isolated() {
  local first_scenario="$1"
  local expected_first_status="$2"
  local scenario_root="$FIXTURE/owned-cleanup-$first_scenario"
  local simulator_state="$scenario_root/simulators"
  local command_log="$scenario_root/commands.log"
  local first_simulator="11111111-1111-1111-1111-111111111111"
  local second_simulator="22222222-2222-2222-2222-222222222222"
  local first_cleanup_pid first_status second_cleanup_pid second_status

  mkdir -p "$scenario_root"
  printf '%s\n' "$first_simulator" "$second_simulator" > "$simulator_state"
  : > "$command_log"

  OPEN_KEYBOARD_POLICY_TEST_LABEL=primary \
    OPEN_KEYBOARD_POLICY_TEST_SIMULATOR_STATE="$simulator_state" \
    OPEN_KEYBOARD_POLICY_TEST_LOG="$command_log" \
    "$OWNED_CLEANUP_PROBE" \
      "$PRIMARY_CHECKOUT/scripts/ios/live-test-safety.sh" \
      "$first_simulator" "$first_scenario" "$scenario_root" primary \
      "$CLEANUP_MOCK_BIN/xcrun" \
    > "$scenario_root/primary-output.log" 2>&1 &
  first_cleanup_pid=$!
  TEST_CHILD_PIDS+=("$first_cleanup_pid")

  OPEN_KEYBOARD_POLICY_TEST_LABEL=linked \
    OPEN_KEYBOARD_POLICY_TEST_SIMULATOR_STATE="$simulator_state" \
    OPEN_KEYBOARD_POLICY_TEST_LOG="$command_log" \
    "$OWNED_CLEANUP_PROBE" \
      "$LINKED_WORKTREE/scripts/ios/live-test-safety.sh" \
      "$second_simulator" normal "$scenario_root" linked \
      "$CLEANUP_MOCK_BIN/xcrun" \
    > "$scenario_root/linked-output.log" 2>&1 &
  second_cleanup_pid=$!
  TEST_CHILD_PIDS+=("$second_cleanup_pid")

  wait_for_cleanup_marker "$scenario_root/primary.ready" "the primary-worktree cleanup harness"
  wait_for_cleanup_marker "$scenario_root/linked.ready" "the linked-worktree cleanup harness"

  : > "$scenario_root/primary.release"
  set +e
  wait "$first_cleanup_pid"
  first_status=$?
  set -e
  forget_test_child_pid "$first_cleanup_pid"
  if [[ "$first_status" -ne "$expected_first_status" ]]; then
    echo "The $first_scenario primary cleanup exited $first_status instead of $expected_first_status." >&2
    exit 1
  fi
  if grep -Fxq "$first_simulator" "$simulator_state" || \
      ! grep -Fxq "$second_simulator" "$simulator_state"; then
    echo "The primary-worktree cleanup did not preserve the linked worktree's simulator." >&2
    exit 1
  fi

  : > "$scenario_root/linked.release"
  set +e
  wait "$second_cleanup_pid"
  second_status=$?
  set -e
  forget_test_child_pid "$second_cleanup_pid"
  if [[ "$second_status" -ne 0 ]]; then
    echo "The linked-worktree cleanup exited $second_status instead of 0." >&2
    exit 1
  fi
  if [[ -s "$simulator_state" ]]; then
    echo "The linked-worktree cleanup did not delete its own simulator." >&2
    exit 1
  fi

  printf '%s\n' \
    "primary shutdown $first_simulator" \
    "primary delete $first_simulator" \
    "linked shutdown $second_simulator" \
    "linked delete $second_simulator" \
    > "$scenario_root/expected-commands.log"
  if ! diff -u "$scenario_root/expected-commands.log" "$command_log"; then
    echo "Concurrent worktree cleanup targeted an unowned simulator or used an unexpected command." >&2
    exit 1
  fi
}

assert_concurrent_worktree_cleanup_isolated normal 0
assert_concurrent_worktree_cleanup_isolated term 143

UNOWNED_SCENARIO_ROOT="$FIXTURE/unowned-cleanup"
UNOWNED_SIMULATOR="33333333-3333-3333-3333-333333333333"
mkdir -p "$UNOWNED_SCENARIO_ROOT"
printf '%s\n' "$UNOWNED_SIMULATOR" > "$UNOWNED_SCENARIO_ROOT/simulators"
: > "$UNOWNED_SCENARIO_ROOT/commands.log"
OPEN_KEYBOARD_POLICY_TEST_LABEL=unowned \
  OPEN_KEYBOARD_POLICY_TEST_SIMULATOR_STATE="$UNOWNED_SCENARIO_ROOT/simulators" \
  OPEN_KEYBOARD_POLICY_TEST_LOG="$UNOWNED_SCENARIO_ROOT/commands.log" \
  "$OWNED_CLEANUP_PROBE" \
    "$PRIMARY_CHECKOUT/scripts/ios/live-test-safety.sh" \
    "$UNOWNED_SIMULATOR" unowned "$UNOWNED_SCENARIO_ROOT" unowned \
    "$CLEANUP_MOCK_BIN/xcrun" \
  > "$UNOWNED_SCENARIO_ROOT/output.log" 2>&1 &
unowned_cleanup_pid=$!
TEST_CHILD_PIDS+=("$unowned_cleanup_pid")
wait_for_cleanup_marker "$UNOWNED_SCENARIO_ROOT/unowned.ready" "the unowned cleanup harness"
: > "$UNOWNED_SCENARIO_ROOT/unowned.release"
set +e
wait "$unowned_cleanup_pid"
unowned_cleanup_status=$?
set -e
forget_test_child_pid "$unowned_cleanup_pid"
if [[ "$unowned_cleanup_status" -ne 1 || \
      ! -s "$UNOWNED_SCENARIO_ROOT/simulators" || \
      -s "$UNOWNED_SCENARIO_ROOT/commands.log" ]]; then
  echo "Cleanup did not refuse an unowned simulator without issuing simctl commands." >&2
  exit 1
fi

resolved_primary="$(openkeyboard_primary_checkout_root "$PRIMARY_CHECKOUT")"
if [[ "$resolved_primary" != "$(realpath "$PRIMARY_CHECKOUT")" ]]; then
  echo "Primary checkout did not resolve to itself." >&2
  exit 1
fi

NORMAL_OUTPUT="$FIXTURE/normal-output.log"
if ! openkeyboard_require_local_seed_file \
  "$PRIMARY_CHECKOUT" \
  '.agent/local-seeds/openkeyboard-gateway.env' > "$NORMAL_OUTPUT" 2>&1; then
  echo "Primary checkout did not accept its canonical local seed." >&2
  exit 1
fi
assert_output_excludes_secret "$NORMAL_OUTPUT" "Normal seed validation"
IFS= read -r resolved_seed < "$NORMAL_OUTPUT"
if [[ "$resolved_seed" != "$(realpath "$VALID_SEED")" ]]; then
  echo "Primary checkout did not resolve its canonical local seed." >&2
  exit 1
fi

resolved_linked_primary="$(openkeyboard_primary_checkout_root "$LINKED_WORKTREE")"
if [[ "$resolved_linked_primary" != "$(realpath "$PRIMARY_CHECKOUT")" ]]; then
  echo "Linked worktree did not resolve the primary checkout through Git metadata." >&2
  exit 1
fi

HOOK_GIT_DIR="$(git -C "$LINKED_WORKTREE" rev-parse --path-format=absolute --git-dir)"
resolved_hook_primary="$(
  GIT_DIR="$HOOK_GIT_DIR" \
    openkeyboard_primary_checkout_root "$LINKED_WORKTREE"
)"
if [[ "$resolved_hook_primary" != "$(realpath "$PRIMARY_CHECKOUT")" ]]; then
  echo "Linked worktree did not resolve the primary checkout from a Git hook environment." >&2
  exit 1
fi

resolved_linked_seed="$(
  openkeyboard_require_local_seed_file \
    "$LINKED_WORKTREE" \
    '.agent/local-seeds/openkeyboard-gateway.env'
)"
if [[ "$resolved_linked_seed" != "$(realpath "$VALID_SEED")" ]]; then
  echo "Linked worktree did not reuse the primary checkout seed." >&2
  exit 1
fi

resolved_hook_seed="$(
  GIT_DIR="$HOOK_GIT_DIR" \
    openkeyboard_require_local_seed_file \
      "$LINKED_WORKTREE" \
      '.agent/local-seeds/openkeyboard-gateway.env'
)"
if [[ "$resolved_hook_seed" != "$(realpath "$VALID_SEED")" ]]; then
  echo "Git hook execution did not reuse the primary checkout seed." >&2
  exit 1
fi

ALTERNATE_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/alternate.env"
write_valid_seed "$ALTERNATE_SEED"
OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE="$ALTERNATE_SEED"
resolved_alternate_seed="$(
  openkeyboard_require_local_seed_file \
    "$LINKED_WORKTREE" \
    "$OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE"
)"
unset OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE
if [[ "$resolved_alternate_seed" != "$(realpath "$ALTERNATE_SEED")" ]]; then
  echo "The alternate primary-checkout seed override did not resolve." >&2
  exit 1
fi

LOAD_OUTPUT="$FIXTURE/load-output.log"
if ! openkeyboard_load_simulator_gateway_seed "$VALID_SEED" > "$LOAD_OUTPUT" 2>&1; then
  echo "The valid simulator seed could not be loaded." >&2
  exit 1
fi
assert_output_excludes_secret "$LOAD_OUTPUT" "Normal seed loading"
if [[ -z "${OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL:-}" || \
      -z "${OPEN_KEYBOARD_SIMULATOR_API_KEY:-}" || \
      -z "${OPEN_KEYBOARD_SIMULATOR_MODEL:-}" ]]; then
  echo "The documented simulator seed keys were not loaded." >&2
  exit 1
fi
openkeyboard_unset_simulator_gateway_profiles

DUAL_PROFILE_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/dual-profile.env"
write_dual_profile_seed "$DUAL_PROFILE_SEED"
DUAL_PROFILE_OUTPUT="$FIXTURE/dual-profile-output.log"
if ! openkeyboard_load_simulator_gateway_seed "$DUAL_PROFILE_SEED" > "$DUAL_PROFILE_OUTPUT" 2>&1; then
  echo "The complete two-profile simulator seed could not be loaded." >&2
  exit 1
fi
assert_output_excludes_secret "$DUAL_PROFILE_OUTPUT" "Two-profile seed loading"
openkeyboard_require_two_profile_gateway_seed

openkeyboard_select_simulator_gateway_profile low
if [[ "$OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE" != "low" || \
      "$OPEN_KEYBOARD_SIMULATOR_MODEL" != "low-model:2b" || \
      "$OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL" != "https://low-gateway.example.invalid" ]]; then
  echo "The low simulator gateway profile was not selected exactly." >&2
  exit 1
fi
if bash -c '[[ -n "${OPEN_KEYBOARD_SIMULATOR_API_KEY+x}" || -n "${OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY+x}" || -n "${OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY+x}" ]]'; then
  echo "A selected simulator API key leaked into an unrelated child environment." >&2
  exit 1
fi

openkeyboard_select_simulator_gateway_profile high
if [[ "$OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE" != "high" || \
      "$OPEN_KEYBOARD_SIMULATOR_MODEL" != "high-model:120b" || \
      "$OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL" != "https://high-gateway.example.invalid" ]]; then
  echo "The high simulator gateway profile was not selected exactly." >&2
  exit 1
fi
if bash -c '[[ -n "${OPEN_KEYBOARD_SIMULATOR_API_KEY+x}" || -n "${OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY+x}" || -n "${OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY+x}" ]]'; then
  echo "A reselected simulator API key leaked into an unrelated child environment." >&2
  exit 1
fi

SIGNAL_EVIDENCE_FILE="$FIXTURE/signal-evidence"
SIGNAL_READY_FILE="$FIXTURE/signal-ready"
printf 'sensitive evidence\n' > "$SIGNAL_EVIDENCE_FILE"
bash -c '
  source "$1"
  evidence_file="$2"
  ready_file="$3"
  trap '\''openkeyboard_exit_after_live_evidence_signal 143 "$evidence_file"'\'' TERM
  : > "$ready_file"
  while :; do sleep 1; done
' _ "$ROOT/scripts/ios/live-test-safety.sh" "$SIGNAL_EVIDENCE_FILE" "$SIGNAL_READY_FILE" &
signal_test_pid=$!
for _ in {1..100}; do
  [[ -f "$SIGNAL_READY_FILE" ]] && break
  sleep 0.01
done
if [[ ! -f "$SIGNAL_READY_FILE" ]]; then
  kill -TERM "$signal_test_pid" >/dev/null 2>&1 || true
  wait "$signal_test_pid" >/dev/null 2>&1 || true
  echo "Signal-cleanup regression process did not become ready." >&2
  exit 1
fi
kill -TERM "$signal_test_pid"
set +e
wait "$signal_test_pid"
signal_status=$?
set -e
if [[ "$signal_status" -ne 143 || -e "$SIGNAL_EVIDENCE_FILE" ]]; then
  echo "Live-evidence signal cleanup did not remove evidence and exit with signal status." >&2
  exit 1
fi

openkeyboard_load_simulator_gateway_seed "$DUAL_PROFILE_SEED"
openkeyboard_select_reference_simulator_gateway_profile
if [[ "$OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE" != "high" || \
      "$OPEN_KEYBOARD_SIMULATOR_MODEL" != "high-model:120b" ]]; then
  echo "Reference live verification did not select the configured high profile." >&2
  exit 1
fi

openkeyboard_load_simulator_gateway_seed "$VALID_SEED"
openkeyboard_select_reference_simulator_gateway_profile
if [[ "$OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE" != "legacy" || \
      "$OPEN_KEYBOARD_SIMULATOR_MODEL" != "test-model" ]]; then
  echo "The legacy single-profile fallback was not preserved." >&2
  exit 1
fi

COMBINED_PROFILE_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/combined-profile.env"
{
  printf '%s\n' \
    'OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL=https://legacy-gateway.example.invalid' \
    "OPEN_KEYBOARD_SIMULATOR_API_KEY=$SECRET_SENTINEL-legacy" \
    'OPEN_KEYBOARD_SIMULATOR_MODEL=legacy-test-model'
  printf '%s\n' \
    'OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL=https://low-gateway.example.invalid' \
    "OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY=$SECRET_SENTINEL-low" \
    'OPEN_KEYBOARD_SIMULATOR_LOW_MODEL=low-model:2b' \
    'OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL=https://high-gateway.example.invalid' \
    "OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY=$SECRET_SENTINEL-high" \
    'OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL=high-model:120b'
} > "$COMBINED_PROFILE_SEED"
chmod 600 "$COMBINED_PROFILE_SEED"
openkeyboard_load_simulator_gateway_seed "$COMBINED_PROFILE_SEED"
openkeyboard_select_simulator_gateway_profile low
openkeyboard_select_simulator_gateway_profile legacy
if [[ "$OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE" != "legacy" || \
      "$OPEN_KEYBOARD_SIMULATOR_MODEL" != "legacy-test-model" || \
      "$OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL" != "https://legacy-gateway.example.invalid" ]]; then
  echo "Legacy selection was contaminated by a previously selected differential profile." >&2
  exit 1
fi

PARTIAL_PROFILE_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/partial-profile.env"
printf '%s\n' \
  'OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL=https://low-gateway.example.invalid' \
  "OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY=$SECRET_SENTINEL-low" \
  > "$PARTIAL_PROFILE_SEED"
chmod 600 "$PARTIAL_PROFILE_SEED"
PARTIAL_PROFILE_OUTPUT="$FIXTURE/partial-profile-output.log"
if openkeyboard_load_simulator_gateway_seed "$PARTIAL_PROFILE_SEED" > "$PARTIAL_PROFILE_OUTPUT" 2>&1; then
  echo "A partial simulator gateway profile was accepted." >&2
  exit 1
fi
assert_output_excludes_secret "$PARTIAL_PROFILE_OUTPUT" "Partial-profile rejection"
assert_simulator_profiles_unset

DUPLICATE_PROFILE_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/duplicate-profile.env"
write_valid_seed "$DUPLICATE_PROFILE_SEED"
printf 'OPEN_KEYBOARD_SIMULATOR_MODEL=second-model\n' >> "$DUPLICATE_PROFILE_SEED"
DUPLICATE_PROFILE_OUTPUT="$FIXTURE/duplicate-profile-output.log"
if openkeyboard_load_simulator_gateway_seed "$DUPLICATE_PROFILE_SEED" > "$DUPLICATE_PROFILE_OUTPUT" 2>&1; then
  echo "A duplicate simulator gateway variable was accepted." >&2
  exit 1
fi
assert_output_excludes_secret "$DUPLICATE_PROFILE_OUTPUT" "Duplicate-variable rejection"
assert_simulator_profiles_unset

UNSAFE_MODEL_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/unsafe-model.env"
printf '%s\n' \
  'OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL=https://gateway.example.invalid' \
  "OPEN_KEYBOARD_SIMULATOR_API_KEY=$SECRET_SENTINEL" \
  'OPEN_KEYBOARD_SIMULATOR_MODEL=unsafe model;echo-no' \
  > "$UNSAFE_MODEL_SEED"
chmod 600 "$UNSAFE_MODEL_SEED"
UNSAFE_MODEL_OUTPUT="$FIXTURE/unsafe-model-output.log"
if openkeyboard_load_simulator_gateway_seed "$UNSAFE_MODEL_SEED" > "$UNSAFE_MODEL_OUTPUT" 2>&1; then
  echo "An unsafe simulator gateway model ID was accepted." >&2
  exit 1
fi
assert_output_excludes_secret "$UNSAFE_MODEL_OUTPUT" "Unsafe-model rejection"
openkeyboard_unset_simulator_gateway_profiles
assert_simulator_profiles_unset

openkeyboard_require_exact_live_model 'low-test-model:2b' 'low-test-model:2b'
openkeyboard_require_exact_live_model 'high-test-model:120b-cloud' 'model-agnostic'
if openkeyboard_require_exact_live_model 'high-test-model:120b-cloud' 'low-test-model:2b' >/dev/null 2>&1; then
  echo "A different live model was accepted as exact Gemma proof." >&2
  exit 1
fi
if openkeyboard_require_exact_live_model 'low-test-model:2b unsafe' 'low-test-model:2b unsafe' >/dev/null 2>&1; then
  echo "An unsafe live model identifier was accepted." >&2
  exit 1
fi
if openkeyboard_require_exact_live_model 'low-test-model:2b' '' >/dev/null 2>&1; then
  echo "An empty required live model was accepted." >&2
  exit 1
fi
long_model_id="$(printf 'm%.0s' {1..256})"
if openkeyboard_require_exact_live_model "$long_model_id" "$long_model_id" >/dev/null 2>&1; then
  echo "An overlong live model ID was accepted." >&2
  exit 1
fi

UNSUPPORTED_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/unsupported.env"
write_valid_seed "$UNSUPPORTED_SEED"
printf 'OPEN_KEYBOARD_SIMULATOR_UNDOCUMENTED=test-only-value\n' >> "$UNSUPPORTED_SEED"
UNSUPPORTED_OUTPUT="$FIXTURE/unsupported-output.log"
if openkeyboard_load_simulator_gateway_seed "$UNSUPPORTED_SEED" > "$UNSUPPORTED_OUTPUT" 2>&1; then
  echo "An undocumented simulator seed key was accepted." >&2
  exit 1
fi
assert_output_excludes_secret "$UNSUPPORTED_OUTPUT" "Failing seed loading"
unset \
  OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL \
  OPEN_KEYBOARD_SIMULATOR_API_KEY \
  OPEN_KEYBOARD_SIMULATOR_MODEL

PERMISSIVE_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/permissive.env"
write_valid_seed "$PERMISSIVE_SEED"
chmod 644 "$PERMISSIVE_SEED"
PERMISSIVE_OUTPUT="$FIXTURE/permissive-output.log"
if openkeyboard_require_local_seed_file \
  "$PRIMARY_CHECKOUT" \
  '.agent/local-seeds/permissive.env' > "$PERMISSIVE_OUTPUT" 2>&1; then
  echo "A seed file readable by group or other users was accepted." >&2
  exit 1
fi
assert_output_excludes_secret "$PERMISSIVE_OUTPUT" "Permission rejection"

ACL_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/acl.env"
write_valid_seed "$ACL_SEED"
ACL_OUTPUT="$FIXTURE/acl-output.log"
if chmod +a "everyone allow read" "$ACL_SEED" 2>/dev/null; then
  if openkeyboard_require_local_seed_file \
    "$PRIMARY_CHECKOUT" \
    '.agent/local-seeds/acl.env' > "$ACL_OUTPUT" 2>&1; then
    echo "A seed file with an extended read ACL was accepted." >&2
    exit 1
  fi
  assert_output_excludes_secret "$ACL_OUTPUT" "ACL rejection"
elif command -v setfacl >/dev/null 2>&1 && setfacl -m u:nobody:r "$ACL_SEED" 2>/dev/null; then
  if openkeyboard_require_local_seed_file \
    "$PRIMARY_CHECKOUT" \
    '.agent/local-seeds/acl.env' > "$ACL_OUTPUT" 2>&1; then
    echo "A seed file with an extended read ACL was accepted." >&2
    exit 1
  fi
  assert_output_excludes_secret "$ACL_OUTPUT" "ACL rejection"
fi

chmod 777 "$PRIMARY_CHECKOUT/.agent/local-seeds"
DIRECTORY_PERMISSION_OUTPUT="$FIXTURE/directory-permission-output.log"
if openkeyboard_require_local_seed_file \
  "$PRIMARY_CHECKOUT" \
  '.agent/local-seeds/openkeyboard-gateway.env' > "$DIRECTORY_PERMISSION_OUTPUT" 2>&1; then
  echo "A seed inside a world-writable canonical directory was accepted." >&2
  exit 1
fi
assert_output_excludes_secret "$DIRECTORY_PERMISSION_OUTPUT" "Directory permission rejection"
chmod 700 "$PRIMARY_CHECKOUT/.agent/local-seeds"

CURRENT_UID="$(id -u)"
stat() {
  if [[ ( "$1" == "-f" || "$1" == "-c" ) && "$2" == "%u" ]]; then
    printf '%s\n' "$((CURRENT_UID + 1))"
    return 0
  fi
  command stat "$@"
}
DIRECTORY_OWNER_OUTPUT="$FIXTURE/directory-owner-output.log"
if openkeyboard_require_local_seed_file \
  "$PRIMARY_CHECKOUT" \
  '.agent/local-seeds/openkeyboard-gateway.env' > "$DIRECTORY_OWNER_OUTPUT" 2>&1; then
  echo "A seed in a canonical directory owned by another user was accepted." >&2
  exit 1
fi
unset -f stat
assert_output_excludes_secret "$DIRECTORY_OWNER_OUTPUT" "Directory owner rejection"

OUTSIDE_SEED="$PRIMARY_CHECKOUT/outside.env"
write_valid_seed "$OUTSIDE_SEED"
if openkeyboard_require_local_seed_file \
  "$LINKED_WORKTREE" \
  '.agent/local-seeds/../../outside.env' >/dev/null 2>&1; then
  echo "Traversal outside the primary checkout's local-seeds directory was accepted." >&2
  exit 1
fi
mkdir -p "$PRIMARY_CHECKOUT/.agent/local-seeds/subdirectory"
chmod 700 "$PRIMARY_CHECKOUT/.agent/local-seeds/subdirectory"
if openkeyboard_require_local_seed_file \
  "$LINKED_WORKTREE" \
  '.agent/local-seeds/subdirectory/../openkeyboard-gateway.env' >/dev/null 2>&1; then
  echo "Traversal within the primary checkout's local-seeds directory was accepted." >&2
  exit 1
fi
if openkeyboard_require_local_seed_file \
  "$LINKED_WORKTREE" \
  "$OUTSIDE_SEED" >/dev/null 2>&1; then
  echo "An external seed path was accepted." >&2
  exit 1
fi

ln -s "$OUTSIDE_SEED" "$PRIMARY_CHECKOUT/.agent/local-seeds/linked.env"
if openkeyboard_require_local_seed_file \
  "$LINKED_WORKTREE" \
  '.agent/local-seeds/linked.env' >/dev/null 2>&1; then
  echo "A seed symlink escaping the primary local-seeds directory was accepted." >&2
  exit 1
fi

mkdir "$PRIMARY_CHECKOUT/.agent/local-seeds/directory.env"
if openkeyboard_require_local_seed_file \
  "$PRIMARY_CHECKOUT" \
  '.agent/local-seeds/directory.env' >/dev/null 2>&1; then
  echo "A non-regular seed path was accepted." >&2
  exit 1
fi

SYMLINK_FIXTURE="$FIXTURE/symlink root/repository"
EXTERNAL_SEED_ROOT="$FIXTURE/symlink root/external seeds"
mkdir -p "$SYMLINK_FIXTURE/.agent" "$EXTERNAL_SEED_ROOT"
git -C "$SYMLINK_FIXTURE" init -q
git -C "$SYMLINK_FIXTURE" config user.name "OpenKeyboard Policy Test"
git -C "$SYMLINK_FIXTURE" config user.email "policy-test@example.invalid"
printf 'base\n' > "$SYMLINK_FIXTURE/README.md"
git -C "$SYMLINK_FIXTURE" add README.md
git -C "$SYMLINK_FIXTURE" commit -q -m base
ln -s "$EXTERNAL_SEED_ROOT" "$SYMLINK_FIXTURE/.agent/local-seeds"
write_valid_seed "$EXTERNAL_SEED_ROOT/openkeyboard-gateway.env"
if openkeyboard_require_local_seed_file \
  "$SYMLINK_FIXTURE" \
  '.agent/local-seeds/openkeyboard-gateway.env' >/dev/null 2>&1; then
  echo "A local-seeds directory escaping the primary checkout was accepted." >&2
  exit 1
fi

TRACKED_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/tracked.env"
write_valid_seed "$TRACKED_SEED"
git -C "$PRIMARY_CHECKOUT" add -f .agent/local-seeds/tracked.env
git -C "$PRIMARY_CHECKOUT" commit -q -m tracked-seed
if openkeyboard_require_local_seed_file \
  "$PRIMARY_CHECKOUT" \
  '.agent/local-seeds/tracked.env' >/dev/null 2>&1; then
  echo "A tracked seed file was accepted." >&2
  exit 1
fi

LINKED_TRACKED_SEED="$LINKED_WORKTREE/.agent/local-seeds/openkeyboard-gateway.env"
mkdir -p "$(dirname "$LINKED_TRACKED_SEED")"
write_valid_seed "$LINKED_TRACKED_SEED"
git -C "$LINKED_WORKTREE" add -f .agent/local-seeds/openkeyboard-gateway.env
git -C "$LINKED_WORKTREE" commit -q -m linked-tracked-seed
LINKED_TRACKED_OUTPUT="$FIXTURE/linked-tracked-output.log"
if openkeyboard_require_local_seed_file \
  "$LINKED_WORKTREE" \
  '.agent/local-seeds/openkeyboard-gateway.env' > "$LINKED_TRACKED_OUTPUT" 2>&1; then
  echo "A seed tracked by the executing linked worktree was accepted." >&2
  exit 1
fi
assert_output_excludes_secret "$LINKED_TRACKED_OUTPUT" "Linked-worktree tracked-file rejection"

SECOND_PRIMARY="$FIXTURE/different machine location/OpenKeyboard checkout"
initialize_repository "$SECOND_PRIMARY"
EXPECTED_MISSING_SEED="$(realpath "$SECOND_PRIMARY")/.agent/local-seeds/openkeyboard-gateway.env"
if missing_output="$(
  openkeyboard_require_local_seed_file \
    "$SECOND_PRIMARY" \
    '.agent/local-seeds/openkeyboard-gateway.env' 2>&1
)"; then
  echo "A missing seed file was accepted." >&2
  exit 1
fi
if [[ "$missing_output" != *"$EXPECTED_MISSING_SEED"* ]]; then
  echo "Missing-seed diagnostics did not report the dynamically resolved expected path." >&2
  exit 1
fi
if [[ "$missing_output" == *"$SECRET_SENTINEL"* ]]; then
  echo "Missing-seed diagnostics emitted a secret value." >&2
  exit 1
fi

SECOND_SEED="$SECOND_PRIMARY/.agent/local-seeds/openkeyboard-gateway.env"
write_valid_seed "$SECOND_SEED"
resolved_second_seed="$(
  openkeyboard_require_local_seed_file \
    "$SECOND_PRIMARY" \
    '.agent/local-seeds/openkeyboard-gateway.env'
)"
if [[ "$resolved_second_seed" != "$(realpath "$SECOND_SEED")" ]]; then
  echo "A different machine-specific checkout location did not resolve its own seed." >&2
  exit 1
fi

git -C "$PRIMARY_CHECKOUT" worktree remove "$LINKED_WORKTREE"
if [[ ! -f "$VALID_SEED" ]]; then
  echo "Removing a linked worktree removed the primary checkout seed." >&2
  exit 1
fi
resolved_after_removal="$(
  openkeyboard_require_local_seed_file \
    "$PRIMARY_CHECKOUT" \
    '.agent/local-seeds/openkeyboard-gateway.env'
)"
if [[ "$resolved_after_removal" != "$(realpath "$VALID_SEED")" ]]; then
  echo "The primary seed was not reusable after removing a linked worktree." >&2
  exit 1
fi

valid_summary='{"result":"Passed","totalTestCount":1,"passedTests":1,"failedTests":0,"skippedTests":0,"expectedFailures":0}'
printf '%s' "$valid_summary" | openkeyboard_assert_single_passing_test_summary
printf '%s' "$valid_summary" | openkeyboard_assert_passing_test_summary_count 1
if [[ "$(printf '%s' "$valid_summary" | openkeyboard_classify_low_differential_test_summary)" != "expected-model-capability" ]]; then
  echo "A passing low-profile boundary test was not classified as the expected capability failure." >&2
  exit 1
fi

diagnostic_summary='{"result":"Skipped","totalTestCount":1,"passedTests":0,"failedTests":0,"skippedTests":1,"expectedFailures":0}'
if [[ "$(printf '%s' "$diagnostic_summary" | openkeyboard_classify_low_differential_test_summary)" != "diagnostic-boundary-not-established" ]]; then
  echo "A low-profile success diagnostic skip was not classified truthfully." >&2
  exit 1
fi
if printf '%s' '{"result":"Failed","totalTestCount":1,"passedTests":0,"failedTests":1,"skippedTests":0,"expectedFailures":0}' |
    openkeyboard_classify_low_differential_test_summary >/dev/null 2>&1; then
  echo "A failing low-profile test was accepted as differential evidence." >&2
  exit 1
fi

verified_completion="$(
  openkeyboard_finish_live_differential_run \
    verification \
    passed passed expected-model-capability passed passed passed verified
)"
if [[ "$verified_completion" != "LIVE_VERIFIED: targeted two-profile live-model differential verification passed." ]]; then
  echo "Verified differential completion used an unexpected status or message." >&2
  exit 1
fi

if strict_unverified_completion="$(
    openkeyboard_finish_live_differential_run \
      verification \
      passed unverified expected-model-capability unverified passed unverified verified 2>&1
  )"; then
  echo "Strict differential verification accepted unverified required outcomes." >&2
  exit 1
fi
if [[ "$strict_unverified_completion" != *"LIVE_UNVERIFIED:"* ]] ||
    [[ "$strict_unverified_completion" != *"verification failed"* ]]; then
  echo "Strict unverified differential output was not labeled truthfully." >&2
  exit 1
fi

diagnostic_unverified_completion="$(
  openkeyboard_finish_live_differential_run \
    diagnostic \
    passed unverified diagnostic-boundary-not-established unverified passed unverified verified
)"
if [[ "$diagnostic_unverified_completion" != "LIVE_UNVERIFIED: targeted two-profile diagnostic run complete; this is not verification." ]]; then
  echo "Diagnostic unverified completion used an unexpected status or message." >&2
  exit 1
fi
if [[ "$diagnostic_unverified_completion" == *"✓"* ]] ||
    [[ "$diagnostic_unverified_completion" == *"verification complete"* ]] ||
    [[ "$diagnostic_unverified_completion" == *"verification passed"* ]]; then
  echo "Diagnostic unverified completion printed a success-style verification claim." >&2
  exit 1
fi

diagnostic_verified_completion="$(
  openkeyboard_finish_live_differential_run \
    diagnostic \
    passed passed expected-model-capability passed passed passed verified
)"
if [[ "$diagnostic_verified_completion" != "LIVE_VERIFIED: targeted two-profile diagnostic run complete; required outcomes were verified." ]]; then
  echo "Diagnostic verified completion used an unexpected status or message." >&2
  exit 1
fi

assert_summary_rejected() {
  local summary="$1"

  if printf '%s' "$summary" | openkeyboard_assert_single_passing_test_summary >/dev/null 2>&1; then
    echo "Invalid live test summary was accepted: $summary" >&2
    exit 1
  fi
}

assert_summary_rejected '{"result":"Passed","totalTestCount":0,"passedTests":0,"failedTests":0,"skippedTests":0,"expectedFailures":0}'
assert_summary_rejected '{"result":"Skipped","totalTestCount":1,"passedTests":0,"failedTests":0,"skippedTests":1,"expectedFailures":0}'
assert_summary_rejected '{"result":"Failed","totalTestCount":1,"passedTests":0,"failedTests":1,"skippedTests":0,"expectedFailures":0}'
assert_summary_rejected '{"result":"Passed","totalTestCount":2,"passedTests":2,"failedTests":0,"skippedTests":0,"expectedFailures":0}'
if printf '%s' "$valid_summary" | openkeyboard_assert_passing_test_summary_count 2 >/dev/null 2>&1; then
  echo "A live test summary with the wrong exact count was accepted." >&2
  exit 1
fi

echo "Live test safety regression tests passed."
