#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/live.yml"
FIXTURE="$(mktemp -d)"
WAITER="$FIXTURE/resolve-current-live-evidence.sh"
RUNNER="$FIXTURE/enforce-live-evidence.sh"
OUTPUT="$FIXTURE/output"
MOCK_BIN="$FIXTURE/bin"
MOCK_CALL_COUNT="$FIXTURE/gh-call-count"
RESOLVED_BODY="$FIXTURE/current-pull-request-body.md"
trap 'rm -rf -- "$FIXTURE"' EXIT
mkdir -p "$MOCK_BIN"

ruby -e '
  require "yaml"

  workflow = YAML.load_file(ARGV.fetch(0))
  step = workflow
    .fetch("jobs")
    .fetch("required-live-verification")
    .fetch("steps")
    .find { |candidate| candidate["name"] == "Resolve current exact-head live evidence" }
  abort "Live-evidence metadata handoff step is missing." unless step
  puts step.fetch("run")
' "$WORKFLOW" > "$WAITER"
chmod +x "$WAITER"

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

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 || "$1" != "api" ]]; then
  echo "Unexpected mocked gh invocation." >&2
  exit 2
fi

call_count=0
if [[ -f "$MOCK_CALL_COUNT" ]]; then
  call_count="$(< "$MOCK_CALL_COUNT")"
fi
((call_count += 1))
printf '%s\n' "$call_count" > "$MOCK_CALL_COUNT"

current_head="$MOCK_HEAD_SHA"
if [[ "${MOCK_MISMATCH_HEAD:-0}" == "1" ]]; then
  current_head="$MOCK_OTHER_SHA"
fi

body_head="$MOCK_STALE_SHA"
if [[ "${MOCK_ALWAYS_STALE:-0}" != "1" && "$call_count" -ge 2 ]]; then
  body_head="$MOCK_HEAD_SHA"
fi

jq -n \
  --arg current_head "$current_head" \
  --arg body "- Exact live-tested head: $body_head" \
  '{head: {sha: $current_head}, body: $body}'
MOCK_GH
chmod +x "$MOCK_BIN/gh"

cat > "$MOCK_BIN/sleep" <<'MOCK_SLEEP'
#!/usr/bin/env bash
exit 0
MOCK_SLEEP
chmod +x "$MOCK_BIN/sleep"

HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
STALE_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
OTHER_SHA="cccccccccccccccccccccccccccccccccccccccc"

run_waiter() {
  rm -f -- "$MOCK_CALL_COUNT" "$RESOLVED_BODY"
  PATH="$MOCK_BIN:$PATH" \
    MOCK_CALL_COUNT="$MOCK_CALL_COUNT" \
    MOCK_HEAD_SHA="$HEAD_SHA" \
    MOCK_STALE_SHA="$STALE_SHA" \
    MOCK_OTHER_SHA="$OTHER_SHA" \
    EVENT_ACTION=synchronize \
    EVENT_HEAD_SHA="$HEAD_SHA" \
    IMPACT_RESULT=success \
    LIVE_IMPACT=gateway \
    PR_NUMBER=21 \
    PR_BODY_FILE="$RESOLVED_BODY" \
    GITHUB_REPOSITORY=maneesh888/open-keyboard \
    bash "$WAITER" > "$OUTPUT" 2>&1
}

if ! run_waiter; then
  echo "The live-evidence handoff did not accept metadata that became current during its bounded retry." >&2
  exit 1
fi
if [[ "$(< "$MOCK_CALL_COUNT")" -ne 2 ]] || ! rg --fixed-strings --quiet -- "- Exact live-tested head: $HEAD_SHA" "$RESOLVED_BODY"; then
  echo "The live-evidence handoff did not retain the first exact-head body it observed." >&2
  exit 1
fi

if MOCK_ALWAYS_STALE=1 run_waiter; then
  echo "The live-evidence handoff accepted metadata that remained stale." >&2
  exit 1
fi
if [[ "$(< "$MOCK_CALL_COUNT")" -ne 24 ]]; then
  echo "The live-evidence handoff did not fail after its bounded retry count." >&2
  exit 1
fi

if MOCK_MISMATCH_HEAD=1 run_waiter; then
  echo "The live-evidence handoff continued after the pull-request head changed." >&2
  exit 1
fi
if [[ "$(< "$MOCK_CALL_COUNT")" -ne 1 ]]; then
  echo "The live-evidence handoff did not fail immediately on a changed head." >&2
  exit 1
fi

valid_body="$(cat <<EOF
- Local live verification: passed
- Live verification target: gateway
- Exact live-tested head: $HEAD_SHA
- Required live models: gemma2:2b
- Exact live-tested models: gemma2:2b
- Live-model substitutions: none
- No credential or gateway response body retained.
- Trust boundary: local execution is contributor-attested; GitHub verifies retained exact-head evidence only.

## Exact head SHA

\`$HEAD_SHA\`
EOF
)"

stale_body="${valid_body/Exact live-tested head: $HEAD_SHA/Exact live-tested head: $STALE_SHA}"
duplicate_body="$valid_body
- Exact live-tested head: $HEAD_SHA"
contradictory_pass_body="${valid_body/Local live verification: passed/Local live verification: failed}
Prose mention: Local live verification: passed"
duplicate_pass_body="$valid_body
- Local live verification: failed"
contradictory_target_body="${valid_body/Live verification target: gateway/Live verification target: none}
Prose mention: Live verification target: gateway"
duplicate_target_body="$valid_body
- Live verification target: none"
wrong_model_body="${valid_body/Exact live-tested models: gemma2:2b/Exact live-tested models: gpt-oss:120b-cloud}"
substituted_model_body="${valid_body/Live-model substitutions: none/Live-model substitutions: gemma2:2b -> gpt-oss:120b-cloud}"
duplicate_models_body="$valid_body
- Exact live-tested models: gemma2:2b"
model_agnostic_body="${valid_body/Required live models: gemma2:2b/Required live models: model-agnostic}"

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

if run_policy "$contradictory_pass_body"; then
  echo "A prose pass marker overrode a failing canonical live-verification field." >&2
  exit 1
fi
if run_policy "$duplicate_pass_body"; then
  echo "Contradictory local live-verification fields were accepted." >&2
  exit 1
fi
if run_policy "$contradictory_target_body"; then
  echo "A prose target marker overrode a different canonical live target." >&2
  exit 1
fi
if run_policy "$duplicate_target_body"; then
  echo "Contradictory live-verification target fields were accepted." >&2
  exit 1
fi
if run_policy "$wrong_model_body"; then
  echo "Wrong-model live evidence was accepted for exact model coverage." >&2
  exit 1
fi
if run_policy "$substituted_model_body"; then
  echo "A live-model substitution was accepted as exact-model proof." >&2
  exit 1
fi
if run_policy "$duplicate_models_body"; then
  echo "Duplicate exact live-tested model fields were accepted." >&2
  exit 1
fi
if ! run_policy "$model_agnostic_body"; then
  echo "Model-agnostic gateway work rejected a named exact tested model." >&2
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
