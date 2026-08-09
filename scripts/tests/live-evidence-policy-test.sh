#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/live.yml"
FIXTURE="$(mktemp -d)"
RUNNER="$FIXTURE/enforce-live-evidence.sh"
OUTPUT="$FIXTURE/output"
trap 'rm -rf -- "$FIXTURE"' EXIT

ruby -e '
  require "yaml"

  workflow = YAML.load_file(ARGV.fetch(0))
  step = workflow
    .fetch("jobs")
    .fetch("required-live-verification")
    .fetch("steps")
    .find { |candidate| candidate["name"] == "Enforce exact-head local live evidence" }
  abort "Live-evidence enforcement step is missing." unless step
  puts step.fetch("run")
' "$WORKFLOW" > "$RUNNER"
chmod +x "$RUNNER"

HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
STALE_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

valid_body="$(cat <<EOF
- Local live verification: passed
- Live verification target: gateway
- Exact live-tested head: $HEAD_SHA
- No credential or gateway response body retained.
- Trust boundary: local execution is contributor-attested; GitHub verifies retained exact-head evidence only.

## Exact head SHA

\`$HEAD_SHA\`
EOF
)"

stale_body="${valid_body/Exact live-tested head: $HEAD_SHA/Exact live-tested head: $STALE_SHA}"
duplicate_body="$valid_body
- Exact live-tested head: $HEAD_SHA"

run_policy() {
  local body="$1"

  IMPACT_RESULT=success \
    LIVE_IMPACT=gateway \
    HEAD_SHA="$HEAD_SHA" \
    PR_BODY="$body" \
    bash "$RUNNER" > "$OUTPUT" 2>&1
}

if ! run_policy "$valid_body"; then
  echo "Valid exact-head live evidence was rejected." >&2
  exit 1
fi

if run_policy "$stale_body"; then
  echo "Stale live-tested evidence passed because the current SHA appeared elsewhere." >&2
  exit 1
fi

if run_policy "$duplicate_body"; then
  echo "Duplicate live-tested head fields were accepted." >&2
  exit 1
fi

if ! IMPACT_RESULT=success \
  LIVE_IMPACT=none \
  HEAD_SHA="$HEAD_SHA" \
  PR_BODY="" \
  bash "$RUNNER" > "$OUTPUT" 2>&1; then
  echo "A no-impact pull request unexpectedly required live evidence." >&2
  exit 1
fi

echo "Live-evidence policy regression tests passed."
