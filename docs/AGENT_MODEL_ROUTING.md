# Agent model routing

This policy selects development assistants, not the app's gateway LOW/HIGH profiles. Those
profiles, exact-model requirements, privacy rules, and live gates remain unchanged. `AGENTS.md`
remains the authority for permissions, evidence, and publication.

## Choose the smallest adequate assignment

Use direct tools for a short search, a command, or a small edit. Spawn an agent when it can complete
a meaningful bounded assignment independently, with less parent context or useful parallelism.
Lower model cost, fewer tokens, and lower elapsed time are separate outcomes: parallel agents can
reduce elapsed time while increasing total tokens. These defaults are routing hypotheses, not
benchmarked capability or pricing claims.

| Task and boundary | Default when exposed by the current agent tool | Escalation |
|---|---|---|
| Locate symbols/files; extract bounded facts with source references | `gpt-6-luna`, low reasoning | Missing context, conflicting sources, or an architectural conclusion |
| Run root-selected repository tests; extract counts, failures, skips, and exit status from redacted output | `gpt-6-luna`, low reasoning | Unexpected failure, ambiguous result, flaky run, or a proposed command/gate change |
| Compare structured output against an explicit deterministic checklist | `gpt-6-luna`, medium reasoning | Semantic judgment, incomplete evidence, or acceptance criteria requiring interpretation |
| Scoped implementation, regression-test design, or localized failure diagnosis | `gpt-6.1-sol`, medium reasoning | Cross-process behavior, unclear ownership, repeated failed approach, or broad design impact |
| Cross-cutting architecture, privacy/security/authority decisions, ambiguous semantic or visual acceptance | `gpt-6-astra`, high reasoning, or the capable root | Material uncertainty remains: report the gap; stronger models do not manufacture proof |
| Independent exact-head PR review | `gpt-6-astra`, high reasoning, using the project `pr-reviewer` role | Preserve the skill's confidence, human-approval, and mandatory-gate rules |

Do not route solely by labels such as “testing” or “verification.” Running a prescribed test is
routine; designing meaningful coverage or deciding whether an output satisfies user intent may be
hard. Screenshot acceptance requires image-capable tools/model access and actual inspection under
the existing runtime-proof rules. A log summary never replaces that inspection.

Check the active tool's available models, reasoning levels, role constraints, and override support
at assignment time. Prefer explicit user selections. These model identifiers are examples supported
by the session in which this policy was introduced, not portable API IDs or a permanent catalog.
If unavailable, select an exposed equivalent by task capability and record the substitution; if no
suitable model exists, retain the task in the capable parent or report the limitation. Never claim
an override succeeded without runtime support. Do not change global configuration or account settings.

For the collaboration API that exposes `model`, `reasoning_effort`, and `fork_turns`, pass the model
and supported effort explicitly with `fork_turns="none"`. Full-history forks inherit the parent and
cannot accept those overrides. Other runtimes must use their documented supported mechanism; this
Markdown does not install roles or configure a model automatically. Keep specialized role contracts
(planner, reviewer) intact; their prohibited actions remain prohibited regardless of model tier.

## Compact handoff and ownership

Give each worker only what it needs:

- Objective, observable acceptance criterion, exact worktree and base/head (or explicit dirty-diff
  scope), relevant paths, and the canonical instructions it must read.
- Applicable authority ledger and sticky constraints, excluded work, owned files and resources,
  permitted commands, and the condition for returning a blocker.
- Required evidence and return format: result, source locations or artifact references, command
  and revision, exit status, actual counts/failures/skips, limits, and unresolved questions.

Do not forward the full conversation, raw gateway logs, credentials, local model identities, or
large successful test output. Ask for bounded excerpts with source references; keep sensitive
artifacts local under existing privacy rules. Workers may read additional relevant sources when
necessary; a compact packet must not hide governing instructions or acceptance criteria.

Tell editing workers they share the codebase, own only the named files, must preserve others'
edits, and must return changes without staging, committing, pushing, or mutating PRs. The root
integrates and owns lifecycle actions. During review/fix phases, follow the review skill's stricter
root-only fix rule. A test runner owns execution and evidence collection, not production edits or
verification-policy changes. Do not mutate files while a gate is testing them; freeze the candidate
and record which revision was tested.

Use only available concurrency slots. Start with at most two independent workers; add another only
when a third disjoint assignment materially helps and the runtime permits it. Do not split work
merely to occupy slots. Source inventory and a disjoint documentation investigation can overlap;
competing edits, dependent diagnosis, staging, publication, and shared Simulator interaction cannot.
All Simulator-backed work uses the existing shared lock and repository routes. Assign one gate
runner; do not run duplicate cumulative gates from multiple agents. Reuse idle agents only for
closely related tasks with current constraints; use fresh context for a new scope and always for
independent review.

## Escalation and evidence acceptance

A lightweight worker returns unexpected failures with the exact evidence and unresolved question.
It must not retry repeatedly, widen scope, edit expectations, suppress skips, change models in the
app, or replace a required gate. The root may perform one bounded diagnosis at the workhorse tier,
then escalate material ambiguity or risk to the frontier tier. Reuse collected valid evidence;
do not rerun successful commands merely to obtain a stronger model's summary. Legitimate reruns
still follow the repository's freshness and resumable-verification rules.

The root checks evidence bindings and completeness before using a worker's result. Independent
review receives the neutral requirements, diff, and inspectable raw evidence references required
by its skill, not an implementer's approval conclusion. A low-cost extraction can prepare that
packet but cannot stand in for independent review. Missing, stale, skipped, wrong-target, or
uninspectable evidence remains unverified at every model tier. Model strength never relaxes gates.

## Evaluate the policy without inventing savings

For substantive assignments, keep a compact local record: task class, selected model/effort,
context mode, outcome, escalation/rework, and elapsed time. Include input/output/cached token counts
and cost only when the runtime actually exposes them; otherwise mark them unavailable. Do not add
telemetry, publish private logs, or claim a measured percentage from model choice alone.

Compare similar task classes and include parent coordination, all child tokens, retries, and
review corrections in totals. Preserve correctness and evidence completeness as the acceptance
criteria. Use observed rework to adjust routing; do not downgrade high-consequence review solely
to optimize a token target. There is no required benchmark run or extra gate for ordinary tasks.
