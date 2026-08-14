#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CI_WORKFLOW="$ROOT/.github/workflows/ci.yml"
LIVE_WORKFLOW="$ROOT/.github/workflows/live.yml"
DEPLOY_WORKFLOW="$ROOT/.github/workflows/deploy-ios.yml"
DEPENDABOT="$ROOT/.github/dependabot.yml"
REVIEWER_AGENT="$ROOT/.codex/agents/pr-reviewer.toml"
PLANNER_AGENT="$ROOT/.codex/agents/work-package-planner.toml"
REVIEW_SKILL="$ROOT/.agents/skills/review-verify-merge-pr/SKILL.md"
REVIEW_INTERFACE="$ROOT/.agents/skills/review-verify-merge-pr/agents/openai.yaml"
DEVELOP_SKILL="$ROOT/.agents/skills/develop-openkeyboard/SKILL.md"
DEVELOP_INTERFACE="$ROOT/.agents/skills/develop-openkeyboard/agents/openai.yaml"
PLAN_SKILL="$ROOT/.agents/skills/plan-openkeyboard-work-package/SKILL.md"
PLAN_INTERFACE="$ROOT/.agents/skills/plan-openkeyboard-work-package/agents/openai.yaml"
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
SEMANTIC_CONTRACT_CHECK="$ROOT/scripts/check-semantic-prompt-contract.sh"
SEMANTIC_CONTRACT_ROOT="$ROOT/Vendor/semantic-prompt-contract"

for required_file in \
  "$CI_WORKFLOW" \
  "$LIVE_WORKFLOW" \
  "$DEPLOY_WORKFLOW" \
  "$DEPENDABOT" \
  "$REVIEWER_AGENT" \
  "$PLANNER_AGENT" \
  "$REVIEW_SKILL" \
  "$REVIEW_INTERFACE" \
  "$DEVELOP_SKILL" \
  "$DEVELOP_INTERFACE" \
  "$PLAN_SKILL" \
  "$PLAN_INTERFACE" \
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
  "$SEMANTIC_CONTRACT_CHECK" \
  "$SEMANTIC_CONTRACT_ROOT/contracts/manifest.json"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Required workflow policy file is missing: $required_file" >&2
    exit 1
  fi
done

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
rg --quiet 'git show "\$PR_BASE_SHA:scripts/\$validator_name"' "$LIVE_WORKFLOW"
rg --quiet 'environment:[[:space:]]*live-policy' "$LIVE_WORKFLOW"
rg --quiet 'local_live_verification_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_verification_target_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_tested_head_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'required_live_models_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'exact_live_tested_models_count' "$LIVE_EVIDENCE_VALIDATOR"
rg --quiet 'live_model_substitutions_count' "$LIVE_EVIDENCE_VALIDATOR"
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
rg --quiet '^sandbox_mode = "read-only"$' "$PLANNER_AGENT"
rg --quiet 'Do not edit files.*access GitHub' "$PLANNER_AGENT"
rg --quiet 'project `pr-reviewer`' "$REVIEW_SKILL"
rg --quiet 'scripts/check\.sh --full' "$REVIEW_SKILL"
rg --fixed-strings --quiet 'Required technical checks' "$REVIEW_SKILL"
rg --quiet 'Required checks' "$REVIEW_SKILL"
rg --quiet 'Required live verification' "$REVIEW_SKILL"
rg --fixed-strings --quiet 'Reviewer confidence: 100%' "$REVIEW_SKILL"
rg --fixed-strings --quiet 'Reviewer confidence: below 100%' "$REVIEW_SKILL"
rg --fixed-strings --quiet 'Merge recommendation: human-review-required' "$REVIEW_SKILL"
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
rg --quiet 'keep draft.*do not merge' "$REVIEW_SKILL"
rg --quiet 'gh pr merge <number> --auto --squash --match-head-commit <reviewed-head-sha>' "$REVIEW_SKILL"
rg --quiet 'Never leave queued auto-merge active' "$REVIEW_SKILL"
rg --quiet '^name: develop-openkeyboard$' "$DEVELOP_SKILL"
rg --quiet '\$plan-openkeyboard-work-package' "$DEVELOP_SKILL"
rg --quiet '\$review-verify-merge-pr' "$DEVELOP_SKILL"
rg --quiet '^## Lifecycle autonomy$' "$DEVELOP_SKILL"
rg --quiet '^name: plan-openkeyboard-work-package$' "$PLAN_SKILL"
rg --quiet 'git hash-object' "$PLAN_SKILL"
rg --quiet 'allow_implicit_invocation:[[:space:]]*false' "$PLAN_INTERFACE"
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
rg --quiet -- '-skip-testing:OpenKeyboardUITests/OnboardingScreenshotUITests' "$ROOT/scripts/ios/test.sh"
rg --quiet -- '-only-testing:OpenKeyboardUITests/OnboardingScreenshotUITests/testWelcomePageContentIsVisibleAndNonOverlapping' "$ROOT/scripts/ios/test.sh"
ruby -e '
  source = File.read(ARGV.fetch(0))
  deterministic_case = source.match(/^  deterministic-ui\)\n(?<body>.*?)^    ;;$/m)&.[](:body)
  abort "The iOS test runner is missing deterministic-ui mode." unless deterministic_case
  expected = %q{-derivedDataPath "$DETERMINISTIC_UI_DERIVED_DATA"}
  unless deterministic_case.scan(expected).length == 2
    abort "Both deterministic UI invocations must use worktree-scoped DerivedData."
  end
' "$ROOT/scripts/ios/test.sh"
rg --quiet 'begin_sensitive_live_workspace live-gateway-smoke' "$ROOT/scripts/ios/test.sh"
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
rg --quiet 'trap cleanup_sensitive_live_artifacts EXIT' "$ROOT/scripts/ios/test.sh"
rg --quiet 'source .*live-test-safety\.sh' "$ROOT/scripts/ios/test.sh"
rg --quiet 'source .*live-test-safety\.sh' "$ROOT/scripts/check-live.sh"
rg --quiet 'source .*live-test-safety\.sh' "$ROOT/scripts/ios/seed-simulator-gateway-config.sh"
rg --quiet 'openkeyboard_require_local_seed_file' "$ROOT/scripts/check-live.sh"
rg --quiet 'OPEN_KEYBOARD_LIVE_REQUIRED_MODEL' "$ROOT/scripts/check-live.sh"
rg --quiet 'TESTED_MODEL.*REQUIRED_MODEL' "$ROOT/scripts/check-live.sh"
rg --quiet 'required_model=\$REQUIRED_MODEL' "$ROOT/scripts/check-live.sh"
rg --quiet 'tested_model=\$TESTED_MODEL' "$ROOT/scripts/check-live.sh"
rg --quiet 'openkeyboard_require_local_seed_file' "$ROOT/scripts/ios/seed-simulator-gateway-config.sh"
rg --quiet 'exact seeded model without catalog fallback' "$ROOT/OpenKeyboardUITests/GatewayClientArchitectureTests.swift"
rg --quiet 'testRealKeyboardImproveReplacesTextWhenGatewayConfigured' "$ROOT/scripts/ios/test.sh"
if rg --quiet 'testRealKeyboardFixGrammarReplacesTextWhenGatewayConfigured' "$ROOT/scripts/ios/test.sh"; then
  echo "The live route still selects the removed real-keyboard test name." >&2
  exit 1
fi
if [[ "$(rg --count 'openkeyboard_assert_single_passing_xcresult' "$ROOT/scripts/ios/test.sh")" -ne 2 ]]; then
  echo "Both credentialed live routes must require exactly one passing xcresult test." >&2
  exit 1
fi
rg --quiet 'SENSITIVE_LIVE_SIMULATOR' "$ROOT/scripts/ios/test.sh"
rg --quiet 'SENSITIVE_LIVE_SOURCE_WAS_BOOTED' "$ROOT/scripts/ios/test.sh"
rg --quiet 'restore_sensitive_live_source_simulator' "$ROOT/scripts/ios/test.sh"
rg --quiet 'simctl clone' "$ROOT/scripts/ios/test.sh"
rg --quiet 'simctl delete' "$ROOT/scripts/ios/test.sh"
rg --quiet 'simctl shutdown' "$ROOT/scripts/ios/test.sh"
rg --quiet 'openkeyboard_restore_booted_simulator' "$ROOT/scripts/ios/test.sh"
rg --quiet 'simctl bootstatus' "$LIVE_TEST_SAFETY"
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
