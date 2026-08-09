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
LIVE_EVIDENCE_POLICY_TEST="$ROOT/scripts/tests/live-evidence-policy-test.sh"
DEPLOY_SOURCE_POLICY_TEST="$ROOT/scripts/tests/deploy-source-policy-test.sh"
LIVE_TEST_SAFETY="$ROOT/scripts/ios/live-test-safety.sh"
LIVE_TEST_SAFETY_POLICY_TEST="$ROOT/scripts/tests/live-test-safety-test.sh"

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
  "$LIVE_EVIDENCE_POLICY_TEST" \
  "$DEPLOY_SOURCE_POLICY_TEST" \
  "$LIVE_TEST_SAFETY" \
  "$LIVE_TEST_SAFETY_POLICY_TEST"; do
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
rg --quiet 'github\.event\.pull_request\.head\.sha \|\| github\.sha' "$CI_WORKFLOW"
rg --quiet 'github\.event\.pull_request\.head\.sha' "$LIVE_WORKFLOW"
rg --quiet 'git show "\$PR_BASE_SHA:scripts/live-impact\.sh"' "$LIVE_WORKFLOW"
rg --quiet 'environment:[[:space:]]*live-policy' "$LIVE_WORKFLOW"
rg --quiet 'live_tested_head_count' "$LIVE_WORKFLOW"
rg --quiet 'live_tested_head.*HEAD_SHA' "$LIVE_WORKFLOW"
if rg --fixed-strings --quiet 'if [[ "$PR_BODY" != *"$HEAD_SHA"* ]]' "$LIVE_WORKFLOW"; then
  echo "Live evidence must bind the dedicated exact-head field, not any PR-body occurrence." >&2
  exit 1
fi
rg --quiet 'Required checks' "$CI_WORKFLOW"
rg --quiet 'Required live verification' "$LIVE_WORKFLOW"
rg --quiet 'environment:[[:space:]]*app-store-connect' "$DEPLOY_WORKFLOW"
rg --quiet '^  validate-release-source:$' "$DEPLOY_WORKFLOW"
rg --quiet 'refs/heads/main' "$DEPLOY_WORKFLOW"
rg --quiet 'git merge-base --is-ancestor' "$DEPLOY_WORKFLOW"
rg --quiet 'validate-release-source' "$DEPLOY_WORKFLOW"
rg --quiet '^sandbox_mode = "read-only"$' "$REVIEWER_AGENT"
rg --quiet 'Remain read-only' "$REVIEWER_AGENT"
rg --quiet '^sandbox_mode = "read-only"$' "$PLANNER_AGENT"
rg --quiet 'Do not edit files.*access GitHub' "$PLANNER_AGENT"
rg --quiet 'project `pr-reviewer`' "$REVIEW_SKILL"
rg --quiet 'scripts/check\.sh --full' "$REVIEW_SKILL"
rg --quiet 'Required checks' "$REVIEW_SKILL"
rg --quiet 'Required live verification' "$REVIEW_SKILL"
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
rg --quiet 'Exact reviewed head:' "$PR_TEMPLATE"
rg --quiet '^## Exact head SHA$' "$PR_TEMPLATE"
rg --quiet 'scripts/ios/test\.sh.*deterministic-ui' "$ROOT/scripts/check.sh"
rg --quiet -- '-skip-testing:OpenKeyboardUITests/KeyboardExtensionConfiguredUITests' "$ROOT/scripts/ios/test.sh"
rg --quiet -- '-skip-testing:OpenKeyboardUITests/LiveGatewayAIUITests' "$ROOT/scripts/ios/test.sh"
rg --quiet -- '-skip-testing:OpenKeyboardUITests/LiveGatewaySmokeTests' "$ROOT/scripts/ios/test.sh"
rg --quiet 'begin_sensitive_live_workspace live-gateway-smoke' "$ROOT/scripts/ios/test.sh"
rg --quiet 'begin_sensitive_live_workspace real-keyboard-live' "$ROOT/scripts/ios/test.sh"
rg --quiet 'trap cleanup_sensitive_live_artifacts EXIT' "$ROOT/scripts/ios/test.sh"
rg --quiet 'source .*live-test-safety\.sh' "$ROOT/scripts/ios/test.sh"
rg --quiet 'source .*live-test-safety\.sh' "$ROOT/scripts/check-live.sh"
rg --quiet 'source .*live-test-safety\.sh' "$ROOT/scripts/ios/seed-simulator-gateway-config.sh"
rg --quiet 'openkeyboard_require_local_seed_file' "$ROOT/scripts/check-live.sh"
rg --quiet 'openkeyboard_require_local_seed_file' "$ROOT/scripts/ios/seed-simulator-gateway-config.sh"
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
rg --quiet 'simctl bootstatus' "$ROOT/scripts/ios/test.sh"
rg --quiet -- '--replace-existing-config' "$ROOT/scripts/ios/test.sh"
if rg --quiet 'filter_map' "$ROOT/scripts/ios/test.sh"; then
  echo "Live-test helpers must remain compatible with the repository's supported host Ruby." >&2
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
  '.githooks/pre-push'
  'scripts/check-live.sh'
  'scripts/check.sh'
  'scripts/live-impact.sh'
  'scripts/ios/enable-openkeyboard-simulator-keyboard.sh'
  'scripts/ios/live-test-safety.sh'
  'scripts/ios/openkeyboard-gateway.seed.env.example'
  'scripts/ios/seed-simulator-gateway-config.sh'
  'scripts/ios/test.sh'
  'OpenKeyboard/Info.plist'
  'OpenKeyboard/*.swift'
  'OpenKeyboardCore/Package.swift'
  'OpenKeyboardCore/Sources/*.swift'
  'OpenKeyboardExtension/Info.plist'
  'OpenKeyboardExtension/*.swift'
  'OpenKeyboardUITests/GatewayClientArchitectureTests.swift'
  'OpenKeyboardUITests/KeyboardExtensionConfiguredUITests.swift'
  'OpenKeyboard.xcodeproj/project.pbxproj'
  'OpenKeyboard/*.entitlements'
  'OpenKeyboardExtension/*.entitlements'
)

for live_impact_pattern in "${live_impact_patterns[@]}"; do
  for classifier_source in "$ROOT/scripts/live-impact.sh" "$LIVE_WORKFLOW"; do
    if ! rg --fixed-strings --quiet "$live_impact_pattern" "$classifier_source"; then
      echo "Live-impact policy omitted $live_impact_pattern from $classifier_source." >&2
      exit 1
    fi
  done
done

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
