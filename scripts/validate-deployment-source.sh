#!/usr/bin/env bash
set -euo pipefail

git fetch --no-tags origin main:refs/remotes/origin/main
source_sha="$(git rev-parse "$GITHUB_SHA^{commit}")"
main_sha="$(git rev-parse refs/remotes/origin/main)"

case "$GITHUB_EVENT_NAME" in
  workflow_dispatch)
    if [[ "$GITHUB_REF" != "refs/heads/main" || "$source_sha" != "$main_sha" ]]; then
      echo "Manual deployment must run from the exact current main commit."
      exit 1
    fi
    ;;
  push)
    if [[ "$GITHUB_REF" != refs/tags/v* ]]; then
      echo "Tag deployment requires a v* tag."
      exit 1
    fi
    if ! git merge-base --is-ancestor "$source_sha" "$main_sha"; then
      echo "Deployment tag is not contained in origin/main."
      exit 1
    fi
    ;;
  *)
    echo "Unsupported deployment event: $GITHUB_EVENT_NAME"
    exit 1
    ;;
esac
