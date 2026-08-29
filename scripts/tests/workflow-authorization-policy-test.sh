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
PRE_COMMIT="$ROOT/.githooks/pre-commit"

POLICY_FILES=(
  "$AGENTS"
  "$DEVELOP_SKILL"
  "$PLAN_SKILL"
  "$MILESTONE_PLAN_SKILL"
  "$REVIEW_SKILL"
  "$REVIEWER_AGENT"
  "$DEVELOPMENT_WORKFLOW"
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
  'Requested activity:' \
  'Read-only activity authorized: YES/NO' \
  'Edits authorized: YES/NO' \
  'Production-code edits authorized: YES/NO' \
  'Commit authorized: YES/NO' \
  'Push authorized: YES/NO' \
  'PR authorized: YES/NO' \
  'Merge authorized: YES/NO' \
  'Required evidence:' \
  'Current blockers:'; do
  require_phrase "$ledger_field" "$AGENTS" "The canonical authority ledger is missing: $ledger_field"
done

require_phrase 'User constraints are sticky and independently scoped.' "$AGENTS" \
  'AGENTS.md must make user authority constraints sticky and independently scoped.'
require_phrase 'Ambiguous or exploratory wording never revokes a sticky constraint.' "$AGENTS" \
  'AGENTS.md must reject ambiguous revocation of sticky constraints.'
require_phrase 'Activate proof-first mode' "$AGENTS" \
  'AGENTS.md must define proof-first mode.'
require_phrase 'Recheck it before the first tracked edit, staging, commit, push, PR mutation, readiness change, or' "$AGENTS" \
  'AGENTS.md must recheck authority before every material mutation stage.'
require_phrase 'AUTHORITY: <mode> | read-only <YES/NO> | edits <YES/NO> | production edits <YES/NO> | commit <YES/NO> | push <YES/NO> | PR <YES/NO> | merge <YES/NO>' "$AGENTS" \
  'AGENTS.md must define the visible constrained-task authority checkpoint.'
require_phrase 'tracked repository mutation—including production, test, documentation, staging, and commit' "$AGENTS" \
  'Proof-first mode must prohibit every tracked repository mutation, not only production changes.'

# Scenario A: results-first remains read-only after "Try chunks."
require_phrase '`Test this and report before implementing` followed by `Try chunks` remains read-only: no tracked' "$AGENTS" \
  'Scenario A is missing its no-edit/no-commit result.'

# Scenario B: a clear fix can authorize edits without clearing a commit prohibition.
require_phrase '`Do not commit` followed by a clear `Fix the issue` may authorize scoped' "$AGENTS" \
  'Scenario B is missing its independent commit constraint.'
require_phrase 'edits, but staging and commit remain blocked.' "$AGENTS" \
  'Scenario B must keep staging and commit blocked.'

# Positive control: ordinary implementation must not be forced into proof-first planning.
require_phrase 'A clear `Implement this feature` request enters normal implementation mode and authorizes scoped' "$AGENTS" \
  'Clear implementation must enter the normal edit-authorized path when no sticky constraint remains.'
require_phrase 'It does not by itself authorize staging, commit, push, a PR, readiness, merge, or deployment.' "$AGENTS" \
  'Normal edit authorization must not silently grant later lifecycle authority.'

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
require_phrase 'If any active sticky constraint says `keep draft`' "$REVIEW_SKILL" \
  'The guarded merge must honor active sticky constraints, not only the latest instruction.'
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
