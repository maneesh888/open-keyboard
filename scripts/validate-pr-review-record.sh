#!/usr/bin/env bash
set -euo pipefail

HEAD_SHA="${HEAD_SHA:-}"
PR_BODY="${PR_BODY:-}"
PR_URL="${PR_URL:-}"
REVIEWS_JSON_FILE="${REVIEWS_JSON_FILE:-}"
EVENT_REVIEW_JSON_FILE="${EVENT_REVIEW_JSON_FILE:-}"

if [[ ! "$HEAD_SHA" =~ ^[0-9a-f]{40}$ || -z "$PR_BODY" || -z "$PR_URL" ]]; then
  echo "Review-record validation needs exact pull-request metadata." >&2
  exit 2
fi
if [[ ! -f "$REVIEWS_JSON_FILE" ]]; then
  echo "Review-record validation needs fetched GitHub reviews." >&2
  exit 2
fi

if [[ -n "$EVENT_REVIEW_JSON_FILE" && ! -f "$EVENT_REVIEW_JSON_FILE" ]]; then
  echo "Review-record validation received an unreadable event review snapshot." >&2
  exit 2
fi

ruby -rjson - "$HEAD_SHA" "$PR_URL" "$REVIEWS_JSON_FILE" "$EVENT_REVIEW_JSON_FILE" <<'RUBY'
head_sha, pr_url, reviews_path = ARGV
event_review_path = ARGV.fetch(3)

def fail_review(message)
  warn message
  exit 1
end

pr_body = ENV.fetch("PR_BODY")
reviews = JSON.parse(File.read(reviews_path))
fail_review("Fetched GitHub reviews must be a JSON array.") unless reviews.is_a?(Array)
unless event_review_path.empty?
  event_review = JSON.parse(File.read(event_review_path))
  fail_review("The event review snapshot must be a GitHub review object.") unless
    event_review.is_a?(Hash) && event_review["id"].is_a?(Integer)
  event_review["state"] = event_review["state"].to_s.upcase
  reviews = reviews.reject { |candidate| candidate.is_a?(Hash) && candidate["id"] == event_review["id"] }
  reviews << event_review
end
human_evidence = "explicit repository-owner approval for this exact head in the active Codex task"

def exact_field(body, label)
  prefix = "- #{label}: "
  values = body.lines.each_with_object([]) do |line, collected|
    normalized = line.delete_suffix("\n").delete_suffix("\r")
    collected << normalized.delete_prefix(prefix).strip if normalized.start_with?(prefix)
  end
  fail_review("Independent review must contain exactly one '#{label}' field.") unless values.length == 1
  value = values.first
  fail_review("Independent review field '#{label}' cannot be empty or pending.") if value.empty? || value.casecmp("pending").zero?
  value
end

def pr_field(body, label)
  prefix = "- #{label}: "
  values = body.lines.map(&:strip).select { |line| line.start_with?(prefix) }.map { |line| line.delete_prefix(prefix).strip }
  fail_review("PR body must contain exactly one '#{label}' field.") unless values.length == 1
  values.first
end

def requirement_ids(value, label)
  return [] if value == "none"

  ids = value.split(",").map(&:strip)
  fail_review("#{label} must be 'none' or a comma-separated requirement ID list.") if
    ids.empty? || ids.any? { |id| !id.match?(/\AR[1-9][0-9]*\z/) } || ids.uniq.length != ids.length
  ids
end

evidence_prefix = "- Independent review evidence: #{pr_url}#pullrequestreview-"
evidence_lines = pr_body.lines.map(&:strip).select { |line| line.start_with?(evidence_prefix) }
fail_review("PR body must link exactly one independent review submission.") unless evidence_lines.length == 1
review_id_text = evidence_lines.first.delete_prefix(evidence_prefix)
fail_review("Independent review submission ID is invalid.") unless review_id_text.match?(/\A[1-9][0-9]*\z/)
review_id = Integer(review_id_text, 10)

review = reviews.find { |candidate| candidate["id"] == review_id }
fail_review("The linked independent review submission was not found.") unless review
expected_review_url = "#{pr_url}#pullrequestreview-#{review_id}"
fail_review("The linked independent review URL does not match GitHub evidence.") unless review["html_url"] == expected_review_url
fail_review("The independent review is not bound to the current head.") unless review["commit_id"] == head_sha
fail_review("The independent review must be a non-approval COMMENTED submission.") unless review["state"].to_s.upcase == "COMMENTED"

review_body = review.fetch("body", "")
reviewer = exact_field(review_body, "Reviewer")
reviewed_head = exact_field(review_body, "Exact reviewed head")
coverage = exact_field(review_body, "Review requirement coverage")
unverified = exact_field(review_body, "Review unverified requirements")
blocking = exact_field(review_body, "Blocking findings")
confidence = exact_field(review_body, "Reviewer confidence")
recommendation = exact_field(review_body, "Merge recommendation")
conclusion = exact_field(review_body, "Conclusion")

fail_review("Independent review identity is not the isolated project reviewer.") unless reviewer == "project pr-reviewer (read-only, no inherited conversation)"
reviewer_marker = "- Reviewer: #{reviewer}"
same_head_reviewer_reports = reviews.select do |candidate|
  next false unless candidate.is_a?(Hash)
  next false unless candidate["commit_id"] == head_sha

  candidate.fetch("body", "").lines.any? { |line| line.strip == reviewer_marker }
end
invalid_reviewer_state = same_head_reviewer_reports.find do |candidate|
  candidate["state"].to_s.upcase != "COMMENTED"
end
fail_review("Every same-head project-reviewer submission must be COMMENTED, never an approval or change request.") if
  invalid_reviewer_state
latest_reviewer_report = same_head_reviewer_reports.max_by do |candidate|
  [candidate["submitted_at"].to_s, candidate["id"].to_i]
end
fail_review("The PR body must link the newest same-head project-reviewer report.") unless
  latest_reviewer_report && latest_reviewer_report["id"] == review_id
fail_review("Independent review head does not match the current head.") unless reviewed_head == head_sha
fail_review("PR body reviewer identity does not match the independent report.") unless pr_field(pr_body, "Reviewer") == reviewer
fail_review("PR body reviewed head does not match the independent report.") unless pr_field(pr_body, "Exact reviewed head") == reviewed_head
fail_review("PR body review coverage does not match the independent report.") unless pr_field(pr_body, "Review requirement coverage") == coverage
fail_review("PR body blocking findings do not match the independent report.") unless pr_field(pr_body, "Blocking findings") == blocking
fail_review("PR body reviewer confidence does not match the independent report.") unless pr_field(pr_body, "Reviewer confidence") == confidence
fail_review("PR body merge recommendation does not match the independent report.") unless pr_field(pr_body, "Merge recommendation") == recommendation

requirement_count_text = pr_field(pr_body, "Requirement count")
fail_review("PR requirement count is invalid.") unless requirement_count_text.match?(/\A[1-9][0-9]*\z/)
requirement_count = Integer(requirement_count_text, 10)
expected_coverage = "#{requirement_count}/#{requirement_count}"
fail_review("Independent review coverage must be #{expected_coverage}.") unless coverage == expected_coverage

requirement_rows = pr_body.lines.each_with_object([]) do |line, collected|
  cells = line.strip.split("|", -1).drop(1).tap(&:pop).map(&:strip)
  next unless cells.length == 6 && cells.first.match?(/\AR[1-9][0-9]*\z/)

  id, _requirement, acceptance, proof, _evidence, status = cells
  collected << [id, acceptance, proof, status]
end
expected_ids = (1..requirement_count).map { |index| "R#{index}" }
fail_review("PR requirement rows must be unique and sequential from R1.") unless requirement_rows.map(&:first) == expected_ids

coverage_rows = review_body.lines.each_with_object([]) do |line, collected|
  cells = line.strip.split("|", -1).drop(1).tap(&:pop).map(&:strip)
  next unless cells.length == 6 && cells.first.match?(/\AR[1-9][0-9]*\z/)
  collected << cells
end
fail_review("Independent review coverage rows must be unique and sequential from R1.") unless coverage_rows.map(&:first) == expected_ids
coverage_rows.each_with_index do |row, index|
  id, acceptance, proof, evidence, status, assessment = row
  _requirement_id, required_acceptance, required_proof, required_status = requirement_rows.fetch(index)
  fail_review("#{id} changed or omitted the PR acceptance criterion.") unless acceptance == required_acceptance
  fail_review("#{id} changed or omitted the required proof type.") unless proof == required_proof
  fail_review("#{id} review status does not match the PR requirement ledger.") unless status == required_status
  fail_review("#{id} has an invalid independent-review status.") unless ["VERIFIED", "UNVERIFIED"].include?(status)
  fail_review("#{id} is missing independently inspected evidence.") if evidence.empty? || evidence.match?(/\A(pending|none|not inspected)\z/i)
  fail_review("#{id} is missing an independent evidence assessment.") if assessment.empty? || assessment.match?(/\A(pending|none)\z/i)
end

unverified_rows = coverage_rows.select { |row| row[4] == "UNVERIFIED" }.map(&:first)
fail_review("Independent review unverified IDs do not match its coverage table.") unless
  requirement_ids(unverified, "Review unverified requirements") == unverified_rows
fail_review("PR and independent-review unverified IDs do not match.") unless
  requirement_ids(pr_field(pr_body, "Review unverified requirements"), "PR review unverified requirements") == unverified_rows

authorization_route = pr_field(pr_body, "Merge authorization route")
human_status = pr_field(pr_body, "Human approval status")
human_head = pr_field(pr_body, "Human-approved head")
human_approval_evidence = pr_field(pr_body, "Human approval evidence")

if unverified_rows.empty?
  fail_review("A complete independent review must have no blocking findings.") unless blocking == "none"
  fail_review("A complete independent review must report confidence as exactly '100%'.") unless confidence == "100%"
  fail_review("A complete independent review must recommend 'automatic'.") unless recommendation == "automatic"
  fail_review("A complete independent review conclusion must be 'requirements-complete'.") unless conclusion == "requirements-complete"
  fail_review("A complete independent review requires the automatic authorization route.") unless authorization_route == "automatic"
  fail_review("Automatic authorization must not claim human approval.") unless
    human_status == "not-required" && human_head == "not-required" && human_approval_evidence == "not-required"
else
  fail_review("An incomplete independent review must retain its blocking findings.") if blocking == "none"
  fail_review("An incomplete independent review must report confidence as exactly 'below 100%'.") unless confidence == "below 100%"
  fail_review("An incomplete independent review must recommend 'human-review-required'.") unless recommendation == "human-review-required"
  fail_review("An incomplete independent review conclusion must be 'human-review-required'.") unless conclusion == "human-review-required"
  fail_review("Reviewer uncertainty requires the human authorization route.") unless authorization_route == "human"
  fail_review("Human approval status must be 'approved'.") unless human_status == "approved"
  fail_review("Human approval is stale or not bound to the current head.") unless human_head == head_sha
  fail_review("Human approval evidence is missing or not exact-head owner authorization.") unless human_approval_evidence == human_evidence
end

latest_by_reviewer = reviews
  .select { |candidate| ["APPROVED", "CHANGES_REQUESTED", "DISMISSED"].include?(candidate["state"]) }
  .reject { |candidate| candidate.dig("user", "login").to_s.empty? }
  .group_by { |candidate| candidate.dig("user", "login") }
  .transform_values { |entries| entries.max_by { |entry| [entry["submitted_at"].to_s, entry["id"].to_i] } }

blocking_review = latest_by_reviewer.values.find do |candidate|
  candidate["commit_id"] == head_sha && candidate["state"] == "CHANGES_REQUESTED"
end
fail_review("A current-head GitHub review requests changes.") if blocking_review

puts "Independent review record is complete for #{head_sha} via the #{authorization_route} authorization route."
RUBY
