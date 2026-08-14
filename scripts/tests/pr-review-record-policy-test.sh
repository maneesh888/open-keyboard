#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-pr-review-record.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
STALE_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
PR_URL="https://github.com/maneesh888/open-keyboard/pull/123"
REVIEW_ID=456
REVIEWS_JSON_FILE="$FIXTURE/reviews.json"
HUMAN_EVIDENCE="explicit repository-owner approval for this exact head in the active Codex task"

automatic_pr_body="$(cat <<EOF
- Requirement count: 2
- Reviewer: project pr-reviewer (read-only, no inherited conversation)
- Exact reviewed head: $HEAD_SHA
- Review requirement coverage: 2/2
- Review unverified requirements: none
- Blocking findings: none
- Independent review evidence: $PR_URL#pullrequestreview-$REVIEW_ID
- Reviewer confidence: 100%
- Merge recommendation: automatic
- Merge authorization route: automatic
- Human approval status: not-required
- Human-approved head: not-required
- Human approval evidence: not-required

| ID | Requirement and source | Observable acceptance | Required proof | Exact evidence | Status |
| --- | --- | --- | --- | --- | --- |
| R1 | Exact model behavior | Exact model succeeds | Live exact-model test | exact-head run | VERIFIED |
| R2 | Parser behavior | Cards parse | Deterministic test | test name | VERIFIED |
EOF
)"

human_pr_body="$(cat <<EOF
- Requirement count: 2
- Reviewer: project pr-reviewer (read-only, no inherited conversation)
- Exact reviewed head: $HEAD_SHA
- Review requirement coverage: 2/2
- Review unverified requirements: R2
- Blocking findings: R2 lacks independently inspectable proof
- Independent review evidence: $PR_URL#pullrequestreview-$REVIEW_ID
- Reviewer confidence: below 100%
- Merge recommendation: human-review-required
- Merge authorization route: human
- Human approval status: approved
- Human-approved head: $HEAD_SHA
- Human approval evidence: $HUMAN_EVIDENCE

| ID | Requirement and source | Observable acceptance | Required proof | Exact evidence | Status |
| --- | --- | --- | --- | --- | --- |
| R1 | Exact model behavior | Exact model succeeds | Live exact-model test | exact-head run | VERIFIED |
| R2 | Parser behavior | Cards parse | Deterministic test | No independently inspectable result | UNVERIFIED |
EOF
)"

automatic_review_body="$(cat <<EOF
- Reviewer: project pr-reviewer (read-only, no inherited conversation)
- Exact reviewed head: $HEAD_SHA
- Review requirement coverage: 2/2
- Review unverified requirements: none
- Blocking findings: none
- Reviewer confidence: 100%
- Merge recommendation: automatic
- Conclusion: requirements-complete

| ID | Observable acceptance | Required proof | Evidence inspected | Status | Independent assessment |
| --- | --- | --- | --- | --- | --- |
| R1 | Exact model succeeds | Live exact-model test | exact-head run | VERIFIED | Exact targeted test inspected. |
| R2 | Cards parse | Deterministic test | test name | VERIFIED | Exact deterministic result inspected. |
EOF
)"

human_review_body="$(cat <<EOF
- Reviewer: project pr-reviewer (read-only, no inherited conversation)
- Exact reviewed head: $HEAD_SHA
- Review requirement coverage: 2/2
- Review unverified requirements: R2
- Blocking findings: R2 lacks independently inspectable proof
- Reviewer confidence: below 100%
- Merge recommendation: human-review-required
- Conclusion: human-review-required

| ID | Observable acceptance | Required proof | Evidence inspected | Status | Independent assessment |
| --- | --- | --- | --- | --- | --- |
| R1 | Exact model succeeds | Live exact-model test | exact-head run | VERIFIED | Exact targeted test inspected. |
| R2 | Cards parse | Deterministic test | No retained test result | UNVERIFIED | Required proof is missing. |
EOF
)"

write_reviews() {
  local review_head="$1"
  local linked_state="$2"
  local independent_body="$3"
  local extra_state="${4:-}"
  jq -n \
    --argjson review_id "$REVIEW_ID" \
    --arg url "$PR_URL#pullrequestreview-$REVIEW_ID" \
    --arg review_head "$review_head" \
    --arg linked_state "$linked_state" \
    --arg independent_body "$independent_body" \
    --arg extra_state "$extra_state" \
    '[{id:$review_id, html_url:$url, commit_id:$review_head, state:$linked_state, body:$independent_body, submitted_at:"2026-08-14T00:00:00Z", user:{login:"implementer",type:"User"}}]
      + (if $extra_state == "" then [] else [{id:900, html_url:"https://example.invalid/review/900", commit_id:$review_head, state:$extra_state, body:"", submitted_at:"2026-08-14T00:01:00Z", user:{login:"maintainer",type:"User"}}] end)' \
    > "$REVIEWS_JSON_FILE"
}

run_validator() {
  local pr_body="$1"
  local event_review_file="${2:-}"
  HEAD_SHA="$HEAD_SHA" \
    PR_BODY="$pr_body" \
    PR_URL="$PR_URL" \
    REVIEWS_JSON_FILE="$REVIEWS_JSON_FILE" \
    EVENT_REVIEW_JSON_FILE="$event_review_file" \
    "$VALIDATOR" >/dev/null 2>&1
}

expect_rejected() {
  local description="$1"
  local pr_body="$2"
  local event_review_file="${3:-}"
  if run_validator "$pr_body" "$event_review_file"; then
    echo "Review-record policy accepted $description." >&2
    exit 1
  fi
}

write_reviews "$HEAD_SHA" COMMENTED "$automatic_review_body"
run_validator "$automatic_pr_body"

revalidation_review_file="$FIXTURE/revalidation-review.json"
jq -n \
  --arg head "$HEAD_SHA" \
  --arg url "$PR_URL#pullrequestreview-999" \
  '{id:999, html_url:$url, commit_id:$head, state:"commented", body:"Review-evidence revalidation trigger. This is not an approval or independent-review report.", submitted_at:"2026-08-14T00:01:00Z", user:{login:"implementer",type:"User"}}' \
  > "$revalidation_review_file"
run_validator "$automatic_pr_body" "$revalidation_review_file"

write_reviews "$HEAD_SHA" COMMENTED "$human_review_body"
run_validator "$human_pr_body"

write_reviews "$STALE_SHA" COMMENTED "$automatic_review_body"
expect_rejected "a stale independent review" "$automatic_pr_body"
write_reviews "$HEAD_SHA" APPROVED "$automatic_review_body"
expect_rejected "an APPROVED independent-review submission" "$automatic_pr_body"
write_reviews "$HEAD_SHA" COMMENTED "$automatic_review_body" CHANGES_REQUESTED
expect_rejected "a current change request" "$automatic_pr_body"
write_reviews "$HEAD_SHA" COMMENTED "${automatic_review_body/Exact reviewed head: $HEAD_SHA/Exact reviewed head: $STALE_SHA}"
expect_rejected "a stale head claimed inside the report" "$automatic_pr_body"
write_reviews "$HEAD_SHA" COMMENTED "${automatic_review_body/| R2 | Cards parse | Deterministic test | test name | VERIFIED | Exact deterministic result inspected. |/| R2 | Narrower behavior | Deterministic test | test name | VERIFIED | Exact deterministic result inspected. |}"
expect_rejected "a narrowed acceptance criterion" "$automatic_pr_body"
write_reviews "$HEAD_SHA" COMMENTED "${automatic_review_body/| R2 | Cards parse | Deterministic test | test name | VERIFIED | Exact deterministic result inspected. |/}"
expect_rejected "an omitted requirement row" "$automatic_pr_body"
write_reviews "$HEAD_SHA" COMMENTED "${automatic_review_body/| R2 | Cards parse | Deterministic test | test name | VERIFIED | Exact deterministic result inspected. |/| R2 | Cards parse | Source inspection | test name | VERIFIED | Exact deterministic result inspected. |}"
expect_rejected "a substituted required-proof type" "$automatic_pr_body"
automatic_pr_with_blocker="${automatic_pr_body/Blocking findings: none/Blocking findings: R1 remains blocked}"
automatic_review_with_blocker="${automatic_review_body/Blocking findings: none/Blocking findings: R1 remains blocked}"
write_reviews "$HEAD_SHA" COMMENTED "$automatic_review_with_blocker"
expect_rejected "an automatic route with blocking findings" "$automatic_pr_with_blocker"
write_reviews "$HEAD_SHA" COMMENTED "${automatic_review_body/Reviewer confidence: 100%/Reviewer confidence: below 100%}"
expect_rejected "an automatic recommendation below 100% confidence" "$automatic_pr_body"
write_reviews "$HEAD_SHA" COMMENTED "$human_review_body"
expect_rejected "reviewer uncertainty on the automatic route" "$automatic_pr_body"
expect_rejected "a weakened blocker summary" "${human_pr_body/Blocking findings: R2 lacks independently inspectable proof/Blocking findings: minor concern}"
expect_rejected "human authorization without explicit approval" "${human_pr_body/Human approval status: approved/Human approval status: pending}"
expect_rejected "human authorization for a stale head" "${human_pr_body/Human-approved head: $HEAD_SHA/Human-approved head: $STALE_SHA}"
expect_rejected "human authorization without exact owner evidence" "${human_pr_body/Human approval evidence: $HUMAN_EVIDENCE/Human approval evidence: someone approved}"
write_reviews "$HEAD_SHA" COMMENTED "${human_review_body/Merge recommendation: human-review-required/Merge recommendation: automatic}"
expect_rejected "an automatic recommendation with an unverified requirement" "$human_pr_body"

write_reviews "$HEAD_SHA" COMMENTED "$automatic_review_body"
newer_review_file="$FIXTURE/reviews-with-newer-project-report.json"
jq \
  --arg body "$human_review_body" \
  '. + [{id:457, html_url:"https://github.com/maneesh888/open-keyboard/pull/123#pullrequestreview-457", commit_id:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", state:"COMMENTED", body:$body, submitted_at:"2026-08-14T00:02:00Z", user:{login:"implementer",type:"User"}}]' \
  "$REVIEWS_JSON_FILE" > "$newer_review_file"
mv "$newer_review_file" "$REVIEWS_JSON_FILE"
expect_rejected "an older linked report superseded by a newer same-head project-reviewer report" "$automatic_pr_body"

write_reviews "$HEAD_SHA" COMMENTED "$automatic_review_body"
newer_approved_file="$FIXTURE/reviews-with-newer-approved-project-report.json"
jq \
  --arg body "$automatic_review_body" \
  '. + [{id:457, html_url:"https://github.com/maneesh888/open-keyboard/pull/123#pullrequestreview-457", commit_id:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", state:"APPROVED", body:$body, submitted_at:"2026-08-14T00:02:00Z", user:{login:"implementer",type:"User"}}]' \
  "$REVIEWS_JSON_FILE" > "$newer_approved_file"
mv "$newer_approved_file" "$REVIEWS_JSON_FILE"
expect_rejected "a newer same-head APPROVED submission carrying the project-reviewer marker" "$automatic_pr_body"

write_reviews "$HEAD_SHA" COMMENTED "$automatic_review_body"
older_approved_file="$FIXTURE/reviews-with-older-approved-project-report.json"
jq \
  --arg body "$automatic_review_body" \
  '[{id:455, html_url:"https://github.com/maneesh888/open-keyboard/pull/123#pullrequestreview-455", commit_id:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", state:"APPROVED", body:$body, submitted_at:"2026-08-13T23:59:00Z", user:{login:"implementer",type:"User"}}] + .' \
  "$REVIEWS_JSON_FILE" > "$older_approved_file"
mv "$older_approved_file" "$REVIEWS_JSON_FILE"
expect_rejected "any same-head APPROVED submission carrying the project-reviewer marker" "$automatic_pr_body"

write_reviews "$HEAD_SHA" COMMENTED "$automatic_review_body"
event_review_file="$FIXTURE/event-review.json"
jq \
  --arg body "$human_review_body" \
  '.[0] + {body:$body, state:"commented"}' \
  "$REVIEWS_JSON_FILE" > "$event_review_file"
expect_rejected "a restored API review that hides the invalid event snapshot" "$automatic_pr_body" "$event_review_file"

write_reviews "$HEAD_SHA" COMMENTED "$automatic_review_body"
approved_event_review_file="$FIXTURE/approved-event-review.json"
jq \
  --arg body "$automatic_review_body" \
  '.[0] + {id:457, html_url:"https://github.com/maneesh888/open-keyboard/pull/123#pullrequestreview-457", body:$body, state:"approved", submitted_at:"2026-08-14T00:02:00Z"}' \
  "$REVIEWS_JSON_FILE" > "$approved_event_review_file"
expect_rejected "an APPROVED project-reviewer event overlay hidden by restored API state" "$automatic_pr_body" "$approved_event_review_file"

echo "Pull-request review-record policy regression tests passed."
