#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENTS="$ROOT/AGENTS.md"
DEVELOP_SKILL="$ROOT/.agents/skills/develop-openkeyboard/SKILL.md"
PLAN_SKILL="$ROOT/.agents/skills/plan-openkeyboard-work-package/SKILL.md"
MILESTONE_PLAN_SKILL="$ROOT/.agents/skills/plan-openkeyboard-major-milestone/SKILL.md"
REVIEW_SKILL="$ROOT/.agents/skills/review-verify-merge-pr/SKILL.md"
REVIEWER_AGENT="$ROOT/.codex/agents/pr-reviewer.toml"
DEVELOPMENT_WORKFLOW="$ROOT/docs/DEVELOPMENT_WORKFLOW.md"
REAL_EXTENSION_SMOKE_PLAN="$ROOT/docs/REAL_EXTENSION_SMOKE_PLAN.md"
CARRY_FORWARD_VERIFIER="$ROOT/scripts/verify-runtime-proof-carry-forward.sh"
PRE_COMMIT="$ROOT/.githooks/pre-commit"

POLICY_FILES=(
  "$AGENTS"
  "$DEVELOP_SKILL"
  "$PLAN_SKILL"
  "$MILESTONE_PLAN_SKILL"
  "$REVIEW_SKILL"
  "$REVIEWER_AGENT"
  "$DEVELOPMENT_WORKFLOW"
  "$REAL_EXTENSION_SMOKE_PLAN"
)

require_phrase() {
  local phrase="$1"
  local file="$2"
  local message="$3"

  if ! rg --fixed-strings --quiet "$phrase" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

for ledger_field in \
  'Objective:' \
  'Current objective/phase:' \
  'Requested activity:' \
  'Active constraints (scope and expiry):' \
  'Read-only activity authorized: YES/NO' \
  'Edits authorized: YES/NO' \
  'Production-code edits authorized: YES/NO' \
  'Physical-device interaction authorized: YES/NO' \
  'Commit authorized: YES/NO' \
  'Push authorized: YES/NO' \
  'PR authorized: YES/NO' \
  'Merge authorized: YES/NO' \
  'Lifecycle gates: commit/push/PR/readiness/merge WAITING|READY|BLOCKED|COMPLETE' \
  'Required evidence:' \
  'Current blockers:'; do
  require_phrase "$ledger_field" "$AGENTS" "The canonical authority ledger is missing: $ledger_field"
done

require_phrase 'User constraints are sticky within their independently recorded scope.' "$AGENTS" \
  'AGENTS.md must make user authority constraints sticky within an explicit scope.'
require_phrase 'experiment/checkpoint, the current objective or phase, or the whole task.' "$AGENTS" \
  'AGENTS.md must distinguish checkpoint, objective/phase, and task-wide constraints.'
require_phrase 'Ambiguous or exploratory wording never revokes a sticky constraint.' "$AGENTS" \
  'AGENTS.md must reject ambiguous revocation of sticky constraints.'
require_phrase 'Recompute authority at every real phase transition.' "$AGENTS" \
  'AGENTS.md must dynamically recompute authority when the task changes phase.'
require_phrase 'Do not carry `NO` values forward merely because they appeared in an earlier ledger.' "$AGENTS" \
  'AGENTS.md must not preserve stale authority NO values across phase transitions.'
require_phrase 'Confidence does not override an active constraint; it advances lifecycle gates' "$AGENTS" \
  'AGENTS.md must separate confidence-driven gates from authority constraints.'
require_phrase 'Activate proof-first mode' "$AGENTS" \
  'AGENTS.md must define proof-first mode.'
require_phrase 'Recheck it before the first tracked edit, staging, commit, push, PR mutation, readiness change, or' "$AGENTS" \
  'AGENTS.md must recheck authority before every material mutation stage.'
require_phrase 'AUTHORITY: <mode> | read-only <YES/NO> | edits <YES/NO> | production edits <YES/NO> | physical device <YES/NO> | commit <YES/NO> | push <YES/NO> | PR <YES/NO> | merge <YES/NO>' "$AGENTS" \
  'AGENTS.md must define the visible constrained-task authority checkpoint.'
require_phrase 'GATES: commit <state> | push <state> | PR <state> | readiness <state> | merge <state>' "$AGENTS" \
  'AGENTS.md must expose lifecycle gate progress separately from authority.'
require_phrase 'tracked repository mutation—including production, test, documentation, staging, and commit' "$AGENTS" \
  'Proof-first mode must prohibit every tracked repository mutation, not only production changes.'
require_phrase 'Physical-device interaction defaults to `NO` and is independently sticky.' "$AGENTS" \
  'AGENTS.md must default physical-device interaction to denied.'
require_phrase 'do not grant physical-device authority.' "$AGENTS" \
  'AGENTS.md must not infer device authority from simulator, evidence, lifecycle, or merge work.'
require_phrase 'Physical-device interaction is a separate ledger entry that defaults to `NO`' "$DEVELOP_SKILL" \
  'The development skill must keep physical-device interaction separately denied by default.'
require_phrase 'A device evidence requirement is a blocker for Codex-operated proof when authority is' "$DEVELOP_SKILL" \
  'The development skill must not treat required device proof as device authority.'
require_phrase 'Physical-device interaction remains separately denied until the user explicitly requests it.' "$REVIEW_SKILL" \
  'The review lifecycle must not infer physical-device authority.'
require_phrase 'Physical-device interaction defaults to denied and requires an explicit user request in the active task' "$REVIEWER_AGENT" \
  'The independent reviewer must enforce explicit physical-device authority.'

# Scenario A: results-first remains read-only after "Try chunks."
require_phrase '`Test this and report before implementing` followed by `Try chunks` remains read-only: no tracked' "$AGENTS" \
  'Scenario A is missing its no-edit/no-commit result.'

# Scenario B: a clear fix can authorize edits without clearing a commit prohibition.
require_phrase '`Do not commit` followed by a clear `Fix the issue` may authorize scoped' "$AGENTS" \
  'Scenario B is missing its independent commit constraint.'
require_phrase 'edits, but staging, commit, and dependent publication remain blocked when `Do not commit` applies' "$AGENTS" \
  'Scenario B must keep staging, commit, and dependent publication blocked.'
require_phrase 'to the continuing objective rather than only a completed checkpoint.' "$AGENTS" \
  'Scenario B must distinguish an active objective constraint from an expired checkpoint constraint.'

# Scenario C: the exact authority-test checkpoint expires when correction begins.
require_phrase '`Perform a workflow-authority test only; begin read-only; do not edit, commit, push, create a PR,' "$AGENTS" \
  'Scenario C must cover the read-only workflow-authority test request.'
require_phrase '`Correct it` starts an implementation phase: recompute edit, commit, push, PR, and merge authority' "$AGENTS" \
  'Scenario C must transition a completed authority test into normal implementation.'
require_phrase "not resurrect the completed test phase's \`NO\` values." "$AGENTS" \
  'Scenario C must reject stale test-phase prohibitions.'

# Scenario D: failed AI screenshot capture transitions to screenshot-free human approval.
require_phrase '`AI screenshot verification is unavailable` followed by explicit repository-owner approval of' "$AGENTS" \
  'Scenario D must recognize exact-head human approval after failed AI screenshot verification.'
require_phrase 'Do not ask for a screenshot or structured report;' "$AGENTS" \
  'Scenario D must never require the owner to upload screenshot evidence.'
require_phrase 'mark the runtime decision gate ready and resume the standing lifecycle automatically' "$AGENTS" \
  'Scenario D must continue the lifecycle automatically after human approval.'

# Positive control: ordinary implementation receives conditional end-to-end lifecycle authority.
require_phrase 'A clear bounded implementation request grants standing conditional authority for the normal' "$AGENTS" \
  'Clear implementation must grant standing conditional authority for the normal repository lifecycle.'
require_phrase 'the user does not' "$AGENTS" \
  'The user must not have to enumerate every ordinary lifecycle stage.'
require_phrase 'Silence' "$AGENTS" \
  'Silence about a lifecycle stage must not be treated as an opt-out.'
require_phrase 'A clear `Implement this feature` request enters normal implementation mode and grants standing' "$AGENTS" \
  'Clear implementation must enter the autonomous lifecycle when no sticky constraint remains.'
if rg --fixed-strings --quiet 'It does not by itself authorize staging, commit, push, a PR, readiness, merge' "$AGENTS"; then
  echo 'AGENTS.md still defaults ordinary implementation lifecycle stages to unauthorized.' >&2
  exit 1
fi

# Scenario E: an external live outage blocks proof-first production work.
require_phrase 'an HTTP `503` or other required-gateway availability failure leaves the task' "$AGENTS" \
  'Scenario E is missing its external gateway failure rule.'
require_phrase 'implementing a speculative solution, or substituting deterministic tests.' "$AGENTS" \
  'Scenario E must stop speculative implementation and deterministic substitution.'

for task_status in \
  EXPERIMENTAL \
  DETERMINISTIC_VERIFIED \
  LIVE_UNVERIFIED \
  LIVE_VERIFIED \
  RUNTIME_UNVERIFIED \
  RUNTIME_VERIFIED; do
  require_phrase "\`$task_status\`" "$AGENTS" "AGENTS.md is missing task status $task_status."
done

require_phrase 'never call behavior fixed or' "$DEVELOP_SKILL" \
  'The development skill must reject fixed/working claims with missing proof.'
require_phrase 'A later ambiguous request cannot' "$DEVELOP_SKILL" \
  'The development skill must preserve sticky constraints across follow-ups.'
require_phrase 'standing conditional authority for the complete' "$DEVELOP_SKILL" \
  'The development skill must carry a clear implementation through the complete normal lifecycle.'
require_phrase 'A completed read-only test checkpoint does not keep its phase-scoped `NO` values' "$DEVELOP_SKILL" \
  'The development skill must expire phase-scoped authority constraints.'
require_phrase 'an authorized stage with incomplete evidence is' "$DEVELOP_SKILL" \
  'The development skill must separate lifecycle gate state from authority.'
require_phrase 'The user does not' "$REVIEW_SKILL" \
  'The review skill must not require the user to name each normal lifecycle stage.'
require_phrase 'Authority mode: READ_ONLY | PROOF_FIRST | IMPLEMENTATION' "$PLAN_SKILL" \
  'The planner must retain the authority mode in its work order.'
require_phrase 'Authority mode: READ_ONLY | PROOF_FIRST | IMPLEMENTATION' "$MILESTONE_PLAN_SKILL" \
  'The milestone planner must retain the authority mode in its roadmap.'
for planner in "$PLAN_SKILL" "$MILESTONE_PLAN_SKILL"; do
  require_phrase 'Read-only activity authorized: YES/NO' "$planner" \
    'Every planner output must track read-only authority independently.'
  require_phrase 'Merge authorized: YES/NO' "$planner" \
    'Every planner output must track merge authority independently.'
done
require_phrase 'Planning is read-only:' "$MILESTONE_PLAN_SKILL" \
  'The milestone planner must not turn roadmap creation into repository mutation.'
require_phrase 'Apply the sticky authority ledger from `AGENTS.md`.' "$REVIEW_SKILL" \
  'The review lifecycle must apply the sticky authority ledger.'
require_phrase 'do not resurrect a completed checkpoint' "$REVIEW_SKILL" \
  'The review lifecycle must not revive expired phase-scoped constraints.'
require_phrase 'If any active sticky constraint says `keep draft`' "$REVIEW_SKILL" \
  'The guarded merge must honor active sticky constraints, not only the latest instruction.'
require_phrase 'do not copy a completed read-only test phase' "$DEVELOPMENT_WORKFLOW" \
  'The detailed workflow must recompute authority across a phase transition.'
require_phrase 'Authority and readiness are separate.' "$DEVELOPMENT_WORKFLOW" \
  'The detailed workflow must separate authority from evidence readiness.'

require_phrase 'render or attach every screenshot actually used as' "$AGENTS" \
  'AGENTS.md must require final-response delivery of every AI proof screenshot.'
require_phrase 'earlier commentary is not final proof' "$AGENTS" \
  'AGENTS.md must reject commentary-only screenshot delivery.'
require_phrase 'Render or attach every required' "$DEVELOP_SKILL" \
  'The development skill must deliver required screenshots in the final response.'
require_phrase 'render or attach every screenshot used' "$REVIEW_SKILL" \
  'The review skill must deliver AI proof screenshots in the final response.'
require_phrase 'Required artifact-backed screenshot proof captured or used by Codex must be inspected' "$DEVELOPMENT_WORKFLOW" \
  'The detailed workflow must require final-response AI screenshot delivery.'
require_phrase 'Never ask the user to upload or transfer screenshots' "$AGENTS" \
  'AGENTS.md must prohibit user screenshot-upload requests.'
require_phrase 'An explicit owner approval for the exact current head selects the human authorization route' "$AGENTS" \
  'AGENTS.md must let exact-head human approval clear the runtime decision gate.'
require_phrase 'without another runtime, readiness, or merge confirmation' "$DEVELOP_SKILL" \
  'The development skill must continue automatically after exact-head human approval.'
require_phrase 'Ask the repository owner only whether they approve or reject that exact head' "$REAL_EXTENSION_SMOKE_PLAN" \
  'The runtime smoke plan must use approval, not uploaded screenshots, for human verification.'
require_phrase '### Final confirmation delivery' "$REAL_EXTENSION_SMOKE_PLAN" \
  'The runtime smoke plan must define final screenshot confirmation delivery.'
require_phrase 'an image shown only in earlier commentary is not final delivery' "$REAL_EXTENSION_SMOKE_PLAN" \
  'The runtime smoke plan must reject commentary-only screenshot delivery.'
require_phrase 'A Computer Use report that the host is locked' "$AGENTS" \
  'AGENTS.md must treat a Computer Use lock report as a route-level failure.'
require_phrase 'not a terminal runtime-proof conclusion' "$AGENTS" \
  'AGENTS.md must not make the first Computer Use lock report terminal.'
require_phrase '`com.apple.iphonesimulator`' "$AGENTS" \
  'AGENTS.md must require the canonical Simulator bundle-target retry when supported.'
require_phrase 'A Computer Use report that the host is locked' "$DEVELOP_SKILL" \
  'The development skill must recover from a Computer Use lock report before blocking.'
require_phrase 'A Computer Use report that the host' "$DEVELOPMENT_WORKFLOW" \
  'The detailed workflow must treat Computer Use lock reports as route-level failures.'
require_phrase 'A Computer Use report that the host is locked' "$REAL_EXTENSION_SMOKE_PLAN" \
  'The runtime smoke plan must define the Computer Use lock fallback.'
require_phrase 'alone does not prove that the required visible interaction occurred' "$REAL_EXTENSION_SMOKE_PLAN" \
  'The runtime smoke plan must not relabel a simctl framebuffer capture as interaction proof.'
require_phrase '**Simulator accessibility/control:**' "$AGENTS" \
  'AGENTS.md must put Simulator accessibility/control at the first proof tier.'
require_phrase '**Computer Use:**' "$AGENTS" \
  'AGENTS.md must put Computer Use after Simulator accessibility/control.'
require_phrase '**Human verification:**' "$AGENTS" \
  'AGENTS.md must make human verification the final proof tier.'
require_phrase 'escalate only the missing or' "$AGENTS" \
  'AGENTS.md must preserve valid proof and escalate only evidence gaps.'
require_phrase 'Accessibility metadata and action' "$AGENTS" \
  'AGENTS.md must not treat accessibility metadata or action success as visual proof.'
require_phrase 'three-tier normal-Simulator escalation hierarchy' "$DEVELOP_SKILL" \
  'The development skill must use the three-tier proof hierarchy.'
require_phrase '1. **Simulator accessibility/control:**' "$DEVELOPMENT_WORKFLOW" \
  'The detailed workflow must start with Simulator accessibility/control.'
require_phrase '2. **Computer Use:**' "$DEVELOPMENT_WORKFLOW" \
  'The detailed workflow must use Computer Use as the second tier.'
require_phrase '3. **Human verification:**' "$DEVELOPMENT_WORKFLOW" \
  'The detailed workflow must use human verification as the final tier.'
require_phrase 'neither automated tier can establish sufficient proof' "$REAL_EXTENSION_SMOKE_PLAN" \
  'The smoke plan must request human verification only after both automated tiers fail.'
require_phrase '### Test-only normal-runtime evidence carry-forward' "$AGENTS" \
  'AGENTS.md must define the narrow test-only runtime-proof carry-forward rule.'
require_phrase './scripts/verify-runtime-proof-carry-forward.sh <capture-sha> <current-sha>' "$AGENTS" \
  'AGENTS.md must require the trusted carry-forward verifier.'
require_phrase 'never claim that it was captured from the current SHA' "$AGENTS" \
  'AGENTS.md must preserve the original screenshot capture SHA.'
require_phrase 'no other exact-head gate or authorization carries forward' "$DEVELOP_SKILL" \
  'The development skill must confine carry-forward to normal-Simulator evidence.'
require_phrase 'verified test-only carry-forward record bound to the current head' "$REVIEW_SKILL" \
  'The review skill must recognize verifier-bound test-only runtime evidence.'
require_phrase '### Test-only carry-forward procedure' "$REAL_EXTENSION_SMOKE_PLAN" \
  'The smoke plan must document the test-only carry-forward procedure.'
require_phrase 'is_nonshipping_test_path' "$CARRY_FORWARD_VERIFIER" \
  'The carry-forward verifier must enforce a non-shipping test-path allowlist.'
require_phrase 'runtime_tree_digest' "$CARRY_FORWARD_VERIFIER" \
  'The carry-forward verifier must compare the non-test Git tree.'
require_phrase 'truthful documentation, commit subjects, or proof claims' "$REVIEWER_AGENT" \
  'The independent reviewer must inspect commit-message truthfulness.'
require_phrase 'Evidence boundary: this hook can establish DETERMINISTIC_VERIFIED only;' "$PRE_COMMIT" \
  'The pre-commit hook must state its deterministic-only evidence boundary.'

if rg --fixed-strings --quiet 'Honor the latest explicit opt-out' "${POLICY_FILES[@]}" ||
    rg --quiet 'Honor the latest .*do not commit' "${POLICY_FILES[@]}"; then
  echo "Active workflow policy still uses latest-only opt-out semantics." >&2
  exit 1
fi

require_phrase 'begin its subject with `Experimental:` or `Diagnostic:`' "$AGENTS" \
  'Experimental commit subjects must be truthful when required proof is missing.'
require_phrase 'This naming rule never grants' "$AGENTS" \
  'Commit-message policy must not grant commit authority.'

echo "Workflow authorization policy regression tests passed."
