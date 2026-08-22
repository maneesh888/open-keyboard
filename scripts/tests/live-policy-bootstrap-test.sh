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
  local trusted_supports="$1"
  local trusted_impact="$2"
  local candidate_impact="$3"
  local expected_impact="$4"
  local expected_bootstrap="$5"

  openkeyboard_resolve_live_policy_bootstrap \
    "$trusted_supports" \
    "$trusted_impact" \
    "$candidate_impact"
  if [[ "$OPEN_KEYBOARD_RESOLVED_LIVE_IMPACT" != "$expected_impact" || \
        "$OPEN_KEYBOARD_BOOTSTRAP_DIFFERENTIAL" != "$expected_bootstrap" ]]; then
    echo "Live-policy bootstrap resolution produced an unsafe result." >&2
    exit 1
  fi
}

assert_resolution false gateway gateway-differential gateway-differential true
assert_resolution false gateway none gateway false
assert_resolution false gateway-differential none gateway-differential false
assert_resolution true gateway gateway-differential gateway false
assert_resolution false none gateway-differential none false
if openkeyboard_resolve_live_policy_bootstrap false gateway invalid >/dev/null 2>&1; then
  echo "An invalid candidate live-impact classification was accepted." >&2
  exit 1
fi

HEAD_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BODY_FILE="$FIXTURE/differential.md"
PROJECTION_FILE="$FIXTURE/trusted-gateway.md"
cat > "$BODY_FILE" <<EOF
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
EOF

HEAD_SHA="$HEAD_SHA" LIVE_IMPACT=gateway-differential PR_BODY="$(< "$BODY_FILE")" \
  "$VALIDATOR" >/dev/null
openkeyboard_write_trusted_gateway_projection "$BODY_FILE" "$HEAD_SHA" "$PROJECTION_FILE"
HEAD_SHA="$HEAD_SHA" LIVE_IMPACT=gateway PR_BODY="$(< "$PROJECTION_FILE")" \
  "$VALIDATOR" >/dev/null

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
TRUSTED_LIVE_IMPACT=gateway \
VALIDATOR_ROOT="$ROOT/scripts" \
  bash -e -o pipefail "$ENFORCER" >/dev/null

LOW_SUCCESS_FILE="$FIXTURE/low-success.md"
sed \
  's/Live differential outcomes: low=expected-model-capability, high=passed/Live differential outcomes: low=passed, high=passed/' \
  "$BODY_FILE" > "$LOW_SUCCESS_FILE"
if HEAD_SHA="$HEAD_SHA" LIVE_IMPACT=gateway-differential PR_BODY="$(< "$LOW_SUCCESS_FILE")" \
    "$VALIDATOR" >/dev/null 2>&1; then
  echo "Bootstrap validation accepted an invalid low-profile success boundary." >&2
  exit 1
fi

DUPLICATE_MODELS_FILE="$FIXTURE/duplicate-models.md"
cp "$BODY_FILE" "$DUPLICATE_MODELS_FILE"
printf '%s\n' '- Required live models: low=low-test-model:2b, high=high-test-model:120b' >> "$DUPLICATE_MODELS_FILE"
if openkeyboard_write_trusted_gateway_projection \
    "$DUPLICATE_MODELS_FILE" "$HEAD_SHA" "$PROJECTION_FILE" >/dev/null 2>&1; then
  echo "Trusted projection accepted duplicate model mappings." >&2
  exit 1
fi

REVERSED_MODELS_FILE="$FIXTURE/reversed-models.md"
sed \
  's/Exact live-tested models: low=low-test-model:2b, high=high-test-model:120b/Exact live-tested models: low=high-test-model:120b, high=low-test-model:2b/' \
  "$BODY_FILE" > "$REVERSED_MODELS_FILE"
if openkeyboard_write_trusted_gateway_projection \
    "$REVERSED_MODELS_FILE" "$HEAD_SHA" "$PROJECTION_FILE" >/dev/null 2>&1; then
  echo "Trusted projection accepted reversed or substituted model roles." >&2
  exit 1
fi

echo "Live-policy bootstrap tests passed."
