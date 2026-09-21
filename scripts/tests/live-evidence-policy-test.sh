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
PROVIDER_BINDINGS='openai=true, anthropic=true, openrouter=true, gateway=true'
PROVIDER_OUTCOMES='openai=passed, anthropic=passed, openrouter=passed, gateway=passed'

valid_body="$(cat <<EOF
- Local live verification: passed
- Live verification target: gateway
- Exact live-tested head: $HEAD_SHA
- Live model requirement: exact
- Live model identity matches: reference=true
- Live model role distinctness: not required
- Live-model substitutions: none
- Live provider exact bindings: $PROVIDER_BINDINGS
- Live provider Test Connection outcomes: $PROVIDER_OUTCOMES
- Live provider diagnostic outcomes: $PROVIDER_OUTCOMES
- Live plain-text grammar verification: verified
- Live summarize outcomes: not required
- Live continue-writing outcomes: not required
- Live baseline outcomes: not required
- Live differential outcomes: not required
- Live follow-up outcomes: not required
- Live operation-scoped warning contracts: not required
- No credential, private provider value, model identity, or gateway response body retained.
- Trust boundary: local execution attests secret-backed exact identity comparisons; GitHub verifies retained exact-head non-sensitive assertions only.

## Exact head SHA

\`$HEAD_SHA\`
EOF
)"

differential_body="$(cat <<EOF
- Local live verification: passed
- Live verification target: gateway-differential
- Exact live-tested head: $HEAD_SHA
- Live model requirement: exact
- Live model identity matches: low=true, high=true
- Live model role distinctness: true
- Live-model substitutions: none
- Live provider exact bindings: $PROVIDER_BINDINGS
- Live provider Test Connection outcomes: $PROVIDER_OUTCOMES
- Live provider diagnostic outcomes: $PROVIDER_OUTCOMES
- Live plain-text grammar verification: verified
- Live summarize outcomes: low=passed, high=passed
- Live continue-writing outcomes: low=passed, high=passed
- Live baseline outcomes: low=passed, high=passed
- Live differential outcomes: low=expected-model-capability, high=passed
- Live follow-up outcomes: low=passed, high=passed
- Live operation-scoped warning contracts: verified
- No credential, private provider value, model identity, or gateway response body retained.
- Trust boundary: local execution attests secret-backed exact identity comparisons; GitHub verifies retained exact-head non-sensitive assertions only.

## Exact head SHA

\`$HEAD_SHA\`
EOF
)"

none_impact_body="$(cat <<'EOF'
## Live gateway evidence

- Local live verification: not required
- Live verification target: not required
- Exact live-tested head: not required
- Live model requirement: not required
- Live model identity matches: not required
- Live model role distinctness: not required
- Live-model substitutions: not required
- Live provider exact bindings: not required
- Live provider Test Connection outcomes: not required
- Live provider diagnostic outcomes: not required
- Live plain-text grammar verification: not required
- Live summarize outcomes: not required
- Live continue-writing outcomes: not required
- Live baseline outcomes: not required
- Live differential outcomes: not required
- Live follow-up outcomes: not required
- Live operation-scoped warning contracts: not required
- No credential, private provider value, model identity, or gateway response body retained.
- Trust boundary: local execution attests secret-backed exact identity comparisons; GitHub verifies retained exact-head non-sensitive assertions only.
EOF
)"

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
    LIVE_POLICY_BOOTSTRAP_DIFFERENTIAL=false \
    RUNNER_TEMP="$FIXTURE" \
    VALIDATOR_ROOT="$ROOT/scripts" \
    bash -e -o pipefail "$ENFORCER" >> "$OUTPUT" 2>&1
}

run_policy() {
  local body="$1"
  local impact="${2:-gateway}"

  LIVE_IMPACT="$impact" HEAD_SHA="$HEAD_SHA" PR_BODY="$body" \
    "$VALIDATOR" > "$OUTPUT" 2>&1
}

if ! run_snapshot_gate "$valid_body" "$valid_body"; then
  cat "$OUTPUT" >&2
  echo "Matching valid event and current live snapshots were rejected." >&2
  exit 1
fi
stale_body="${valid_body/Exact live-tested head: $HEAD_SHA/Exact live-tested head: $STALE_SHA}"
if run_snapshot_gate "$valid_body" "$stale_body"; then
  echo "A valid older event hid invalid current live evidence." >&2
  exit 1
fi
if run_snapshot_gate "$stale_body" "$valid_body"; then
  echo "Restored current evidence erased an invalid event snapshot." >&2
  exit 1
fi
if run_snapshot_gate "$valid_body" "$valid_body" "$STALE_SHA"; then
  echo "Live snapshot resolution accepted a changed current head." >&2
  exit 1
fi

if ! run_policy "$valid_body"; then
  cat "$OUTPUT" >&2
  echo "Valid exact-head live evidence was rejected." >&2
  exit 1
fi
if ! run_policy "${valid_body/Live model requirement: exact/Live model requirement: model-agnostic}"; then
  echo "Model-agnostic gateway evidence was rejected." >&2
  exit 1
fi
if ! run_policy "$differential_body" gateway-differential; then
  cat "$OUTPUT" >&2
  echo "Valid redacted differential evidence was rejected." >&2
  exit 1
fi
if run_policy "$valid_body" gateway-differential; then
  echo "Ordinary gateway evidence was accepted as differential evidence outside schema bootstrap." >&2
  exit 1
fi

assert_rejected() {
  local body="$1"
  local description="$2"
  local impact="${3:-gateway}"

  if run_policy "$body" "$impact"; then
    echo "$description was accepted." >&2
    exit 1
  fi
}

assert_rejected "$stale_body" "Stale exact-head evidence"
assert_rejected "$valid_body
- Exact live-tested head: $HEAD_SHA" "Duplicate exact-head evidence"
assert_rejected "${valid_body/Local live verification: passed/Local live verification: failed}" "Failed local verification"
assert_rejected "$valid_body
- Local live verification: passed" "Duplicate local verification"
assert_rejected "${valid_body/Live model identity matches: reference=true/Live model identity matches: reference=false}" "A false exact-identity assertion"
assert_rejected "${valid_body/Live model identity matches: reference=true/Live model identity matches: reference=private-model-id}" "A raw model-shaped identity value"
assert_rejected "${valid_body/- Live model identity matches: reference=true/}" "Missing exact-identity evidence"
assert_rejected "$valid_body
- Live model identity matches: reference=true" "Duplicate exact-identity evidence"
assert_rejected "${valid_body/Live model role distinctness: not required/Live model role distinctness: false}" "An ordinary role-distinctness claim"
assert_rejected "${valid_body/Live-model substitutions: none/Live-model substitutions: fallback}" "A model substitution"
assert_rejected "$valid_body
- Required live models: private-model-id" "A legacy required-model field"
assert_rejected "$valid_body
- Exact live-tested models: private-model-id" "A legacy tested-model field"
assert_rejected "$valid_body
- Live model commitment scheme: hmac-sha256" "A legacy opaque commitment field"

assert_rejected "${valid_body/Live provider exact bindings: $PROVIDER_BINDINGS/Live provider exact bindings: openai=true, anthropic=true, openrouter=true}" "A missing provider row"
assert_rejected "${valid_body/Live provider exact bindings: $PROVIDER_BINDINGS/Live provider exact bindings: openai=true, anthropic=false, openrouter=true, gateway=true}" "A false provider binding"
assert_rejected "${valid_body/Live provider exact bindings: $PROVIDER_BINDINGS/Live provider exact bindings: anthropic=true, openai=true, openrouter=true, gateway=true}" "Reordered provider bindings"
assert_rejected "$valid_body
- Live provider exact bindings: $PROVIDER_BINDINGS" "Duplicate provider bindings"
assert_rejected "${valid_body/- Live provider Test Connection outcomes: $PROVIDER_OUTCOMES/}" "Missing provider Test Connection outcomes"
assert_rejected "${valid_body/Live provider Test Connection outcomes: $PROVIDER_OUTCOMES/Live provider Test Connection outcomes: openai=passed, anthropic=failed, openrouter=passed, gateway=passed}" "A failed provider Test Connection row"
assert_rejected "${valid_body/Live provider Test Connection outcomes: $PROVIDER_OUTCOMES/Live provider Test Connection outcomes: anthropic=passed, openai=passed, openrouter=passed, gateway=passed}" "Reordered provider Test Connection outcomes"
assert_rejected "$valid_body
- Live provider Test Connection outcomes: $PROVIDER_OUTCOMES" "Duplicate provider Test Connection outcomes"
assert_rejected "${valid_body/- Live provider diagnostic outcomes: $PROVIDER_OUTCOMES/}" "Missing provider diagnostic outcomes"
assert_rejected "${valid_body/Live provider diagnostic outcomes: $PROVIDER_OUTCOMES/Live provider diagnostic outcomes: openai=passed, anthropic=passed, openrouter=failed, gateway=passed}" "A failed provider diagnostic row"
assert_rejected "${valid_body/Live provider diagnostic outcomes: $PROVIDER_OUTCOMES/Live provider diagnostic outcomes: anthropic=passed, openai=passed, openrouter=passed, gateway=passed}" "Reordered provider diagnostic outcomes"
assert_rejected "$valid_body
- Live provider diagnostic outcomes: $PROVIDER_OUTCOMES" "Duplicate provider diagnostic outcomes"
assert_rejected "$valid_body
- Live provider matrix latencies: openai=1.111s, anthropic=2.222s, openrouter=3.333s, gateway=4.444s" "A legacy provider timing field"
assert_rejected "$valid_body
- Live profile latencies: low=12.345s, high=23.456s" "A legacy profile timing field"
assert_rejected "$valid_body
- Live diagnostic latencies low: transport=12ms, grammar=34ms, rewrite=56ms, translation=78ms" "A legacy diagnostic timing field"
assert_rejected "$valid_body
- diagnostic_latencies_high=transport=12ms, grammar=34ms, rewrite=56ms, translation=78ms" "A machine-form diagnostic timing field"
assert_rejected "$valid_body
- Live diagnostic latency low: transport=12ms" "A singular diagnostic timing field"

assert_rejected "${differential_body/Live model identity matches: low=true, high=true/Live model identity matches: high=true, low=true}" "Reversed differential identity roles" gateway-differential
assert_rejected "${differential_body/Live model identity matches: low=true, high=true/Live model identity matches: low=true, high=false}" "A false differential identity role" gateway-differential
assert_rejected "${differential_body/Live model role distinctness: true/Live model role distinctness: false}" "Non-distinct differential roles" gateway-differential
assert_rejected "${differential_body/Live differential outcomes: low=expected-model-capability, high=passed/Live differential outcomes: low=passed, high=passed}" "An invalid low-profile success boundary" gateway-differential
assert_rejected "${differential_body/Live differential outcomes: low=expected-model-capability, high=passed/Live differential outcomes: low=expected-model-capability, high=failed}" "A failed high-profile boundary" gateway-differential
assert_rejected "${differential_body/- Live baseline outcomes: low=passed, high=passed/}" "Missing differential baseline evidence" gateway-differential
assert_rejected "${differential_body/- Live summarize outcomes: low=passed, high=passed/}" "Missing differential Summarize evidence" gateway-differential
assert_rejected "${differential_body/Live continue-writing outcomes: low=passed, high=passed/Live continue-writing outcomes: low=passed, high=failed}" "Failed differential Continue Writing evidence" gateway-differential
assert_rejected "${differential_body/Live operation-scoped warning contracts: verified/Live operation-scoped warning contracts: unverified}" "Unverified warning contracts" gateway-differential

if ! run_policy "$none_impact_body" none; then
  cat "$OUTPUT" >&2
  echo "A clean no-impact pull request unexpectedly required live assertions." >&2
  exit 1
fi
if ! run_policy "" none; then
  cat "$OUTPUT" >&2
  echo "An empty no-impact live-evidence section was rejected." >&2
  exit 1
fi
assert_rejected "$none_impact_body
- Required live models: private-model-id" "No-impact evidence containing a legacy raw-model field" none
assert_rejected "${none_impact_body/Live model identity matches: not required/Live model identity matches: reference=private-model-id}" "No-impact evidence containing a raw model-shaped identity field" none
assert_rejected "$none_impact_body
- Live model commitment scheme: hmac-sha256" "No-impact evidence containing an HMAC commitment field" none
assert_rejected "$none_impact_body
- Live profile latencies: low=1.000s, high=2.000s" "No-impact evidence containing a retained timing field" none
assert_rejected "${none_impact_body/Local live verification: not required/Local live verification: passed}" "No-impact evidence claiming a live pass" none
assert_rejected "${none_impact_body/Live verification target: not required/Live verification target: gateway}" "No-impact evidence claiming a live target" none
assert_rejected "${none_impact_body/Exact live-tested head: not required/Exact live-tested head: $HEAD_SHA}" "No-impact evidence claiming a live-tested head" none
assert_rejected "${none_impact_body/Live model requirement: not required/Live model requirement: exact}" "No-impact evidence claiming an exact-model requirement" none
assert_rejected "${none_impact_body/Live model identity matches: not required/Live model identity matches: reference=true}" "No-impact evidence claiming an identity match" none
assert_rejected "${none_impact_body/Live model role distinctness: not required/Live model role distinctness: true}" "No-impact evidence claiming distinct model roles" none
assert_rejected "${none_impact_body/Live-model substitutions: not required/Live-model substitutions: none}" "No-impact evidence claiming a substitution result" none
assert_rejected "${none_impact_body/Live provider exact bindings: not required/Live provider exact bindings: $PROVIDER_BINDINGS}" "No-impact evidence claiming provider bindings" none
assert_rejected "${none_impact_body/Live provider Test Connection outcomes: not required/Live provider Test Connection outcomes: $PROVIDER_OUTCOMES}" "No-impact evidence claiming provider Test Connection outcomes" none
assert_rejected "${none_impact_body/Live provider diagnostic outcomes: not required/Live provider diagnostic outcomes: $PROVIDER_OUTCOMES}" "No-impact evidence claiming provider diagnostic outcomes" none
assert_rejected "${none_impact_body/Live plain-text grammar verification: not required/Live plain-text grammar verification: verified}" "No-impact evidence claiming grammar verification" none
assert_rejected "${none_impact_body/Live baseline outcomes: not required/Live baseline outcomes: low=passed, high=passed}" "No-impact evidence claiming differential outcomes" none
assert_rejected "$none_impact_body
- Live verification target: not required" "No-impact evidence duplicating a current-schema field" none
assert_rejected "$none_impact_body
- No credential, private provider value, model identity, or gateway response body retained." "No-impact evidence duplicating the retention boundary" none
assert_rejected "$none_impact_body
- Trust boundary: local execution attests secret-backed exact identity comparisons; GitHub verifies retained exact-head non-sensitive assertions only." "No-impact evidence duplicating the trust boundary" none

echo "Live-evidence policy regression tests passed."
