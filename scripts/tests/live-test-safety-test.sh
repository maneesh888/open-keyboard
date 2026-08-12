#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/ios/live-test-safety.sh"

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/openkeyboard-live-safety.XXXXXX")"
trap 'rm -rf -- "$FIXTURE"' EXIT

# Git exports repository-local variables to hooks. Clear them before operating on fixture repos.
while IFS= read -r git_environment_name; do
  unset "$git_environment_name"
done < <(git -C "$ROOT" rev-parse --local-env-vars)

xcrun() {
  if [[ "${1:-}" == "simctl" && "${2:-}" == "bootstatus" ]]; then
    return 1
  fi
  return 0
}

if openkeyboard_restore_booted_simulator fixture-simulator; then
  echo "Simulator restoration accepted a failed bootstatus check." >&2
  exit 1
fi
unset -f xcrun

initialize_repository() {
  local repository="$1"

  mkdir -p "$repository/.agent/local-seeds"
  git -C "$repository" init -q
  git -C "$repository" config user.name "OpenKeyboard Policy Test"
  git -C "$repository" config user.email "policy-test@example.invalid"
  printf '.agent/local-seeds/\n' > "$repository/.gitignore"
  printf 'base\n' > "$repository/README.md"
  git -C "$repository" add .gitignore README.md
  git -C "$repository" commit -q -m base
}

write_valid_seed() {
  local seed_file="$1"

  printf '%s\n' \
    'OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL=https://gateway.example.invalid' \
    'OPEN_KEYBOARD_SIMULATOR_API_KEY=test-only-value' \
    'OPEN_KEYBOARD_SIMULATOR_MODEL=test-model' \
    > "$seed_file"
}

PRIMARY_CHECKOUT="$FIXTURE/machine one/Open Keyboard"
LINKED_WORKTREE="$FIXTURE/temporary linked worktree"
VALID_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/openkeyboard-gateway.env"
initialize_repository "$PRIMARY_CHECKOUT"
write_valid_seed "$VALID_SEED"

resolved_primary="$(openkeyboard_primary_checkout_root "$PRIMARY_CHECKOUT")"
if [[ "$resolved_primary" != "$(realpath "$PRIMARY_CHECKOUT")" ]]; then
  echo "Primary checkout did not resolve to itself." >&2
  exit 1
fi

resolved_seed="$(
  openkeyboard_require_local_seed_file \
    "$PRIMARY_CHECKOUT" \
    '.agent/local-seeds/openkeyboard-gateway.env'
)"
if [[ "$resolved_seed" != "$(realpath "$VALID_SEED")" ]]; then
  echo "Primary checkout did not resolve its canonical local seed." >&2
  exit 1
fi

git -C "$PRIMARY_CHECKOUT" worktree add -q -b linked-worktree-test "$LINKED_WORKTREE"
resolved_linked_primary="$(openkeyboard_primary_checkout_root "$LINKED_WORKTREE")"
if [[ "$resolved_linked_primary" != "$(realpath "$PRIMARY_CHECKOUT")" ]]; then
  echo "Linked worktree did not resolve the primary checkout through Git metadata." >&2
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

openkeyboard_load_simulator_gateway_seed "$VALID_SEED"
if [[ -z "${OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL:-}" || \
      -z "${OPEN_KEYBOARD_SIMULATOR_API_KEY:-}" || \
      -z "${OPEN_KEYBOARD_SIMULATOR_MODEL:-}" ]]; then
  echo "The documented simulator seed keys were not loaded." >&2
  exit 1
fi
unset \
  OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL \
  OPEN_KEYBOARD_SIMULATOR_API_KEY \
  OPEN_KEYBOARD_SIMULATOR_MODEL

UNSUPPORTED_SEED="$PRIMARY_CHECKOUT/.agent/local-seeds/unsupported.env"
printf 'OPEN_KEYBOARD_SIMULATOR_UNDOCUMENTED=test-only-value\n' > "$UNSUPPORTED_SEED"
if openkeyboard_load_simulator_gateway_seed "$UNSUPPORTED_SEED" >/dev/null 2>&1; then
  echo "An undocumented simulator seed key was accepted." >&2
  exit 1
fi

OUTSIDE_SEED="$PRIMARY_CHECKOUT/outside.env"
write_valid_seed "$OUTSIDE_SEED"
if openkeyboard_require_local_seed_file \
  "$LINKED_WORKTREE" \
  '.agent/local-seeds/../../outside.env' >/dev/null 2>&1; then
  echo "Traversal outside the primary checkout's local-seeds directory was accepted." >&2
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

echo "Live test safety regression tests passed."
