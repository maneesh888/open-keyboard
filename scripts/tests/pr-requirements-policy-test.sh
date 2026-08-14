#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-pr-requirements.sh"
HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
STALE_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
PR_URL="https://github.com/maneesh888/open-keyboard/pull/123"
HUMAN_EVIDENCE="explicit repository-owner approval for this exact head in the active Codex task"
exact_head_line="$(printf '`%s`' "$HEAD_SHA")"

automatic_body="$(cat <<EOF
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
- Reviewer confidence: 100%
- Merge recommendation: automatic

## Merge authorization

- Merge authorization route: automatic
- Human approval status: not-required
- Human-approved head: not-required
- Human approval evidence: not-required

## Exact head SHA

$exact_head_line
EOF
)"

human_body="$(cat <<EOF
## Requirements and proof

| ID | Requirement and source | Observable acceptance | Required proof | Exact evidence | Status |
| --- | --- | --- | --- | --- | --- |
| R1 | Exact model behavior | Exact model succeeds | Live exact-model test | exact-head run | VERIFIED |
| R2 | Parser behavior | Cards parse | Deterministic test | No independently inspectable result | UNVERIFIED |

- Requirement count: 2
- Verified requirement count: 1
- Unverified in-scope requirements: R2
- Authorized out-of-scope items: none

## Independent review

- Exact reviewed head: $HEAD_SHA
- Review requirement coverage: 2/2
- Review unverified requirements: R2
- Blocking findings: R2 lacks independently inspectable proof
- Independent review evidence: $PR_URL#pullrequestreview-456
- Reviewer confidence: below 100%
- Merge recommendation: human-review-required

## Merge authorization

- Merge authorization route: human
- Human approval status: approved
- Human-approved head: $HEAD_SHA
- Human approval evidence: $HUMAN_EVIDENCE

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

run_validator "$automatic_body"
run_validator "$human_body"

expect_rejected "an unverified automatic-route table row" "${automatic_body/| R2 | Parser behavior | Cards parse | Deterministic test | test name | VERIFIED |/| R2 | Parser behavior | Cards parse | Deterministic test | no result | UNVERIFIED |}"
expect_rejected "pending evidence marked verified" "${automatic_body/| R2 | Parser behavior | Cards parse | Deterministic test | test name | VERIFIED |/| R2 | Parser behavior | Cards parse | Deterministic test | pending | VERIFIED |}"
expect_rejected "a missing acceptance criterion" "${automatic_body/| R2 | Parser behavior | Cards parse | Deterministic test | test name | VERIFIED |/| R2 | Parser behavior |  | Deterministic test | test name | VERIFIED |}"
expect_rejected "a false verified count" "${automatic_body/Verified requirement count: 2/Verified requirement count: 1}"
expect_rejected "an unverified requirement list inconsistent with the table" "${automatic_body/Unverified in-scope requirements: none/Unverified in-scope requirements: R2}"
expect_rejected "a stale reviewed head" "${automatic_body/Exact reviewed head: $HEAD_SHA/Exact reviewed head: $STALE_SHA}"
expect_rejected "incomplete review coverage" "${automatic_body/Review requirement coverage: 2\/2/Review requirement coverage: 1\/2}"
expect_rejected "a pending independent review" "${automatic_body/Independent review evidence: $PR_URL#pullrequestreview-456/Independent review evidence: pending}"
expect_rejected "an unrelated review link" "${automatic_body/Independent review evidence: $PR_URL#pullrequestreview-456/Independent review evidence: https:\/\/github.com\/other\/repo\/pull\/1#pullrequestreview-9}"
expect_rejected "automatic authorization below 100% reviewer confidence" "${automatic_body/Reviewer confidence: 100%/Reviewer confidence: below 100%}"
expect_rejected "automatic authorization that claims human approval" "${automatic_body/Human approval status: not-required/Human approval status: approved}"
expect_rejected "human authorization without explicit approval" "${human_body/Human approval status: approved/Human approval status: pending}"
expect_rejected "human authorization for a stale head" "${human_body/Human-approved head: $HEAD_SHA/Human-approved head: $STALE_SHA}"
expect_rejected "human authorization without the exact owner evidence phrase" "${human_body/Human approval evidence: $HUMAN_EVIDENCE/Human approval evidence: someone approved}"
expect_rejected "a human route paired with a 100% reviewer" "${human_body/Reviewer confidence: below 100%/Reviewer confidence: 100%}"
expect_rejected "duplicate requirement count fields" "$automatic_body
- Requirement count: 2"

echo "Pull-request requirement policy regression tests passed."
