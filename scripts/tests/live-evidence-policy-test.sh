#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Hooks export repository-local Git state; fixtures must not inherit it.
while IFS= read -r git_environment_name; do
  unset "$git_environment_name"
done < <(git -C "$ROOT" rev-parse --local-env-vars)
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
mkdir -p "$MOCK_BIN" "$FIXTURE/validators"
cp "$ROOT/scripts/live-policy-bootstrap.sh" "$FIXTURE/validators/bootstrap.sh"
cp "$VALIDATOR" "$FIXTURE/validators/validate-pr-live-evidence.sh"

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
- Live model requirement: exact
- Live model identity matches: reference=true
- Live model role distinctness: not required
- Live-model substitutions: none
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
wrong_model_body="${valid_body/reference=true/reference=false}"
substituted_model_body="${valid_body/Live-model substitutions: none/Live-model substitutions: reference-test-model -> substituted-test-model}"
duplicate_models_body="$valid_body
- Live model identity matches: reference=true"
model_agnostic_body="${valid_body/Live model requirement: exact/Live model requirement: model-agnostic}"
model_agnostic_unverified_body="${model_agnostic_body/Live plain-text grammar verification: verified/Live plain-text grammar verification: unverified}"
exact_model_unverified_body="${valid_body/Live plain-text grammar verification: verified/Live plain-text grammar verification: unverified}"
invalid_verification_body="${valid_body/Live plain-text grammar verification: verified/Live plain-text grammar verification: unknown}"
duplicate_verification_body="$valid_body
- Live plain-text grammar verification: verified"

differential_body="$(cat <<EOF
- Local live verification: passed
- Live verification target: gateway-differential
- Exact live-tested head: $HEAD_SHA
- Live model requirement: exact
- Live model identity matches: low=true, high=true
- Live model role distinctness: true
- Live-model substitutions: none
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
missing_profile_body="${differential_body/low=true, high=true/low=true}"
reversed_profile_body="${differential_body/low=true, high=true/high=true, low=true}"
substituted_profile_body="${differential_body/low=true, high=true/low=true, high=false}"
same_profile_body="${differential_body/Live model role distinctness: true/Live model role distinctness: false}"
low_success_body="${differential_body/Live differential outcomes: low=expected-model-capability, high=passed/Live differential outcomes: low=passed, high=passed}"
high_failure_body="${differential_body/Live differential outcomes: low=expected-model-capability, high=passed/Live differential outcomes: low=expected-model-capability, high=expected-model-capability}"
missing_baseline_body="${differential_body/- Live baseline outcomes: low=passed, high=passed/}"
missing_summarize_body="${differential_body/- Live summarize outcomes: low=passed, high=passed/}"
failed_continue_body="${differential_body/Live continue-writing outcomes: low=passed, high=passed/Live continue-writing outcomes: low=passed, high=failed}"
unverified_warning_body="${differential_body/Live operation-scoped warning contracts: verified/Live operation-scoped warning contracts: unverified}"
malformed_latency_body="$differential_body
- Live profile latencies: low=12.345s, high=23.456s"

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
    VALIDATOR_ROOT="$FIXTURE/validators" \
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
if run_policy "$missing_summarize_body" gateway-differential; then
  echo "Missing differential Summarize evidence was accepted." >&2
  exit 1
fi
if run_policy "$failed_continue_body" gateway-differential; then
  echo "Failed differential Continue Writing evidence was accepted." >&2
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

# Privacy and completeness failures are rejected without echoing the supplied value.
for extra in \
  '- Required live models: private-model-sentinel' \
  '- Exact live-tested models: private-model-sentinel' \
  '- Live model commitment: model-hash-sentinel' \
  '- Live endpoint: https://private.invalid' \
  '- Live credential: private-credential-sentinel' \
  '- Live prompt: private-prompt-sentinel' \
  '- Live response: private-response-sentinel'; do
  if run_policy "$differential_body
$extra" gateway-differential; then
    echo "Prohibited public evidence was accepted." >&2; exit 1
  fi
  if grep -q 'sentinel' "$OUTPUT"; then
    echo "Validator echoed private evidence." >&2; exit 1
  fi
done
if run_policy "## Live gateway evidence
private-prompt-sentinel
$differential_body" gateway-differential; then
  echo "Unstructured live-section payload was accepted." >&2; exit 1
fi
for line in $(seq 1 16); do
  incomplete_body="$(printf '%s\n' "$differential_body" | sed "${line}d")"
  if run_policy "$incomplete_body" gateway-differential; then
    echo "Incomplete public assertion record passed." >&2; exit 1
  fi
done

if ! LIVE_IMPACT=none \
  HEAD_SHA="$HEAD_SHA" \
  PR_BODY="" \
  "$VALIDATOR" > "$OUTPUT" 2>&1; then
  echo "A no-impact pull request unexpectedly required live evidence." >&2
  exit 1
fi

# The actual tracked connector dependency makes provider coverage mandatory, without a skip flag.
mkdir -p "$FIXTURE/provider-repo"
git -C "$FIXTURE/provider-repo" init -q
git -C "$FIXTURE/provider-repo" config user.name Fixture
git -C "$FIXTURE/provider-repo" config user.email fixture@example.invalid
git -C "$FIXTURE/provider-repo" -c core.hooksPath=/dev/null commit --allow-empty -qm base
provider_base="$(git -C "$FIXTURE/provider-repo" rev-parse HEAD)"
git -C "$FIXTURE/provider-repo" update-index --add --cacheinfo "160000,$provider_base,Vendor/universal-ai-connector"
git -C "$FIXTURE/provider-repo" -c core.hooksPath=/dev/null commit -qm connector
provider_head="$(git -C "$FIXTURE/provider-repo" rev-parse HEAD)"
provider_body="${differential_body//$HEAD_SHA/$provider_head}"
(
  cd "$FIXTURE/provider-repo"
  HEAD_SHA="$provider_head"
  if run_policy "$provider_body" gateway-differential; then
    echo "Connector head skipped required provider evidence." >&2; exit 1
  fi
  provider_body="$provider_body
- Live provider exact bindings: openai=true, anthropic=true, openrouter=true, gateway=true
- Live provider Test Connection outcomes: openai=passed, anthropic=passed, openrouter=passed, gateway=passed
- Live provider diagnostic outcomes: openai=passed, anthropic=passed, openrouter=passed, gateway=passed"
  run_policy "$provider_body" gateway-differential
  for invalid_provider_body in \
    "${provider_body/openai=true/openai=false}" \
    "${provider_body/openai=passed/openai=failed}" \
    "${provider_body/openai=true, anthropic=true/anthropic=true, openai=true}" \
    "$provider_body
- Live provider exact bindings: openai=true, anthropic=true, openrouter=true, gateway=true"; do
    if run_policy "$invalid_provider_body" gateway-differential; then
      echo "Invalid provider contract passed." >&2; exit 1
    fi
  done
)

echo "Live-evidence policy regression tests passed."
