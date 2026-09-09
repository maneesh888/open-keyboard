#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPEN_KEYBOARD_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MODE="commits"
base_sha=""
head_sha=""

usage() {
  cat >&2 <<'EOF'
Usage: ./scripts/technical-impact.sh <base-sha> <head-sha>
       ./scripts/technical-impact.sh --staged

Prints docs-only only when every changed path is a regular top-level README.md
or LICENSE* file, or a regular Markdown file under docs/. All other changes,
invalid inputs, and empty change sets require the full technical gate.
EOF
}

changed_paths_file="$(mktemp)"
trap 'rm -f "$changed_paths_file"' EXIT

case "${1:-}" in
  --staged)
    if [[ "$#" -ne 1 ]]; then
      usage
      exit 2
    fi
    if ! git -C "$ROOT" rev-parse --verify HEAD^{commit} >/dev/null 2>&1; then
      echo "Staged technical-impact classification requires an existing HEAD commit." >&2
      exit 2
    fi
    MODE="staged"
    git -C "$ROOT" diff \
      --cached \
      --no-renames \
      --name-only \
      --diff-filter=ACDMRT \
      -z \
      HEAD > "$changed_paths_file"
    ;;
  --help|-h|help)
    usage
    exit 0
    ;;
  *)
    if [[ "$#" -ne 2 ]]; then
      usage
      exit 2
    fi

    base_sha="$1"
    head_sha="$2"
    for revision in "$base_sha" "$head_sha"; do
      if ! git -C "$ROOT" cat-file -e "$revision^{commit}" 2>/dev/null; then
        echo "Technical-impact classification requires two valid commit SHAs." >&2
        exit 2
      fi
    done
    if ! git -C "$ROOT" merge-base "$base_sha" "$head_sha" >/dev/null 2>&1; then
      echo "Technical-impact classification requires commits with a common ancestor." >&2
      exit 2
    fi

    git -C "$ROOT" diff \
      --no-renames \
      --name-only \
      --diff-filter=ACDMRT \
      -z \
      "$base_sha...$head_sha" > "$changed_paths_file"
    ;;
esac

path_is_plain_document() {
  local changed_path="$1"

  case "$changed_path" in
    README.md | docs/*.md)
      return 0
      ;;
    LICENSE*)
      [[ "$changed_path" != */* ]]
      return
      ;;
    *)
      return 1
      ;;
  esac
}

commit_path_is_plain_file() {
  local revision="$1"
  local changed_path="$2"
  local entry
  local mode

  entry="$(git -C "$ROOT" ls-tree "$revision" -- ":(literal)$changed_path")"
  if [[ -z "$entry" ]]; then
    return 0
  fi
  mode="${entry%% *}"
  [[ "$mode" == "100644" ]]
}

index_path_is_plain_file() {
  local changed_path="$1"
  local entry
  local mode

  entry="$(git -C "$ROOT" ls-files --stage -- ":(literal)$changed_path")"
  if [[ -z "$entry" ]]; then
    return 0
  fi
  mode="${entry%% *}"
  [[ "$mode" == "100644" ]]
}

changed_path_count=0
while IFS= read -r -d '' changed_path; do
  changed_path_count=$((changed_path_count + 1))

  if ! path_is_plain_document "$changed_path"; then
    echo "full"
    exit 0
  fi

  if [[ "$MODE" == "staged" ]]; then
    if ! commit_path_is_plain_file HEAD "$changed_path" ||
      ! index_path_is_plain_file "$changed_path"; then
      echo "full"
      exit 0
    fi
  elif ! commit_path_is_plain_file "$base_sha" "$changed_path" ||
    ! commit_path_is_plain_file "$head_sha" "$changed_path"; then
    echo "full"
    exit 0
  fi
done < "$changed_paths_file"

if [[ "$changed_path_count" -eq 0 ]]; then
  echo "full"
else
  echo "docs-only"
fi
