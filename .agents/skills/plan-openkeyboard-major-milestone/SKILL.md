---
name: plan-openkeyboard-major-milestone
description: Create a read-only, source-bound OpenKeyboard roadmap for an explicitly requested major milestone or multi-phase cross-cutting effort. Keep ordinary bounded tasks on the compact work-package planner and do not delay clear implementation requests.
---

# Plan an OpenKeyboard Major Milestone

Produce one phased roadmap that can be executed as a sequence of bounded work packages. Remain
read-only and preserve the authority and proof boundaries in `AGENTS.md`.

## Select this route narrowly

Use this skill only when the user explicitly asks for a major milestone, roadmap, long-horizon plan,
or multi-phase plan, or when the requested planning scope necessarily crosses several independently
verifiable subsystems or releases.

- Use `$plan-openkeyboard-work-package` for one bounded task or a concise "what next" plan.
- Return control to `$develop-openkeyboard` when implementation is already clear and the user did
  not request a plan.
- Never insert milestone planning as a mandatory gate before ordinary implementation.

## Establish authority and sources

1. Resolve the repository root, inspect `git status --short --branch`, and read `AGENTS.md`
   completely.
2. Apply its sticky authority ledger. Planning is read-only: do not fetch, create worktrees,
   initialize submodules, edit, stage, commit, push, create or modify a PR, access GitHub, run tests,
   or spawn agents.
3. Read the current status and roadmap sections in `README.md`, status headings in
   `docs/WORK_QUEUE.md`, and the relevant parts of
   `docs/KEYBOARD_PRODUCT_COMPLETION_PLAN.md`.
4. Read `docs/DEVELOPMENT_WORKFLOW.md` for route and proof boundaries. Follow only directly relevant
   focused plans, architecture sources, and semantic-contract sources.
5. Treat old research, logs, and completed plans as historical unless a current source links to
   them. State material conflicts instead of silently choosing a stale source.
6. Record every final requirement source and its `git hash-object` digest.

## Build an executable roadmap

Start from the desired milestone outcome and work backward through dependencies. Prefer 3–8 phases;
use fewer or more only when the dependency structure genuinely requires it. Each phase must be
small enough to become a bounded work package and must include:

- objective and user-visible or engineering outcome
- deliverables and affected surfaces
- dependencies and entry criteria
- explicit non-goals
- deterministic verification
- required live, normal-simulator, or physical-device evidence, only when applicable
- exit criteria and a clear `GO`, `REWORK`, or `BLOCKED` decision gate
- material risks and rollback or containment strategy

Separate work that can proceed in parallel from the critical path. Put uncertain architecture or
external dependencies behind an early discovery phase; do not bury them in implementation.
Automated regression evidence never replaces required normal runtime proof. Do not require a
physical device by default: add device proof only for a device-specific requirement or a material
device-only uncertainty that Simulator cannot resolve, and identify manual verification when Codex
cannot perform it confidently.

Keep publication, guarded merge, deployment, and destructive cleanup as explicit later gates. A
plan does not authorize any of them. End with the first bounded work package that can be handed to
`$develop-openkeyboard`; do not implement it.

## Return this form

Keep the roadmap direct and normally under 2,000 words:

```text
Major milestone:
Outcome and success measures:
Current state:
Assumptions and source conflicts:

Requirement sources:
Source digests:

In scope:
Out of scope:
Critical path:
Parallel work:

Phase 1 — <name>
Objective:
Deliverables / affected surfaces:
Dependencies / entry criteria:
Non-goals:
Verification and evidence:
Exit criteria:
Decision gate: GO | REWORK | BLOCKED
Risks / rollback:

<repeat only for necessary phases>

Cross-phase proof and release gates:
Risk register:
Milestone completion criteria:

Authority mode: READ_ONLY | PROOF_FIRST | IMPLEMENTATION
Edits authorized: YES/NO
Production-code edits authorized: YES/NO
Commit authorized: YES/NO
Push authorized: YES/NO
PR authorized: YES/NO
Current blockers:

First bounded work package:
Next action:
```

Do not turn every phase into an approval request. Ask only about a decision that materially changes
scope, architecture, proof, credentials, deployment, or destructive state. When source digests
change, refresh only the affected phases and dependencies.
