#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

POLICY_FILES=(
  "$ROOT/AGENTS.md"
  "$ROOT/.agents/skills/develop-openkeyboard/SKILL.md"
  "$ROOT/.agents/skills/review-verify-merge-pr/SKILL.md"
  "$ROOT/.agents/skills/review-verify-merge-pr/SKILL.md"
  "$ROOT/.codex/agents/pr-reviewer.toml"
  "$ROOT/.github/BRANCH_PROTECTION_GUIDE.md"
  "$ROOT/.github/pull_request_template.md"
  "$ROOT/README.md"
  "$ROOT/docs/AI_KEYBOARD_TODO.md"
  "$ROOT/docs/DEVELOPMENT_WORKFLOW.md"
  "$ROOT/docs/KEYBOARD_PRODUCT_COMPLETION_PLAN.md"
  "$ROOT/docs/M2_PROGRESS.md"
  "$ROOT/docs/PR_PROOF_AUDIT_2026-08-14.md"
  "$ROOT/docs/REAL_EXTENSION_SMOKE_PLAN.md"
  "$ROOT/docs/RELEASE_HARDENING.md"
  "$ROOT/docs/TDD_STATUS.md"
  "$ROOT/docs/WORK_QUEUE.md"
)

ACTIVE_INTERACTION_POLICY_FILES=(
  "$ROOT/AGENTS.md"
  "$ROOT/.agents/skills/develop-openkeyboard/SKILL.md"
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
require_phrase 'a purpose-built, generically named Simulator-control integration;' "$ROOT/AGENTS.md" \
  "AGENTS.md must prefer a vendor-neutral Simulator-control integration."
require_phrase 'Computer Use or equivalent host UI automation' "$ROOT/AGENTS.md" \
  "AGENTS.md must retain the generic host-UI automation fallback."

require_phrase 'XCUITest real-extension coverage remains automated regression' "$ROOT/.agents/skills/develop-openkeyboard/SKILL.md" \
  "The development skill must classify real-extension XCUITest accurately."
require_phrase 'do not push or create/update a readiness PR until normal simulator runtime' "$ROOT/.agents/skills/develop-openkeyboard/SKILL.md" \
  "The development skill must block proof-sensitive publication without runtime proof."
require_phrase 'Missing required AI simulator or physical-device screenshots' "$ROOT/.agents/skills/review-verify-merge-pr/SKILL.md" \
  "The review skill must block automatic authorization without AI screenshot proof."
require_phrase 'explicit repository-owner approval for the exact head may accept that disclosed gap' "$ROOT/.codex/agents/pr-reviewer.toml" \
  "The independent reviewer must recognize the screenshot-free human route."
require_phrase 'Never ask the user to upload or transfer screenshots' "$ROOT/AGENTS.md" \
  "AGENTS.md must never require a user screenshot upload."
require_phrase 'Ask for an exact-head approve/reject decision, never a screenshot upload.' "$ROOT/docs/REAL_EXTENSION_SMOKE_PLAN.md" \
  "The runtime handoff must request human approval rather than screenshots."
require_phrase '`RUNTIME_VERIFIED (human-approved)`' "$ROOT/docs/REAL_EXTENSION_SMOKE_PLAN.md" \
  "The runtime plan must define the human-approved evidence boundary."

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

if rg --ignore-case --quiet 'ClawMaster' "${ACTIVE_INTERACTION_POLICY_FILES[@]}"; then
  echo "Active interaction policy must use capability names, not a vendor-specific tool name." >&2
  exit 1
fi

require_phrase 'Normal simulator runtime proof:' "$ROOT/.github/pull_request_template.md" \
  "The PR template must retain the normal runtime proof classification."
require_phrase 'Physical-device proof:' "$ROOT/.github/pull_request_template.md" \
  "The PR template must retain the physical-device proof classification."
require_phrase 'Missing AI simulator/device' "$ROOT/.github/BRANCH_PROTECTION_GUIDE.md" \
  "Branch-protection guidance must keep missing screenshots out of the automatic route."
require_phrase 'The human route may proceed after explicit repository-owner' "$ROOT/.github/BRANCH_PROTECTION_GUIDE.md" \
  "Branch-protection guidance must permit exact-head human approval without screenshot upload."

require_phrase 'Evidence boundary: XCTest/XCUITest regression only; not normal simulator or device proof.' "$ROOT/scripts/ios/test.sh" \
  "The real-keyboard-live route must print its automated evidence boundary."
require_phrase 'automated real-extension regression (not final runtime proof)' "$ROOT/scripts/ios/test.sh" \
  "The real-keyboard-live help text must not advertise final runtime proof."
require_phrase 'automated real-extension regression (not final runtime proof)' "$ROOT/scripts/local-ci.sh" \
  "The local CI help text must label the route as automated regression."

reject_forbidden_implications() {
  local files=("$@")

  if rg --ignore-case \
    'XCTAttachments?[^.\n]*(are|is|count(s)? as|satisf(y|ies)|provide(s)?)[^.\n]*(final|manual|normal)[^.\n]*simulator (runtime )?proof' \
    "${files[@]}" | rg --invert-match --ignore-case --quiet '(not|cannot|never|do not)'; then
    return 1
  fi
  if rg --ignore-case \
    '(test[- ]seeded|seeded (UI|result|loading|success|warning|failure) state)[^.\n]*(prove(s)?|count(s)? as|establish(es)?|verif(y|ies))[^.\n]*(production|normal runtime|live request)' \
    "${files[@]}" | rg --invert-match --ignore-case --quiet '(not|cannot|never|do not)'; then
    return 1
  fi
  if rg --ignore-case \
    '(passing )?(XCTest|XCUITest)[^.\n]*(alone|by itself)[^.\n]*(is enough|is sufficient|authoriz(es|e)|permits?)[^.\n]*(push|readiness|release)' \
    "${files[@]}" | rg --invert-match --ignore-case --quiet '(not|cannot|never|do not)'; then
    return 1
  fi
  if rg --ignore-case \
    '(Simulator|XCTest|XCUITest) evidence (replaces|satisfies|counts as|is equivalent to) physical[- ]device proof' \
    "${files[@]}" | rg --invert-match --ignore-case --quiet '(not|cannot|never|do not)'; then
    return 1
  fi
}

if ! reject_forbidden_implications "${POLICY_FILES[@]}"; then
  echo "Workflow sources contain a forbidden automated/runtime/device proof implication." >&2
  exit 1
fi

FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE_DIR"' EXIT

assert_rejected_fixture() {
  local name="$1"
  local wording="$2"
  local fixture="$FIXTURE_DIR/$name.md"

  printf '%s\n' "$wording" > "$fixture"
  if reject_forbidden_implications "$fixture"; then
    echo "Runtime-proof policy accepted forbidden fixture: $name" >&2
    exit 1
  fi
}

assert_rejected_fixture xctattachment \
  'XCTAttachment satisfies final simulator proof for this change.'
assert_rejected_fixture seeded-state \
  'A test-seeded UI state counts as production behavior proof.'
assert_rejected_fixture xcuitest-readiness \
  'Passing XCUITest alone is enough to authorize push readiness.'
assert_rejected_fixture simulator-device \
  'Simulator evidence replaces physical-device proof.'

if rg --fixed-strings --quiet 'real keyboard extension live test' \
  "$ROOT/scripts/ios/test.sh" "$ROOT/scripts/local-ci.sh"; then
  echo "An XCTest route is still labeled as a real keyboard extension live test." >&2
  exit 1
fi

if rg --fixed-strings --quiet 'Send the three direct screenshots' "${ACTIVE_INTERACTION_POLICY_FILES[@]}" ||
    rg --fixed-strings --quiet 'supply the required screenshots' "${ACTIVE_INTERACTION_POLICY_FILES[@]}"; then
  echo "Human verification must never require the user to upload screenshots." >&2
  exit 1
fi

echo "Runtime-proof workflow policy tests passed."
