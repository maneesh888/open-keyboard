#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/ios/live-test-safety.sh"

FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

# Git exports repository-local variables to hooks. Clear them before operating on a fixture repo.
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

git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.name "OpenKeyboard Policy Test"
git -C "$FIXTURE" config user.email "policy-test@example.invalid"
mkdir -p "$FIXTURE/.agent/local-seeds"
printf '.agent/local-seeds/\n' > "$FIXTURE/.gitignore"
printf 'base\n' > "$FIXTURE/README.md"
git -C "$FIXTURE" add .gitignore README.md
git -C "$FIXTURE" commit -q -m base

valid_seed="$FIXTURE/.agent/local-seeds/gateway.env"
printf 'OPEN_KEYBOARD_SIMULATOR_API_KEY=test-only-value\n' > "$valid_seed"
resolved_seed="$(openkeyboard_require_local_seed_file "$FIXTURE" "$valid_seed")"
if [[ "$resolved_seed" != "$(realpath "$valid_seed")" ]]; then
  echo "Valid local seed did not resolve to its canonical path." >&2
  exit 1
fi

outside_seed="$FIXTURE/outside.env"
printf 'outside\n' > "$outside_seed"
if openkeyboard_require_local_seed_file \
  "$FIXTURE" \
  '.agent/local-seeds/../../outside.env' >/dev/null 2>&1; then
  echo "Traversal outside .agent/local-seeds was accepted." >&2
  exit 1
fi

ln -s "$outside_seed" "$FIXTURE/.agent/local-seeds/linked.env"
if openkeyboard_require_local_seed_file \
  "$FIXTURE" \
  '.agent/local-seeds/linked.env' >/dev/null 2>&1; then
  echo "A seed symlink resolving outside .agent/local-seeds was accepted." >&2
  exit 1
fi

symlink_fixture="$(mktemp -d)"
mkdir -p "$symlink_fixture/repository/.agent" "$symlink_fixture/external-seeds"
git -C "$symlink_fixture/repository" init -q
ln -s "$symlink_fixture/external-seeds" "$symlink_fixture/repository/.agent/local-seeds"
printf 'outside\n' > "$symlink_fixture/external-seeds/gateway.env"
if openkeyboard_require_local_seed_file \
  "$symlink_fixture/repository" \
  '.agent/local-seeds/gateway.env' >/dev/null 2>&1; then
  echo "A local-seeds directory resolving outside the repository was accepted." >&2
  exit 1
fi
rm -rf -- "$symlink_fixture"

tracked_seed="$FIXTURE/.agent/local-seeds/tracked.env"
printf 'tracked\n' > "$tracked_seed"
git -C "$FIXTURE" add -f .agent/local-seeds/tracked.env
git -C "$FIXTURE" commit -q -m tracked-seed
if openkeyboard_require_local_seed_file \
  "$FIXTURE" \
  '.agent/local-seeds/tracked.env' >/dev/null 2>&1; then
  echo "A tracked seed file was accepted." >&2
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
