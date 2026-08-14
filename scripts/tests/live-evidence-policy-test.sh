#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$(mktemp -d)"
OUTPUT="$FIXTURE/output"
VALIDATOR="$ROOT/scripts/validate-pr-live-evidence.sh"
WORKFLOW="$ROOT/.github/workflows/live.yml"
RESOLVER="$FIXTURE/resolve-live-snapshots.sh"
ENFORCER="$FIXTURE/enforce-live-snapshots.sh"
MOCK_BIN="$FIXTURE/bin"
EVENT_JSON="$FIXTURE/event.json"
EVENT_BODY_FILE="$FIXTURE/event-body.md"
CURRENT_BODY_FILE="$FIXTURE/current-body.md"
MOCK_CURRENT_BODY_FILE="$FIXTURE/mock-current-body.md"
trap 'rm -rf -- "$FIXTURE"' EXIT
mkdir -p "$MOCK_BIN"

if [[ ! -x "$VALIDATOR" ]]; then
  echo "Live-evidence validator must be executable." >&2
  exit 1
fi

ruby -e '
  require "yaml"
  step = YAML.load_file(ARGV.fetch(0))
    .fetch("jobs")
    .fetch("required-live-verification")
    .fetch("steps")
    .find { |candidate| candidate["name"] == "Resolve immutable and current live-evidence snapshots" }
  abort "Live snapshot resolver is missing." unless step
  puts step.fetch("run")
' "$WORKFLOW" > "$RESOLVER"
chmod +x "$RESOLVER"

ruby -e '
  require "yaml"
  step = YAML.load_file(ARGV.fetch(0))
    .fetch("jobs")
    .fetch("required-live-verification")
    .fetch("steps")
    .find { |candidate| candidate["name"] == "Enforce event and current exact-head live evidence" }
  abort "Live snapshot enforcement is missing." unless step
  puts step.fetch("run")
' "$WORKFLOW" > "$ENFORCER"
chmod +x "$ENFORCER"

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" != "api" ]]; then
  echo "Unexpected mocked gh command." >&2
  exit 2
fi

jq -n \
  --arg head "$MOCK_CURRENT_HEAD" \
  --rawfile body "$MOCK_CURRENT_BODY_FILE" \
  '{head: {sha: $head}, body: $body}'
MOCK_GH
chmod +x "$MOCK_BIN/gh"

HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
STALE_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

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

run_snapshot_gate() {
  local event_body="$1"
  local current_body="$2"
  local current_head="${3:-$HEAD_SHA}"

  printf '%s\n' "$current_body" > "$MOCK_CURRENT_BODY_FILE"
  jq -n \
    --arg head "$HEAD_SHA" \
    --arg body "$event_body" \
    '{pull_request: {head: {sha: $head}, body: $body}}' > "$EVENT_JSON"
  rm -f -- "$EVENT_BODY_FILE" "$CURRENT_BODY_FILE"

  PATH="$MOCK_BIN:$PATH" \
    CURRENT_BODY_FILE="$CURRENT_BODY_FILE" \
    EVENT_BODY_FILE="$EVENT_BODY_FILE" \
    EVENT_HEAD_SHA="$HEAD_SHA" \
    GH_TOKEN=fixture \
    GITHUB_EVENT_PATH="$EVENT_JSON" \
    GITHUB_REPOSITORY=maneesh888/open-keyboard \
    MOCK_CURRENT_BODY_FILE="$MOCK_CURRENT_BODY_FILE" \
    MOCK_CURRENT_HEAD="$current_head" \
    PR_NUMBER=21 \
    bash -e -o pipefail "$RESOLVER" > "$OUTPUT" 2>&1 &&
  CURRENT_BODY_FILE="$CURRENT_BODY_FILE" \
    EVENT_BODY_FILE="$EVENT_BODY_FILE" \
    EVENT_HEAD_SHA="$HEAD_SHA" \
    LIVE_IMPACT=gateway \
    VALIDATOR_ROOT="$ROOT/scripts" \
    bash -e -o pipefail "$ENFORCER" >> "$OUTPUT" 2>&1
}

if ! run_snapshot_gate "$valid_body" "$valid_body"; then
  echo "Matching valid event and current live snapshots were rejected." >&2
  exit 1
fi
if run_snapshot_gate "$valid_body" "$stale_body"; then
  echo "A valid older event hid invalid current live evidence." >&2
  exit 1
fi
if run_snapshot_gate "$stale_body" "$valid_body"; then
  cat "$OUTPUT" >&2
  echo "Restored current live evidence erased an invalid event snapshot." >&2
  exit 1
fi
if run_snapshot_gate "$valid_body" "$valid_body" "$STALE_SHA"; then
  echo "Live snapshot resolution accepted a changed current head." >&2
  exit 1
fi

run_policy() {
  local body="$1"

  LIVE_IMPACT=gateway \
    HEAD_SHA="$HEAD_SHA" \
    PR_BODY="$body" \
    "$VALIDATOR" > "$OUTPUT" 2>&1
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

if ! LIVE_IMPACT=none \
  HEAD_SHA="$HEAD_SHA" \
  PR_BODY="" \
  "$VALIDATOR" > "$OUTPUT" 2>&1; then
  echo "A no-impact pull request unexpectedly required live evidence." >&2
  exit 1
fi

echo "Live-evidence policy regression tests passed."
