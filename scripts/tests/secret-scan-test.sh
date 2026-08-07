#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCANNER="$ROOT/scripts/secret-scan.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

# Git exports repository-local variables to hooks. Clear them before operating on a fixture repo.
while IFS= read -r git_environment_name; do
  unset "$git_environment_name"
done < <(git -C "$ROOT" rev-parse --local-env-vars)

git -C "$FIXTURE" init -q
printf 'safe fixture\n' > "$FIXTURE/README.md"
git -C "$FIXTURE" add README.md

OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$SCANNER" >/dev/null

printf 'sk-%s\n' 'abcdefghijklmnopqrstuvwxyz123456' > "$FIXTURE/leak.txt"
if OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$SCANNER" >/dev/null 2>&1; then
  echo "Secret scan accepted a high-confidence key fixture." >&2
  exit 1
fi
rm -f "$FIXTURE/leak.txt"

mkdir -p "$FIXTURE/.agent/local-seeds"
printf 'OPEN_KEYBOARD_SIMULATOR_API_KEY=local-only-fixture-value\n' \
  > "$FIXTURE/.agent/local-seeds/openkeyboard-gateway.env"
printf '.agent/\n' > "$FIXTURE/.gitignore"
git -C "$FIXTURE" add .gitignore
OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$SCANNER" >/dev/null

git -C "$FIXTURE" add -f .agent/local-seeds/openkeyboard-gateway.env
if OPEN_KEYBOARD_REPOSITORY_ROOT="$FIXTURE" "$SCANNER" >/dev/null 2>&1; then
  echo "Secret scan accepted a tracked local seed file." >&2
  exit 1
fi

echo "Secret-scan regression tests passed."
