#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASSIFIER="$ROOT/scripts/technical-impact.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

# Git exports repository-local variables to hooks. Clear them before operating on fixture repos.
while IFS= read -r git_environment_name; do
  unset "$git_environment_name"
done < <(git -C "$ROOT" rev-parse --local-env-vars)

git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.name "OpenKeyboard Policy Test"
git -C "$FIXTURE" config user.email "policy-test@example.invalid"

printf 'base\n' > "$FIXTURE/README.md"
git -C "$FIXTURE" add README.md
git -C "$FIXTURE" commit -q -m base
base_sha="$(git -C "$FIXTURE" rev-parse HEAD)"

if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" "$base_sha" "$base_sha")" != "full" ]]; then
  echo "An empty change set did not fail closed to the full gate." >&2
  exit 1
fi
if OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" \
    "$CLASSIFIER" invalid "$base_sha" >/dev/null 2>&1; then
  echo "Technical-impact classification accepted an invalid revision." >&2
  exit 1
fi

commit_path() {
  local relative_path="$1"
  local content="${2:-changed}"

  mkdir -p "$(dirname "$FIXTURE/$relative_path")"
  printf '%s\n' "$content" > "$FIXTURE/$relative_path"
  git -C "$FIXTURE" add -- "$relative_path"
  git -C "$FIXTURE" commit -q -m "change $relative_path"
  git -C "$FIXTURE" rev-parse HEAD
}

assert_commit_impact() {
  local relative_path="$1"
  local expected_impact="$2"
  local path_sha

  git -C "$FIXTURE" checkout -q -B impact-case "$base_sha"
  path_sha="$(commit_path "$relative_path")"
  actual_impact="$(
    OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" \
      "$CLASSIFIER" "$base_sha" "$path_sha"
  )"
  if [[ "$actual_impact" != "$expected_impact" ]]; then
    echo "Expected $expected_impact for $relative_path, received $actual_impact." >&2
    exit 1
  fi
}

docs_only_paths=(
  docs/plan.md
  docs/plans/connector-migration.md
  README.md
  LICENSE
)
for docs_only_path in "${docs_only_paths[@]}"; do
  assert_commit_impact "$docs_only_path" docs-only
done

full_gate_paths=(
  AGENTS.md
  .agents/skills/develop-openkeyboard/SKILL.md
  .github/workflows/ci.yml
  .github/dependabot.yml
  .githooks/pre-push
  docs/runtime-policy.json
  third_party/LICENSE.txt
  scripts/check.sh
  scripts/tests/policy-test.sh
  OpenKeyboard/Views/ContentView.swift
  OpenKeyboardCore/Package.swift
  OpenKeyboardCore/Sources/OpenKeyboardCore/GatewayClient.swift
  OpenKeyboardCore/Tests/OpenKeyboardCoreTests/GatewayClientTests.swift
  OpenKeyboardExtension/KeyboardViewModel.swift
  OpenKeyboardUITests/KeyboardFlowTests.swift
  OpenKeyboard.xcodeproj/project.pbxproj
  Package.resolved
  .gitmodules
  Vendor/semantic-prompt-contract
)
for full_gate_path in "${full_gate_paths[@]}"; do
  assert_commit_impact "$full_gate_path" full
done

git -C "$FIXTURE" checkout -q -B executable-doc-case "$base_sha"
mkdir -p "$FIXTURE/docs/plans"
printf 'plain plan\n' > "$FIXTURE/docs/plans/executable.md"
git -C "$FIXTURE" add docs/plans/executable.md
git -C "$FIXTURE" commit -q -m plain-document
plain_document_sha="$(git -C "$FIXTURE" rev-parse HEAD)"
chmod +x "$FIXTURE/docs/plans/executable.md"
git -C "$FIXTURE" add docs/plans/executable.md
git -C "$FIXTURE" commit -q -m executable-document
executable_document_sha="$(git -C "$FIXTURE" rev-parse HEAD)"
if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" "$plain_document_sha" "$executable_document_sha")" != "full" ]]; then
  echo "An executable committed Markdown file bypassed the full gate." >&2
  exit 1
fi

git -C "$FIXTURE" checkout -q -B symlink-doc-case "$base_sha"
mkdir -p "$FIXTURE/docs"
ln -s ../README.md "$FIXTURE/docs/link.md"
git -C "$FIXTURE" add docs/link.md
git -C "$FIXTURE" commit -q -m symlink-document
symlink_document_sha="$(git -C "$FIXTURE" rev-parse HEAD)"
if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" "$base_sha" "$symlink_document_sha")" != "full" ]]; then
  echo "A committed Markdown symlink bypassed the full gate." >&2
  exit 1
fi

git -C "$FIXTURE" checkout -q -B rename-case "$base_sha"
mkdir -p "$FIXTURE/OpenKeyboard" "$FIXTURE/docs"
printf 'runtime\n' > "$FIXTURE/OpenKeyboard/runtime.json"
git -C "$FIXTURE" add OpenKeyboard/runtime.json
git -C "$FIXTURE" commit -q -m runtime-base
rename_base_sha="$(git -C "$FIXTURE" rev-parse HEAD)"
git -C "$FIXTURE" mv OpenKeyboard/runtime.json docs/runtime.md
git -C "$FIXTURE" commit -q -m rename-runtime-into-docs
rename_head_sha="$(git -C "$FIXTURE" rev-parse HEAD)"
if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" "$rename_base_sha" "$rename_head_sha")" != "full" ]]; then
  echo "Renaming a non-documentation path into docs bypassed the full gate." >&2
  exit 1
fi

git -C "$FIXTURE" checkout -q -B staged-case "$base_sha"
mkdir -p "$FIXTURE/docs/plans"
printf 'staged plan\n' > "$FIXTURE/docs/plans/staged.md"
git -C "$FIXTURE" add docs/plans/staged.md
if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" --staged)" != "docs-only" ]]; then
  echo "A staged documentation-only change did not select the docs-only gate." >&2
  exit 1
fi

chmod +x "$FIXTURE/docs/plans/staged.md"
git -C "$FIXTURE" add docs/plans/staged.md
if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" --staged)" != "full" ]]; then
  echo "A staged executable Markdown file bypassed the full gate." >&2
  exit 1
fi

git -C "$FIXTURE" reset -q HEAD -- docs/plans/staged.md
rm "$FIXTURE/docs/plans/staged.md"
ln -s ../../README.md "$FIXTURE/docs/plans/link.md"
git -C "$FIXTURE" add docs/plans/link.md
if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" --staged)" != "full" ]]; then
  echo "A staged Markdown symlink bypassed the full gate." >&2
  exit 1
fi

git -C "$FIXTURE" checkout -q -B rename-base "$base_sha"
mkdir -p "$FIXTURE/OpenKeyboard" "$FIXTURE/docs"
printf 'runtime\n' > "$FIXTURE/OpenKeyboard/runtime.txt"
git -C "$FIXTURE" add OpenKeyboard/runtime.txt
git -C "$FIXTURE" commit -q -m runtime-base
rename_base_sha="$(git -C "$FIXTURE" rev-parse HEAD)"
git -C "$FIXTURE" mv OpenKeyboard/runtime.txt docs/runtime.md
git -C "$FIXTURE" commit -q -m rename-runtime-to-docs
rename_head_sha="$(git -C "$FIXTURE" rev-parse HEAD)"
if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" "$rename_base_sha" "$rename_head_sha")" != "full" ]]; then
  echo "Renaming a non-documentation path into docs bypassed the full gate." >&2
  exit 1
fi

if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" "$base_sha" "$base_sha")" != "full" ]]; then
  echo "An empty change set must fail closed to the full gate." >&2
  exit 1
fi
if OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" invalid "$base_sha" >/dev/null 2>&1; then
  echo "Technical-impact classification accepted an invalid revision." >&2
  exit 1
fi

echo "Technical-impact regression tests passed."
