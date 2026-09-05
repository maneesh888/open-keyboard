#!/usr/bin/env bash
set -euo pipefail

# Git exports repository-local variables to hooks. Clear them before creating fixture repositories
# so `git -C <fixture>` cannot mutate or inspect the calling repository.
while IFS= read -r git_local_variable; do
  unset "$git_local_variable"
done < <(git rev-parse --local-env-vars)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFIER="$ROOT/scripts/verify-runtime-proof-carry-forward.sh"
FIXTURE_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf -- "$FIXTURE_ROOT"
}
trap cleanup EXIT

initialize_fixture() {
  local repository="$1"

  mkdir -p "$repository/OpenKeyboard" "$repository/OpenKeyboardUITests"
  git -C "$repository" init -q
  git -C "$repository" config user.name "Workflow Test"
  git -C "$repository" config user.email "workflow-test@example.invalid"
  printf '%s\n' 'runtime-v1' > "$repository/OpenKeyboard/runtime.swift"
  printf '%s\n' 'test-v1' > "$repository/OpenKeyboardUITests/layout.swift"
  git -C "$repository" add .
  git -C "$repository" commit -qm 'Initial fixture'
}

TEST_ONLY_REPOSITORY="$FIXTURE_ROOT/test-only"
initialize_fixture "$TEST_ONLY_REPOSITORY"
CAPTURE_SHA="$(git -C "$TEST_ONLY_REPOSITORY" rev-parse HEAD)"
printf '%s\n' 'test-v2' > "$TEST_ONLY_REPOSITORY/OpenKeyboardUITests/layout.swift"
git -C "$TEST_ONLY_REPOSITORY" add OpenKeyboardUITests/layout.swift
git -C "$TEST_ONLY_REPOSITORY" commit -qm 'Update test only'
CURRENT_SHA="$(git -C "$TEST_ONLY_REPOSITORY" rev-parse HEAD)"

SUCCESS_OUTPUT="$(
  OPEN_KEYBOARD_RUNTIME_PROOF_REPOSITORY="$TEST_ONLY_REPOSITORY" \
    "$VERIFIER" "$CAPTURE_SHA" "$CURRENT_SHA"
)"
rg --fixed-strings --quiet 'Runtime proof carry-forward verified.' <<< "$SUCCESS_OUTPUT"
rg --fixed-strings --quiet 'OpenKeyboardUITests/layout.swift' <<< "$SUCCESS_OUTPUT"

printf '%s\n' 'dirty-test-change' >> "$TEST_ONLY_REPOSITORY/OpenKeyboardUITests/layout.swift"
if OPEN_KEYBOARD_RUNTIME_PROOF_REPOSITORY="$TEST_ONLY_REPOSITORY" \
    "$VERIFIER" "$CAPTURE_SHA" "$CURRENT_SHA" >/dev/null 2>&1; then
  echo 'Carry-forward verifier accepted a dirty current worktree.' >&2
  exit 1
fi

RUNTIME_REPOSITORY="$FIXTURE_ROOT/runtime-change"
initialize_fixture "$RUNTIME_REPOSITORY"
RUNTIME_CAPTURE_SHA="$(git -C "$RUNTIME_REPOSITORY" rev-parse HEAD)"
printf '%s\n' 'runtime-v2' > "$RUNTIME_REPOSITORY/OpenKeyboard/runtime.swift"
git -C "$RUNTIME_REPOSITORY" add OpenKeyboard/runtime.swift
git -C "$RUNTIME_REPOSITORY" commit -qm 'Change runtime content'
RUNTIME_CURRENT_SHA="$(git -C "$RUNTIME_REPOSITORY" rev-parse HEAD)"

if OPEN_KEYBOARD_RUNTIME_PROOF_REPOSITORY="$RUNTIME_REPOSITORY" \
    "$VERIFIER" "$RUNTIME_CAPTURE_SHA" "$RUNTIME_CURRENT_SHA" >/dev/null 2>&1; then
  echo 'Carry-forward verifier accepted an intervening runtime change.' >&2
  exit 1
fi

if OPEN_KEYBOARD_RUNTIME_PROOF_REPOSITORY="$RUNTIME_REPOSITORY" \
    "$VERIFIER" "$RUNTIME_CAPTURE_SHA" "$RUNTIME_CAPTURE_SHA" >/dev/null 2>&1; then
  echo 'Carry-forward verifier accepted a current SHA that was not HEAD.' >&2
  exit 1
fi

REVERTED_RUNTIME_REPOSITORY="$FIXTURE_ROOT/reverted-runtime-change"
initialize_fixture "$REVERTED_RUNTIME_REPOSITORY"
REVERTED_RUNTIME_CAPTURE_SHA="$(git -C "$REVERTED_RUNTIME_REPOSITORY" rev-parse HEAD)"
printf '%s\n' 'runtime-v2' > "$REVERTED_RUNTIME_REPOSITORY/OpenKeyboard/runtime.swift"
git -C "$REVERTED_RUNTIME_REPOSITORY" add OpenKeyboard/runtime.swift
git -C "$REVERTED_RUNTIME_REPOSITORY" commit -qm 'Temporarily change runtime content'
printf '%s\n' 'runtime-v1' > "$REVERTED_RUNTIME_REPOSITORY/OpenKeyboard/runtime.swift"
git -C "$REVERTED_RUNTIME_REPOSITORY" add OpenKeyboard/runtime.swift
git -C "$REVERTED_RUNTIME_REPOSITORY" commit -qm 'Restore runtime content'
printf '%s\n' 'test-v2' > "$REVERTED_RUNTIME_REPOSITORY/OpenKeyboardUITests/layout.swift"
git -C "$REVERTED_RUNTIME_REPOSITORY" add OpenKeyboardUITests/layout.swift
git -C "$REVERTED_RUNTIME_REPOSITORY" commit -qm 'Update test after runtime restoration'
REVERTED_RUNTIME_CURRENT_SHA="$(git -C "$REVERTED_RUNTIME_REPOSITORY" rev-parse HEAD)"

if OPEN_KEYBOARD_RUNTIME_PROOF_REPOSITORY="$REVERTED_RUNTIME_REPOSITORY" \
    "$VERIFIER" "$REVERTED_RUNTIME_CAPTURE_SHA" "$REVERTED_RUNTIME_CURRENT_SHA" \
    >/dev/null 2>&1; then
  echo 'Carry-forward verifier accepted a reverted intervening runtime change.' >&2
  exit 1
fi

RENAMED_TEST_REPOSITORY="$FIXTURE_ROOT/renamed-test"
initialize_fixture "$RENAMED_TEST_REPOSITORY"
RENAMED_TEST_CAPTURE_SHA="$(git -C "$RENAMED_TEST_REPOSITORY" rev-parse HEAD)"
git -C "$RENAMED_TEST_REPOSITORY" mv \
  OpenKeyboardUITests/layout.swift OpenKeyboardUITests/renamed-layout.swift
git -C "$RENAMED_TEST_REPOSITORY" commit -qm 'Rename test source'
RENAMED_TEST_CURRENT_SHA="$(git -C "$RENAMED_TEST_REPOSITORY" rev-parse HEAD)"

if OPEN_KEYBOARD_RUNTIME_PROOF_REPOSITORY="$RENAMED_TEST_REPOSITORY" \
    "$VERIFIER" "$RENAMED_TEST_CAPTURE_SHA" "$RENAMED_TEST_CURRENT_SHA" \
    >/dev/null 2>&1; then
  echo 'Carry-forward verifier accepted an intervening test-target rename.' >&2
  exit 1
fi

COPIED_TEST_REPOSITORY="$FIXTURE_ROOT/copied-test"
initialize_fixture "$COPIED_TEST_REPOSITORY"
COPIED_TEST_CAPTURE_SHA="$(git -C "$COPIED_TEST_REPOSITORY" rev-parse HEAD)"
cp "$COPIED_TEST_REPOSITORY/OpenKeyboardUITests/layout.swift" \
  "$COPIED_TEST_REPOSITORY/OpenKeyboardUITests/copied-layout.swift"
git -C "$COPIED_TEST_REPOSITORY" add OpenKeyboardUITests/copied-layout.swift
git -C "$COPIED_TEST_REPOSITORY" commit -qm 'Copy test source'
COPIED_TEST_CURRENT_SHA="$(git -C "$COPIED_TEST_REPOSITORY" rev-parse HEAD)"

if OPEN_KEYBOARD_RUNTIME_PROOF_REPOSITORY="$COPIED_TEST_REPOSITORY" \
    "$VERIFIER" "$COPIED_TEST_CAPTURE_SHA" "$COPIED_TEST_CURRENT_SHA" \
    >/dev/null 2>&1; then
  echo 'Carry-forward verifier accepted an intervening unchanged-source test copy.' >&2
  exit 1
fi

echo 'Runtime proof carry-forward regression tests passed.'
