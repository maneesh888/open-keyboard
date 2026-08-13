#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-pr-requirements.sh"
HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
PR_URL="https://github.com/maneesh888/open-keyboard/pull/123"
exact_head_line="$(printf '`%s`' "$HEAD_SHA")"

valid_body="$(cat <<EOF
## Requirements and proof

| ID | Requirement and source | Observable acceptance | Required proof | Exact evidence | Status |
| --- | --- | --- | --- | --- | --- |
| R1 | Exact model behavior | Exact model succeeds | Live exact-model test | exact-head run | VERIFIED |
| R2 | Parser behavior | Cards parse | Deterministic test | test name | VERIFIED |

- Requirement count: 2
- Verified requirement count: 2
- Unverified in-scope requirements: none
- Authorized out-of-scope items: none

## Independent review

- Exact reviewed head: $HEAD_SHA
- Review requirement coverage: 2/2
- Review unverified requirements: none
- Blocking findings: none
- Independent review evidence: $PR_URL#pullrequestreview-456
- Reviewer confidence: requirements-complete

## Exact head SHA

$exact_head_line
EOF
)"

run_validator() {
  local body="$1"
  HEAD_SHA="$HEAD_SHA" PR_URL="$PR_URL" PR_BODY="$body" "$VALIDATOR" >/dev/null 2>&1
}

expect_rejected() {
  local description="$1"
  local body="$2"
  if run_validator "$body"; then
    echo "Requirement policy accepted $description." >&2
    exit 1
  fi
}

run_validator "$valid_body"
expect_rejected "an unverified table row" "${valid_body/| R2 | Parser behavior | Cards parse | Deterministic test | test name | VERIFIED |/| R2 | Parser behavior | Cards parse | Deterministic test | pending | UNVERIFIED |}"
expect_rejected "pending evidence marked verified" "${valid_body/| R2 | Parser behavior | Cards parse | Deterministic test | test name | VERIFIED |/| R2 | Parser behavior | Cards parse | Deterministic test | pending | VERIFIED |}"
expect_rejected "a missing acceptance criterion" "${valid_body/| R2 | Parser behavior | Cards parse | Deterministic test | test name | VERIFIED |/| R2 | Parser behavior |  | Deterministic test | test name | VERIFIED |}"
expect_rejected "a false verified count" "${valid_body/Verified requirement count: 2/Verified requirement count: 1}"
expect_rejected "an unverified requirement list" "${valid_body/Unverified in-scope requirements: none/Unverified in-scope requirements: R2}"
expect_rejected "a stale reviewed head" "${valid_body/Exact reviewed head: $HEAD_SHA/Exact reviewed head: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}"
expect_rejected "incomplete review coverage" "${valid_body/Review requirement coverage: 2\/2/Review requirement coverage: 1\/2}"
expect_rejected "a pending independent review" "${valid_body/Independent review evidence: $PR_URL#pullrequestreview-456/Independent review evidence: pending}"
expect_rejected "an unrelated review link" "${valid_body/Independent review evidence: $PR_URL#pullrequestreview-456/Independent review evidence: https:\/\/github.com\/other\/repo\/pull\/1#pullrequestreview-9}"
expect_rejected "duplicate requirement count fields" "$valid_body
- Requirement count: 2"

echo "Pull-request requirement policy regression tests passed."
