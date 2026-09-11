#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CI_WORKFLOW="$ROOT/.github/workflows/ci.yml"
LIVE_WORKFLOW="$ROOT/.github/workflows/live.yml"
PRE_PUSH_HOOK="$ROOT/.githooks/pre-push"
DEPLOY_WORKFLOW="$ROOT/.github/workflows/deploy-ios.yml"
DEPENDABOT="$ROOT/.github/dependabot.yml"
REVIEWER_AGENT="$ROOT/.codex/agents/pr-reviewer.toml"
PLANNER_AGENT="$ROOT/.codex/agents/work-package-planner.toml"
MILESTONE_PLANNER_AGENT="$ROOT/.codex/agents/major-milestone-planner.toml"
REVIEW_SKILL="$ROOT/.agents/skills/review-verify-merge-pr/SKILL.md"
REVIEW_INTERFACE="$ROOT/.agents/skills/review-verify-merge-pr/agents/openai.yaml"
DEVELOP_SKILL="$ROOT/.agents/skills/develop-openkeyboard/SKILL.md"
DEVELOP_INTERFACE="$ROOT/.agents/skills/develop-openkeyboard/agents/openai.yaml"
PRODUCT_COPY_SKILL="$ROOT/.agents/skills/write-openkeyboard-product-copy/SKILL.md"
PRODUCT_COPY_INTERFACE="$ROOT/.agents/skills/write-openkeyboard-product-copy/agents/openai.yaml"
UI_AUDIT_SKILL="$ROOT/.agents/skills/audit-openkeyboard-ui/SKILL.md"
UI_AUDIT_INTERFACE="$ROOT/.agents/skills/audit-openkeyboard-ui/agents/openai.yaml"
PLAN_SKILL="$ROOT/.agents/skills/plan-openkeyboard-work-package/SKILL.md"
PLAN_INTERFACE="$ROOT/.agents/skills/plan-openkeyboard-work-package/agents/openai.yaml"
MILESTONE_PLAN_SKILL="$ROOT/.agents/skills/plan-openkeyboard-major-milestone/SKILL.md"
MILESTONE_PLAN_INTERFACE="$ROOT/.agents/skills/plan-openkeyboard-major-milestone/agents/openai.yaml"
PR_TEMPLATE="$ROOT/.github/pull_request_template.md"
BRANCH_PROTECTION_GUIDE="$ROOT/.github/BRANCH_PROTECTION_GUIDE.md"
LIVE_EVIDENCE_POLICY_TEST="$ROOT/scripts/tests/live-evidence-policy-test.sh"
LIVE_EVIDENCE_VALIDATOR="$ROOT/scripts/validate-pr-live-evidence.sh"
PR_REQUIREMENTS_VALIDATOR="$ROOT/scripts/validate-pr-requirements.sh"
PR_REQUIREMENTS_POLICY_TEST="$ROOT/scripts/tests/pr-requirements-policy-test.sh"
PR_REVIEW_RECORD_VALIDATOR="$ROOT/scripts/validate-pr-review-record.sh"
PR_REVIEW_RECORD_POLICY_TEST="$ROOT/scripts/tests/pr-review-record-policy-test.sh"
REVIEW_WORKFLOW_SNAPSHOT_TEST="$ROOT/scripts/tests/review-workflow-snapshot-test.sh"
DEPLOY_SOURCE_POLICY_TEST="$ROOT/scripts/tests/deploy-source-policy-test.sh"
DEPLOY_SOURCE_VALIDATOR="$ROOT/scripts/validate-deployment-source.sh"
LIVE_TEST_SAFETY="$ROOT/scripts/ios/live-test-safety.sh"
LIVE_TEST_SAFETY_POLICY_TEST="$ROOT/scripts/tests/live-test-safety-test.sh"
LIVE_POLICY_BOOTSTRAP="$ROOT/scripts/live-policy-bootstrap.sh"
LIVE_POLICY_BOOTSTRAP_TEST="$ROOT/scripts/tests/live-policy-bootstrap-test.sh"
RUNTIME_PROOF_POLICY_TEST="$ROOT/scripts/tests/runtime-proof-policy-test.sh"
WORKFLOW_AUTHORIZATION_POLICY_TEST="$ROOT/scripts/tests/workflow-authorization-policy-test.sh"
SEMANTIC_CONTRACT_CHECK="$ROOT/scripts/check-semantic-prompt-contract.sh"
SEMANTIC_CONTRACT_ROOT="$ROOT/Vendor/semantic-prompt-contract"

for required_file in \
  "$CI_WORKFLOW" \
  "$LIVE_WORKFLOW" \
  "$PRE_PUSH_HOOK" \
  "$DEPLOY_WORKFLOW" \
  "$DEPENDABOT" \
  "$REVIEWER_AGENT" \
  "$PLANNER_AGENT" \
  "$MILESTONE_PLANNER_AGENT" \
  "$REVIEW_SKILL" \
  "$REVIEW_INTERFACE" \
  "$DEVELOP_SKILL" \
  "$DEVELOP_INTERFACE" \
  "$PRODUCT_COPY_SKILL" \
  "$PRODUCT_COPY_INTERFACE" \
  "$UI_AUDIT_SKILL" \
  "$UI_AUDIT_INTERFACE" \
  "$PLAN_SKILL" \
  "$PLAN_INTERFACE" \
  "$MILESTONE_PLAN_SKILL" \
  "$MILESTONE_PLAN_INTERFACE" \
  "$PR_TEMPLATE" \
  "$BRANCH_PROTECTION_GUIDE" \
  "$LIVE_EVIDENCE_POLICY_TEST" \
  "$LIVE_EVIDENCE_VALIDATOR" \
  "$PR_REQUIREMENTS_VALIDATOR" \
  "$PR_REQUIREMENTS_POLICY_TEST" \
  "$PR_REVIEW_RECORD_VALIDATOR" \
  "$PR_REVIEW_RECORD_POLICY_TEST" \
  "$REVIEW_WORKFLOW_SNAPSHOT_TEST" \
  "$DEPLOY_SOURCE_POLICY_TEST" \
  "$DEPLOY_SOURCE_VALIDATOR" \
  "$LIVE_TEST_SAFETY" \
  "$LIVE_TEST_SAFETY_POLICY_TEST" \
  "$LIVE_POLICY_BOOTSTRAP" \
  "$LIVE_POLICY_BOOTSTRAP_TEST" \
  "$RUNTIME_PROOF_POLICY_TEST" \
  "$WORKFLOW_AUTHORIZATION_POLICY_TEST" \
  "$SEMANTIC_CONTRACT_CHECK" \
  "$SEMANTIC_CONTRACT_ROOT/contracts/manifest.json"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Required workflow policy file is missing: $required_file" >&2
    exit 1
  fi
done

"$RUNTIME_PROOF_POLICY_TEST"

if rg --quiet 'pull_request_target|secrets\.' "$CI_WORKFLOW" "$LIVE_WORKFLOW"; then
  echo "Ordinary and live-policy CI must remain read-only and secretless." >&2
  exit 1
fi
if rg --quiet ':[[:space:]]*write([[:space:]]|$)' "$CI_WORKFLOW" "$LIVE_WORKFLOW"; then
  echo "Ordinary and live-policy CI must not request write permissions." >&2
  exit 1
fi

rg --quiet 'contents:[[:space:]]*read' "$CI_WORKFLOW"
rg --quiet 'pull-requests:[[:space:]]*read' "$LIVE_WORKFLOW"
rg --quiet 'checks:[[:space:]]*read' "$CI_WORKFLOW"
rg --quiet 'github\.event\.pull_request\.head\.sha \|\| github\.sha' "$CI_WORKFLOW"
rg --quiet 'github\.event\.pull_request\.head\.sha' "$LIVE_WORKFLOW"
if rg --quiet '^concurrency:|queue:[[:space:]]*max' "$CI_WORKFLOW" "$LIVE_WORKFLOW"; then
  echo "Metadata checks must not rely on capped or non-chronological concurrency queues." >&2
  exit 1
fi
if rg --quiet '^  workflow_dispatch:' "$CI_WORKFLOW"; then
  echo "Manual CI dispatch must not create a protected review check on an arbitrary branch." >&2
  exit 1
fi
rg --fixed-strings --quiet 'live-impact.sh \' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'supports_differential=false' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'TRUSTED_LIVE_IMPACT=$trusted_live_impact' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'LIVE_POLICY_BOOTSTRAP_DIFFERENTIAL=$bootstrap_differential' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'source "$GITHUB_WORKSPACE/scripts/live-policy-bootstrap.sh"' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'openkeyboard_resolve_live_policy_bootstrap' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'openkeyboard_write_trusted_gateway_projection' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet '"$GITHUB_WORKSPACE/scripts/validate-pr-live-evidence.sh"' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'trusted-gateway-projection.md' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'LIVE_IMPACT="$TRUSTED_LIVE_IMPACT"' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'gateway-differential)' "$PRE_PUSH_HOOK"
rg --fixed-strings --quiet '"$ROOT/scripts/check-live.sh" gateway-differential' "$PRE_PUSH_HOOK"
rg --quiet 'git show "\$PR_BASE_SHA:scripts/\$validator_name"' "$LIVE_WORKFLOW"
rg --quiet 'environment:[[:space:]]*live-policy' "$LIVE_WORKFLOW"
rg --quiet 'local_live_verification_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_verification_target_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_tested_head_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'required_live_models_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'exact_live_tested_models_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_model_substitutions_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_baseline_outcomes_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_differential_outcomes_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_follow_up_outcomes_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_profile_latencies_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'required_live_models.*exact_live_tested_models' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_tested_head.*HEAD_SHA' "$LIVE_EVIDENCE_VALIDATOR"
rg --fixed-strings --quiet 'jq -r '\''.pull_request.body // ""'\'' "$GITHUB_EVENT_PATH" > "$EVENT_BODY_FILE"' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'current_pr_json="$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER")"' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'current_head_sha="$(jq -er '\''.head.sha'\'' <<<"$current_pr_json")"' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'if [[ "$current_head_sha" != "$EVENT_HEAD_SHA" ]]' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'EVENT_BODY_FILE: ${{ runner.temp }}/event-pull-request-body.md' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'CURRENT_BODY_FILE: ${{ runner.temp }}/current-pull-request-body.md' "$LIVE_WORKFLOW"
rg --fixed-strings --quiet 'for snapshot_name in event current; do' "$LIVE_WORKFLOW"
if rg --quiet 'max_attempts=|sleep [0-9]' "$LIVE_WORKFLOW"; then
  echo "Live evidence must not poll mutable metadata or wait for a handoff." >&2
  exit 1
fi
if rg --fixed-strings --quiet 'if [[ "$PR_BODY" != *"$HEAD_SHA"* ]]' "$LIVE_EVIDENCE_VALIDATOR"; then
  echo "Live evidence must bind the dedicated exact-head field, not any PR-body occurrence." >&2
  exit 1
fi
rg --quiet 'Required checks' "$CI_WORKFLOW"
rg --fixed-strings --quiet 'Required technical checks' "$CI_WORKFLOW"
if rg --fixed-strings --quiet 'Incomplete review evidence' "$CI_WORKFLOW"; then
  echo "Every review-metadata event must create the protected check instead of hiding failures under another name." >&2
  exit 1
fi
rg --quiet '^  required-review-evidence:$' "$CI_WORKFLOW"
rg --quiet 'validate-pr-requirements\.sh' "$CI_WORKFLOW"
rg --quiet 'validate-pr-review-record\.sh' "$CI_WORKFLOW"
rg --quiet 'pull_request_review:' "$CI_WORKFLOW"
rg --quiet 'pull-requests:[[:space:]]*read' "$CI_WORKFLOW"
rg --quiet 'pull-request-reviews\.json' "$CI_WORKFLOW"
rg --fixed-strings --quiet 'event_head_sha="$(jq -er '\''.pull_request.head.sha'\'' "$GITHUB_EVENT_PATH")"' "$CI_WORKFLOW"
rg --fixed-strings --quiet 'jq -r '\''.pull_request.body // ""'\'' "$GITHUB_EVENT_PATH" > "$event_body_file"' "$CI_WORKFLOW"
rg --fixed-strings --quiet 'current_pr_json="$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER")"' "$CI_WORKFLOW"
rg --fixed-strings --quiet 'jq -r '\''.body // ""'\'' <<<"$current_pr_json" > "$current_body_file"' "$CI_WORKFLOW"
rg --fixed-strings --quiet 'if [[ "$EVENT_NAME" == "pull_request_review" ]]' "$CI_WORKFLOW"
rg --fixed-strings --quiet 'jq -e '\''.review | objects'\'' "$GITHUB_EVENT_PATH" > "$event_review_file"' "$CI_WORKFLOW"
rg --fixed-strings --quiet 'validate_snapshot event "$event_body_file" "$event_review_file"' "$CI_WORKFLOW"
rg --fixed-strings --quiet 'validate_snapshot current "$current_body_file" ""' "$CI_WORKFLOW"
if rg --quiet 'classify-review-check-state|history_poisoned|emit_incomplete|check_name=' "$CI_WORKFLOW"; then
  echo "Review readiness must not depend on processing or completion order from historical check runs." >&2
  exit 1
fi
if rg --quiet 'pull-request-commits\.json|CONTRIBUTORS_JSON_FILE' "$CI_WORKFLOW"; then
  echo "Conditional owner authorization must not depend on an impossible non-author approval in a solo repository." >&2
  exit 1
fi
rg --quiet 'git show "\$PR_BASE_SHA:scripts/\$validator_name"' "$CI_WORKFLOW"
ruby -e '
  require "yaml"

  jobs = YAML.load_file(ARGV.fetch(0)).fetch("jobs")
  technical = jobs.fetch("required-technical-checks")
  abort "Technical aggregation has the wrong protected name." unless technical.fetch("name") == "Required technical checks"
  abort "Technical aggregation must not depend on review classification." if
    Array(technical.fetch("needs")).include?("required-review-evidence")

  review = jobs.fetch("required-review-evidence")
  review_name = review.fetch("name")
  abort "Every review event must use the fixed protected check name." unless
    review_name.include?("Required checks") && review_name.include?("Review evidence not applicable")
  abort "The protected review check must be a root job so cancellation cannot hide behind a prerequisite." if review.key?("needs")

  live = YAML.load_file(ARGV.fetch(1)).fetch("jobs").fetch("required-live-verification")
  abort "The live check has the wrong protected name." unless live.fetch("name") == "Required live verification"
  abort "The protected live check must be a root job so cancellation cannot hide behind a prerequisite." if live.key?("needs")
' "$CI_WORKFLOW" "$LIVE_WORKFLOW"
rg --quiet 'name: Semantic prompt contract' "$CI_WORKFLOW"
rg --quiet 'submodules:[[:space:]]*recursive' "$CI_WORKFLOW"
rg --quiet 'check-semantic-prompt-contract\.sh' "$CI_WORKFLOW"
rg --quiet '^## Shared Semantic Prompt Contract$' "$ROOT/AGENTS.md"
rg --quiet 'only canonical home' "$ROOT/AGENTS.md"
rg --quiet '^## Straight-line task flow$' "$ROOT/AGENTS.md"
rg --fixed-strings --quiet 'Follow this order. Load a detailed document or specialized skill only when the matching step needs' "$ROOT/AGENTS.md"
git -C "$ROOT" ls-files --stage Vendor/semantic-prompt-contract | rg --quiet '^160000 '
rg --quiet 'Required live verification' "$LIVE_WORKFLOW"
rg --quiet 'environment:[[:space:]]*app-store-connect' "$DEPLOY_WORKFLOW"
rg --quiet '^  validate-release-source:$' "$DEPLOY_WORKFLOW"
rg --quiet 'refs/heads/main' "$DEPLOY_SOURCE_VALIDATOR"
rg --quiet 'validate-release-source' "$DEPLOY_WORKFLOW"
rg --quiet 'git merge-base --is-ancestor' "$DEPLOY_SOURCE_VALIDATOR"
if [[ "$(rg --count '\./scripts/validate-deployment-source\.sh' "$DEPLOY_WORKFLOW")" -ne 2 ]]; then
  echo "Deployment source must be validated before and after protected-environment approval." >&2
  exit 1
fi
ruby -e '
  require "yaml"

  jobs = YAML.load_file(ARGV.fetch(0)).fetch("jobs")
  expected = {
    "validate-release-source" => "Enforce trusted deployment ref",
    "deploy-ios" => "Revalidate trusted deployment ref after approval"
  }
  expected.each do |job_name, step_name|
    steps = jobs.fetch(job_name).fetch("steps")
    step = steps.find { |candidate| candidate["name"] == step_name }
    abort "#{job_name} is missing #{step_name}." unless step
    abort "#{step_name} must use the shared validator." unless step["run"] == "./scripts/validate-deployment-source.sh"
  end
' "$DEPLOY_WORKFLOW"
rg --quiet '^sandbox_mode = "read-only"$' "$REVIEWER_AGENT"
rg --quiet 'Remain read-only' "$REVIEWER_AGENT"
rg --fixed-strings --quiet 'Reviewer confidence' "$REVIEWER_AGENT"
rg --fixed-strings --quiet 'Merge recommendation' "$REVIEWER_AGENT"
rg --fixed-strings --quiet 'below 100%' "$REVIEWER_AGENT"
rg --fixed-strings --quiet 'human-review-required' "$REVIEWER_AGENT"
rg --fixed-strings --quiet 'across both `pull_request` and `pull_request_review` event families' "$REVIEWER_AGENT"
rg --fixed-strings --quiet 'gh pr checks <number> --required' "$REVIEWER_AGENT"
rg --quiet '^sandbox_mode = "read-only"$' "$PLANNER_AGENT"
rg --quiet 'Do not edit files.*access GitHub' "$PLANNER_AGENT"
rg --quiet '^sandbox_mode = "read-only"$' "$MILESTONE_PLANNER_AGENT"
rg --fixed-strings --quiet 'Do not edit files, fetch, create a worktree' "$MILESTONE_PLANNER_AGENT"
rg --fixed-strings --quiet 'GitHub, spawn agents' "$MILESTONE_PLANNER_AGENT"
rg --quiet 'project `pr-reviewer`' "$REVIEW_SKILL"
rg --quiet 'scripts/check\.sh --full' "$REVIEW_SKILL"
rg --fixed-strings --quiet 'Required technical checks' "$REVIEW_SKILL"
rg --quiet 'Required checks' "$REVIEW_SKILL"
rg --quiet 'Required live verification' "$REVIEW_SKILL"
rg --fixed-strings --quiet 'Reviewer confidence: 100%' "$REVIEW_SKILL"
rg --fixed-strings --quiet 'Reviewer confidence: below 100%' "$REVIEW_SKILL"
rg --fixed-strings --quiet 'Merge recommendation: human-review-required' "$REVIEW_SKILL"
rg --fixed-strings --quiet 'Review-evidence revalidation trigger for exact head <full-sha>.' "$REVIEW_SKILL"
rg --fixed-strings --quiet 'gh pr checks <number> --required' "$REVIEW_SKILL"
rg --quiet 'repository-owner approval' "$REVIEW_SKILL"
rg --quiet 'Human-approved head' "$REVIEW_SKILL"
rg --quiet 'statement about policy' "$REVIEW_SKILL"
rg --fixed-strings --quiet 'report-dependent `Required checks`' "$REVIEW_SKILL"
rg --quiet 'After the root posts and links the report' "$REVIEW_SKILL"
rg --quiet 'wrong-model' "$REVIEW_SKILL"
rg --quiet 'durable GitHub `COMMENTED` review' "$REVIEW_SKILL"
if rg --quiet 'at least one approving GitHub review' "$REVIEW_SKILL"; then
  echo "The review skill retained the impossible non-author approval gate." >&2
  exit 1
fi
rg --quiet 'bounded implementation request.*normal autonomous.*guarded merge' "$REVIEW_SKILL"
rg --quiet 'active sticky constraint says `keep draft`' "$REVIEW_SKILL"
rg --quiet 'constraint says `do not merge`' "$REVIEW_SKILL"
rg --quiet 'gh pr merge <number> --auto --squash --match-head-commit <reviewed-head-sha>' "$REVIEW_SKILL"
rg --quiet 'Never leave queued auto-merge active' "$REVIEW_SKILL"
rg --quiet '^name: develop-openkeyboard$' "$DEVELOP_SKILL"
rg --fixed-strings --quiet 'Use `AGENTS.md` as the canonical execution policy.' "$DEVELOP_SKILL"
rg --fixed-strings --quiet '$write-openkeyboard-product-copy' "$DEVELOP_SKILL"
rg --quiet '\$plan-openkeyboard-work-package' "$DEVELOP_SKILL"
rg --quiet '\$plan-openkeyboard-major-milestone' "$DEVELOP_SKILL"
rg --quiet '\$review-verify-merge-pr' "$DEVELOP_SKILL"
rg --quiet '^## Lifecycle autonomy$' "$DEVELOP_SKILL"
rg --quiet '^name: write-openkeyboard-product-copy$' "$PRODUCT_COPY_SKILL"
rg --fixed-strings --quiet 'predecessor to target to successor' "$PRODUCT_COPY_SKILL"
ruby -e '
  require "yaml"

  normalize = ->(path) { File.read(path).gsub(/\s+/, " ").strip }
  skill = normalize.call(ARGV.fetch(0))
  interface_path = ARGV.fetch(1)
  agents = normalize.call(ARGV.fetch(2))
  develop = normalize.call(ARGV.fetch(3))
  workflow = normalize.call(ARGV.fetch(4))

  expected_agents_route =
    "For work centered on user-visible app or keyboard wording, use " \
    "`$write-openkeyboard-product-copy` within `$develop-openkeyboard` to shape the target screen " \
    "and its connected journey before editing."
  abort "AGENTS.md must route copy-centered implementation through the product-copy specialist inside the development route." unless
    agents.include?(expected_agents_route)

  expected_develop_route =
    "For work centered on user-visible app or keyboard wording, use " \
    "`$write-openkeyboard-product-copy` to review the target screen, incoming and outgoing journey, " \
    "product claims, terminology, reachable states, and accessibility labels before editing."
  abort "The development skill must apply the product-copy specialist to screen, journey, claim, state, and accessibility decisions before editing." unless
    develop.include?(expected_develop_route)

  workflow_requirements = {
    "development route" =>
      "For work centered on visible app or keyboard wording, `$write-openkeyboard-product-copy` runs inside the development route.",
    "screen-to-journey review" =>
      "It reviews the requested screen together with its incoming and outgoing journey, balances interface clarity with truthful product positioning, checks reachable states and accessibility language, and protects shared terminology.",
    "read-only audit boundary" =>
      "A copy audit remains read-only unless implementation is already authorized.",
    "semantic prompt boundary" =>
      "The skill never edits canonical semantic prompts or generated user content",
    "UI proof boundary" =>
      "an implemented UI-copy change still requires the normal UI proof route."
  }
  workflow_requirements.each do |label, requirement|
    abort "The development workflow is missing the product-copy #{label}." unless workflow.include?(requirement)
  end

  semantic_scope =
    "Keep semantic operation identifiers, model instructions, prompt wording, response schemas, " \
    "and generated response content in the pinned `Vendor/semantic-prompt-contract`. This skill owns " \
    "product-interface language, not model prompts or the user\u0027s generated writing."
  abort "The product-copy specialist must exclude canonical model prompts and generated user content from its scope." unless
    skill.include?(semantic_scope)

  runtime_boundary =
    "User-visible copy changes are UI changes, so follow `AGENTS.md` for automated regression " \
    "evidence and normal simulator runtime proof before push."
  abort "The product-copy specialist must require normal simulator runtime proof for implemented UI copy." unless
    skill.include?(runtime_boundary)

  interface = YAML.load_file(interface_path)
  abort "The product-copy interface metadata must be a mapping." unless interface.is_a?(Hash)
  interface_values = interface["interface"]
  abort "The product-copy interface metadata is missing interface values." unless interface_values.is_a?(Hash)
  default_prompt = interface_values["default_prompt"]
  unless default_prompt.is_a?(String) &&
      default_prompt.match?(/\AUse \$write-openkeyboard-product-copy(?:\s|[.,:;])/)
    abort "The product-copy interface default prompt must explicitly invoke $write-openkeyboard-product-copy."
  end

  policy = interface["policy"]
  unless policy.nil?
    abort "The product-copy interface policy must be a mapping when present." unless policy.is_a?(Hash)
    if policy.key?("allow_implicit_invocation")
      value = policy["allow_implicit_invocation"]
      implicit_allowed = value == true || (value.is_a?(String) && value.casecmp("true").zero?)
      abort "The product-copy skill must remain available for implicit workflow routing." unless implicit_allowed
    end
  end
' "$PRODUCT_COPY_SKILL" "$PRODUCT_COPY_INTERFACE" "$ROOT/AGENTS.md" "$DEVELOP_SKILL" "$ROOT/docs/DEVELOPMENT_WORKFLOW.md"
rg --quiet '^name: audit-openkeyboard-ui$' "$UI_AUDIT_SKILL"
ruby -e '
  require "yaml"

  normalize = ->(text) { text.gsub(/\s+/, " ").strip }
  require_match = lambda do |label, text, pattern|
    abort "The UI-audit policy is missing #{label}." unless text.match?(pattern)
  end

  skill_source = File.read(ARGV.fetch(0))
  interface_path = ARGV.fetch(1)
  agents = normalize.call(File.read(ARGV.fetch(2)))
  develop = normalize.call(File.read(ARGV.fetch(3)))
  workflow = normalize.call(File.read(ARGV.fetch(4)))

  frontmatter_match = skill_source.match(/\A---\s*\n(?<yaml>.*?)\n---\s*\n/m)
  abort "The UI-audit skill is missing YAML frontmatter." unless frontmatter_match
  frontmatter = YAML.safe_load(frontmatter_match[:yaml], aliases: false)
  abort "The UI-audit skill frontmatter must be a mapping." unless frontmatter.is_a?(Hash)
  abort "The UI-audit skill has the wrong canonical name." unless frontmatter["name"] == "audit-openkeyboard-ui"
  description = frontmatter["description"]
  unless description.is_a?(String) &&
      description.match?(/Audit OpenKeyboard SwiftUI screens and end-to-end journeys/) &&
      description.match?(/route wording-only analysis to the product-copy skill/) &&
      description.match?(/authorized fixes to the development skill/)
    abort "The UI-audit skill description must advertise journey-aware audits and its copy/fix handoffs."
  end

  interface = YAML.load_file(interface_path)
  abort "The UI-audit interface metadata must be a mapping." unless interface.is_a?(Hash)
  interface_values = interface["interface"]
  abort "The UI-audit interface metadata is missing interface values." unless interface_values.is_a?(Hash)
  default_prompt = interface_values["default_prompt"]
  unless default_prompt.is_a?(String) &&
      default_prompt.match?(/\AUse \$audit-openkeyboard-ui(?:\s|[.,:;])/)
    abort "The UI-audit interface default prompt must explicitly invoke $audit-openkeyboard-ui."
  end
  policy = interface["policy"]
  unless policy.nil?
    abort "The UI-audit interface policy must be a mapping when present." unless policy.is_a?(Hash)
    if policy.key?("allow_implicit_invocation")
      value = policy["allow_implicit_invocation"]
      implicit_allowed = value == true || (value.is_a?(String) && value.casecmp("true").zero?)
      abort "The UI-audit skill must remain available for implicit workflow routing." unless implicit_allowed
    end
  end

  skill = normalize.call(skill_source)
  skill_requirements = {
    "read-only audit authority" =>
      /Treat audit, review, diagnosis, and recommendation requests as read-only\..*Do not edit tracked files, stage, commit, publish, or change a PR during an audit\./,
    "production reachability before UI judgment" =>
      /Find the production app or extension entry point and the reachable call site.*Separate shipping paths from previews, component hosts, debug launch states, test-only routes, and dead or unreachable declarations\./,
    "control-to-behavior tracing" =>
      /Trace every material control to its production action and observable state transition\..*button-shaped view, accessibility identifier, or test fixture does not prove that a production action works\./,
    "state-producer tracing" =>
      /Enumerate reachable states from the real state producers, including applicable default, empty, loading, disabled, stale, success, partial, permission-needed, offline, authentication, timeout, cancellation, destructive, and recovery states\./,
    "layout, hierarchy, and adaptive presentation review" =>
      /Check reading order, visual priority, grouping, spacing, alignment, safe areas, scrolling, overlays.*Inspect fixed widths and heights.*Dynamic Type.*localization expansion\./,
    "tap-target review" =>
      /Check actual interactive bounds, padding, overlap, `contentShape`, and enabled state for tap targets\..*visible symbol size alone\./,
    "control, CTA, and state-behavior review" =>
      /Verify that every control.s affordance, enabled\/disabled appearance, loading behavior, action, success state, and retry path agree\./,
    "accessibility semantics and operation review" =>
      /Check accessible names, values, traits, hints, grouping, focus order, and state announcements\..*`accessibilityIdentifier` supports automation but is not a VoiceOver label\./,
    "theme and MVVM review" =>
      /Compare colors, typography, surfaces, strokes, shadows, radii, and semantic states with `OpenKeyboardTheme`\..*Views present data.*ViewModels own UI state and actions; services own networking, persistence, App Group, Keychain, gateway, and file I\/O\./,
    "source-only evidence ceiling" =>
      /Source, previews, fixtures, debug hosts, tests, accessibility metadata, and XCTest attachments are useful evidence, but none proves the normally rendered or operated product\..*Never claim visual, interaction, or runtime acceptance from source inspection alone\./,
    "adjacent-screen continuity without scope expansion" =>
      /For an isolated-screen request, inspect adjacent screens only far enough to detect broken entry, exit, terminology, state, or interaction continuity\..*Do not expand the requested deliverable or later fix scope without the user.s authorization\./,
    "wording-specialist delegation" =>
      /Use `\$write-openkeyboard-product-copy` for wording-specific analysis: titles, labels, explanatory text, claims, terminology, tone, and the semantic accuracy of CTA language\..*This skill retains ownership of control behavior, action reachability, placement, hierarchy, layout fit, accessibility behavior, navigation, and state transitions\./,
    "authorized-fix handoff" =>
      /After an explicit implementation request, use `\$develop-openkeyboard` and preserve the agreed finding IDs as the work boundary\..*Fix only the authorized target surfaces/
  }
  skill_requirements.each do |label, pattern|
    require_match.call(label, skill, pattern)
  end

  classification_section = skill_source.match(
    /^## Classify every finding\s*$\n(?<body>.*?)(?=^## |\z)/m
  )&.[](:body)
  abort "The UI-audit skill is missing its finding-classification section." unless classification_section
  classification_rules = classification_section.split(/\nUse these severities consistently:/, 2).first
  classifications = classification_rules.scan(/^- \*\*(.+?)\*\* —/).flatten
  expected_classifications = [
    "confirmed from code",
    "likely visual risk",
    "requires simulator verification"
  ]
  unless classifications == expected_classifications &&
      classification_rules.include?("Use exactly one of these classifications for every reported finding")
    abort "Every UI-audit finding must use exactly the three canonical evidence classifications."
  end

  finding_header = skill_source.lines.find { |line| line.start_with?("| ID | Severity | Classification |") }
  abort "The UI-audit report is missing its findings table." unless finding_header
  finding_fields = finding_header.strip.split("|").map(&:strip).reject(&:empty?)
  expected_fields = [
    "ID",
    "Severity",
    "Classification",
    "Surface / state",
    "Exact source evidence",
    "User impact",
    "Recommendation",
    "Required verification"
  ]
  abort "UI-audit findings must report severity, source evidence, impact, recommendation, and verification." unless
    finding_fields == expected_fields

  routing_requirements = {
    "AGENTS.md read-only audit route" => [
      agents,
      /Route a read-only UI audit through `\$audit-openkeyboard-ui`\./
    ],
    "AGENTS.md authorized-fix route" => [
      agents,
      /For authorized UI fixes, use that skill within `\$develop-openkeyboard`.*review adjacent-screen continuity without expanding the edit scope\./
    ],
    "AGENTS.md evidence and wording ownership" => [
      agents,
      /[Dd]elegate wording-specific analysis to `\$write-openkeyboard-product-copy`\..*Source inspection may establish code findings and visual risks, but never rendered or runtime acceptance\./
    ],
    "development-skill read-only and authorized-fix routes" => [
      develop,
      /Route UI audit requests through the read-only `\$audit-openkeyboard-ui`\..*When UI fixes are authorized, use it inside this implementation loop to trace SwiftUI controls and visible states through navigation, ViewModels, production behavior, and relevant tests before editing\./
    ],
    "development-skill scope and specialist boundaries" => [
      develop,
      /Review adjacent screens for journey continuity without adding them to the edit scope\..*delegate wording-specific analysis to `\$write-openkeyboard-product-copy`\..*never present source inspection as rendered or runtime acceptance\./
    ],
    "documented read-only audit route" => [
      workflow,
      /UI audit requests route to the read-only `\$audit-openkeyboard-ui`\..*without silently expanding the edit scope\./
    ],
    "documented specialist and evidence boundaries" => [
      workflow,
      /It owns layout, behavior, accessibility, and interaction findings while delegating wording-specific analysis to `\$write-openkeyboard-product-copy`\..*Source-only results must use `confirmed from code`, `likely visual risk`, or `requires simulator verification`; they never establish rendered or runtime acceptance\./
    ],
    "documented authorized-fix route" => [
      workflow,
      /When fixes are authorized, use the audit inside `\$develop-openkeyboard` and apply the normal implementation and proof gates\./
    ]
  }
  routing_requirements.each do |label, (source, pattern)|
    require_match.call(label, source, pattern)
  end
' "$UI_AUDIT_SKILL" "$UI_AUDIT_INTERFACE" "$ROOT/AGENTS.md" "$DEVELOP_SKILL" "$ROOT/docs/DEVELOPMENT_WORKFLOW.md"
rg --quiet '^name: plan-openkeyboard-work-package$' "$PLAN_SKILL"
rg --quiet 'git hash-object' "$PLAN_SKILL"
rg --quiet 'allow_implicit_invocation:[[:space:]]*false' "$PLAN_INTERFACE"
rg --quiet '^name: plan-openkeyboard-major-milestone$' "$MILESTONE_PLAN_SKILL"
rg --quiet 'git hash-object' "$MILESTONE_PLAN_SKILL"
rg --fixed-strings --quiet 'Prefer 3–8 phases' "$MILESTONE_PLAN_SKILL"
rg --fixed-strings --quiet 'Each phase must be' "$MILESTONE_PLAN_SKILL"
rg --fixed-strings --quiet 'First bounded work package:' "$MILESTONE_PLAN_SKILL"
rg --fixed-strings --quiet 'physical device by default' "$MILESTONE_PLAN_SKILL"
rg --quiet 'allow_implicit_invocation:[[:space:]]*false' "$MILESTONE_PLAN_INTERFACE"
rg --fixed-strings --quiet '$plan-openkeyboard-major-milestone' "$ROOT/AGENTS.md"
rg --fixed-strings --quiet 'A clear implementation request bypasses both planning routes.' "$ROOT/docs/DEVELOPMENT_WORKFLOW.md"
rg --quiet '^## Independent review$' "$PR_TEMPLATE"
rg --quiet '^## Requirements and proof$' "$PR_TEMPLATE"
rg --quiet '^## Merge authorization$' "$PR_TEMPLATE"
rg --quiet 'Review requirement coverage:' "$PR_TEMPLATE"
rg --quiet 'Independent review evidence:' "$PR_TEMPLATE"
rg --quiet 'Reviewer confidence:' "$PR_TEMPLATE"
rg --quiet 'Merge recommendation:' "$PR_TEMPLATE"
rg --quiet 'Merge authorization route:' "$PR_TEMPLATE"
rg --quiet 'Human approval status:' "$PR_TEMPLATE"
rg --quiet 'Human-approved head:' "$PR_TEMPLATE"
rg --quiet 'Human approval evidence:' "$PR_TEMPLATE"
rg --quiet 'Required live models:' "$PR_TEMPLATE"
rg --quiet 'Exact live-tested models:' "$PR_TEMPLATE"
rg --quiet 'Live-model substitutions:' "$PR_TEMPLATE"
rg --quiet 'Live baseline outcomes:' "$PR_TEMPLATE"
rg --quiet 'Live differential outcomes:' "$PR_TEMPLATE"
rg --quiet 'Live follow-up outcomes:' "$PR_TEMPLATE"
rg --quiet 'Live operation-scoped warning contracts:' "$PR_TEMPLATE"
rg --quiet 'Live profile latencies:' "$PR_TEMPLATE"
rg --quiet 'Live plain-text grammar verification:' "$PR_TEMPLATE"
rg --quiet 'Live summarize outcomes:' "$PR_TEMPLATE"
rg --quiet 'Live continue-writing outcomes:' "$PR_TEMPLATE"
rg --quiet 'Exact reviewed head:' "$PR_TEMPLATE"
rg --quiet '^## Exact head SHA$' "$PR_TEMPLATE"
rg --fixed-strings --quiet '`Required technical checks`' "$BRANCH_PROTECTION_GUIDE"
rg --fixed-strings --quiet '`Required checks`' "$BRANCH_PROTECTION_GUIDE"
rg --fixed-strings --quiet '`Required live verification`' "$BRANCH_PROTECTION_GUIDE"
rg --quiet 'scripts/ios/test\.sh.*deterministic-ui' "$ROOT/scripts/check.sh"
rg --fixed-strings --quiet 'BUILD_DESTINATION="generic/platform=iOS Simulator"' "$ROOT/scripts/ios/test.sh"
rg --fixed-strings --quiet 'DETERMINISTIC_UI_DERIVED_DATA="$REPO_ROOT/.build/deterministic-ui/DerivedData"' "$ROOT/scripts/ios/test.sh"
ruby -e '
  source = File.read(ARGV.fetch(0))
  build_case = source.match(/^  build\)\n(?<body>.*?)^    ;;$/m)&.[](:body)
  abort "The iOS test runner is missing its build mode." unless build_case
  unless build_case.include?(%q{-destination "$BUILD_DESTINATION"})
    abort "The build mode must use the generic simulator destination."
  end
  if build_case.include?(%q{-destination "$DESTINATION"})
    abort "The build mode must not require a named simulator."
  end
' "$ROOT/scripts/ios/test.sh"
rg --quiet -- '-skip-testing:OpenKeyboardUITests/KeyboardExtensionConfiguredUITests' "$ROOT/scripts/ios/test.sh"
rg --quiet -- '-skip-testing:OpenKeyboardUITests/LiveGatewayAIUITests' "$ROOT/scripts/ios/test.sh"
rg --quiet -- '-skip-testing:OpenKeyboardUITests/LiveGatewaySmokeTests' "$ROOT/scripts/ios/test.sh"
rg --quiet -- '-skip-testing:OpenKeyboardUITests/LiveModelDifferentialTests' "$ROOT/scripts/ios/test.sh"
ruby -e '
  source = File.read(ARGV.fetch(0))
  deterministic_case = source.match(/^  deterministic-ui\)\n(?<body>.*?)^    ;;$/m)&.[](:body)
  abort "The iOS test runner is missing deterministic-ui mode." unless deterministic_case
  expected = %q{-derivedDataPath "$DETERMINISTIC_UI_DERIVED_DATA"}
  unless deterministic_case.scan(expected).length == 1
    abort "The deterministic UI gate must use one worktree-scoped Xcode test session."
  end
  unless deterministic_case.scan(/-parallel-testing-enabled NO/).length == 1
    abort "The deterministic UI gate must keep its fixed simulator session serial."
  end
  if deterministic_case.include?("OnboardingScreenshotUITests")
    abort "The deterministic UI gate must include the onboarding assertion in its single test session."
  end
' "$ROOT/scripts/ios/test.sh"
rg --quiet 'begin_sensitive_live_workspace live-gateway-smoke' "$ROOT/scripts/ios/test.sh"
rg --quiet 'begin_sensitive_live_workspace live-model-differential' "$ROOT/scripts/ios/test.sh"
rg --fixed-strings --quiet 'live-model-differential [--diagnostic]' "$ROOT/scripts/ios/test.sh"
rg --fixed-strings --quiet 'openkeyboard_finish_live_differential_run \' "$ROOT/scripts/ios/test.sh"
rg --fixed-strings --quiet 'LIVE_UNVERIFIED: targeted two-profile live-model differential verification failed; required outcomes were unverified.' "$LIVE_TEST_SAFETY"
rg --fixed-strings --quiet 'LIVE_UNVERIFIED: targeted two-profile diagnostic run complete; this is not verification.' "$LIVE_TEST_SAFETY"
if rg --fixed-strings --quiet 'Targeted two-profile live-model differential verification complete' "$ROOT/scripts/ios/test.sh"; then
  echo "The differential runner retained the misleading green verification-complete message." >&2
  exit 1
fi
if rg --fixed-strings --quiet 'live-model-differential --diagnostic' "$ROOT/scripts/check-live.sh"; then
  echo "The exact-head live gate must never use diagnostic differential mode." >&2
  exit 1
fi
rg --quiet 'begin_sensitive_live_workspace real-keyboard-live' "$ROOT/scripts/ios/test.sh"
ruby -e '
  source = File.read(ARGV.fetch(0))
  live_case = source.match(/^  live-gateway-smoke\)\n(?<body>.*?)^    ;;$/m)&.[](:body)
  abort "The iOS test runner is missing live-gateway-smoke mode." unless live_case
  unless live_case.include?(%q{create_sensitive_live_simulator "iPhone 16"})
    abort "The live gateway smoke must create a disposable iPhone 16 simulator."
  end
  unless live_case.include?(%q{inject_xctestrun_live_smoke_env "$xctestrun"})
    abort "The live gateway smoke must use the encoded sensitive environment handoff."
  end
  expected = %q{-destination "$destination"}
  unless live_case.scan(expected).length == 2
    abort "Both live gateway Xcode invocations must use the disposable simulator destination."
  end
' "$ROOT/scripts/ios/test.sh"
ruby -e '
  source = File.read(ARGV.fetch(0))
  differential_case = source.match(/^  live-model-differential\)\n(?<body>.*?)^    ;;$/m)&.[](:body)
  abort "The iOS test runner is missing live-model-differential mode." unless differential_case
  unless differential_case.scan(/xcodebuild build-for-testing/).length == 1
    abort "The differential live runner must build its Xcode test artifacts exactly once."
  end
  unless differential_case.include?("for profile_role in low high")
    abort "The differential live runner must execute profiles in canonical low/high order."
  end
  unless differential_case.scan(/xcodebuild test-without-building/).length == 2
    abort "The differential live runner must reuse one build for one prerequisite command and the per-profile loop."
  end
  unless differential_case.include?(%q{openkeyboard_assert_passing_xcresult_count "$contract_result_bundle" 6})
    abort "The differential live runner must prove its deterministic warning prerequisites ran once."
  end
  unless differential_case.include?(%q{openkeyboard_classify_low_differential_xcresult "$profile_result_bundle"}) &&
      differential_case.include?(%q{openkeyboard_assert_single_passing_xcresult "$profile_result_bundle"})
    abort "The differential runner must classify low diagnostic success and require high-profile success."
  end
  unless differential_case.include?(%q{openkeyboard_extract_live_diagnostic_evidence "$profile_result_bundle" "$profile_role"})
    abort "The differential runner must retain sanitized per-profile diagnostic capability evidence."
  end
  unless differential_case.include?("openkeyboard_finish_live_differential_run") &&
      differential_case.include?(%q{"$LIVE_DIFFERENTIAL_EXECUTION_MODE"})
    abort "The differential runner must apply strict-versus-diagnostic completion semantics."
  end
' "$ROOT/scripts/ios/test.sh"
rg --fixed-strings --quiet 'live-gateway-diagnostics-\(role)' "$ROOT/OpenKeyboardUITests/GatewayClientArchitectureTests.swift"
rg --quiet '^openkeyboard_format_live_diagnostic_attachment()' "$ROOT/scripts/ios/live-test-safety.sh"
rg --quiet '^openkeyboard_extract_live_diagnostic_evidence()' "$ROOT/scripts/ios/live-test-safety.sh"
rg --quiet 'DIAGNOSTIC_OUTCOMES_LOW_LINE' "$ROOT/scripts/check-live.sh"
rg --quiet 'DIAGNOSTIC_LATENCIES_HIGH_LINE' "$ROOT/scripts/check-live.sh"
rg --quiet 'trap cleanup_sensitive_live_artifacts EXIT' "$ROOT/scripts/ios/test.sh"
rg --quiet 'source .*live-test-safety\.sh' "$ROOT/scripts/ios/test.sh"
rg --quiet 'source .*live-test-safety\.sh' "$ROOT/scripts/check-live.sh"
rg --quiet 'source .*live-test-safety\.sh' "$ROOT/scripts/ios/seed-simulator-gateway-config.sh"
rg --quiet 'openkeyboard_require_local_seed_file' "$ROOT/scripts/check-live.sh"
rg --quiet 'OPEN_KEYBOARD_LIVE_REQUIRED_MODEL' "$ROOT/scripts/check-live.sh"
rg --quiet 'OPEN_KEYBOARD_LIVE_REQUIRED_MODELS' "$ROOT/scripts/check-live.sh"
rg --quiet 'gateway-differential' "$ROOT/scripts/check-live.sh"
rg --quiet 'required_models=\$REQUIRED_MODELS' "$ROOT/scripts/check-live.sh"
rg --quiet 'tested_models=\$TESTED_MODELS' "$ROOT/scripts/check-live.sh"
rg --quiet 'TESTED_MODEL.*REQUIRED_MODEL' "$ROOT/scripts/check-live.sh"
rg --quiet 'required_model=\$REQUIRED_MODEL' "$ROOT/scripts/check-live.sh"
rg --quiet 'tested_model=\$TESTED_MODEL' "$ROOT/scripts/check-live.sh"
rg --quiet 'plain_text_grammar_verified=true' "$ROOT/scripts/check-live.sh"
if rg --quiet 'OPEN_KEYBOARD_LIVE_REQUIRE_STRUCTURED_CORRECTIONS|structured_corrections_required' "$ROOT/scripts/check-live.sh"; then
  echo "The exact-head live gate still has a structured-correction escape hatch." >&2
  exit 1
fi
if rg --quiet 'OPEN_KEYBOARD_TEST_REQUIRE_STRUCTURED_CORRECTIONS' "$ROOT/scripts/ios/test.sh"; then
  echo "The live simulator smoke still injects the removed structured-correction requirement." >&2
  exit 1
fi
rg --quiet 'Test Connection did not verify plain-text grammar' "$ROOT/OpenKeyboardUITests/GatewayClientArchitectureTests.swift"
rg --quiet 'openkeyboard_require_local_seed_file' "$ROOT/scripts/ios/seed-simulator-gateway-config.sh"
rg --quiet 'exact seeded model without catalog fallback' "$ROOT/OpenKeyboardUITests/GatewayClientArchitectureTests.swift"
rg --quiet 'testRealKeyboardImproveReplacesTextWhenGatewayConfigured' "$ROOT/scripts/ios/test.sh"
if rg --quiet 'testRealKeyboardFixGrammarReplacesTextWhenGatewayConfigured' "$ROOT/scripts/ios/test.sh"; then
  echo "The live route still selects the removed real-keyboard test name." >&2
  exit 1
fi
if [[ "$(rg --count 'openkeyboard_assert_single_passing_xcresult' "$ROOT/scripts/ios/test.sh")" -ne 3 ]]; then
  echo "Every single-test credentialed live route must require exactly one passing xcresult test." >&2
  exit 1
fi
rg --quiet 'SENSITIVE_LIVE_SIMULATOR' "$ROOT/scripts/ios/test.sh"
rg --quiet 'SENSITIVE_LIVE_SIMULATOR_OWNED' "$ROOT/scripts/ios/test.sh"
rg --quiet 'simctl create' "$ROOT/scripts/ios/test.sh"
rg --quiet 'simctl delete' "$LIVE_TEST_SAFETY"
if [[ "$(rg -n 'simctl shutdown' "$ROOT/scripts/ios/test.sh" "$LIVE_TEST_SAFETY" | wc -l | tr -d '[:space:]')" -ne 2 ]]; then
  echo "Only disposable live-test simulators may be shut down by the test runner." >&2
  exit 1
fi
rg --fixed-strings --quiet 'xcrun simctl shutdown "$owned_simulator"' "$LIVE_TEST_SAFETY"
rg --fixed-strings --quiet 'xcrun simctl shutdown "$simulator"' "$ROOT/scripts/ios/test.sh"
rg --fixed-strings --quiet 'openkeyboard_delete_sensitive_live_simulator' \
  "$ROOT/scripts/ios/test.sh" "$LIVE_TEST_SAFETY"
if rg --quiet 'simctl erase' "$ROOT/scripts/ios/test.sh"; then
  echo "The test runner must not erase Simulator state." >&2
  exit 1
fi
if rg --pcre2 --quiet '(?:pkill|killall)[^\n]*(?:Simulator|CoreSimulator)|openkeyboard_stop_simulator_app' \
    "$ROOT/scripts/ios" "$ROOT/.github" "$ROOT/.githooks"; then
  echo "Workflows must never terminate Simulator.app or CoreSimulator processes globally." >&2
  exit 1
fi
if rg --pcre2 --quiet '(?:^|[^A-Za-z0-9_-])(?:devicectl|ios-deploy)(?:[^A-Za-z0-9_-]|$)' \
    "$ROOT/scripts/ios" "$ROOT/.github" "$ROOT/.githooks"; then
  echo "Repository automation must never discover, install, launch, or test on physical devices." >&2
  exit 1
fi
if rg --pcre2 --quiet 'platform=iOS,[^"'\''\n]*(?:id|name)=' \
    "$ROOT/scripts/ios" "$ROOT/.github" "$ROOT/.githooks"; then
  echo "Repository automation must never select a concrete physical-device destination." >&2
  exit 1
fi
rg --fixed-strings --quiet 'BUILD_DESTINATION="generic/platform=iOS Simulator"' "$ROOT/scripts/ios/test.sh"
rg --fixed-strings --quiet 'DESTINATION="platform=iOS Simulator,name=iPhone 16"' "$ROOT/scripts/ios/test.sh"
rg --fixed-strings --quiet -- '-destination "generic/platform=iOS"' "$ROOT/.github/workflows/deploy-ios.yml"
if rg --pcre2 --quiet 'simctl\s+(?:shutdown|delete|erase)\s+(?:all|booted)(?:\s|$)' \
    "$ROOT/scripts/ios" "$ROOT/.github" "$ROOT/.githooks"; then
  echo "Workflows must never use broad simctl cleanup." >&2
  exit 1
fi
rg --quiet 'openkeyboard_relaunch_with_simulator_lock' "$ROOT/scripts/ios/test.sh" "$LIVE_TEST_SAFETY"
rg --quiet 'File::LOCK_EX' "$LIVE_TEST_SAFETY"
if rg --quiet '__test-sensitive-live-cleanup|OPEN_KEYBOARD_WORKFLOW_POLICY_TEST' "$ROOT/scripts/ios/test.sh"; then
  echo "The production iOS test runner must not expose a cleanup test harness." >&2
  exit 1
fi
rg --fixed-strings --quiet 'OWNED_CLEANUP_PROBE=' "$LIVE_TEST_SAFETY_POLICY_TEST"
rg --fixed-strings --quiet 'assert_concurrent_worktree_cleanup_isolated normal 0' "$LIVE_TEST_SAFETY_POLICY_TEST"
rg --fixed-strings --quiet 'assert_concurrent_worktree_cleanup_isolated term 143' "$LIVE_TEST_SAFETY_POLICY_TEST"
ruby -e '
  source = File.read(ARGV.fetch(0))
  worktree_creation = source.index(%q{git -C "$PRIMARY_CHECKOUT" worktree add})
  linked_waiter = source.index(%q{"$LOCK_PROBE" "$ROOT/scripts/ios/live-test-safety.sh" "$LINKED_WORKTREE" "$LOCK_OUTPUT" second 0})
  unless worktree_creation && linked_waiter && worktree_creation < linked_waiter
    abort "The Simulator lock regression must run its waiting contender from a linked worktree."
  end
' "$ROOT/scripts/tests/live-test-safety-test.sh"
if rg --quiet 'SENSITIVE_LIVE_SOURCE|restore_sensitive_live_source_simulator|simctl clone|openkeyboard_restore_booted_simulator' \
    "$ROOT/scripts/ios/test.sh" "$LIVE_TEST_SAFETY"; then
  echo "Live routes must not clone, stop, or restore an existing source simulator." >&2
  exit 1
fi
ruby -e '
  source = File.read(ARGV.fetch(0))
  safety_source = File.read(ARGV.fetch(1))
  create_method = source.match(/^create_sensitive_live_simulator\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
  abort "The iOS test runner is missing its disposable simulator creator." unless create_method
  unless create_method.include?(%q{device.fetch("deviceTypeIdentifier")}) &&
      create_method.include?(%q{xcrun simctl create "$simulator_name" "$device_type" "$runtime"})
    abort "Disposable live simulators must be freshly created with the selected type and runtime."
  end
  if create_method.match?(/simctl (?:shutdown|erase|delete)/)
    abort "Disposable simulator creation must not mutate the selected existing simulator."
  end
  unless create_method.include?(%q{SENSITIVE_LIVE_SIMULATOR="$created_simulator"}) &&
      create_method.include?(%q{SENSITIVE_LIVE_SIMULATOR_OWNED="true"})
    abort "Disposable simulator ownership must be recorded only after creation returns a valid UDID."
  end

  ownership_method = safety_source.match(/^openkeyboard_require_sensitive_live_simulator_ownership\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
  abort "The live-test safety library is missing its simulator ownership guard." unless ownership_method
  unless ownership_method.include?(%q{SENSITIVE_LIVE_SIMULATOR_OWNED:-false}) &&
      ownership_method.include?(%q{"$simulator" != "${SENSITIVE_LIVE_SIMULATOR:-}"}) &&
      ownership_method.include?(%q{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}})
    abort "Simulator ownership must require the exact recorded canonical UDID."
  end

  delete_method = safety_source.match(/^openkeyboard_delete_sensitive_live_simulator\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
  abort "The live-test safety library is missing its owned simulator cleanup." unless delete_method
  unless delete_method.include?(%q{openkeyboard_require_sensitive_live_simulator_ownership "${SENSITIVE_LIVE_SIMULATOR:-}"}) &&
      delete_method.include?(%q{xcrun simctl shutdown "$owned_simulator"}) &&
      delete_method.include?(%q{xcrun simctl delete "$owned_simulator"})
    abort "Live cleanup must shut down and delete only the workflow-owned simulator UDID."
  end
  if delete_method.match?(/(?:pkill|killall)|simctl (?:shutdown|delete|erase) (?:all|booted)/)
    abort "Live cleanup must not terminate Simulator.app or use broad simctl cleanup."
  end

  lock_method = source.match(/^simulator_mode_requires_lock\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
  abort "The iOS test runner is missing its Simulator exclusivity policy." unless lock_method
  required_modes = %w[
    ui deterministic-ui live-ui live-gateway-smoke live-model-differential
    real-keyboard-live screenshots
  ]
  missing_modes = required_modes.reject { |mode| lock_method.include?(mode) }
  abort "Simulator-backed routes are missing from the exclusivity policy: #{missing_modes.join(", ")}" unless missing_modes.empty?
' "$ROOT/scripts/ios/test.sh" "$LIVE_TEST_SAFETY"
rg --quiet -- '--replace-existing-config' "$ROOT/scripts/ios/test.sh"
if rg --quiet 'filter_map' "$ROOT/scripts/ios/test.sh"; then
  echo "Live-test helpers must remain compatible with the repository's supported host Ruby." >&2
  exit 1
fi
if rg --quiet 'filter_map' "$PR_REQUIREMENTS_VALIDATOR"; then
  echo "The PR requirements validator must remain compatible with the repository's supported host Ruby." >&2
  exit 1
fi
if rg --quiet 'filter_map' "$PR_REVIEW_RECORD_VALIDATOR"; then
  echo "The PR review-record validator must remain compatible with the repository's supported host Ruby." >&2
  exit 1
fi
if rg --quiet '\.derived-(live-gateway-smoke|real-keyboard-live)|\.ci-results/(live-gateway-smoke|real-keyboard-live)' "$ROOT/scripts/ios/test.sh"; then
  echo "Live tests must not retain secret-bearing derived data or result bundles in the repository." >&2
  exit 1
fi
if rg --fixed-strings --quiet 'clean-validated.\\(UUID().uuidString)' "$ROOT/OpenKeyboardUITests/SettingsViewModelTests.swift"; then
  echo "The settings isolation suite must interpolate a unique UUID instead of retaining a literal expression." >&2
  exit 1
fi

live_impact_patterns=(
  '.github/pull_request_template.md'
  '.github/workflows/live.yml'
  '.gitmodules'
  '.githooks/pre-push'
  'scripts/check-live.sh'
  'scripts/check.sh'
  'scripts/check-semantic-prompt-contract.sh'
  'scripts/live-impact.sh'
  'scripts/validate-pr-live-evidence.sh'
  'scripts/ios/enable-openkeyboard-simulator-keyboard.sh'
  'scripts/ios/live-test-safety.sh'
  'scripts/ios/openkeyboard-gateway.seed.env.example'
  'scripts/ios/seed-simulator-gateway-config.sh'
  'scripts/ios/test.sh'
  'Vendor/semantic-prompt-contract'
  'OpenKeyboard/*'
  'OpenKeyboardCore/Package.swift'
  'OpenKeyboardCore/Sources/*'
  'OpenKeyboardExtension/*'
  'OpenKeyboardUITests/GatewayClientArchitectureTests.swift'
  'OpenKeyboardUITests/KeyboardExtensionConfiguredUITests.swift'
  'OpenKeyboard.xcodeproj/project.pbxproj'
)

for live_impact_pattern in "${live_impact_patterns[@]}"; do
  if ! rg --fixed-strings --quiet "$live_impact_pattern" "$ROOT/scripts/live-impact.sh"; then
    echo "Live-impact policy omitted $live_impact_pattern." >&2
    exit 1
  fi
done

if ! rg --fixed-strings --quiet -- '--no-renames' "$ROOT/scripts/live-impact.sh"; then
  echo "Live-impact policy must classify both sides of file renames." >&2
  exit 1
fi

while IFS= read -r use_line; do
  action_ref="${use_line#*uses:}"
  action_ref="${action_ref%%#*}"
  action_ref="${action_ref#"${action_ref%%[![:space:]]*}"}"
  action_ref="${action_ref%"${action_ref##*[![:space:]]}"}"
  case "$action_ref" in
    ./*)
      ;;
    *@*)
      action_sha="${action_ref##*@}"
      if [[ ! "$action_sha" =~ ^[0-9a-f]{40}$ ]]; then
        echo "GitHub Action is not pinned to a full commit SHA: $action_ref" >&2
        exit 1
      fi
      ;;
    *)
      echo "Invalid GitHub Action reference: $action_ref" >&2
      exit 1
      ;;
  esac
done < <(rg --no-filename '^[[:space:]]*uses:' "$ROOT/.github/workflows")

ruby -e '
  require "open3"
  require "yaml"

  walk = lambda do |value, path|
    case value
    when Hash
      value.each do |key, child|
        if key == "run" && child.is_a?(String)
          _stdout, stderr, status = Open3.capture3("bash", "-n", stdin_data: child)
          abort "Invalid embedded shell in #{path}: #{stderr}" unless status.success?
        else
          walk.call(child, path)
        end
      end
    when Array
      value.each { |child| walk.call(child, path) }
    end
  end

  ARGV.each { |path| walk.call(YAML.load_file(path), path) }
' "$CI_WORKFLOW" "$LIVE_WORKFLOW" "$DEPLOY_WORKFLOW"

ruby -e '
  require "yaml"
  policy = YAML.load_file(ARGV.fetch(0))
  ecosystems = policy.fetch("updates").map { |entry| entry.fetch("package-ecosystem") }
  abort "Dependabot must cover GitHub Actions." unless ecosystems.include?("github-actions")
  abort "Dependabot must cover Swift Package Manager." unless ecosystems.include?("swift")
' "$DEPENDABOT"

echo "GitHub workflow policy tests passed."
