#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

POLICY_FILES=(
  "$ROOT/AGENTS.md"
  "$ROOT/.agents/skills/develop-openkeyboard/SKILL.md"
  "$ROOT/.agents/skills/review-verify-merge-pr/SKILL.md"
  "$ROOT/.codex/agents/pr-reviewer.toml"
  "$ROOT/.github/BRANCH_PROTECTION_GUIDE.md"
  "$ROOT/.github/pull_request_template.md"
  "$ROOT/docs/DEVELOPMENT_WORKFLOW.md"
  "$ROOT/docs/REAL_EXTENSION_SMOKE_PLAN.md"
)

for policy_file in "${POLICY_FILES[@]}"; do
  if [[ ! -f "$policy_file" ]]; then
    echo "Runtime-proof policy source is missing: $policy_file" >&2
    exit 1
  fi
done

require_phrase() {
  local phrase="$1"
  local file="$2"
  local message="$3"

  if ! rg --fixed-strings --quiet "$phrase" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

require_phrase '**Automated regression evidence:**' "$ROOT/AGENTS.md" \
  "AGENTS.md must define automated regression evidence."
require_phrase '**Normal simulator runtime proof:**' "$ROOT/AGENTS.md" \
  "AGENTS.md must define normal simulator runtime proof."
require_phrase '**Physical-device proof:**' "$ROOT/AGENTS.md" \
  "AGENTS.md must define physical-device proof."
require_phrase 'XCTest/XCUITest cannot' "$ROOT/AGENTS.md" \
  "AGENTS.md must prevent XCTest/XCUITest-only proof authorization."
require_phrase 'require normal simulator runtime proof before push' "$ROOT/AGENTS.md" \
  "AGENTS.md must gate proof-sensitive pushes on normal runtime proof."
require_phrase 'Additional XCTest runs do not replace missing runtime proof.' "$ROOT/AGENTS.md" \
  "AGENTS.md must stop XCTest substitution when normal runtime interaction is blocked."
require_phrase 'and XCTest are not substitutes.' "$ROOT/AGENTS.md" \
  "AGENTS.md must keep physical-device proof distinct."
require_phrase 'Report automated test results, transport success, semantic acceptance, and visual/runtime' "$ROOT/AGENTS.md" \
  "AGENTS.md must separate transport, semantic, and runtime acceptance."

require_phrase 'XCUITest real-extension coverage remains automated regression' "$ROOT/.agents/skills/develop-openkeyboard/SKILL.md" \
  "The development skill must classify real-extension XCUITest accurately."
require_phrase 'do not push or create/update a readiness PR until normal simulator runtime' "$ROOT/.agents/skills/develop-openkeyboard/SKILL.md" \
  "The development skill must block proof-sensitive publication without runtime proof."
require_phrase 'simulator or physical-device proof blocks readiness and merge in both routes.' "$ROOT/.agents/skills/review-verify-merge-pr/SKILL.md" \
  "The review skill must fail closed on missing runtime/device proof."
require_phrase 'Missing required normal simulator or physical-device proof is always a readiness and merge blocker' "$ROOT/.codex/agents/pr-reviewer.toml" \
  "The independent reviewer must reject runtime/device proof substitution."

require_phrase '## Evidence classes and claims' "$ROOT/docs/DEVELOPMENT_WORKFLOW.md" \
  "Development workflow must define the evidence classes."
require_phrase '## Normal simulator and device proof gate' "$ROOT/docs/DEVELOPMENT_WORKFLOW.md" \
  "Development workflow must define the runtime publication gate."
require_phrase '## Automated real-extension regression routes' "$ROOT/docs/REAL_EXTENSION_SMOKE_PLAN.md" \
  "The extension plan must label automated real-extension routes."
require_phrase '## Normal simulator runtime procedure' "$ROOT/docs/REAL_EXTENSION_SMOKE_PLAN.md" \
  "The extension plan must provide a normal runtime procedure."
require_phrase '## Physical-device procedure' "$ROOT/docs/REAL_EXTENSION_SMOKE_PLAN.md" \
  "The extension plan must provide a physical-device procedure."
require_phrase 'Do not run more XCTest as a substitute for the missing runtime proof.' "$ROOT/docs/REAL_EXTENSION_SMOKE_PLAN.md" \
  "The extension plan must provide a fail-closed manual handoff."

require_phrase 'Normal simulator runtime proof:' "$ROOT/.github/pull_request_template.md" \
  "The PR template must retain the normal runtime proof classification."
require_phrase 'Physical-device proof:' "$ROOT/.github/pull_request_template.md" \
  "The PR template must retain the physical-device proof classification."
require_phrase 'Missing required simulator/device proof blocks readiness and' "$ROOT/.github/BRANCH_PROTECTION_GUIDE.md" \
  "Branch-protection guidance must not allow readiness without runtime/device proof."

require_phrase 'Evidence boundary: XCTest/XCUITest regression only; not normal simulator or device proof.' "$ROOT/scripts/ios/test.sh" \
  "The real-keyboard-live route must print its automated evidence boundary."
require_phrase 'automated real-extension regression (not final runtime proof)' "$ROOT/scripts/ios/test.sh" \
  "The real-keyboard-live help text must not advertise final runtime proof."
require_phrase 'automated real-extension regression (not final runtime proof)' "$ROOT/scripts/local-ci.sh" \
  "The local CI help text must label the route as automated regression."

if rg --ignore-case --quiet \
  'XCTAttachments? (are|count as|provide) (final|manual|normal) simulator proof' \
  "${POLICY_FILES[@]}"; then
  echo "Workflow policy incorrectly treats XCTAttachments as final simulator proof." >&2
  exit 1
fi
if rg --ignore-case --quiet \
  'test-seeded[^.\n]*(proves|is proof of)[^.\n]*production (behavior|request|result)' \
  "${POLICY_FILES[@]}"; then
  echo "Workflow policy incorrectly treats test-seeded UI state as production proof." >&2
  exit 1
fi
if rg --ignore-case --quiet \
  'passing XCUITest alone (is sufficient|authorizes|proves readiness)' \
  "${POLICY_FILES[@]}"; then
  echo "Workflow policy incorrectly allows XCUITest alone to authorize push/readiness." >&2
  exit 1
fi
if rg --ignore-case --quiet \
  '(Simulator|XCTest) (satisfies|replaces|is equivalent to) physical-device proof' \
  "${POLICY_FILES[@]}"; then
  echo "Workflow policy incorrectly substitutes Simulator evidence for physical-device proof." >&2
  exit 1
fi

if rg --fixed-strings --quiet 'real keyboard extension live test' \
  "$ROOT/scripts/ios/test.sh" "$ROOT/scripts/local-ci.sh"; then
  echo "An XCTest route is still labeled as a real keyboard extension live test." >&2
  exit 1
fi

echo "Runtime-proof workflow policy tests passed."
