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
8. For semantic prompts, schemas, generated adapters, or gateway diagnostic fixtures, initialize the pinned `Vendor/semantic-prompt-contract` submodule and treat its canonical JSON as the source of truth.

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
6. Keep three evidence classes explicit:
   - automated regression evidence: unit tests, XCTest/XCUITest, mocks, debug launch or seeded UI
     states, component hosts, and `XCTAttachment` screenshots, including tests that activate the
     installed keyboard extension;
   - normal simulator runtime proof: a normally installed/launched app and actual extension used
     through an ordinary host-app text field and visible production UI, with direct Simulator/Xcode
     screenshots outside XCTest and no test-only arguments, state injection, seeded result panels,
     or test-host shortcuts;
   - physical-device proof: the exact signed build on the configured device, exercised through the
     normal extension lifecycle with direct device screenshots.
7. Update affected documentation when a user-visible contract, proof route, workflow, or status source changes.
8. Never claim evidence for an unexecuted simulator, extension lifecycle, device, gateway, signing,
   deployment, or release path. XCUITest real-extension coverage remains automated regression
   evidence and must never be called manual or normal simulator runtime proof.
9. Test-seeded loading, success, warning, and failure states are diagnostics only and do not prove a
   production request produced that state. Simulator and XCTest evidence cannot satisfy a
   physical-device requirement.
10. Never add fallback prompt copies. Make semantic changes in the shared package, classify version impact, regenerate adapters, inspect equivalence fixtures, and advance the consumer gitlink intentionally.
11. For model-capability classification, long-input handling, parser compatibility, retry behavior,
    automatic-analysis warnings, manual-action error scope, or Translate warning scope, use the
    targeted two-profile matrix. Run deterministic prerequisites and the Xcode build once; never run
    the full suite separately for both profiles.

## Lifecycle autonomy

A bounded implementation request starts the normal repository lifecycle through guarded merge:
branch/worktree preparation, edits, tests, commit, push, PR publication, in-scope review fixes,
readiness, and merge. Continue without separate confirmation between those stages only when the
exact-head independent reviewer reports operational confidence of exactly `100%`. If confidence is
below 100%, keep the PR draft, disclose every unverified requirement and blocker, and require
explicit repository-owner approval for that same exact head before readiness or merge.

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
- XCTest/XCUITest may be used freely for development, regression, request-shape, lifecycle, and
  deterministic CI evidence, but cannot alone authorize a proof-sensitive push, PR readiness,
  release readiness, or claims that a user-visible workflow works.
- Changes affecting UI, keyboard-extension lifecycle, Apply/Copy/Back/Rerun behavior, live gateway
  behavior, or result presentation require normal simulator runtime proof before push. Use the
  actual app/extension, an ordinary host-app text field, visible production UI, and the configured
  live gateway for semantic verification. Record exact Git SHA, build configuration, simulator
  model, OS version, action, source text, observed result, and direct Simulator screenshots without
  credentials or private configuration.
- If normal simulator interaction is unavailable, unreliable, or ambiguous, stop before push or
  readiness; disclose exactly what is unverified and request manual testing with a short checklist
  and expected screenshots. Do not substitute more XCTest. Physical-device requirements similarly
  stop when the configured device or exact signed build is unavailable.
- Run `./scripts/check.sh --hygiene` for a Fast handoff with file changes.
- Run `./scripts/check.sh --quick` for Standard; mandatory hooks may supply it at commit.
- Run `./scripts/check.sh --full` for Release and before an authorized push.
- Run `./scripts/check-semantic-prompt-contract.sh` whenever the contract gitlink, canonical semantics, schemas, fixtures, or generated-adapter wiring changes.
- Run `./scripts/check-live.sh gateway` only when the exact-head classifier selects gateway impact.
- Run `./scripts/check-live.sh gateway-differential` when the classifier selects
  `gateway-differential` and for pre-release verification. Required/tested evidence stays in
  canonical `low=<id>, high=<id>` order. A low success or intermittent boundary is diagnostic,
  remains `UNVERIFIED`, and blocks guarded merge rather than becoming a flaky gate.
- Never bypass hooks or scanners.
- Report automated tests, transport success, semantic acceptance, and visual/runtime acceptance as
  separate outcomes.

Local implementation and commits may proceed after deterministic tests. For proof-sensitive
user-facing changes, do not push or create/update a readiness PR until normal simulator runtime
proof succeeds unless the user explicitly authorizes proceeding with the missing proof disclosed.
That authorization does not mark the proof verified. Never mark ready or merge while required
normal simulator or physical-device proof is missing.

Create PRs as drafts with a concise brief containing a separate row for every in-scope requirement,
its observable acceptance criterion, required proof type, exact evidence, and verification status.
Include independent review state, live evidence, explicitly authorized out-of-scope limits, and the
full exact head SHA. An unverified, ambiguous, skipped, stale, fallback, or wrong-target requirement
is a blocker, not a residual limitation. Human authorization may accept a disclosed blocker but
must not relabel it as verified or bypass a failed mandatory gate. A new commit invalidates both
reviewer confidence and human authorization. For PR review, readiness, or merge, use
`$review-verify-merge-pr`.

## Report compactly

Report the branch/worktree, changed areas, checks and results, and proof limits or blockers. For
Release, add the exact SHA, required CI, independent-review result, readiness or merge action, and
post-merge evidence when applicable.
