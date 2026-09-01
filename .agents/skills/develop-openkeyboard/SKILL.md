---
name: develop-openkeyboard
description: Execute bounded OpenKeyboard analysis, implementation, testing, documentation, CI, gateway, keyboard-extension, and release-hardening work through the repository's canonical workflow.
---

# Develop OpenKeyboard

Use `AGENTS.md` as the canonical execution policy. This skill supplies the implementation loop; do
not restate or weaken the repository's evidence, secret, git, or review gates.

## Enter the task

1. Resolve the repository root and inspect status without mutation, then read `AGENTS.md`
   completely.
2. Build the canonical authority ledger before fetching, creating a branch/worktree, initializing
   submodules, editing, or testing. Record each constraint's objective/phase/task scope and expiry,
   preserve active constraints independently, and recompute the ledger at every real phase
   transition. A completed read-only test checkpoint does not keep its phase-scoped `NO` values
   after a clear `correct it`, `fix it`, or implementation request starts the next phase. Ambiguous
   later wording such as `try`, `find out`, or `try chunks` does not cause a transition.
   Physical-device interaction is a separate ledger entry that defaults to `NO`; simulator work,
   proof requirements, publication, and merge authority never turn it on.
3. Keep a compact work order: objective, affected surfaces, exclusions, final state, verification
   level, required evidence class, and authority ledger.
4. Work in the isolated session worktree selected by `AGENTS.md` only when edits are authorized.
5. If the user explicitly asks for a major milestone, roadmap, long-horizon plan, or multi-phase
   plan, use the read-only `$plan-openkeyboard-major-milestone`. Use the read-only
   `$plan-openkeyboard-work-package` for one bounded plan or a concise "what next" request.
   Otherwise proceed directly; never add either planning route before a clear implementation.
6. Read only relevant source, acceptance, and focused-plan sections. Read
   `docs/DEVELOPMENT_WORKFLOW.md` for workflow/CI/signing/deployment changes and initialize the
   pinned semantic-contract submodule for prompt/schema/adapter work only after the needed
   repository mutation is authorized.

## Implement and verify

1. Preserve unrelated work and keep edits inside the work order.
2. Follow the repository's MVVM, theme, App Group, Keychain, extension-lifecycle, gateway, semantic
   contract, and secret boundaries.
3. Add or update focused automated regression coverage for changed behavior.
4. Run affected tests while iterating, then select the final gate:
   - **Fast/local policy:** affected tests plus `./scripts/check.sh --hygiene`.
   - **Standard completed work:** `./scripts/check.sh --quick`.
   - **Release/publish:** exact-head `./scripts/check.sh --full`, classifier-selected live gate,
     required runtime proof, GitHub checks, and independent review.
5. Run `./scripts/check-semantic-prompt-contract.sh` for contract/gitlink/schema/fixture/adapter
   changes. Use `gateway-differential` only for the classifier-selected low/high surfaces or
   pre-release verification; preserve exact role/model identity and treat an unstable low boundary
   as diagnostic/`UNVERIFIED`.
6. Run `git diff --check`, install and honor hooks, stage only task files, and inspect staged names
   plus content before committing.

In proof-first mode, use existing routes or temporary non-repository harnesses and report results
before implementation. Do not mutate any tracked production, test, documentation, configuration,
or workflow file, and do not stage or commit. A required live outage is `LIVE_UNVERIFIED` and stops
the task without speculative production changes or extra deterministic tests presented as
replacement proof. Recheck the authority ledger before the first tracked edit, staging, commit,
push, PR mutation, readiness change, and merge.

Use repository Simulator routes so their shared lock and disposable-device ownership apply.
Never clear, stop, erase, or delete an existing or user-open Simulator to prepare a test.
Never enumerate, inspect, connect to, install on, launch on, sign for, test on, or capture from a
physical device unless the user explicitly requests physical-device interaction in the active
task. A device evidence requirement is a blocker when authority is absent, not permission.

XCUITest real-extension coverage remains automated regression evidence. Test-seeded states remain
diagnostics. Neither proves production behavior or physical-device behavior. UI, extension
lifecycle, Apply/Copy/Back/Rerun, live gateway, and result-presentation changes require the normal
runtime route in `AGENTS.md` and `docs/REAL_EXTENSION_SMOKE_PLAN.md`.

Use a three-tier normal-Simulator escalation hierarchy. First use a purpose-built Simulator
accessibility/control integration to inspect the normal app's accessibility hierarchy, operate
discoverable controls, and capture direct screenshots. If that route cannot establish every
required system interaction or visible result, retain its valid evidence and use Computer Use or
equivalent reliable host UI automation for the missing proof. Ask for the exact human verification
handoff only when both automated tiers remain unavailable, unreliable, or ambiguous. Accessibility
metadata or action success without an inspected visible result and delivered screenshot is not
visual proof.

A Computer Use report that the host is locked or Simulator is unavailable is a route-level failure,
not a terminal runtime-proof conclusion. Refresh once and retry Simulator with bundle identifier
`com.apple.iphonesimulator` when supported, then attempt any other available non-XCTest Simulator
accessibility/control route. Do not loop on a genuinely locked host or treat a `simctl` framebuffer
capture as proof of interaction. If interaction is still unavailable or ambiguous, stop before
publication and disclose the gap; do not substitute more XCTest.

Do not repeat a complete normal-Simulator screenshot run merely because a later commit changes only
non-shipping test-target files. Run
`./scripts/verify-runtime-proof-carry-forward.sh <capture-sha> <current-sha>` on the clean current
head. Carry the prior runtime evidence forward only when the verifier confirms ancestor ordering,
the test-only path allowlist, and an identical non-test Git-tree digest. Retain the original capture
SHA on every image and record both SHAs, the digest, and intervening paths. Any other change or
verifier failure requires fresh proof; no other exact-head gate or authorization carries forward.

Local implementation and commits may proceed after deterministic checks for a bounded
implementation request under the standing conditional lifecycle authority in `AGENTS.md`, unless
proof-first mode or an explicit edit/commit opt-out remains active. For proof-sensitive user-facing
changes, do not push or create/update a readiness PR until normal simulator runtime proof succeeds
unless the user explicitly authorizes a push with the gap disclosed. Never mark a PR ready or merge
while required simulator or physical-device proof is missing.

Report automated regression, transport, semantic acceptance, visual/runtime acceptance, and device
acceptance separately. Use the task-status labels from `AGENTS.md` and never call behavior fixed or
working while required live/runtime evidence remains unverified.

## Lifecycle autonomy

A clear bounded implementation request grants standing conditional authority for the complete
normal repository lifecycle: worktree preparation, implementation, verification, commit, push,
draft PR, in-scope fixes, exact-head review, readiness, and guarded merge. Advance without asking
the user to enumerate or reconfirm ordinary stages when their required gates pass.
Keep authority separate from gate state: an authorized stage with incomplete evidence is
`WAITING`, not authority `NO`. Recompute gate state as deterministic, live, runtime, exact-head,
review, and GitHub evidence arrives; when a required gate becomes `READY`, execute the next
authorized stage without requesting permission again. A later ambiguous request cannot clear an
active earlier edit, implementation, commit, push, PR, readiness, or merge constraint. A clear
implementation request after a completed checkpoint does clear that checkpoint's phase-scoped
constraints, but not an explicit task-wide constraint. Deployment and destructive cleanup always
require separate authority.

Use `$review-verify-merge-pr` for the exact report schema, GitHub event-family validation,
automatic-versus-human authorization, readiness, and merge mechanics. Below reviewer confidence of
exactly `100%`, keep the PR draft and request repository-owner approval for that exact SHA after all
unverified requirements are disclosed. A new commit expires prior exact-head evidence and
authorization; only normal-Simulator evidence that passes the test-only carry-forward verifier may
survive, and it remains labeled with its capture SHA.

## Handoff

Report the worktree/branch, changed areas, checks and results, exact evidence classes, proof gaps,
exact SHA/PR state when published, and commit ID when committed. Render or attach every required
proof screenshot in the final response, even if it was shown in commentary; a filesystem path,
`.xcresult`, PR link, or summary alone is not delivery. If delivery is unavailable, keep the
affected requirement and runtime status unverified and give the exact manual screenshot checklist.
Never claim an unexecuted simulator, extension, gateway, device, signing, deployment, or release
path.
