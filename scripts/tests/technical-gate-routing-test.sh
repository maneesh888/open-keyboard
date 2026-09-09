#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE_ROOT"' EXIT

# Git exports repository-local variables to hooks. Clear them before operating on fixture repos.
while IFS= read -r git_environment_name; do
  unset "$git_environment_name"
done < <(git -C "$ROOT" rev-parse --local-env-vars)

make_fixture() {
  local fixture="$1"

  mkdir -p "$fixture/.githooks" "$fixture/scripts"
  cp "$ROOT/.githooks/pre-commit" "$fixture/.githooks/pre-commit"
  cp "$ROOT/.githooks/pre-push" "$fixture/.githooks/pre-push"
  cp "$ROOT/scripts/technical-impact.sh" "$fixture/scripts/technical-impact.sh"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "check:%s\\n" "$1" >> "$OPEN_KEYBOARD_TEST_CALL_LOG"' \
    > "$fixture/scripts/check.sh"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "live:%s\\n" "$*" >> "$OPEN_KEYBOARD_TEST_CALL_LOG"' \
    'echo none' \
    > "$fixture/scripts/live-impact.sh"
  chmod +x \
    "$fixture/.githooks/pre-commit" \
    "$fixture/.githooks/pre-push" \
    "$fixture/scripts/check.sh" \
    "$fixture/scripts/live-impact.sh" \
    "$fixture/scripts/technical-impact.sh"

  git -C "$fixture" init -q
  git -C "$fixture" config user.name "OpenKeyboard Policy Test"
  git -C "$fixture" config user.email "policy-test@example.invalid"
  printf 'base\n' > "$fixture/README.md"
  git -C "$fixture" add .
  git -C "$fixture" commit -q -m base
}

assert_log() {
  local log_file="$1"
  local expected="$2"
  local actual=""

  if [[ -f "$log_file" ]]; then
    actual="$(< "$log_file")"
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected hook routing log." >&2
    echo "expected=$expected" >&2
    echo "actual=$actual" >&2
    exit 1
  fi
}

docs_commit_fixture="$FIXTURE_ROOT/pre-commit-docs"
make_fixture "$docs_commit_fixture"
mkdir -p "$docs_commit_fixture/docs/plans"
printf 'plan\n' > "$docs_commit_fixture/docs/plans/migration.md"
git -C "$docs_commit_fixture" add docs/plans/migration.md
docs_commit_log="$FIXTURE_ROOT/pre-commit-docs.log"
(
  cd "$docs_commit_fixture"
  OPEN_KEYBOARD_TEST_CALL_LOG="$docs_commit_log" ./.githooks/pre-commit >/dev/null
)
assert_log "$docs_commit_log" 'check:--hygiene'

source_commit_fixture="$FIXTURE_ROOT/pre-commit-source"
make_fixture "$source_commit_fixture"
mkdir -p "$source_commit_fixture/OpenKeyboard"
printf 'struct Changed {}\n' > "$source_commit_fixture/OpenKeyboard/Changed.swift"
git -C "$source_commit_fixture" add OpenKeyboard/Changed.swift
source_commit_log="$FIXTURE_ROOT/pre-commit-source.log"
(
  cd "$source_commit_fixture"
  OPEN_KEYBOARD_TEST_CALL_LOG="$source_commit_log" ./.githooks/pre-commit >/dev/null
)
assert_log "$source_commit_log" 'check:--quick'

docs_push_fixture="$FIXTURE_ROOT/pre-push-docs"
make_fixture "$docs_push_fixture"
docs_push_base="$(git -C "$docs_push_fixture" rev-parse HEAD)"
mkdir -p "$docs_push_fixture/docs"
printf 'documentation\n' > "$docs_push_fixture/docs/workflow.md"
git -C "$docs_push_fixture" add docs/workflow.md
git -C "$docs_push_fixture" commit -q -m docs
docs_push_head="$(git -C "$docs_push_fixture" rev-parse HEAD)"
docs_push_log="$FIXTURE_ROOT/pre-push-docs.log"
printf 'refs/heads/topic %s refs/heads/topic %s\n' "$docs_push_head" "$docs_push_base" | \
  (
    cd "$docs_push_fixture"
    OPEN_KEYBOARD_TEST_CALL_LOG="$docs_push_log" \
      OPEN_KEYBOARD_LIVE_BASE_REF="$docs_push_base" \
      ./.githooks/pre-push >/dev/null
  )
assert_log "$docs_push_log" 'check:--hygiene'

source_push_fixture="$FIXTURE_ROOT/pre-push-source"
make_fixture "$source_push_fixture"
source_push_base="$(git -C "$source_push_fixture" rev-parse HEAD)"
mkdir -p "$source_push_fixture/OpenKeyboard"
printf 'struct Changed {}\n' > "$source_push_fixture/OpenKeyboard/Changed.swift"
git -C "$source_push_fixture" add OpenKeyboard/Changed.swift
git -C "$source_push_fixture" commit -q -m source
source_push_head="$(git -C "$source_push_fixture" rev-parse HEAD)"
source_push_log="$FIXTURE_ROOT/pre-push-source.log"
printf 'refs/heads/topic %s refs/heads/topic %s\n' "$source_push_head" "$source_push_base" | \
  (
    cd "$source_push_fixture"
    OPEN_KEYBOARD_TEST_CALL_LOG="$source_push_log" \
      OPEN_KEYBOARD_LIVE_BASE_REF="$source_push_base" \
      ./.githooks/pre-push >/dev/null
  )
assert_log "$source_push_log" "check:--full
live:$source_push_base $source_push_head"

echo "Technical gate hook-routing regression tests passed."
