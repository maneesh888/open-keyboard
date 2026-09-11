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
rg --quiet 'live_model_requirement_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_model_identity_matches_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_model_role_distinctness_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_model_substitutions_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_provider_exact_bindings_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_provider_test_connection_outcomes_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_provider_diagnostic_outcomes_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_baseline_outcomes_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_differential_outcomes_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_follow_up_outcomes_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'prohibited_latency_fields_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'legacy_required_models_count.*legacy_tested_models_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --fixed-strings --quiet 'low=true, high=true' "$LIVE_EVIDENCE_VALIDATOR"
rg --fixed-strings --quiet 'openai=true, anthropic=true, openrouter=true, gateway=true' "$LIVE_EVIDENCE_VALIDATOR"
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
rg --quiet '\$plan-openkeyboard-work-package' "$DEVELOP_SKILL"
rg --quiet '\$plan-openkeyboard-major-milestone' "$DEVELOP_SKILL"
rg --quiet '\$review-verify-merge-pr' "$DEVELOP_SKILL"
rg --quiet '^## Lifecycle autonomy$' "$DEVELOP_SKILL"
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
rg --quiet 'Live model requirement:' "$PR_TEMPLATE"
rg --quiet 'Live model identity matches:' "$PR_TEMPLATE"
rg --quiet 'Live model role distinctness:' "$PR_TEMPLATE"
rg --quiet 'Live-model substitutions:' "$PR_TEMPLATE"
rg --quiet 'Live provider exact bindings:' "$PR_TEMPLATE"
rg --quiet 'Live provider Test Connection outcomes:' "$PR_TEMPLATE"
rg --quiet 'Live provider diagnostic outcomes:' "$PR_TEMPLATE"
rg --quiet 'Live baseline outcomes:' "$PR_TEMPLATE"
rg --quiet 'Live differential outcomes:' "$PR_TEMPLATE"
rg --quiet 'Live follow-up outcomes:' "$PR_TEMPLATE"
rg --quiet 'Live operation-scoped warning contracts:' "$PR_TEMPLATE"
if rg --quiet 'Live .*latenc|diagnostic_latencies_' "$PR_TEMPLATE"; then
  echo "The pull-request template must not retain live timing fields." >&2
  exit 1
fi
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
rg --quiet 'begin_sensitive_live_workspace live-provider-matrix' "$ROOT/scripts/ios/test.sh"
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
  live_case = source.match(/^  real-keyboard-live\)\n(?<body>.*?)^    ;;$/m)&.[](:body)
  abort "The iOS test runner is missing real-keyboard-live mode." unless live_case
  permission = live_case.index(%q{chmod 600 "$xctestrun"})
  injection = live_case.index(%q{inject_xctestrun_gateway_env "$xctestrun"})
  unless permission && injection && permission < injection
    abort "The real-keyboard live route must make its credential-bearing xctestrun private before injection."
  end
' "$ROOT/scripts/ios/test.sh"
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
  unless live_case.include?(%q{chmod 600 "$xctestrun"})
    abort "The live gateway smoke must make its injected xctestrun private."
  end
  expected = %q{-destination "$destination"}
  unless live_case.scan(expected).length == 2
    abort "Both live gateway Xcode invocations must use the disposable simulator destination."
  end
' "$ROOT/scripts/ios/test.sh"
ruby -e '
  source = File.read(ARGV.fetch(0))
  live_tests = File.read(ARGV.fetch(1))
  matrix_case = source.match(/^  live-provider-matrix\)\n(?<body>.*?)^    ;;$/m)&.[](:body)
  abort "The iOS test runner is missing live-provider-matrix mode." unless matrix_case
  ambient_scrub = matrix_case.index("openkeyboard_unset_seed_backed_live_ambient_inputs")
  toolchain_preflight = matrix_case.index("require_xcodebuild")
  unless ambient_scrub && toolchain_preflight && ambient_scrub < toolchain_preflight
    abort "The provider matrix must scrub ambient credentials before toolchain preflight or build."
  end
  unless matrix_case.scan(/xcodebuild build-for-testing/).length == 1
    abort "The provider matrix must build its Xcode test artifacts exactly once."
  end
  unless matrix_case.include?("for provider in openai anthropic openrouter gateway")
    abort "The provider matrix must execute all four providers in canonical order."
  end
  unless matrix_case.scan(/xcodebuild test-without-building/).length == 1
    abort "The provider matrix must reuse one build inside its four-provider loop."
  end
  required_steps = [
    %q{openkeyboard_load_uac_live_provider_profile "$provider" "$uac_checkout"},
    %q{inject_xctestrun_live_smoke_env "$xctestrun"},
    %q{openkeyboard_unset_simulator_gateway_profiles},
    %q{openkeyboard_assert_single_passing_xcresult "$result_bundle"}
  ]
  positions = required_steps.map { |step| matrix_case.index(step) }
  unless positions.all? && positions == positions.sort
    abort "The provider matrix must load, inject, scrub, execute, and validate each row in fail-closed order."
  end
  unless matrix_case.include?(%q{create_sensitive_live_simulator "iPhone 16"}) &&
      matrix_case.include?(%q{live-provider-$provider.xcresult}) &&
      matrix_case.include?(%q{uac_validate_live_env_file "$uac_checkout" "$uac_seed_file"}) &&
      matrix_case.include?(%q{openkeyboard_require_private_seed_permissions "$uac_seed_file"}) &&
      matrix_case.include?(%q{openkeyboard_require_trusted_seed_directory "$uac_checkout"}) &&
      matrix_case.include?(%q{chmod 600 "$xctestrun"})
    abort "The provider matrix must use one owned simulator, isolated result bundles, and the canonical ignored seed."
  end
  retained_fields = %w[
    provider_exact_bindings
    provider_test_connection_outcomes
    provider_diagnostic_outcomes
  ]
  unless retained_fields.all? { |field| matrix_case.include?("#{field}=") } &&
      matrix_case.include?(%q{requested_provider_evidence_output}) &&
      matrix_case.include?(%q{chmod 600 "$requested_provider_evidence_output"}) &&
      !matrix_case.match?(/latenc|duration|timing/i)
    abort "The provider matrix must write only its canonical mode-600 evidence summary."
  end

  provider_loader = source.match(/^openkeyboard_load_uac_live_provider_profile\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
  abort "The provider matrix loader is missing." unless provider_loader
  scrub = provider_loader.index("openkeyboard_unset_uac_live_provider_inputs")
  first_load = provider_loader.index("uac_load_live_environment")
  unless scrub && first_load && scrub < first_load
    abort "Ambient provider inputs must be scrubbed before the first ignored-seed load."
  end
  copied_model = provider_loader.index(%q{OPEN_KEYBOARD_SIMULATOR_MODEL="$model_value"})
  post_copy_scrub = provider_loader.rindex("openkeyboard_unset_uac_live_provider_inputs")
  unless copied_model && post_copy_scrub && first_load < copied_model && copied_model < post_copy_scrub
    abort "Exported UAC seed values must be copied and scrubbed before the provider loader returns."
  end
  if provider_loader.include?(%q{$([[ "$provider"})
    abort "Provider selection must not spawn a child while exported UAC values are loaded."
  end
  unless provider_loader.include?(%q{openkeyboard_is_safe_live_gateway_base_url "$base_url"}) &&
      provider_loader.include?(%q{openkeyboard_is_safe_uac_provider_model_id "$provider" "$model_value"})
    abort "Provider matrix inputs must use pinned gateway-base and provider-model safety grammars."
  end
  provider_injector = source.match(/^inject_xctestrun_live_smoke_env\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
  abort "The live smoke environment injector is missing." unless provider_injector
  unless provider_injector.include?(%q{if [[ -z "${OPEN_KEYBOARD_SIMULATOR_PROVIDER:-}" ]]}) &&
      provider_injector.include?(%q{"$root:OPEN_KEYBOARD_TEST_PROVIDER" "$OPEN_KEYBOARD_SIMULATOR_PROVIDER"}) &&
      !provider_injector.include?(":-openai-compatible")
    abort "Live provider propagation must be explicit and fail closed."
  end
  unless source.scan(%q{OPEN_KEYBOARD_SIMULATOR_PROVIDER="openai-compatible"}).length >= 2
    abort "Legacy gateway and differential routes must explicitly select the compatible provider."
  end
  if live_tests.include?(%q{environment["OPEN_KEYBOARD_TEST_PROVIDER"] ??}) ||
      live_tests.scan(%q{let providerValue = environment["OPEN_KEYBOARD_TEST_PROVIDER"]}).length < 2
    abort "Live XCTest entry points must require an explicit provider identity."
  end
' "$ROOT/scripts/ios/test.sh" "$ROOT/OpenKeyboardUITests/GatewayClientArchitectureTests.swift"
ruby -e '
  source = File.read(ARGV.fetch(0))
  safety_source = File.read(ARGV.fetch(1))
  early_scrubber = source.match(/^openkeyboard_unset_ambient_private_live_values\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
  abort "The pre-child private live scrubber is missing." unless early_scrubber
  scrubber = source.match(/^openkeyboard_unset_seed_backed_live_ambient_inputs\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
  abort "The seed-backed live ambient scrubber is missing." unless scrubber
  uac_scrubber = source.match(/^openkeyboard_unset_uac_live_provider_inputs\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
  abort "The UAC live-provider scrubber is missing." unless uac_scrubber
  simulator_scrubber = safety_source.match(/^openkeyboard_unset_simulator_gateway_profiles\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
  abort "The simulator gateway-profile scrubber is missing." unless simulator_scrubber
  required = %w[
    UAC_LIVE_ENV_FILE OPEN_KEYBOARD_UAC_LIVE_CHECKOUT OPENAI_API_KEY OPENAI_LIVE_MODEL
    OPEN_KEYBOARD_LIVE_BASE_REF OPEN_KEYBOARD_LIVE_EXPECTED_SHA
    OPEN_KEYBOARD_LIVE_REQUIRE_DIFFERENTIAL
    ANTHROPIC_API_KEY ANTHROPIC_LIVE_MODEL OPENROUTER_API_KEY OPENROUTER_LIVE_MODEL
    GATEWAY_LIVE_BASE_URL GATEWAY_API_KEY GATEWAY_LIVE_MODEL GATEWAY_LIVE_STRUCTURED_OUTPUT
    OPEN_KEYBOARD_LIVE_REQUIRED_MODEL OPEN_KEYBOARD_LIVE_REQUIRED_MODELS
    OPEN_KEYBOARD_LIVE_GATEWAY_URL OPEN_KEYBOARD_LIVE_API_KEY OPEN_KEYBOARD_LIVE_MODEL
    OPEN_KEYBOARD_LIVE_PROFILE OPEN_KEYBOARD_LIVE_PROVIDER_EVIDENCE_OUTPUT
    OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT OPEN_KEYBOARD_TEST_GATEWAY_URL
    OPEN_KEYBOARD_TEST_API_KEY OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX
    OPEN_KEYBOARD_TEST_API_KEY_HEX OPEN_KEYBOARD_TEST_MODEL OPEN_KEYBOARD_TEST_PROVIDER
    OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE
    OPEN_KEYBOARD_SIMULATOR_PROVIDER OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE
    OPEN_KEYBOARD_SIMULATOR_LOCK_HELD
    OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL OPEN_KEYBOARD_SIMULATOR_API_KEY
    OPEN_KEYBOARD_SIMULATOR_MODEL OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL
    OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY OPEN_KEYBOARD_SIMULATOR_LOW_MODEL
    OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY
    OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL OPEN_KEYBOARD_SIMULATOR_LEGACY_GATEWAY_URL
    OPEN_KEYBOARD_SIMULATOR_LEGACY_API_KEY OPEN_KEYBOARD_SIMULATOR_LEGACY_MODEL
    OPEN_KEYBOARD_SIMULATOR_LEGACY_PROFILE_STATE OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE
    OPEN_KEYBOARD_REAL_KEYBOARD_LIVE_TEST OPEN_KEYBOARD_REAL_KEYBOARD_SIMULATOR
    OPEN_KEYBOARD_REAL_SCREENSHOT_DIR OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE
    OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_DIR OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_PHRASE
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_GATEWAY_URL SIMCTL_CHILD_OPEN_KEYBOARD_TEST_API_KEY
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_MODEL SIMCTL_CHILD_OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG
  ]
  complete_scrubber = scrubber + early_scrubber + uac_scrubber + simulator_scrubber
  missing = required.reject { |name| complete_scrubber.include?(name) }
  abort "The seed-backed live scrubber misses: #{missing.join(", ")}" unless missing.empty?
  unless scrubber.include?("openkeyboard_unset_ambient_private_live_values") &&
      scrubber.include?("openkeyboard_unset_uac_live_provider_inputs") &&
      scrubber.include?("openkeyboard_unset_simulator_gateway_profiles")
    abort "The seed-backed scrubber must clear UAC and loaded simulator profiles."
  end

  %w[live-gateway-smoke live-provider-matrix live-model-differential real-keyboard-live].each do |mode|
    body = source.match(/^  #{Regexp.escape(mode)}\)\n(?<body>.*?)^    ;;$/m)&.[](:body)
    abort "Missing seed-backed mode #{mode}." unless body
    scrub = body.index("openkeyboard_unset_seed_backed_live_ambient_inputs")
    preflight = body.index("require_xcodebuild")
    abort "#{mode} must scrub ambient live inputs before toolchain preflight." unless
      scrub && preflight && scrub < preflight
  end
' "$ROOT/scripts/ios/test.sh" "$ROOT/scripts/ios/live-test-safety.sh"
ruby -e '
  scripts = ARGV.map { |path| [path, File.read(path)] }
  required_private_names = %w[
    OPENAI_API_KEY OPENAI_LIVE_MODEL ANTHROPIC_API_KEY ANTHROPIC_LIVE_MODEL
    OPENROUTER_API_KEY OPENROUTER_LIVE_MODEL GATEWAY_LIVE_BASE_URL GATEWAY_API_KEY
    GATEWAY_LIVE_MODEL OPEN_KEYBOARD_LIVE_GATEWAY_URL OPEN_KEYBOARD_LIVE_API_KEY
    OPEN_KEYBOARD_LIVE_MODEL OPEN_KEYBOARD_LIVE_REQUIRED_MODEL
    OPEN_KEYBOARD_LIVE_REQUIRED_MODELS OPEN_KEYBOARD_TEST_GATEWAY_URL
    OPEN_KEYBOARD_TEST_API_KEY OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX
    OPEN_KEYBOARD_TEST_API_KEY_HEX OPEN_KEYBOARD_TEST_MODEL
    OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL OPEN_KEYBOARD_SIMULATOR_API_KEY
    OPEN_KEYBOARD_SIMULATOR_MODEL OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL
    OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY OPEN_KEYBOARD_SIMULATOR_LOW_MODEL
    OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY
    OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL SIMCTL_CHILD_OPEN_KEYBOARD_TEST_GATEWAY_URL
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_API_KEY SIMCTL_CHILD_OPEN_KEYBOARD_TEST_MODEL
    SIMCTL_CHILD_OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG
    line value base_url key_value model_value model_id tested_model required_model
    low_model high_model expected_profile_model gateway_url_hex api_key_hex
    requested_screenshot_dir requested_screenshot_phrase
  ]
  scripts.each do |path, source|
    root_marker = path.end_with?("check-live.sh") ? "ROOT=\"$(" : "REPO_ROOT=\"$("
    root_resolution = source.index(root_marker)
    abort "Repository-root resolution is missing from #{path}." unless root_resolution
    pre_child = source[0...root_resolution]
    unless pre_child.scan("openkeyboard_unset_ambient_private_live_values").length >= 2
      abort "#{path} must scrub raw ambient live values before its first child shell."
    end
    early_scrubber = pre_child.match(/^openkeyboard_unset_ambient_private_live_values\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
    abort "The pre-child scrubber is missing from #{path}." unless early_scrubber
    missing = required_private_names.reject { |name| early_scrubber.include?(name) }
    abort "#{path} pre-child scrubber misses: #{missing.join(", ")}" unless missing.empty?
  end
' "$ROOT/scripts/check-live.sh" "$ROOT/scripts/ios/test.sh" "$ROOT/scripts/ios/seed-simulator-gateway-config.sh"
ruby -e '
  source = File.read(ARGV.fetch(0))
  first_child = source.index(%q{echo "Running deterministic gateway prerequisites for exact HEAD."})
  abort "The exact-head prerequisite boundary is missing." unless first_child
  pre_child = source[0...first_child]
  required = %w[
    REQUIRED_MODEL REQUIRED_MODELS REQUIRED_LOW_MODEL REQUIRED_HIGH_MODEL
    TESTED_MODEL TESTED_MODELS REQUIRED_MODEL_INPUT REQUIRED_MODELS_INPUT
  ]
  missing = required.reject { |name| pre_child.include?(name) }
  abort "The exact-head gate misses private internal state: #{missing.join(", ")}" unless missing.empty?
  unexport = pre_child.rindex("export -n")
  abort "The exact-head gate must unexport derived private identities before its first external prerequisite." unless unexport
  unexport_block = pre_child[unexport..]
  missing_unexports = required.reject { |name| unexport_block.include?(name) }
  abort "The exact-head gate leaves derived identities exported: #{missing_unexports.join(", ")}" unless missing_unexports.empty?
' "$ROOT/scripts/check-live.sh"
ruby -e '
  source = File.read(ARGV.fetch(0))
  body = source.match(/^openkeyboard_validate_simulator_gateway_profiles\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
  abort "Simulator profile validation is missing." unless body
  unless body.include?("export -n model_id")
    abort "Simulator profile validation must clear an inherited export attribute from raw model IDs."
  end
' "$ROOT/scripts/ios/live-test-safety.sh"
ruby -e '
  source = File.read(ARGV.fetch(0))
  cleanup = source.match(/^cleanup_sensitive_live_artifacts\(\) \{\n(?<body>.*?)^\}$/m)&.[](:body)
  abort "Sensitive live cleanup is missing." unless cleanup
  scrub = cleanup.index("openkeyboard_unset_ambient_private_live_values")
  delete_simulator = cleanup.index("openkeyboard_delete_sensitive_live_simulator")
  unless scrub && delete_simulator && scrub < delete_simulator
    abort "Sensitive live cleanup must scrub credentials before invoking simulator tools."
  end
' "$ROOT/scripts/ios/test.sh"
ruby -e '
  source = File.read(ARGV.fetch(0))
  release_case = source.match(/^  release-exclusion\)\n(?<body>.*?)^    ;;$/m)&.[](:body)
  abort "The iOS test runner is missing release-exclusion mode." unless release_case
  unless release_case.include?("-destination") &&
      release_case.include?("generic/platform=iOS") &&
      release_case.include?(%q{-configuration Release}) &&
      release_case.include?(%q{CODE_SIGNING_ALLOWED=NO})
    abort "The release exclusion gate must use an unsigned generic-iOS Release destination."
  end
  unless release_case.include?(%q{"$release_app/OpenKeyboard"}) &&
      release_case.include?(%q{"$release_extension/OpenKeyboardExtension"}) &&
      release_case.include?(%q{strings -a "$release_binary"}) &&
      release_case.include?(%q{nm -j "$release_binary"})
    abort "The release exclusion gate must inspect both app and extension strings and symbols."
  end
  required_tokens = %w[
    OPEN_KEYBOARD_TEST_API_KEY OPEN_KEYBOARD_TEST_GATEWAY_URL OPEN_KEYBOARD_TEST_MODEL
    OPEN_KEYBOARD_LIVE_API_KEY OPEN_KEYBOARD_LIVE_GATEWAY_URL OPEN_KEYBOARD_LIVE_MODEL
    OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG SimulatorLiveAIConfiguration
    LiveAITestHarnessView captureUITestGatewayEnvironment seedUITestGatewayConfigAtLaunchIfNeeded
    saveTestSeed KeyboardUITestConfigProcessAuthorization keyboardUITestConfigAuthorization
    hasFreshKeyboardExtensionUITestConfigSeed
  ]
  missing_tokens = required_tokens.reject { |token| release_case.include?(token) }
  abort "The release exclusion scan is missing tokens: #{missing_tokens.join(", ")}" unless missing_tokens.empty?
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
if rg --quiet 'LIVE_GATEWAY_DIAGNOSTIC.*latenc|LIVE_GRAMMAR_VARIANT.*latenc|LIVE_MODEL_DIFFERENTIAL_LATENCY|OpenKeyboard live diagnostic .*latenc' \
    "$ROOT/OpenKeyboardUITests/GatewayClientArchitectureTests.swift" || \
    rg --quiet 'diagnostic_latencies_' "$ROOT/scripts/ios/live-test-safety.sh" || \
    rg --quiet 'print\([^\n]*(latency|duration|timeIntervalSince)' \
      "$ROOT/OpenKeyboardCore/Tests/OpenKeyboardCoreTests/LivePromptEvaluationTests.swift" \
      "$ROOT/OpenKeyboardUITests/LiveGatewayAIUITests.swift"; then
  echo "Live XCTest output and attachments must retain outcomes without timing fields." >&2
  exit 1
fi
rg --fixed-strings --quiet 'print("LIVE_GRAMMAR_REQUEST status=passed")' \
  "$ROOT/OpenKeyboardCore/Tests/OpenKeyboardCoreTests/LivePromptEvaluationTests.swift"
rg --fixed-strings --quiet 'print("OpenKeyboard live grammar request status=passed")' \
  "$ROOT/OpenKeyboardUITests/LiveGatewayAIUITests.swift"
if rg --quiet 'XCTAssert(Equal|NotEqual)\((result\.displayText|value|output)|\\\((result\.displayText|value|output)\\\)' \
    "$ROOT/OpenKeyboardCore/Tests/OpenKeyboardCoreTests/LivePromptEvaluationTests.swift" \
    "$ROOT/OpenKeyboardUITests/LiveGatewayAIUITests.swift"; then
  echo "Live XCTest failures must not print or interpolate raw gateway response bodies." >&2
  exit 1
fi
rg --quiet 'DIAGNOSTIC_OUTCOMES_LOW_LINE' "$ROOT/scripts/check-live.sh"
rg --quiet 'trap cleanup_sensitive_live_artifacts EXIT' "$ROOT/scripts/ios/test.sh"
rg --quiet 'source .*live-test-safety\.sh' "$ROOT/scripts/ios/test.sh"
rg --quiet 'source .*live-test-safety\.sh' "$ROOT/scripts/check-live.sh"
rg --quiet 'source .*live-test-safety\.sh' "$ROOT/scripts/ios/seed-simulator-gateway-config.sh"
rg --quiet 'openkeyboard_require_local_seed_file' "$ROOT/scripts/check-live.sh"
rg --quiet 'OPEN_KEYBOARD_LIVE_REQUIRED_MODEL' "$ROOT/scripts/check-live.sh"
rg --quiet 'OPEN_KEYBOARD_LIVE_REQUIRED_MODELS' "$ROOT/scripts/check-live.sh"
rg --quiet 'gateway-differential' "$ROOT/scripts/check-live.sh"
rg --quiet 'model_requirement=\$MODEL_REQUIREMENT' "$ROOT/scripts/check-live.sh"
rg --quiet 'model_identity_matches=\$MODEL_IDENTITY_MATCHES' "$ROOT/scripts/check-live.sh"
rg --quiet 'model_roles_distinct=\$MODEL_ROLES_DISTINCT' "$ROOT/scripts/check-live.sh"
rg --fixed-strings --quiet 'MODEL_ROLES_DISTINCT="not required"' "$ROOT/scripts/check-live.sh"
rg --fixed-strings --quiet 'openkeyboard_require_compatible_live_model_inputs' "$ROOT/scripts/check-live.sh"
rg --fixed-strings --quiet 'openkeyboard_require_exact_live_model "$TESTED_MODEL" "$REQUIRED_MODEL" true' "$ROOT/scripts/check-live.sh"
if rg --fixed-strings --quiet '$([[ "$MODEL_REQUIREMENT" == "model-agnostic" ]]' "$ROOT/scripts/check-live.sh"; then
  echo "The exact-head live gate must not spawn a child while selecting its private model requirement mode." >&2
  exit 1
fi
if rg --quiet 'LIVE_(GRAMMAR_VARIANT|GRAMMAR_FOLLOW_UP).*?(source_chars|result_chars|presentation)=' \
    "$ROOT/OpenKeyboardUITests/GatewayClientArchitectureTests.swift"; then
  echo "Credentialed live differential logs must retain status-only scenario evidence." >&2
  exit 1
fi
rg --quiet 'provider_exact_bindings=' "$ROOT/scripts/ios/test.sh"
rg --quiet 'provider_test_connection_outcomes=' "$ROOT/scripts/ios/test.sh"
rg --quiet 'provider_diagnostic_outcomes=' "$ROOT/scripts/ios/test.sh"
if rg --quiet 'provider_matrix_latencies=|profile_latencies=|diagnostic_latencies_' \
    "$ROOT/scripts/check-live.sh" "$ROOT/scripts/ios/test.sh"; then
  echo "Live runners must not print or persist timing evidence." >&2
  exit 1
fi
rg --fixed-strings --quiet '"$ROOT/scripts/ios/test.sh" live-provider-matrix' "$ROOT/scripts/check-live.sh"
if rg --quiet 'required_models=|tested_models=|required_model=|tested_model=|model_commitment|MODEL_COMMITMENT' "$ROOT/scripts/check-live.sh"; then
  echo "The exact-head live gate retains raw model identities or opaque commitments." >&2
  exit 1
fi
CHECK_LIVE_PATH="$ROOT/scripts/check-live.sh" ruby -e '
  source = File.read(ENV.fetch("CHECK_LIVE_PATH"))
  provider_block = source.match(/provider_evidence_file=.*?(?<body>env \\\n.*?live-provider-matrix)/m)&.[](:body)
  abort "The exact-head gate provider-matrix environment block is missing." unless provider_block
  required_unsets = %w[
    UAC_LIVE_ENV_FILE OPENAI_API_KEY OPENAI_LIVE_MODEL ANTHROPIC_API_KEY
    ANTHROPIC_LIVE_MODEL OPENROUTER_API_KEY OPENROUTER_LIVE_MODEL
    GATEWAY_LIVE_BASE_URL GATEWAY_API_KEY GATEWAY_LIVE_MODEL
    GATEWAY_LIVE_STRUCTURED_OUTPUT OPEN_KEYBOARD_LIVE_BASE_REF
    OPEN_KEYBOARD_LIVE_EXPECTED_SHA OPEN_KEYBOARD_LIVE_REQUIRE_DIFFERENTIAL
    OPEN_KEYBOARD_LIVE_GATEWAY_URL
    OPEN_KEYBOARD_LIVE_API_KEY OPEN_KEYBOARD_LIVE_MODEL
    OPEN_KEYBOARD_TEST_GATEWAY_URL OPEN_KEYBOARD_TEST_API_KEY
    OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX OPEN_KEYBOARD_TEST_API_KEY_HEX
    OPEN_KEYBOARD_TEST_MODEL OPEN_KEYBOARD_TEST_PROVIDER
  ]
  missing_unsets = required_unsets.reject { |name| provider_block.include?("-u #{name}") }
  abort "The provider matrix inherited ambient inputs: #{missing_unsets.join(", ")}" unless missing_unsets.empty?
  all_child_unsets = required_unsets + %w[
    REQUIRED_MODEL REQUIRED_MODELS REQUIRED_LOW_MODEL REQUIRED_HIGH_MODEL
    TESTED_MODEL TESTED_MODELS REQUIRED_MODEL_INPUT REQUIRED_MODELS_INPUT
    OPEN_KEYBOARD_UAC_LIVE_CHECKOUT OPEN_KEYBOARD_LIVE_REQUIRED_MODEL
    OPEN_KEYBOARD_LIVE_REQUIRED_MODELS OPEN_KEYBOARD_LIVE_PROFILE
    OPEN_KEYBOARD_LIVE_PROVIDER_EVIDENCE_OUTPUT OPEN_KEYBOARD_LIVE_EVIDENCE_OUTPUT
    OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE
    OPEN_KEYBOARD_SIMULATOR_PROVIDER OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE
    OPEN_KEYBOARD_SIMULATOR_LOCK_HELD
    OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL OPEN_KEYBOARD_SIMULATOR_API_KEY
    OPEN_KEYBOARD_SIMULATOR_MODEL OPEN_KEYBOARD_SIMULATOR_LOW_GATEWAY_URL
    OPEN_KEYBOARD_SIMULATOR_LOW_API_KEY OPEN_KEYBOARD_SIMULATOR_LOW_MODEL
    OPEN_KEYBOARD_SIMULATOR_HIGH_GATEWAY_URL OPEN_KEYBOARD_SIMULATOR_HIGH_API_KEY
    OPEN_KEYBOARD_SIMULATOR_HIGH_MODEL OPEN_KEYBOARD_SIMULATOR_LEGACY_GATEWAY_URL
    OPEN_KEYBOARD_SIMULATOR_LEGACY_API_KEY OPEN_KEYBOARD_SIMULATOR_LEGACY_MODEL
    OPEN_KEYBOARD_SIMULATOR_LEGACY_PROFILE_STATE OPEN_KEYBOARD_SIMULATOR_SELECTED_PROFILE
    OPEN_KEYBOARD_REAL_KEYBOARD_LIVE_TEST OPEN_KEYBOARD_REAL_KEYBOARD_SIMULATOR
    OPEN_KEYBOARD_REAL_SCREENSHOT_DIR OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE
    OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_DIR OPEN_KEYBOARD_PRIVATE_REAL_SCREENSHOT_PHRASE
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_GATEWAY_URL SIMCTL_CHILD_OPEN_KEYBOARD_TEST_API_KEY
    SIMCTL_CHILD_OPEN_KEYBOARD_TEST_MODEL SIMCTL_CHILD_OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG
  ]
  incomplete = all_child_unsets.uniq.select do |name|
    source.scan(/-u #{Regexp.escape(name)}(?:\s|\\)/).length < 4
  end
  abort "Not every exact-head child scrubs ambient live inputs: #{incomplete.join(", ")}" unless incomplete.empty?
  provider = source.index(%q{"$ROOT/scripts/ios/test.sh" live-provider-matrix})
  gateway = source.index(%q{"$ROOT/scripts/ios/test.sh" live-gateway-smoke})
  differential = source.index(%q{"$ROOT/scripts/ios/test.sh" live-model-differential})
  abort "The exact-head gate must run the provider matrix before either gateway target." unless
    provider && gateway && differential && provider < gateway && provider < differential
'
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
ruby -e '
  source = File.read(ARGV.fetch(0))
  %w[live-gateway-smoke live-provider-matrix live-model-differential real-keyboard-live].each do |mode|
    body = source.match(/^  #{Regexp.escape(mode)}\)\n(?<body>.*?)^    ;;$/m)&.[](:body)
    abort "The iOS test runner is missing #{mode} mode." unless body
    unless body.include?(%q{openkeyboard_assert_single_passing_xcresult})
      abort "The #{mode} credentialed route must require one passing, non-skipped xcresult test."
    end
  end
' "$ROOT/scripts/ios/test.sh"
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
    ui deterministic-ui live-ui live-gateway-smoke live-provider-matrix live-model-differential
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
if rg --quiet '\.derived-(live-gateway-smoke|live-provider-matrix|real-keyboard-live)|\.ci-results/(live-gateway-smoke|live-provider-matrix|real-keyboard-live)' "$ROOT/scripts/ios/test.sh"; then
  echo "Live tests must not retain secret-bearing derived data or result bundles in the repository." >&2
  exit 1
fi
for private_live_script in \
  "$ROOT/scripts/check-live.sh" \
  "$ROOT/scripts/ios/test.sh" \
  "$ROOT/scripts/ios/seed-simulator-gateway-config.sh"; do
  private_live_preamble="$(sed -n '1,18p' "$private_live_script")"
  if ! grep -Fq '*x*) set +x ;;' <<< "$private_live_preamble" || \
      ! grep -Fq '*a*) set +a ;;' <<< "$private_live_preamble"; then
    echo "Private live scripts must disable inherited tracing and automatic export before reading inputs." >&2
    exit 1
  fi
done
ruby -e '
  source = File.read(ARGV.fetch(0))
  body = source.match(/^  real-keyboard-live\)\n(?<body>.*?)^    ;;$/m)&.[](:body)
  abort "The real-keyboard live mode is missing." unless body
  capture = body.index(%q{requested_screenshot_phrase=})
  scrub = body.index("openkeyboard_unset_seed_backed_live_ambient_inputs")
  abort "Real-keyboard live controls must be captured before the complete scrub." unless
    capture && scrub && capture < scrub
  unexport_block = body[capture...scrub]
  unless unexport_block.include?("export -n") &&
      unexport_block.include?("requested_screenshot_dir") &&
      unexport_block.include?("requested_screenshot_phrase")
    abort "Real-keyboard live controls must not retain inherited export attributes."
  end
' "$ROOT/scripts/ios/test.sh"
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
