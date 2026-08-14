#!/usr/bin/env bash
set -euo pipefail

HEAD_SHA="${HEAD_SHA:-}"
PR_BODY="${PR_BODY:-}"
PR_URL="${PR_URL:-}"

if [[ ! "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Requirement evidence needs the exact 40-character pull-request head." >&2
  exit 2
fi
if [[ -z "$PR_BODY" || -z "$PR_URL" ]]; then
  echo "Requirement evidence needs the pull-request body and URL." >&2
  exit 2
fi

ruby - "$HEAD_SHA" "$PR_URL" <<'RUBY'
head_sha = ARGV.fetch(0)
pr_url = ARGV.fetch(1)
body = ENV.fetch("PR_BODY")
human_evidence = "explicit repository-owner approval for this exact head in the active Codex task"

def fail_evidence(message)
  warn message
  exit 1
end

def exact_field(body, label)
  prefix = "- #{label}: "
  values = body.lines.each_with_object([]) do |line, collected|
    normalized = line.delete_suffix("\n").delete_suffix("\r")
    collected << normalized.delete_prefix(prefix) if normalized.start_with?(prefix)
  end
  fail_evidence("PR evidence must contain exactly one '#{label}' field.") unless values.length == 1
  value = values.first.strip
  fail_evidence("PR evidence field '#{label}' cannot be empty or pending.") if value.empty? || value.casecmp("pending").zero?
  value
end

def requirement_ids(value, label)
  return [] if value == "none"

  ids = value.split(",").map(&:strip)
  fail_evidence("#{label} must be 'none' or a comma-separated requirement ID list.") if
    ids.empty? || ids.any? { |id| !id.match?(/\AR[1-9][0-9]*\z/) } || ids.uniq.length != ids.length
  ids
end

requirement_count_text = exact_field(body, "Requirement count")
verified_count_text = exact_field(body, "Verified requirement count")
unverified = exact_field(body, "Unverified in-scope requirements")
authorized_out_of_scope = exact_field(body, "Authorized out-of-scope items")
reviewed_head = exact_field(body, "Exact reviewed head")
review_coverage = exact_field(body, "Review requirement coverage")
review_unverified = exact_field(body, "Review unverified requirements")
blocking_findings = exact_field(body, "Blocking findings")
review_evidence = exact_field(body, "Independent review evidence")
reviewer_confidence = exact_field(body, "Reviewer confidence")
merge_recommendation = exact_field(body, "Merge recommendation")
authorization_route = exact_field(body, "Merge authorization route")
human_status = exact_field(body, "Human approval status")
human_head = exact_field(body, "Human-approved head")
human_approval_evidence = exact_field(body, "Human approval evidence")

unless requirement_count_text.match?(/\A[1-9][0-9]*\z/) && verified_count_text.match?(/\A[0-9]+\z/)
  fail_evidence("Requirement counts must be non-negative integers and at least one requirement is required.")
end
requirement_count = Integer(requirement_count_text, 10)
verified_count = Integer(verified_count_text, 10)

rows = body.lines.each_with_object([]) do |line, collected|
  cells = line.strip.split("|", -1).drop(1).tap(&:pop).map(&:strip)
  next unless cells.length == 6 && cells.first.match?(/\AR[1-9][0-9]*\z/)

  id, requirement, acceptance, proof, evidence, status = cells
  fail_evidence("#{id} must provide a requirement source, acceptance criterion, proof type, and exact evidence.") if
    [requirement, acceptance, proof, evidence].any?(&:empty?)
  fail_evidence("#{id} exact evidence cannot be pending or unverified when marked VERIFIED.") if
    status == "VERIFIED" && evidence.match?(/\A(pending|unverified|not run|none)\z/i)
  fail_evidence("#{id} has an invalid status.") unless ["VERIFIED", "UNVERIFIED"].include?(status)
  collected << [id, status]
end
expected_ids = (1..requirement_count).map { |index| "R#{index}" }
actual_ids = rows.map(&:first)
fail_evidence("Requirement table IDs must be unique and sequential from R1.") unless actual_ids == expected_ids

verified_rows = rows.count { |_id, status| status == "VERIFIED" }
unverified_rows = rows.select { |_id, status| status == "UNVERIFIED" }.map(&:first)
fail_evidence("Verified requirement count does not match the requirement table.") unless verified_count == verified_rows
fail_evidence("Unverified in-scope requirements do not match the requirement table.") unless
  requirement_ids(unverified, "Unverified in-scope requirements") == unverified_rows
fail_evidence("Review unverified requirements do not match the requirement table.") unless
  requirement_ids(review_unverified, "Review unverified requirements") == unverified_rows

fail_evidence("Exact reviewed head does not match the pull-request head.") unless reviewed_head == head_sha
expected_coverage = "#{requirement_count}/#{requirement_count}"
fail_evidence("Review requirement coverage must be #{expected_coverage}.") unless review_coverage == expected_coverage

valid_review_prefix = "#{pr_url}#pullrequestreview-"
unless review_evidence.start_with?(valid_review_prefix) && review_evidence.match?(/[0-9]+\z/)
  fail_evidence("Independent review evidence must link to a durable review submission on this pull request.")
end

case authorization_route
when "automatic"
  fail_evidence("Automatic authorization requires every in-scope requirement to be VERIFIED.") unless unverified_rows.empty?
  fail_evidence("Automatic authorization requires no blocking findings.") unless blocking_findings == "none"
  fail_evidence("Automatic authorization requires reviewer confidence of exactly '100%'.") unless reviewer_confidence == "100%"
  fail_evidence("Automatic authorization requires an 'automatic' merge recommendation.") unless merge_recommendation == "automatic"
  fail_evidence("Automatic authorization must not claim human approval.") unless
    human_status == "not-required" && human_head == "not-required" && human_approval_evidence == "not-required"
when "human"
  fail_evidence("Human authorization is only valid when at least one in-scope requirement remains UNVERIFIED.") if unverified_rows.empty?
  fail_evidence("Human authorization requires reviewer confidence of exactly 'below 100%'.") unless reviewer_confidence == "below 100%"
  fail_evidence("Human authorization requires a 'human-review-required' merge recommendation.") unless merge_recommendation == "human-review-required"
  fail_evidence("Human authorization must retain the reviewer's blocking findings.") if blocking_findings == "none"
  fail_evidence("Human approval status must be 'approved'.") unless human_status == "approved"
  fail_evidence("Human approval is stale or not bound to the pull-request head.") unless human_head == head_sha
  fail_evidence("Human approval evidence must record explicit repository-owner authorization for this exact head.") unless
    human_approval_evidence == human_evidence
else
  fail_evidence("Merge authorization route must be 'automatic' or 'human'.")
end

if authorized_out_of_scope != "none" && !authorized_out_of_scope.match?(/explicitly authorized/i)
  fail_evidence("Out-of-scope items must be 'none' or identify explicit authorization.")
end

exact_head_lines = body.lines.map(&:strip).count { |line| line == "`#{head_sha}`" }
fail_evidence("The Exact head SHA section must contain the current head exactly once.") unless exact_head_lines == 1

puts "Pull-request requirement evidence is complete for #{head_sha} via the #{authorization_route} authorization route."
RUBY
