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
   submodules, editing, or testing. Preserve sticky constraints independently; ambiguous later
   wording such as `try`, `find out`, or `try chunks` does not revoke them.
3. Keep a compact work order: objective, affected surfaces, exclusions, final state, verification
   level, required evidence class, and authority ledger.
4. Work in the isolated session worktree selected by `AGENTS.md` only when edits are authorized.
5. If the user asks for planning or what to do next, use the read-only planner through
   `$plan-openkeyboard-work-package`. Otherwise proceed directly.
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
before implementation. Do not edit production or documentation, stage, or commit. A required live
outage is `LIVE_UNVERIFIED` and stops the task without speculative production changes or extra
deterministic tests presented as replacement proof. Recheck the authority ledger before the first
tracked edit, staging, commit, push, and PR mutation.

Use repository Simulator routes so their shared lock and disposable-device ownership apply.
Never clear, stop, erase, or delete an existing or user-open Simulator to prepare a test.

XCUITest real-extension coverage remains automated regression evidence. Test-seeded states remain
diagnostics. Neither proves production behavior or physical-device behavior. UI, extension
lifecycle, Apply/Copy/Back/Rerun, live gateway, and result-presentation changes require the normal
runtime route in `AGENTS.md` and `docs/REAL_EXTENSION_SMOKE_PLAN.md`.

Use the first reliable normal-Simulator interaction route: a purpose-built Simulator-control
integration, then Computer Use or equivalent reliable host UI automation, then the exact manual
handoff. If interaction is unavailable or ambiguous, stop before publication and disclose the gap;
do not substitute more XCTest.

Local implementation and commits may proceed after deterministic checks only when the authority
ledger permits implementation and commit and no proof-first constraint remains. For proof-sensitive
user-facing changes, do not push or create/update a readiness PR until normal simulator runtime
proof succeeds unless the user explicitly authorizes a push with the gap disclosed. Never mark a
PR ready or merge while required simulator or physical-device proof is missing.

Report automated regression, transport, semantic acceptance, visual/runtime acceptance, and device
acceptance separately. Use the task-status labels from `AGENTS.md` and never call behavior fixed or
working while required live/runtime evidence remains unverified.

## Lifecycle autonomy

A bounded implementation request follows only the lifecycle stages individually authorized by the
sticky ledger in `AGENTS.md`: worktree, implementation, verification, commit, push, draft PR,
in-scope fixes, exact-head review, readiness, and guarded merge. A later ambiguous request cannot
clear an earlier edit, implementation, commit, push, PR, readiness, or merge constraint. Deployment
and destructive cleanup always require separate authority.

Use `$review-verify-merge-pr` for the exact report schema, GitHub event-family validation,
automatic-versus-human authorization, readiness, and merge mechanics. Below reviewer confidence of
exactly `100%`, keep the PR draft and request repository-owner approval for that exact SHA after all
unverified requirements are disclosed. A new commit expires prior exact-head evidence and
authorization.

## Handoff

Report the worktree/branch, changed areas, checks and results, exact evidence classes, screenshots
when required, proof gaps, exact SHA/PR state when published, and commit ID when committed. Never
claim an unexecuted simulator, extension, gateway, device, signing, deployment, or release path.
