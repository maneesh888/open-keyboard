#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASSIFIER="$ROOT/scripts/live-impact.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

# Git exports repository-local variables to hooks. Clear them before operating on a fixture repo.
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

mkdir -p "$FIXTURE/docs"
printf 'documentation\n' > "$FIXTURE/docs/workflow.md"
git -C "$FIXTURE" add docs/workflow.md
git -C "$FIXTURE" commit -q -m docs
docs_sha="$(git -C "$FIXTURE" rev-parse HEAD)"

if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" "$base_sha" "$docs_sha")" != "none" ]]; then
  echo "Documentation-only changes must not require live verification." >&2
  exit 1
fi

mkdir -p "$FIXTURE/OpenKeyboard/Services"
printf 'gateway runtime\n' > "$FIXTURE/OpenKeyboard/Services/CanonicalGatewayClient.swift"
git -C "$FIXTURE" add OpenKeyboard/Services/CanonicalGatewayClient.swift
git -C "$FIXTURE" commit -q -m gateway
gateway_sha="$(git -C "$FIXTURE" rev-parse HEAD)"

if [[ "$(OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" "$base_sha" "$gateway_sha")" != "gateway" ]]; then
  echo "Gateway runtime changes must require live verification." >&2
  exit 1
fi

if OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$CLASSIFIER" invalid "$gateway_sha" >/dev/null 2>&1; then
  echo "Live-impact classification accepted an invalid revision." >&2
  exit 1
fi

echo "Live-impact regression tests passed."
