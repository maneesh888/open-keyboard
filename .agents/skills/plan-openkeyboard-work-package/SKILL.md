---
name: plan-openkeyboard-work-package
description: Create a concise, source-bound OpenKeyboard work order from current status, work queue, completion plan, and relevant focused plans. Use when the user asks what to do next or explicitly requests a plan; do not delay an already clear implementation.
---

# Plan an OpenKeyboard Work Package

Produce one compact read-only work order without editing files or changing project status.

## Read minimal sources

1. Resolve the repository root and inspect `git status --short --branch`.
2. Read `AGENTS.md` completely.
3. Read only the status and roadmap sections in `README.md` and status headings in `docs/WORK_QUEUE.md`.
4. Read the relevant milestone or next-slice section in `docs/KEYBOARD_PRODUCT_COMPLETION_PLAN.md` when it covers the requested surface.
5. Follow links to a focused plan such as `docs/REAL_EXTENSION_SMOKE_PLAN.md` or `docs/plans/*.md` only when directly relevant.
6. Read only the purpose, modes, applicable targeted-routing row, and proof boundaries in `docs/DEVELOPMENT_WORKFLOW.md`.
7. Treat historical research, CI logs, and old status documents as context rather than current authority unless the current queue links to them.
8. Compute source digests with `git hash-object` for every source used in the final work order.

Read complete source files only when targeted sections are materially ambiguous or inconsistent.

## Keep planning non-blocking

- Do not edit files, install hooks, run tests, access GitHub, or spawn another agent.
- Do not repeat source prose; cite paths and headings.
- Do not ask for information already available in the repository.
- If implementation is already requested and clearly bounded, return control immediately instead of creating another planning gate.
- Surface only a decision that materially changes scope, architecture, proof, credentials, deployment, or lifecycle.

## Return this form

Keep the complete response under 500 words:

```text
Work package:
Current project state:
Objective:
Requirement sources:
Source digests:

In scope:
Out of scope:
Affected surfaces:
Likely files/modules:

Mode: Fast | Standard | Release
Targeted verification:
Release-only deferred gates:
Proof limits:

Lifecycle: planning only | implementation requested | narrowed by explicit opt-out
Blocking decision: none | concise decision
Next action:
```

Choose Release only for PR readiness, merge, release hardening, explicit release verification, or a
surface whose focused plan requires exact-head Release proof. Record explicit opt-outs instead of
turning routine implementation details into additional approvals.

When current status sources conflict, report the smallest material conflict and select no work that
depends on resolving it. When one source is clearly historical and the current queue is explicit,
use the current queue and record the older source as a proof limit rather than a blocker.

The implementation agent may rely on the work order while all listed digests match. A digest mismatch
requires refreshing only the changed source and affected fields.
