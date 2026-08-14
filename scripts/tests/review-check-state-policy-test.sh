#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASSIFIER="$ROOT/scripts/classify-review-check-state.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

if [[ ! -x "$CLASSIFIER" ]]; then
  echo "Review-check state classifier must be executable." >&2
  exit 1
fi

write_history() {
  local destination="$1"
  local body="$2"
  printf '%s\n' "$body" > "$destination"
}

expect_state() {
  local label="$1"
  local evidence_ready="$2"
  local history_body="$3"
  local expected_incomplete="$4"
  local expected_poisoned="$5"
  local history_file="$TMP_ROOT/$label.json"
  local output

  write_history "$history_file" "$history_body"
  output="$(CURRENT_RUN_ID=700 EVIDENCE_READY="$evidence_ready" "$CLASSIFIER" "$history_file")"
  if [[ "$output" != $'emit_incomplete='"$expected_incomplete"$'\nhistory_poisoned='"$expected_poisoned" ]]; then
    echo "$label produced an unexpected review-check state:" >&2
    echo "$output" >&2
    exit 1
  fi
}

expect_state \
  incomplete_before_review \
  false \
  '[]' \
  true \
  false

expect_state \
  valid_first_review \
  true \
  '[]' \
  false \
  false

expect_state \
  invalid_after_success \
  false \
  '[{"name":"Required checks","status":"completed","conclusion":"success"}]' \
  false \
  false

expect_state \
  valid_after_success \
  true \
  '[{"name":"Required checks","status":"completed","conclusion":"success"}]' \
  false \
  false

expect_state \
  restored_after_failure \
  true \
  '[{"name":"Required checks","status":"completed","conclusion":"failure"}]' \
  false \
  true

expect_state \
  invalid_after_cancellation \
  false \
  '[{"name":"Required checks","status":"completed","conclusion":"cancelled"}]' \
  false \
  true

expect_state \
  unresolved_required_run \
  false \
  '[{"name":"Required checks","status":"in_progress","conclusion":null}]' \
  false \
  true

expect_state \
  unrelated_failure \
  false \
  '[{"name":"Incomplete review evidence","status":"completed","conclusion":"failure"}]' \
  true \
  false

expect_state \
  current_run_is_ignored \
  true \
  '[{"name":"Required checks","status":"queued","conclusion":null,"details_url":"https://github.com/example/repo/actions/runs/700/job/9"}]' \
  false \
  false

if CURRENT_RUN_ID=700 EVIDENCE_READY=unknown "$CLASSIFIER" "$TMP_ROOT/incomplete_before_review.json" >/dev/null 2>&1; then
  echo "Invalid evidence readiness unexpectedly passed." >&2
  exit 1
fi
if EVIDENCE_READY=false "$CLASSIFIER" "$TMP_ROOT/incomplete_before_review.json" >/dev/null 2>&1; then
  echo "Missing current workflow run ID unexpectedly passed." >&2
  exit 1
fi

write_history "$TMP_ROOT/not-array.json" '{}'
if CURRENT_RUN_ID=700 EVIDENCE_READY=false "$CLASSIFIER" "$TMP_ROOT/not-array.json" >/dev/null 2>&1; then
  echo "Non-array check history unexpectedly passed." >&2
  exit 1
fi

echo "Review-check state policy tests passed."
