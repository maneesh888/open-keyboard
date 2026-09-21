#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BOOTSTRAP="$ROOT/scripts/live-policy-bootstrap.sh"
VALIDATOR="$ROOT/scripts/validate-pr-live-evidence.sh"
WORKFLOW="$ROOT/.github/workflows/live.yml"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT
source "$BOOTSTRAP"

assert_resolution() {
  local trusted_schema="$1"
  local trusted_supports="$2"
  local trusted_impact="$3"
  local candidate_impact="$4"
  local expected_impact="$5"
  local expected_bootstrap="$6"

  OPEN_KEYBOARD_TRUSTED_REDACTED_LIVE_EVIDENCE_SCHEMA="$trusted_schema"
  openkeyboard_resolve_live_policy_bootstrap \
    "$trusted_supports" \
    "$trusted_impact" \
    "$candidate_impact"
  unset OPEN_KEYBOARD_TRUSTED_REDACTED_LIVE_EVIDENCE_SCHEMA
  if [[ "$OPEN_KEYBOARD_RESOLVED_LIVE_IMPACT" != "$expected_impact" || \
        "$OPEN_KEYBOARD_BOOTSTRAP_DIFFERENTIAL" != "$expected_bootstrap" ]]; then
    echo "Live-policy bootstrap resolution produced an unsafe result." >&2
    exit 1
  fi
}

assert_resolution false false gateway gateway-differential gateway-differential true
assert_resolution false true gateway-differential gateway-differential gateway-differential true
assert_resolution false true gateway gateway gateway true
assert_resolution true true gateway-differential gateway-differential gateway-differential false
assert_resolution true true gateway gateway-differential gateway false
assert_resolution false false none gateway-differential none false
if OPEN_KEYBOARD_TRUSTED_REDACTED_LIVE_EVIDENCE_SCHEMA=true \
    openkeyboard_resolve_live_policy_bootstrap false gateway invalid >/dev/null 2>&1; then
  echo "An invalid candidate live-impact classification was accepted." >&2
  exit 1
fi

HEAD_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BODY_FILE="$FIXTURE/differential.md"
PROJECTION_FILE="$FIXTURE/trusted-projection.md"
PROVIDER_BINDINGS='openai=true, anthropic=true, openrouter=true, gateway=true'
PROVIDER_OUTCOMES='openai=passed, anthropic=passed, openrouter=passed, gateway=passed'
cat > "$BODY_FILE" <<EOF
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
EOF

HEAD_SHA="$HEAD_SHA" LIVE_IMPACT=gateway-differential PR_BODY="$(< "$BODY_FILE")" \
  "$VALIDATOR" >/dev/null

TRUSTED_LIVE_IMPACT=gateway-differential \
  openkeyboard_write_trusted_gateway_projection "$BODY_FILE" "$HEAD_SHA" "$PROJECTION_FILE"
if ! grep -Fxq -- '- Live verification target: gateway-differential' "$PROJECTION_FILE" || \
    ! grep -Fxq -- '- Required live models: low=locally-verified-low-role, high=locally-verified-high-role' "$PROJECTION_FILE" || \
    ! grep -Fxq -- '- Exact live-tested models: low=locally-verified-low-role, high=locally-verified-high-role' "$PROJECTION_FILE" || \
    ! grep -Fxq -- '- Live profile latencies: low=0.000s, high=0.000s' "$PROJECTION_FILE"; then
  echo "The trusted differential projection is malformed." >&2
  exit 1
fi
if grep -Eq -- 'private-model|low-test-model|high-test-model|hmac|commitment' "$PROJECTION_FILE"; then
  echo "The trusted projection retained a private identity or opaque commitment." >&2
  exit 1
fi
projection_mode="$(stat -f '%Lp' "$PROJECTION_FILE" 2>/dev/null || stat -c '%a' "$PROJECTION_FILE")"
if (( (8#$projection_mode & 077) != 0 )); then
  echo "The trusted projection is not mode 600-equivalent." >&2
  exit 1
fi

TRUSTED_LIVE_IMPACT=gateway \
  openkeyboard_write_trusted_gateway_projection "$BODY_FILE" "$HEAD_SHA" "$PROJECTION_FILE"
if ! grep -Fxq -- '- Live verification target: gateway' "$PROJECTION_FILE" || \
    ! grep -Fxq -- '- Required live models: locally-verified-exact-model' "$PROJECTION_FILE" || \
    ! grep -Fxq -- '- Exact live-tested models: locally-verified-exact-model' "$PROJECTION_FILE"; then
  echo "The trusted ordinary-gateway projection is malformed." >&2
  exit 1
fi

assert_projection_rejected() {
  local input_file="$1"
  local description="$2"

  if TRUSTED_LIVE_IMPACT=gateway-differential \
      openkeyboard_write_trusted_gateway_projection \
        "$input_file" "$HEAD_SHA" "$PROJECTION_FILE" >/dev/null 2>&1; then
    echo "$description was accepted by trusted projection." >&2
    exit 1
  fi
}

INVALID_FILE="$FIXTURE/invalid.md"
sed 's/Live model identity matches: low=true, high=true/Live model identity matches: high=true, low=true/' \
  "$BODY_FILE" > "$INVALID_FILE"
assert_projection_rejected "$INVALID_FILE" "Reversed identity roles"
sed 's/Live model role distinctness: true/Live model role distinctness: false/' \
  "$BODY_FILE" > "$INVALID_FILE"
assert_projection_rejected "$INVALID_FILE" "Non-distinct roles"
sed "s/Live provider exact bindings: $PROVIDER_BINDINGS/Live provider exact bindings: openai=true, anthropic=false, openrouter=true, gateway=true/" \
  "$BODY_FILE" > "$INVALID_FILE"
assert_projection_rejected "$INVALID_FILE" "A false provider binding"
sed "s/Live provider exact bindings: $PROVIDER_BINDINGS/Live provider exact bindings: anthropic=true, openai=true, openrouter=true, gateway=true/" \
  "$BODY_FILE" > "$INVALID_FILE"
assert_projection_rejected "$INVALID_FILE" "Reordered provider bindings"
cp "$BODY_FILE" "$INVALID_FILE"
printf '%s\n' "- Live provider exact bindings: $PROVIDER_BINDINGS" >> "$INVALID_FILE"
assert_projection_rejected "$INVALID_FILE" "Duplicate provider bindings"
cp "$BODY_FILE" "$INVALID_FILE"
printf '%s\n' '- Live profile latencies: low=1.000s, high=2.000s' >> "$INVALID_FILE"
assert_projection_rejected "$INVALID_FILE" "Retained candidate timing evidence"

# Exercise the unchanged workflow's bootstrap path with a candidate validator and a trusted
# legacy validator. The mock accepts only the fixed, non-sensitive legacy projection.
LEGACY_ROOT="$FIXTURE/legacy-validators"
mkdir -p "$LEGACY_ROOT"
cat > "$LEGACY_ROOT/validate-pr-live-evidence.sh" <<'LEGACY_VALIDATOR'
#!/usr/bin/env bash
set -euo pipefail
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]]
grep -Fxq -- "- Exact live-tested head: $HEAD_SHA" <<< "$PR_BODY"
case "$LIVE_IMPACT" in
  gateway)
    grep -Fxq -- '- Live verification target: gateway' <<< "$PR_BODY"
    grep -Fxq -- '- Required live models: locally-verified-exact-model' <<< "$PR_BODY"
    grep -Fxq -- '- Exact live-tested models: locally-verified-exact-model' <<< "$PR_BODY"
    grep -Fxq -- '- Live profile latencies: not required' <<< "$PR_BODY"
    ;;
  gateway-differential)
    grep -Fxq -- '- Live verification target: gateway-differential' <<< "$PR_BODY"
    grep -Fxq -- '- Required live models: low=locally-verified-low-role, high=locally-verified-high-role' <<< "$PR_BODY"
    grep -Fxq -- '- Exact live-tested models: low=locally-verified-low-role, high=locally-verified-high-role' <<< "$PR_BODY"
    grep -Fxq -- '- Live profile latencies: low=0.000s, high=0.000s' <<< "$PR_BODY"
    ;;
  *) exit 1 ;;
esac
LEGACY_VALIDATOR
chmod +x "$LEGACY_ROOT/validate-pr-live-evidence.sh"

ENFORCER="$FIXTURE/enforce-live-snapshots.sh"
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
cp "$BODY_FILE" "$FIXTURE/event.md"
cp "$BODY_FILE" "$FIXTURE/current.md"
CURRENT_BODY_FILE="$FIXTURE/current.md" \
EVENT_BODY_FILE="$FIXTURE/event.md" \
EVENT_HEAD_SHA="$HEAD_SHA" \
GITHUB_WORKSPACE="$ROOT" \
LIVE_IMPACT=gateway-differential \
LIVE_POLICY_BOOTSTRAP_DIFFERENTIAL=true \
RUNNER_TEMP="$FIXTURE" \
TRUSTED_LIVE_IMPACT=gateway-differential \
VALIDATOR_ROOT="$LEGACY_ROOT" \
  bash -e -o pipefail "$ENFORCER" >/dev/null

# The unchanged workflow also enters the same historically named branch when the trusted base
# understands an ordinary gateway impact but not the new redacted evidence schema. Fail closed in
# that bridge: the candidate must still provide differential evidence, which can then be projected
# to the fixed, non-secret ordinary-gateway schema expected by the legacy validator.
ORDINARY_BODY_FILE="$FIXTURE/gateway.md"
sed \
  -e 's/Live verification target: gateway-differential/Live verification target: gateway/' \
  -e 's/Live model identity matches: low=true, high=true/Live model identity matches: reference=true/' \
  -e 's/Live model role distinctness: true/Live model role distinctness: not required/' \
  -e 's/Live summarize outcomes: low=passed, high=passed/Live summarize outcomes: not required/' \
  -e 's/Live continue-writing outcomes: low=passed, high=passed/Live continue-writing outcomes: not required/' \
  -e 's/Live baseline outcomes: low=passed, high=passed/Live baseline outcomes: not required/' \
  -e 's/Live differential outcomes: low=expected-model-capability, high=passed/Live differential outcomes: not required/' \
  -e 's/Live follow-up outcomes: low=passed, high=passed/Live follow-up outcomes: not required/' \
  -e 's/Live operation-scoped warning contracts: verified/Live operation-scoped warning contracts: not required/' \
  "$BODY_FILE" > "$ORDINARY_BODY_FILE"
cp "$ORDINARY_BODY_FILE" "$FIXTURE/event.md"
cp "$ORDINARY_BODY_FILE" "$FIXTURE/current.md"
if CURRENT_BODY_FILE="$FIXTURE/current.md" \
    EVENT_BODY_FILE="$FIXTURE/event.md" \
    EVENT_HEAD_SHA="$HEAD_SHA" \
    GITHUB_WORKSPACE="$ROOT" \
    LIVE_IMPACT=gateway-differential \
    LIVE_POLICY_BOOTSTRAP_DIFFERENTIAL=true \
    RUNNER_TEMP="$FIXTURE" \
    TRUSTED_LIVE_IMPACT=gateway \
    VALIDATOR_ROOT="$LEGACY_ROOT" \
      bash -e -o pipefail "$ENFORCER" >/dev/null 2>&1; then
  echo "The schema bootstrap accepted ordinary gateway evidence as a differential record." >&2
  exit 1
fi

cp "$BODY_FILE" "$FIXTURE/event.md"
cp "$BODY_FILE" "$FIXTURE/current.md"
CURRENT_BODY_FILE="$FIXTURE/current.md" \
EVENT_BODY_FILE="$FIXTURE/event.md" \
EVENT_HEAD_SHA="$HEAD_SHA" \
GITHUB_WORKSPACE="$ROOT" \
LIVE_IMPACT=gateway-differential \
LIVE_POLICY_BOOTSTRAP_DIFFERENTIAL=true \
RUNNER_TEMP="$FIXTURE" \
TRUSTED_LIVE_IMPACT=gateway \
VALIDATOR_ROOT="$LEGACY_ROOT" \
  bash -e -o pipefail "$ENFORCER" >/dev/null

TRAP_PROJECTION_FILE="$FIXTURE/trap-cleaned-projection.md"
BOOTSTRAP_PATH="$BOOTSTRAP" BODY_FILE="$BODY_FILE" HEAD_SHA="$HEAD_SHA" \
TRAP_PROJECTION_FILE="$TRAP_PROJECTION_FILE" bash -e -o pipefail -c '
  source "$BOOTSTRAP_PATH"
  TRUSTED_LIVE_IMPACT=gateway-differential \
    openkeyboard_write_trusted_gateway_projection \
      "$BODY_FILE" "$HEAD_SHA" "$TRAP_PROJECTION_FILE"
  [[ -f "$TRAP_PROJECTION_FILE" ]]
'
if [[ -e "$TRAP_PROJECTION_FILE" ]]; then
  echo "The temporary trusted projection was not trap-cleaned." >&2
  exit 1
fi

echo "Live-policy bootstrap tests passed."
