#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Hooks export repository-local Git state; fixtures must not inherit it.
while IFS= read -r git_environment_name; do
  unset "$git_environment_name"
done < <(git -C "$ROOT" rev-parse --local-env-vars)
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT
source "$ROOT/scripts/live-policy-bootstrap.sh"
# This immutable base is the migration source, not the mutable origin/main ref.
LEGACY_BASE=6619f0bb1f3aa8306a4b1dc94b2fdd514ee1f6f6
HEAD_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BODY="$FIXTURE/body.md"
cat > "$BODY" <<EVIDENCE
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
EVIDENCE
openkeyboard_prepare_live_validators "$LEGACY_BASE" "$FIXTURE/validators" "$ROOT"
openkeyboard_validate_live_snapshot "$BODY" "$HEAD_SHA" gateway-differential "$FIXTURE/validators"
# Check exactly what changed in the trusted source: only the explicit withheld timing alternative.
git -C "$ROOT" show "$LEGACY_BASE:scripts/validate-pr-live-evidence.sh" > "$FIXTURE/legacy.sh"
python3 - "$FIXTURE/legacy.sh" "$FIXTURE/validators/validate-pr-live-evidence.sh" <<'PY'
import pathlib, sys
old, new = map(lambda p: pathlib.Path(p).read_text(), sys.argv[1:])
needle = '! "$live_profile_latencies" =~ ^low=[0-9]+([.][0-9]{3})?s,\\ high=[0-9]+([.][0-9]{3})?s$'
assert new == old.replace(needle, '( "$live_profile_latencies" != "withheld" && ' + needle + ' )')
assert '0.000s' not in new
PY
for mutation in stale swapped missing substituted outcome exposure; do
  cp "$BODY" "$FIXTURE/invalid.md"
  case "$mutation" in
    stale) sed -i.bak "s/$HEAD_SHA/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/" "$FIXTURE/invalid.md" ;;
    swapped) sed -i.bak 's/low=true, high=true/high=true, low=true/' "$FIXTURE/invalid.md" ;;
    missing) sed -i.bak '/Live baseline outcomes/d' "$FIXTURE/invalid.md" ;;
    substituted) sed -i.bak 's/low=true, high=true/low=true, high=false/' "$FIXTURE/invalid.md" ;;
    outcome) sed -i.bak 's/low=expected-model-capability/low=passed/' "$FIXTURE/invalid.md" ;;
    exposure) printf '%s\n' '- Required live models: private-model-sentinel' >> "$FIXTURE/invalid.md" ;;
  esac
  if openkeyboard_validate_live_snapshot "$FIXTURE/invalid.md" "$HEAD_SHA" gateway-differential "$FIXTURE/validators" > "$FIXTURE/output" 2>&1; then
    echo "Legacy migration accepted invalid evidence: $mutation" >&2; exit 1
  fi
done
# Once main speaks the schema, use its validator directly. No candidate parser or migration.
mkdir -p "$FIXTURE/modern"
cp "$ROOT/scripts/validate-pr-live-evidence.sh" "$FIXTURE/modern/validate-pr-live-evidence.sh"
openkeyboard_validate_live_snapshot "$BODY" "$HEAD_SHA" gateway-differential "$FIXTURE/modern"
# Unknown legacy source must not silently acquire a candidate validator.
mkdir -p "$FIXTURE/repo/scripts"
git -C "$FIXTURE/repo" init -q
git -C "$FIXTURE/repo" config user.name Fixture
git -C "$FIXTURE/repo" config user.email fixture@example.invalid
printf '#!/bin/bash\nexit 0\n' > "$FIXTURE/repo/scripts/validate-pr-live-evidence.sh"
cp "$ROOT/scripts/live-impact.sh" "$FIXTURE/repo/scripts/live-impact.sh"
git -C "$FIXTURE/repo" add .
git -C "$FIXTURE/repo" -c core.hooksPath=/dev/null commit -qm fixture
if openkeyboard_prepare_live_validators HEAD "$FIXTURE/unknown" "$FIXTURE/repo" >/dev/null 2>&1; then
  echo "Unknown legacy validator was accepted." >&2; exit 1
fi
echo "Live-policy bootstrap tests passed."
