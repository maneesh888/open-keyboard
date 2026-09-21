#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
while IFS= read -r name; do unset "$name"; done < <(git -C "$ROOT" rev-parse --local-env-vars)
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT
ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).fetch("jobs").fetch("required-live-verification").fetch("steps").find { |s| s["name"] == "Prepare trusted live-policy validators" }.fetch("run")' "$ROOT/.github/workflows/live.yml" > "$FIXTURE/prepare.sh"
mkdir -p "$FIXTURE/repo/scripts" "$FIXTURE/tmp"
git -C "$FIXTURE/repo" init -q
git -C "$FIXTURE/repo" config user.name Fixture
git -C "$FIXTURE/repo" config user.email fixture@example.invalid
printf '#!/bin/bash\necho gateway-differential\n' > "$FIXTURE/repo/scripts/live-impact.sh"
printf '#!/bin/bash\nreadonly OPEN_KEYBOARD_REDACTED_LIVE_EVIDENCE_SCHEMA=1\nexit 37\n' > "$FIXTURE/repo/scripts/validate-pr-live-evidence.sh"
git -C "$FIXTURE/repo" add .
git -C "$FIXTURE/repo" -c core.hooksPath=/dev/null commit -qm trusted
base="$(git -C "$FIXTURE/repo" rev-parse HEAD)"
# Candidate files must never replace trusted policy.
printf '#!/bin/bash\necho none\n' > "$FIXTURE/repo/scripts/live-impact.sh"
printf '#!/bin/bash\nexit 0\n' > "$FIXTURE/repo/scripts/validate-pr-live-evidence.sh"
prepare() (
 cd "$FIXTURE/repo"
 PR_BASE_SHA="$1" RUNNER_TEMP="$FIXTURE/tmp" GITHUB_OUTPUT="$FIXTURE/output" \
   bash -e -o pipefail "$FIXTURE/prepare.sh" > "$FIXTURE/log" 2>&1
)
prepare "$base"
[[ "$(bash "$FIXTURE/tmp/live-policy-validators/live-impact.sh")" == gateway-differential ]]
status=0
bash "$FIXTURE/tmp/live-policy-validators/validate-pr-live-evidence.sh" || status=$?
[[ "$status" == 37 ]] || { echo "Candidate weakened trusted validation." >&2; exit 1; }
for invalid in legacy missing; do
 if [[ "$invalid" == missing ]]; then rm "$FIXTURE/repo/scripts/validate-pr-live-evidence.sh"; fi
 git -C "$FIXTURE/repo" add -A
 git -C "$FIXTURE/repo" -c core.hooksPath=/dev/null commit -qm "$invalid"
 if prepare "$(git -C "$FIXTURE/repo" rev-parse HEAD)"; then
   echo "Unsupported trusted base accepted: $invalid" >&2; exit 1
 fi
done
if prepare aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; then
 echo "Unknown base accepted." >&2; exit 1
fi
echo "Trusted live-policy bootstrap regression tests passed."
