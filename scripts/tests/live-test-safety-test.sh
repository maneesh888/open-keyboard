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

assert_output_excludes_secret() {
  local output_file="$1"
  local context="$2"

  if grep -Fq -- "$SECRET_SENTINEL" "$output_file"; then
    echo "$context emitted a secret value." >&2
    exit 1
  fi
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

git -C "$PRIMARY_CHECKOUT" worktree add -q -b linked-worktree-test "$LINKED_WORKTREE"
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
unset \
  OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL \
  OPEN_KEYBOARD_SIMULATOR_API_KEY \
  OPEN_KEYBOARD_SIMULATOR_MODEL

openkeyboard_require_exact_live_model 'gemma2:2b' 'gemma2:2b'
openkeyboard_require_exact_live_model 'gpt-oss:120b-cloud' 'model-agnostic'
if openkeyboard_require_exact_live_model 'gpt-oss:120b-cloud' 'gemma2:2b' >/dev/null 2>&1; then
  echo "A different live model was accepted as exact Gemma proof." >&2
  exit 1
fi
if openkeyboard_require_exact_live_model 'gemma2:2b unsafe' 'gemma2:2b unsafe' >/dev/null 2>&1; then
  echo "An unsafe live model identifier was accepted." >&2
  exit 1
fi
if openkeyboard_require_exact_live_model 'gemma2:2b' '' >/dev/null 2>&1; then
  echo "An empty required live model was accepted." >&2
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
