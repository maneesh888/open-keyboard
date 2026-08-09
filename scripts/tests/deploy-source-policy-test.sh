#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$(mktemp -d)"
REMOTE="$FIXTURE/remote.git"
REPOSITORY="$FIXTURE/repository"
RUNNER="$ROOT/scripts/validate-deployment-source.sh"
OUTPUT="$FIXTURE/output"
trap 'rm -rf -- "$FIXTURE"' EXIT

while IFS= read -r git_environment_name; do
  unset "$git_environment_name"
done < <(git -C "$ROOT" rev-parse --local-env-vars)

git init -q --bare "$REMOTE"
git init -q "$REPOSITORY"
git -C "$REPOSITORY" config user.name "OpenKeyboard Deployment Policy Test"
git -C "$REPOSITORY" config user.email "deployment-policy@example.invalid"
git -C "$REPOSITORY" remote add origin "$REMOTE"

printf 'trusted\n' > "$REPOSITORY/README.md"
git -C "$REPOSITORY" add README.md
git -C "$REPOSITORY" commit -q -m trusted
git -C "$REPOSITORY" branch -M main
git -C "$REPOSITORY" push -q -u origin main
main_sha="$(git -C "$REPOSITORY" rev-parse HEAD)"

git -C "$REPOSITORY" checkout -q -b feature/untrusted
printf 'untrusted\n' > "$REPOSITORY/untrusted.txt"
git -C "$REPOSITORY" add untrusted.txt
git -C "$REPOSITORY" commit -q -m untrusted
untrusted_sha="$(git -C "$REPOSITORY" rev-parse HEAD)"

run_policy() {
  local event_name="$1"
  local ref="$2"
  local sha="$3"

  (
    cd "$REPOSITORY"
    GITHUB_EVENT_NAME="$event_name" \
      GITHUB_REF="$ref" \
      GITHUB_SHA="$sha" \
      bash "$RUNNER"
  ) > "$OUTPUT" 2>&1
}

if ! run_policy workflow_dispatch refs/heads/main "$main_sha"; then
  echo "Manual deployment rejected the exact current main commit." >&2
  exit 1
fi
if run_policy workflow_dispatch refs/heads/feature/untrusted "$untrusted_sha"; then
  echo "Manual deployment accepted an untrusted branch." >&2
  exit 1
fi
if run_policy workflow_dispatch refs/heads/main "$untrusted_sha"; then
  echo "Manual deployment accepted a non-main commit under the main ref." >&2
  exit 1
fi
if ! run_policy push refs/tags/v1.0.0 "$main_sha"; then
  echo "Deployment rejected a v* tag contained in main." >&2
  exit 1
fi
if run_policy push refs/tags/v1.0.0 "$untrusted_sha"; then
  echo "Deployment accepted a v* tag not contained in main." >&2
  exit 1
fi
if run_policy push refs/tags/not-a-release "$main_sha"; then
  echo "Deployment accepted a tag outside the v* namespace." >&2
  exit 1
fi

echo "Deployment source policy regression tests passed."
