#!/usr/bin/env bash
set -euo pipefail

EVIDENCE_READY="${EVIDENCE_READY:-}"
CHECK_RUNS_JSON_FILE="${1:-}"

if [[ "$EVIDENCE_READY" != "true" && "$EVIDENCE_READY" != "false" ]]; then
  echo "Review-check classification needs an explicit evidence-ready boolean." >&2
  exit 2
fi
if [[ -z "$CHECK_RUNS_JSON_FILE" || ! -r "$CHECK_RUNS_JSON_FILE" ]]; then
  echo "Review-check classification needs fetched check-run history." >&2
  exit 2
fi

ruby -rjson - "$EVIDENCE_READY" "$CHECK_RUNS_JSON_FILE" <<'RUBY'
evidence_ready = ARGV.fetch(0) == "true"
check_runs = JSON.parse(File.read(ARGV.fetch(1)))

unless check_runs.is_a?(Array)
  warn "Review-check history must be a JSON array."
  exit 2
end

required_runs = check_runs.select do |run|
  run.is_a?(Hash) && run["name"] == "Required checks"
end
successful_history = required_runs.any? do |run|
  run["status"] == "completed" && run["conclusion"] == "success"
end
poisoned_history = required_runs.any? do |run|
  run["status"] != "completed" || run["conclusion"] != "success"
end

# Before the first protected success, incomplete evidence uses a different name so
# the exact SHA can complete its report/body handoff. Once the protected name has
# appeared, any non-success permanently burns that SHA; a new commit is required.
emit_incomplete = !evidence_ready && !successful_history && !poisoned_history

puts "emit_incomplete=#{emit_incomplete}"
puts "history_poisoned=#{poisoned_history}"
RUBY
