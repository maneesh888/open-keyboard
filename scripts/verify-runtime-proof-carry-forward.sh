#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY="${OPEN_KEYBOARD_RUNTIME_PROOF_REPOSITORY:-$SCRIPT_ROOT}"

usage() {
  cat <<'EOF'
Usage: ./scripts/verify-runtime-proof-carry-forward.sh <capture-sha> <current-sha>

Verify that normal-Simulator screenshot evidence from an ancestor commit may be carried forward
to the clean current HEAD because every intervening change is confined to a non-shipping test
target and the non-test Git tree is identical.
EOF
}

fail() {
  echo "Runtime proof carry-forward rejected: $*" >&2
  exit 1
}

is_nonshipping_test_path() {
  case "$1" in
    OpenKeyboardCore/Tests/*|OpenKeyboardTests/*|OpenKeyboardUITests/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

runtime_tree_digest() {
  local revision="$1"

  git -C "$REPOSITORY" ls-tree -r -z --full-tree "$revision" |
    while IFS= read -r -d '' entry; do
      local path="${entry#*$'\t'}"
      if is_nonshipping_test_path "$path"; then
        continue
      fi
      printf '%s\0' "$entry"
    done |
    shasum -a 256 |
    awk '{print $1}'
}

record_intervening_paths() {
  local output_file="$1"
  local commit
  local revision_line
  local parent
  local renamed_or_copied_paths

  while IFS= read -r commit; do
    read -r -a revision_line <<< "$(
      git -C "$REPOSITORY" rev-list --parents --max-count=1 "$commit"
    )"
    [[ "${#revision_line[@]}" -gt 1 ]] ||
      fail "intervening commit has no parent: $commit"

    for parent in "${revision_line[@]:1}"; do
      renamed_or_copied_paths="$(
        git -C "$REPOSITORY" diff --name-only --diff-filter=RC \
          --find-renames --find-copies "$parent" "$commit"
      )"
      [[ -z "$renamed_or_copied_paths" ]] ||
        fail "intervening commit contains a renamed or copied path: $commit"

      git -C "$REPOSITORY" diff-tree \
        --no-commit-id --name-only -r -z --no-renames \
        "$parent" "$commit" >> "$output_file"
    done
  done < <(
    git -C "$REPOSITORY" rev-list --reverse --topo-order \
      "$CAPTURE_SHA..$CURRENT_SHA"
  )
}

if [[ "$#" -ne 2 ]]; then
  usage >&2
  exit 2
fi

REPOSITORY="$(git -C "$REPOSITORY" rev-parse --show-toplevel)"
CAPTURE_SHA="$(git -C "$REPOSITORY" rev-parse --verify "$1^{commit}")"
CURRENT_SHA="$(git -C "$REPOSITORY" rev-parse --verify "$2^{commit}")"
HEAD_SHA="$(git -C "$REPOSITORY" rev-parse HEAD)"

[[ "$CURRENT_SHA" == "$HEAD_SHA" ]] ||
  fail "current SHA must equal the repository's current HEAD ($HEAD_SHA)."

if [[ -n "$(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all)" ]]; then
  fail "the current worktree is not clean."
fi

git -C "$REPOSITORY" merge-base --is-ancestor "$CAPTURE_SHA" "$CURRENT_SHA" ||
  fail "capture SHA is not an ancestor of current HEAD."

if [[ "$CAPTURE_SHA" == "$CURRENT_SHA" ]]; then
  fail "capture and current SHA are identical; carry-forward is unnecessary."
fi

INTERVENING_PATHS_FILE="$(mktemp "${TMPDIR:-/tmp}/openkeyboard-runtime-proof-paths.XXXXXX")"
trap 'rm -f -- "$INTERVENING_PATHS_FILE"' EXIT
record_intervening_paths "$INTERVENING_PATHS_FILE"

CHANGE_COUNT=0
while IFS= read -r -d '' path; do
  CHANGE_COUNT=$((CHANGE_COUNT + 1))
  is_nonshipping_test_path "$path" ||
    fail "intervening path can affect runtime content: $path"
done < "$INTERVENING_PATHS_FILE"

[[ "$CHANGE_COUNT" -gt 0 ]] || fail "the commit range contains no changed paths."

CAPTURE_DIGEST="$(runtime_tree_digest "$CAPTURE_SHA")"
CURRENT_DIGEST="$(runtime_tree_digest "$CURRENT_SHA")"
[[ "$CAPTURE_DIGEST" == "$CURRENT_DIGEST" ]] ||
  fail "the non-test Git tree digest changed."

echo "Runtime proof carry-forward verified."
echo "Capture SHA: $CAPTURE_SHA"
echo "Current SHA: $CURRENT_SHA"
echo "Runtime content digest: $CURRENT_DIGEST"
echo "Allowed intervening paths:"
while IFS= read -r -d '' path; do
  printf -- '- %s\n' "$path"
done < "$INTERVENING_PATHS_FILE"
