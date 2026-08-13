#!/usr/bin/env bash
set -euo pipefail

HEAD_SHA="${HEAD_SHA:-}"
PR_BODY="${PR_BODY:-}"
PR_URL="${PR_URL:-}"
PR_AUTHOR="${PR_AUTHOR:-}"
REVIEWS_JSON_FILE="${REVIEWS_JSON_FILE:-}"
CONTRIBUTORS_JSON_FILE="${CONTRIBUTORS_JSON_FILE:-}"

if [[ ! "$HEAD_SHA" =~ ^[0-9a-f]{40}$ || -z "$PR_BODY" || -z "$PR_URL" || -z "$PR_AUTHOR" ]]; then
  echo "Review-record validation needs exact pull-request metadata." >&2
  exit 2
fi
if [[ ! -f "$REVIEWS_JSON_FILE" ]]; then
  echo "Review-record validation needs fetched GitHub reviews." >&2
  exit 2
fi
if [[ ! -f "$CONTRIBUTORS_JSON_FILE" ]]; then
  echo "Review-record validation needs fetched pull-request commits." >&2
  exit 2
fi

ruby -rjson - "$HEAD_SHA" "$PR_URL" "$PR_AUTHOR" "$REVIEWS_JSON_FILE" "$CONTRIBUTORS_JSON_FILE" <<'RUBY'
head_sha, pr_url, pr_author, reviews_path, contributors_path = ARGV
pr_body = ENV.fetch("PR_BODY")
reviews = JSON.parse(File.read(reviews_path))
commits = JSON.parse(File.read(contributors_path))

def fail_review(message)
  warn message
  exit 1
end

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
fail_review("The independent review must be a non-approval COMMENTED submission.") unless review["state"] == "COMMENTED"

review_body = review.fetch("body", "")
reviewer = exact_field(review_body, "Reviewer")
reviewed_head = exact_field(review_body, "Exact reviewed head")
coverage = exact_field(review_body, "Review requirement coverage")
unverified = exact_field(review_body, "Review unverified requirements")
blocking = exact_field(review_body, "Blocking findings")
conclusion = exact_field(review_body, "Conclusion")

fail_review("Independent review identity is not the isolated project reviewer.") unless reviewer == "project pr-reviewer (read-only, no inherited conversation)"
fail_review("Independent review head does not match the current head.") unless reviewed_head == head_sha
fail_review("Independent review contains unverified in-scope requirements.") unless unverified == "none"
fail_review("Independent review contains blocking findings.") unless blocking == "none"
fail_review("Independent review conclusion is incomplete.") unless conclusion == "requirements-complete"

requirement_count_line = pr_body.lines.map(&:strip).find { |line| line.start_with?("- Requirement count: ") }
fail_review("PR requirement count is missing.") unless requirement_count_line
requirement_count_text = requirement_count_line.delete_prefix("- Requirement count: ")
fail_review("PR requirement count is invalid.") unless requirement_count_text.match?(/\A[1-9][0-9]*\z/)
requirement_count = Integer(requirement_count_text, 10)
expected_coverage = "#{requirement_count}/#{requirement_count}"
fail_review("Independent review coverage must be #{expected_coverage}.") unless coverage == expected_coverage

requirement_rows = pr_body.lines.each_with_object([]) do |line, collected|
  cells = line.strip.split("|", -1).drop(1).tap(&:pop).map(&:strip)
  next unless cells.length == 6 && cells.first.match?(/\AR[1-9][0-9]*\z/)

  id, _requirement, acceptance, proof, _evidence, _status = cells
  collected << [id, acceptance, proof]
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
  _requirement_id, required_acceptance, required_proof = requirement_rows.fetch(index)
  fail_review("#{id} changed or omitted the PR acceptance criterion.") unless acceptance == required_acceptance
  fail_review("#{id} changed or omitted the required proof type.") unless proof == required_proof
  fail_review("#{id} remains unverified in the independent review.") unless status == "VERIFIED"
  fail_review("#{id} is missing independently inspected evidence.") if evidence.empty? || evidence.match?(/\A(pending|unverified|none|not inspected)\z/i)
  fail_review("#{id} is missing an independent evidence assessment.") if assessment.empty? || assessment.match?(/\A(pending|unverified|none)\z/i)
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

implementation_logins = [pr_author]
commits.each do |commit|
  implementation_logins << commit.dig("author", "login").to_s
  implementation_logins << commit.dig("committer", "login").to_s
end
implementation_logins = implementation_logins.reject(&:empty?).map(&:downcase).uniq

approval = latest_by_reviewer.values.find do |candidate|
  login = candidate.dig("user", "login").to_s
  user_type = candidate.dig("user", "type").to_s
  !implementation_logins.include?(login.downcase) && user_type != "Bot" && !login.end_with?("[bot]") &&
    candidate["commit_id"] == head_sha && candidate["state"] == "APPROVED"
end
fail_review("At least one current-head approval from a non-author, non-implementer human reviewer is required.") unless approval

puts "Independent review record and non-author approval are complete for #{head_sha}."
RUBY
