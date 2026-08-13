#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-pr-review-record.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
STALE_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
PR_URL="https://github.com/maneesh888/open-keyboard/pull/123"
PR_AUTHOR="implementer"
REVIEW_ID=456
REVIEWS_JSON_FILE="$FIXTURE/reviews.json"
CONTRIBUTORS_JSON_FILE="$FIXTURE/contributors.json"

PR_BODY="$(cat <<EOF
- Requirement count: 2
- Independent review evidence: $PR_URL#pullrequestreview-$REVIEW_ID

| ID | Requirement and source | Observable acceptance | Required proof | Exact evidence | Status |
| --- | --- | --- | --- | --- | --- |
| R1 | Exact model behavior | Exact model succeeds | Live exact-model test | exact-head run | VERIFIED |
| R2 | Parser behavior | Cards parse | Deterministic test | test name | VERIFIED |
EOF
)"
review_body="$(cat <<EOF
- Reviewer: project pr-reviewer (read-only, no inherited conversation)
- Exact reviewed head: $HEAD_SHA
- Review requirement coverage: 2/2
- Review unverified requirements: none
- Blocking findings: none
- Conclusion: requirements-complete

| ID | Observable acceptance | Required proof | Evidence inspected | Status | Independent assessment |
| --- | --- | --- | --- | --- | --- |
| R1 | Exact model succeeds | Live exact-model test | exact-head run | VERIFIED | Exact targeted test inspected. |
| R2 | Cards parse | Deterministic test | test name | VERIFIED | Exact live model evidence inspected. |
EOF
)"

jq -n '[{author:{login:"implementer"},committer:{login:"implementer"}}]' > "$CONTRIBUTORS_JSON_FILE"

write_reviews() {
  local review_head="$1"
  local approval_state="$2"
  local approval_head="$3"
  local independent_body="$4"
  jq -n \
    --argjson review_id "$REVIEW_ID" \
    --arg url "$PR_URL#pullrequestreview-$REVIEW_ID" \
    --arg review_head "$review_head" \
    --arg independent_body "$independent_body" \
    --arg approval_state "$approval_state" \
    --arg approval_head "$approval_head" \
    '[
      {id:$review_id, html_url:$url, commit_id:$review_head, state:"COMMENTED", body:$independent_body, submitted_at:"2026-08-14T00:00:00Z", user:{login:"implementer",type:"User"}},
      {id:900, html_url:"https://example.invalid/review/900", commit_id:$approval_head, state:$approval_state, body:"", submitted_at:"2026-08-14T00:01:00Z", user:{login:"maintainer",type:"User"}}
    ]' > "$REVIEWS_JSON_FILE"
}

run_validator() {
  HEAD_SHA="$HEAD_SHA" \
    PR_BODY="$PR_BODY" \
    PR_URL="$PR_URL" \
    PR_AUTHOR="$PR_AUTHOR" \
    REVIEWS_JSON_FILE="$REVIEWS_JSON_FILE" \
    CONTRIBUTORS_JSON_FILE="$CONTRIBUTORS_JSON_FILE" \
    "$VALIDATOR" >/dev/null 2>&1
}

expect_rejected() {
  local description="$1"
  if run_validator; then
    echo "Review-record policy accepted $description." >&2
    exit 1
  fi
}

write_reviews "$HEAD_SHA" APPROVED "$HEAD_SHA" "$review_body"
run_validator

write_reviews "$STALE_SHA" APPROVED "$HEAD_SHA" "$review_body"
expect_rejected "a stale independent review"
write_reviews "$HEAD_SHA" APPROVED "$STALE_SHA" "$review_body"
expect_rejected "a stale approval"
write_reviews "$HEAD_SHA" COMMENTED "$HEAD_SHA" "$review_body"
expect_rejected "no non-author approval"
write_reviews "$HEAD_SHA" CHANGES_REQUESTED "$HEAD_SHA" "$review_body"
expect_rejected "a current change request"
write_reviews "$HEAD_SHA" APPROVED "$HEAD_SHA" "${review_body/| R2 | Cards parse | Deterministic test | test name | VERIFIED | Exact live model evidence inspected. |/| R2 | Cards parse | Deterministic test | missing | UNVERIFIED | Exact live model evidence missing. |}"
expect_rejected "an unverified requirement in the independent report"
write_reviews "$HEAD_SHA" APPROVED "$HEAD_SHA" "${review_body/Exact reviewed head: $HEAD_SHA/Exact reviewed head: $STALE_SHA}"
expect_rejected "a stale head claimed inside the report"
write_reviews "$HEAD_SHA" APPROVED "$HEAD_SHA" "${review_body/| R2 | Cards parse | Deterministic test | test name | VERIFIED | Exact live model evidence inspected. |/| R2 | Narrower behavior | Deterministic test | test name | VERIFIED | Exact live model evidence inspected. |}"
expect_rejected "a narrowed acceptance criterion"

jq -n '[{author:{login:"maintainer"},committer:{login:"implementer"}}]' > "$CONTRIBUTORS_JSON_FILE"
write_reviews "$HEAD_SHA" APPROVED "$HEAD_SHA" "$review_body"
expect_rejected "approval from an implementing contributor"

echo "Pull-request review-record policy regression tests passed."
