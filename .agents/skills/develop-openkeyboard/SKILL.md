---
name: develop-openkeyboard
description: Execute bounded OpenKeyboard analysis, planning, implementation, testing, documentation, CI, gateway, keyboard-extension, and release-hardening work while preserving iOS and secret boundaries.
---

# Develop OpenKeyboard

Work on one bounded package while preserving the host app, keyboard extension, shared configuration,
gateway, and proof boundaries.

## Establish only needed context

1. Resolve the repository root and inspect `git status --short --branch`.
2. Read `AGENTS.md` completely.
3. Read the current status and roadmap in `README.md` plus only the relevant status entries in `docs/WORK_QUEUE.md`.
4. If the user requests planning or asks what is next, invoke the read-only `work-package-planner` without inherited conversation; it uses `$plan-openkeyboard-work-package`.
5. Otherwise read only the requested work package, acceptance, verification, and proof-limit sections needed for the change.
6. Read `docs/KEYBOARD_PRODUCT_COMPLETION_PLAN.md` and focused plans only when their surface is affected or status sources are ambiguous.
7. Read `docs/DEVELOPMENT_WORKFLOW.md` when selecting checks or changing workflow, hooks, CI, signing, deployment, or external-tool behavior.

Preserve unrelated work. Use an isolated worktree when exact-head operations would disturb a dirty
checkout.

## Select the mode

- **Fast:** focused local change, affected tests, and hygiene.
- **Standard:** completed implementation plus the quick deterministic gate.
- **Release:** exact-head full gate, applicable live proof, CI, independent review, and guarded readiness or merge.

Use the highest mode required by the requested outcome or changed surface. Mandatory hooks may run
a higher cumulative gate without expanding the task's proof claim.

## Execute

1. Keep a compact internal work order with objective, affected surfaces, out-of-scope behavior, mode, and proof boundaries.
2. Add or update focused tests when behavior changes.
3. Keep SwiftUI views presentation-focused; place UI state and actions in ViewModels and side effects in services or repositories.
4. Preserve App Group, Keychain, signing, extension-lifecycle, and gateway trust boundaries.
5. Use `OpenKeyboardTheme` tokens and existing local patterns in touched UI.
6. Keep deterministic, screenshot, real-extension, live-gateway, signing, deployment, and App Review evidence distinct.
7. Update affected documentation when a user-visible contract, proof route, workflow, or status source changes.
8. Never claim evidence for an unexecuted simulator, extension lifecycle, device, gateway, signing, deployment, or release path.

## Lifecycle autonomy

A bounded implementation request starts the normal repository lifecycle through guarded merge:
branch/worktree preparation, edits, tests, commit, push, PR publication, in-scope review fixes,
readiness, and merge. Continue without separate confirmation between those stages.

Honor the latest explicit opt-out:

- `local only`
- `do not commit`
- `do not push`
- `do not create a PR`
- `keep draft` or `do not mark ready`
- `do not merge`

Planning, review-only work, readiness assessment, and blocker requests remain read-only. Deployment
and destructive cleanup remain separate external actions requiring explicit authority. Stop for
unavailable credentials, destructive actions, material scope expansion, ambiguous ownership of
dirty work, or an external state change outside that authority.

Use available GitHub tooling for repository operations. Never add a write-enabled or secret-bearing
ordinary pull-request workflow.

## Verify and publish

- Run affected tests while iterating.
- Run `./scripts/check.sh --hygiene` for a Fast handoff with file changes.
- Run `./scripts/check.sh --quick` for Standard; mandatory hooks may supply it at commit.
- Run `./scripts/check.sh --full` for Release and before an authorized push.
- Run `./scripts/check-live.sh gateway` only when the exact-head classifier selects gateway impact.
- Never bypass hooks or scanners.

Create PRs as drafts with a concise brief containing scope, requirement sources, verification,
independent review state, live evidence, proof limits, and the full exact head SHA. For PR review,
readiness, or merge, use `$review-verify-merge-pr`.

## Report compactly

Report the branch/worktree, changed areas, checks and results, and proof limits or blockers. For
Release, add the exact SHA, required CI, independent-review result, readiness or merge action, and
post-merge evidence when applicable.
