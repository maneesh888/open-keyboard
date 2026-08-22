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
- Required live models: reference-test-model
- Exact live-tested models: reference-test-model
- Live-model substitutions: none
- Live plain-text grammar verification: verified
- Live baseline outcomes: not required
- Live differential outcomes: not required
- Live follow-up outcomes: not required
- Live operation-scoped warning contracts: not required
- Live profile latencies: not required
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
wrong_model_body="${valid_body/Exact live-tested models: reference-test-model/Exact live-tested models: substituted-test-model}"
substituted_model_body="${valid_body/Live-model substitutions: none/Live-model substitutions: reference-test-model -> substituted-test-model}"
duplicate_models_body="$valid_body
- Exact live-tested models: reference-test-model"
model_agnostic_body="${valid_body/Required live models: reference-test-model/Required live models: model-agnostic}"
model_agnostic_unverified_body="${model_agnostic_body/Live plain-text grammar verification: verified/Live plain-text grammar verification: unverified}"
exact_model_unverified_body="${valid_body/Live plain-text grammar verification: verified/Live plain-text grammar verification: unverified}"
invalid_verification_body="${valid_body/Live plain-text grammar verification: verified/Live plain-text grammar verification: unknown}"
duplicate_verification_body="$valid_body
- Live plain-text grammar verification: verified"

differential_body="$(cat <<EOF
- Local live verification: passed
- Live verification target: gateway-differential
- Exact live-tested head: $HEAD_SHA
- Required live models: low=low-test-model:2b, high=high-test-model:120b
- Exact live-tested models: low=low-test-model:2b, high=high-test-model:120b
- Live-model substitutions: none
- Live plain-text grammar verification: verified
- Live baseline outcomes: low=passed, high=passed
- Live differential outcomes: low=expected-model-capability, high=passed
- Live follow-up outcomes: low=passed, high=passed
- Live operation-scoped warning contracts: verified
- Live profile latencies: low=12.345s, high=23.456s
- No credential or gateway response body retained.
- Trust boundary: local execution is contributor-attested; GitHub verifies retained exact-head evidence only.

## Exact head SHA

\`$HEAD_SHA\`
EOF
)"
missing_profile_body="${differential_body/Required live models: low=low-test-model:2b, high=high-test-model:120b/Required live models: low=low-test-model:2b}"
reversed_profile_body="${differential_body/Exact live-tested models: low=low-test-model:2b, high=high-test-model:120b/Exact live-tested models: high=high-test-model:120b, low=low-test-model:2b}"
substituted_profile_body="${differential_body/Exact live-tested models: low=low-test-model:2b, high=high-test-model:120b/Exact live-tested models: low=low-test-model:2b, high=substituted-test-model:120b}"
same_profile_body="${differential_body//high-test-model:120b/low-test-model:2b}"
low_success_body="${differential_body/Live differential outcomes: low=expected-model-capability, high=passed/Live differential outcomes: low=passed, high=passed}"
high_failure_body="${differential_body/Live differential outcomes: low=expected-model-capability, high=passed/Live differential outcomes: low=expected-model-capability, high=expected-model-capability}"
missing_baseline_body="${differential_body/- Live baseline outcomes: low=passed, high=passed/}"
unverified_warning_body="${differential_body/Live operation-scoped warning contracts: verified/Live operation-scoped warning contracts: unverified}"
malformed_latency_body="${differential_body/Live profile latencies: low=12.345s, high=23.456s/Live profile latencies: high=23.456s, low=12.345s}"

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
    GITHUB_WORKSPACE="$ROOT" \
    LIVE_IMPACT=gateway \
    RUNNER_TEMP="$FIXTURE" \
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
  local impact="${2:-gateway}"

  LIVE_IMPACT="$impact" \
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
if run_policy "$model_agnostic_unverified_body"; then
  echo "Model-agnostic gateway work accepted unverified plain-text grammar." >&2
  exit 1
fi
if run_policy "$exact_model_unverified_body"; then
  echo "Exact-model live evidence accepted unverified plain-text grammar." >&2
  exit 1
fi
if run_policy "$invalid_verification_body"; then
  echo "An unsupported plain-text grammar verification value was accepted." >&2
  exit 1
fi
if run_policy "$duplicate_verification_body"; then
  echo "Duplicate plain-text grammar verification fields were accepted." >&2
  exit 1
fi

if ! run_policy "$differential_body" gateway-differential; then
  cat "$OUTPUT" >&2
  echo "Valid targeted two-profile live evidence was rejected." >&2
  exit 1
fi
if run_policy "$missing_profile_body" gateway-differential; then
  echo "Differential evidence with a missing profile was accepted." >&2
  exit 1
fi
if run_policy "$reversed_profile_body" gateway-differential; then
  echo "Reversed differential profile mappings were accepted." >&2
  exit 1
fi
if run_policy "$substituted_profile_body" gateway-differential; then
  echo "A substituted high-profile model was accepted." >&2
  exit 1
fi
if run_policy "$same_profile_body" gateway-differential; then
  echo "The same model was accepted for both differential roles." >&2
  exit 1
fi
if run_policy "$low_success_body" gateway-differential; then
  echo "A low-model success was accepted as a stable capability boundary." >&2
  exit 1
fi
if run_policy "$high_failure_body" gateway-differential; then
  echo "A high-model capability failure was accepted." >&2
  exit 1
fi
if run_policy "$missing_baseline_body" gateway-differential; then
  echo "Missing differential baseline evidence was accepted." >&2
  exit 1
fi
if run_policy "$unverified_warning_body" gateway-differential; then
  echo "Unverified operation-scoped warning evidence was accepted." >&2
  exit 1
fi
if run_policy "$malformed_latency_body" gateway-differential; then
  echo "Malformed or reversed per-profile latency evidence was accepted." >&2
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
