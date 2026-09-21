#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Hooks export repository-local Git state; fixtures must not inherit it.
while IFS= read -r git_environment_name; do
  unset "$git_environment_name"
done < <(git -C "$ROOT" rev-parse --local-env-vars)
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT
REPO="$FIXTURE/repo"
mkdir -p "$REPO/scripts/ios" "$REPO/.agent/local-seeds"
cp "$ROOT/scripts/check-live.sh" "$REPO/scripts/"
cp "$ROOT/scripts/ios/live-test-safety.sh" "$REPO/scripts/ios/"
printf '#!/bin/bash\necho gateway\n' > "$REPO/scripts/live-impact.sh"
chmod +x "$REPO/scripts/live-impact.sh"
printf '.agent/\n' > "$REPO/.gitignore"
cat > "$REPO/.agent/local-seeds/openkeyboard-gateway.env" <<'SEED'
OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL=https://private.invalid
OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY=credential-sentinel
OPEN_KEYBOARD_SIMULATOR_LOW_MODEL=low-identity-sentinel
OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL=https://private.invalid
OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY=credential-sentinel
OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL=high-identity-sentinel
SEED
chmod 600 "$REPO/.agent/local-seeds/openkeyboard-gateway.env"
# Mock only the expensive XCTest process. The gate and guarded seed/identity validation are real.
cat > "$REPO/scripts/ios/test.sh" <<'MOCK'
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[[ "$1" != core ]] || exit 0
if [[ "$1" == live-gateway-smoke ]]; then
  if [[ "$(cat "$ROOT/.agent/scenario")" == substituted ]]; then
    printf 'model=substituted-identity-sentinel\n' > "$OPEN_KEYBOARD_LIVE_REFERENCE_EVIDENCE_OUTPUT"
  else
    printf 'model=high-identity-sentinel\n' > "$OPEN_KEYBOARD_LIVE_REFERENCE_EVIDENCE_OUTPUT"
  fi
  exit 0
fi
cat > "$OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT" <<'EVIDENCE'
models=low=low-identity-sentinel, high=high-identity-sentinel
baseline_outcomes=low=passed, high=passed
differential_outcomes=low=expected-model-capability, high=passed
follow_up_outcomes=low=passed, high=passed
summarize_outcomes=low=passed, high=passed
continue_writing_outcomes=low=passed, high=passed
operation_scoped_warning_contracts=verified
profile_latencies=low=12.345s, high=23.456s
diagnostic_outcomes_low=transport=passed, grammar=passed, rewrite=passed, translation=passed
diagnostic_latencies_low=transport=1ms, grammar=2ms, rewrite=3ms, translation=4ms
diagnostic_outcomes_high=transport=passed, grammar=passed, rewrite=passed, translation=passed
diagnostic_latencies_high=transport=1ms, grammar=2ms, rewrite=3ms, translation=4ms
EVIDENCE
case "$(cat "$ROOT/.agent/scenario")" in
  substituted) sed -i.bak 's/high-identity-sentinel/substituted-identity-sentinel/' "$OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT" ;;
  swapped) sed -i.bak 's/models=.*/models=low=high-identity-sentinel, high=low-identity-sentinel/' "$OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT" ;;
  missing) sed -i.bak '/follow_up_outcomes/d' "$OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT" ;;
  outcome) sed -i.bak 's/low=expected-model-capability/low=passed/' "$OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT" ;;
  extra) printf 'prompt=private-text-sentinel\n' >> "$OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT" ;;
  duplicate) printf 'models=low=low-identity-sentinel, high=high-identity-sentinel\n' >> "$OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT" ;;
esac
rm -f "$OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT.bak"
MOCK
chmod +x "$REPO/scripts/ios/test.sh"
git -C "$REPO" init -q
git -C "$REPO" config user.name Fixture
git -C "$REPO" config user.email fixture@example.invalid
git -C "$REPO" add .
git -C "$REPO" -c core.hooksPath=/dev/null commit -qm fixture
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
run_gate() {
  env -u OPEN_KEYBOARD_LIVE_REQUIRED_MODEL -u OPEN_KEYBOARD_LIVE_REQUIRED_MODELS \
    -u OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE "$@" \
    bash -ax "$REPO/scripts/check-live.sh" "${GATE_TARGET:-gateway-differential}" > "$FIXTURE/output" 2>&1
}
assert_private() {
  if grep -Eq 'sentinel|private.invalid|12.345s|23.456s' "$FIXTURE/output"; then
    echo "Private runner values escaped into output." >&2; exit 1
  fi
}
printf valid > "$REPO/.agent/scenario"
run_gate
assert_private
grep -q 'model_identity_matches=low=true, high=true' "$FIXTURE/output"
for scenario in substituted swapped missing outcome extra duplicate; do
  printf '%s' "$scenario" > "$REPO/.agent/scenario"
  if run_gate; then echo "Invalid private evidence accepted: $scenario" >&2; exit 1; fi
  assert_private
done
printf valid > "$REPO/.agent/scenario"
for requirement in \
  'low=high-identity-sentinel, high=low-identity-sentinel' \
  'low=low-identity-sentinel, high=substituted-identity-sentinel' \
  'low=low-identity-sentinel' \
  ''; do
  if run_gate "OPEN_KEYBOARD_LIVE_REQUIRED_MODELS=$requirement"; then
    echo "Invalid exact model requirement accepted." >&2; exit 1
  fi
  assert_private
done
if run_gate OPEN_KEYBOARD_LIVE_REQUIRED_MODEL=identity-sentinel; then
  echo "Single-model requirement silently discarded by differential target." >&2; exit 1
fi
assert_private
if run_gate OPEN_KEYBOARD_LIVE_EXPECTED_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; then
  echo "Stale local head accepted." >&2; exit 1
fi
assert_private
GATE_TARGET=gateway
printf valid > "$REPO/.agent/scenario"
run_gate
assert_private
grep -q 'model_identity_matches=reference=true' "$FIXTURE/output"
run_gate OPEN_KEYBOARD_LIVE_REQUIRED_MODEL=high-identity-sentinel
assert_private
for requirement in wrong-identity-sentinel model-agnostic ''; do
  if run_gate "OPEN_KEYBOARD_LIVE_REQUIRED_MODEL=$requirement"; then
    echo "Ordinary gate accepted an invalid explicit identity requirement." >&2; exit 1
  fi
  assert_private
done
printf substituted > "$REPO/.agent/scenario"
if run_gate; then echo "Ordinary gate accepted a substituted runtime identity." >&2; exit 1; fi
assert_private
# Direct real runner source must keep identity IPC off stdout and withhold live XCTest output.
python3 - "$ROOT/scripts/ios/test.sh" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text()
assert 'printf \'%s\\n\' "$evidence_lines"\n' not in s
assert '"$@" > "$live_log" 2>&1' in s
assert 'openkeyboard_require_exact_live_model "$OPEN_KEYBOARD_SIMULATOR_MODEL" "$low_model"' in s
assert 'openkeyboard_require_exact_live_model "$OPEN_KEYBOARD_SIMULATOR_MODEL" "$high_model"' in s
PY
echo "Private live-runner regression tests passed (mock XCTest)."
