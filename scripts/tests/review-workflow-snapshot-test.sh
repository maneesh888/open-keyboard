#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/ci.yml"
FIXTURE="$(mktemp -d)"
RUNNER="$FIXTURE/validate-review-snapshots.sh"
MOCK_BIN="$FIXTURE/bin"
VALIDATOR_ROOT="$FIXTURE/validators"
EVENT_JSON="$FIXTURE/event.json"
MOCK_CURRENT_BODY_FILE="$FIXTURE/mock-current-body.md"
OUTPUT="$FIXTURE/output"
trap 'rm -rf -- "$FIXTURE"' EXIT
mkdir -p "$MOCK_BIN" "$VALIDATOR_ROOT"

ruby -e '
  require "yaml"
  step = YAML.load_file(ARGV.fetch(0))
    .fetch("jobs")
    .fetch("required-review-evidence")
    .fetch("steps")
    .find { |candidate| candidate["name"] == "Validate immutable event and current review evidence" }
  abort "Review snapshot validation step is missing." unless step
  puts step.fetch("run")
' "$WORKFLOW" > "$RUNNER"
chmod +x "$RUNNER"

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" != "api" ]]; then
  echo "Unexpected mocked gh command." >&2
  exit 2
fi

if [[ "$*" == *'/reviews?per_page=100'* ]]; then
  printf '[]\n'
  exit 0
fi

jq -n \
  --arg head "$MOCK_CURRENT_HEAD" \
  --arg url "https://github.com/maneesh888/open-keyboard/pull/21" \
  --rawfile body "$MOCK_CURRENT_BODY_FILE" \
  '{head: {sha: $head}, html_url: $url, body: $body}'
MOCK_GH
chmod +x "$MOCK_BIN/gh"

cat > "$VALIDATOR_ROOT/validate-pr-requirements.sh" <<'MOCK_REQUIREMENTS'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$PR_BODY" != "VALID" ]]; then
  echo "Requirement snapshot is invalid." >&2
  exit 1
fi
echo "Requirement snapshot passed."
MOCK_REQUIREMENTS
chmod +x "$VALIDATOR_ROOT/validate-pr-requirements.sh"

cat > "$VALIDATOR_ROOT/validate-pr-review-record.sh" <<'MOCK_REVIEW'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$PR_BODY" != "VALID" ]]; then
  echo "Review snapshot is invalid." >&2
  exit 1
fi
if [[ ! -r "$REVIEWS_JSON_FILE" ]]; then
  echo "Review list is unavailable." >&2
  exit 1
fi
echo "Review snapshot passed."
MOCK_REVIEW
chmod +x "$VALIDATOR_ROOT/validate-pr-review-record.sh"

HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
OTHER_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
PR_URL="https://github.com/maneesh888/open-keyboard/pull/21"

run_snapshot_gate() {
  local event_body="$1"
  local current_body="$2"
  local current_head="${3:-$HEAD_SHA}"
  local run_temp="$FIXTURE/run"

  rm -rf -- "$run_temp"
  mkdir -p "$run_temp"
  printf '%s' "$current_body" > "$MOCK_CURRENT_BODY_FILE"
  jq -n \
    --arg head "$HEAD_SHA" \
    --arg url "$PR_URL" \
    --arg body "$event_body" \
    '{pull_request: {head: {sha: $head}, html_url: $url, body: $body}}' > "$EVENT_JSON"

  PATH="$MOCK_BIN:$PATH" \
    EVENT_HEAD_SHA="$HEAD_SHA" \
    EVENT_NAME=pull_request \
    GH_TOKEN=fixture \
    GITHUB_EVENT_PATH="$EVENT_JSON" \
    GITHUB_REPOSITORY=maneesh888/open-keyboard \
    MOCK_CURRENT_BODY_FILE="$MOCK_CURRENT_BODY_FILE" \
    MOCK_CURRENT_HEAD="$current_head" \
    PR_NUMBER=21 \
    RUNNER_TEMP="$run_temp" \
    VALIDATOR_ROOT="$VALIDATOR_ROOT" \
    bash -e -o pipefail "$RUNNER" > "$OUTPUT" 2>&1
}

if ! run_snapshot_gate VALID VALID; then
  echo "Matching valid event and current review snapshots were rejected." >&2
  exit 1
fi
if run_snapshot_gate VALID INVALID; then
  echo "A valid older event hid invalid current review metadata." >&2
  exit 1
fi
if run_snapshot_gate INVALID VALID; then
  echo "Restored current review metadata erased an invalid event snapshot." >&2
  exit 1
fi
if run_snapshot_gate VALID VALID "$OTHER_SHA"; then
  echo "Review snapshot validation accepted a changed current head." >&2
  exit 1
fi

echo "Review-workflow snapshot regression tests passed."
