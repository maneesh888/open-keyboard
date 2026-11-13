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

## Select applicable evidence

Apply `AGENTS.md` verification applicability before selecting or reviewing gates. Inspect the
actual changed behavior and its dependencies, not just filenames. A non-applicable test is not a
missing requirement. For a diff-bound assessment, read `docs/VERIFICATION_APPLICABILITY.md`, verify
its complete bindings and named requirement row, and independently evaluate its rationale and
alternative proof. Do not accept a manifest as self-approval or silently narrow acceptance criteria.
Normal runtime evidence exercises the affected app surface; extension and live interactions are
required only when the acceptance criterion involves them. Preserve valid equivalent evidence and
escalate only actual gaps. Keep all applicable exact-head, review, and protected-check gates.

## Implement and verify

1. Preserve unrelated work and keep edits inside the work order.
2. Follow the repository's MVVM, theme, App Group, Keychain, extension-lifecycle, gateway, semantic
   contract, and secret boundaries.
3. Route UI audit requests through the read-only `$audit-openkeyboard-ui`. When UI fixes are
   authorized, use it inside this implementation loop to trace SwiftUI controls and visible states
   through navigation, ViewModels, production behavior, and relevant tests before editing. Review
   adjacent screens for journey continuity without adding them to the edit scope. Keep ownership of
   layout, behavior, accessibility, and interaction findings in the UI audit; delegate
   wording-specific analysis to `$write-openkeyboard-product-copy`. Classify source-only findings
   as `confirmed from code`, `likely visual risk`, or `requires simulator verification`, and never
   present source inspection as rendered or runtime acceptance.
4. For work centered on user-visible app or keyboard wording, use
   `$write-openkeyboard-product-copy` to review the target screen, incoming and outgoing journey,
   product claims, terminology, reachable states, and accessibility labels before editing.
5. Add or update focused automated regression coverage for changed behavior.
6. Run affected tests while iterating, then select the final gate:
   - **Fast/local policy:** affected tests plus `./scripts/check.sh --hygiene`.
   - **Standard completed work:** `./scripts/check.sh --quick`.
   - **Release/publish:** exact-head `./scripts/check.sh --hygiene` only for a strictly classified
     documentation-only diff; `--full` otherwise, plus the classifier-selected live gate,
     required runtime proof, GitHub checks, and independent review.
7. Run `./scripts/check-semantic-prompt-contract.sh` for contract/gitlink/schema/fixture/adapter
   changes. Use `gateway-differential` only for the classifier-selected low/high surfaces or
   pre-release verification; preserve exact role/model identity and treat an unstable low boundary
   as diagnostic/`UNVERIFIED`.
8. Run `git diff --check`, install and honor hooks, stage only task files, and inspect staged names
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
task. A device evidence requirement is a blocker for Codex-operated proof when authority is
absent, not permission. This restriction governs Codex and its tools; the user may perform their
own verification and approve the exact head without granting device access.

Use Xcode 27-or-newer MCP tools as focused accelerators when available. Bind each call to the
active session worktree by passing its absolute path as `workspaceIdentifier`, and confirm it is
open with `XcodeListWorkspaces` before the first call and after any Xcode-window change. Prefer
project-aware reads of targets, schemes, test plans, tests, build settings, logs, issues, and Apple
documentation. Xcode MCP tools supplement; they never replace the repository scripts, exact-head
gates, independent review, or human approval. Treat an MCP build as build evidence only, a
completed MCP test as automated regression evidence, and a rendered preview as diagnostic visual
evidence only unless `AGENTS.md` explicitly defines a stronger route. Project-mutating Xcode tools
require existing edit authority and the same diff, secret,
artifact, hook, and verification review as filesystem edits.

For Device Hub-backed interaction, bind the attempt to one Xcode installation with scoped
`DEVELOPER_DIR` rather than changing or relying on global `xcode-select`. Record the selected Xcode
path, `xcodebuild -version`, Device Hub/Xcode version, simulator runtime and build, and exact owned
UUID, then open Device Hub from that same Xcode. Treat host-window visibility, Device Hub sidebar
membership, CoreSimulator device state, and app runtime state as separate signals. Device Hub only
lists simulators added there or previously used as Xcode run destinations, so a missing row is not
proof that an owned simulator is stopped, locked, unauthorized, or unavailable. Confirm the Info
inspector UUID and OS against the owned UUID before interaction.

Use Xcode release-note caveats only to guide diagnosis: parallel-test simulators can be active while
invisible in Xcode 27 Device Hub, and pasteboard transfer or synchronization behavior must not be
relabelled as an authorization, lock, or service failure without direct evidence. Allow for Xcode
27.1's slow initial Simulator launch. Treat iPhone Duo Closed, Partially Open, and Open as device
poses and record the pose when relevant; most app extensions are unavailable in the Xcode 27.1 Duo
runtime, so use a supported non-Duo runtime for extension proof unless Duo behavior is itself the
criterion. Never install or change certificates or trust roots, broaden Xcode/MCP permissions, or
put credentials, private endpoints, or other secrets on a clipboard as a workaround without
explicit repository-owner authorization for that action.

Do not make interactive Device Hub control a prerequisite for automated regression. Run XCTest and
XCUIAutomation through the repository scripts and their `xcodebuild test` result-bundle route. For
a new-Xcode gate, record the required marketing version, build number, and release channel against
Apple's release listing, then use a scoped `DEVELOPER_DIR`, compatible runtime, and exact owned
simulator UUID. Do not install or update Xcode or alter global toolchain selection. Treat a beta or
RC as evidence for that named prerelease only, and an older-Xcode fallback as diagnostic unless the
requirement explicitly defines it as the gate. Keep this automated evidence distinct from normal
runtime Device Hub interaction and screenshots.

Hold the repository's shared Simulator lock for the full Xcode MCP device-interaction session.
Create and record a fresh disposable simulator, pass only its exact UUID, and require
`deviceIsSimulator == true` and an exact match to the recorded disposable simulator UUID before
any install, launch, or synthesized event. Do not use best-match selection, a pre-existing
Simulator, or a discovery call that may enumerate connected physical devices while physical-device
authority is `NO`. End the interaction session and delete only the exact workflow-owned simulator.
If the session returns a `skillToTrigger` integration that is unavailable, end the session and
report the boundary instead of calling lower-level interaction tools directly.

When the interaction capabilities are discoverable, prefer their structured route over blind host
clicks: confirm `XcodeListWorkspaces`; discover destinations only if the call can stay
Simulator-only; start `DeviceInteractionStartWorkspaceSession` with the owned UUID; recheck the
returned simulator flag and UUID; call `DeviceInteractionInstallAndRun` without test or seed
arguments; follow the returned `skillToTrigger` worker instructions; capture a fresh hierarchy;
derive each action from that hierarchy; inspect the direct post-action screenshot; and always call
`DeviceInteractionEndSession`. Record the capture SHA, Xcode build, runtime/build, exact UUID,
action, result, mock-versus-live source, and app-only-versus-extension scope. An app screenshot or
preview is never real keyboard-extension lifecycle proof.

Use light/dark, orientation, and Dynamic Type preview variants for focused layout diagnosis when
available, but label them diagnostic visual evidence rather than automated regression, normal
runtime, or extension proof.

While physical-device authority is `NO`, do not call `XcodeListRunDestinations` or another tool that
may enumerate a connected physical device. `BuildProject`, `RunAllTests`, `RunSomeTests`,
`RunProject`, and `RenderPreview` inherit Xcode's active destination and do not accept an exact
simulator UUID, so use the repository scripts instead of those destination-implicit actions.

XCUITest real-extension coverage remains automated regression evidence. Test-seeded states remain
diagnostics. Neither proves production behavior or physical-device behavior. UI, extension
lifecycle, Apply/Copy/Back/Rerun, and result-presentation changes require the applicable normal
runtime route in `AGENTS.md` and `docs/REAL_EXTENSION_SMOKE_PLAN.md`. Nonvisual gateway criteria may
use relevant live evidence without an unrelated UI walkthrough.

Use a three-tier normal-Simulator escalation hierarchy. First use a purpose-built Simulator
accessibility/control integration to inspect the normal app's accessibility hierarchy, operate
discoverable controls, and capture direct screenshots. If that route cannot establish every
required system interaction or visible result, retain its valid evidence and use Computer Use or
equivalent reliable host UI automation for the missing proof. Ask for the exact human verification
handoff only when both automated tiers remain unavailable, unreliable, or ambiguous. The handoff
requests an exact-head approve/reject decision, never a user-uploaded screenshot or structured
attestation. Accessibility metadata or action success without an inspected visible result and
Codex-captured screenshot is not AI visual proof.

A Computer Use report that the host is locked or Simulator is unavailable is a route-level failure,
not a terminal runtime-proof conclusion. Refresh once; for Xcode 27 or newer, first target Device
Hub from the same recorded Xcode installation and verify the exact owned UUID. Otherwise, or when
that surface cannot be targeted, retry Simulator with bundle identifier
`com.apple.iphonesimulator` when supported, then attempt any other available non-XCTest Simulator
accessibility/control route. Do not loop on a genuinely locked host or treat a `simctl` framebuffer
capture as proof of interaction. A full-resolution Device Hub screenshot still proves normal
runtime only after the required production interaction, visible-state inspection, privacy review,
runtime record, and artifact delivery. If interaction is still unavailable or ambiguous, stop
before publication and disclose the gap; do not substitute more XCTest or ask the user to upload
an image. Explicit repository-owner approval for the exact head selects the human authorization
route, satisfies the runtime/device decision gate, and lets the workflow continue automatically
through the remaining authorized stages without another runtime, readiness, or merge confirmation.
Record the mode as `human-approved`, qualify `RUNTIME_VERIFIED` accordingly, keep the independently
uninspectable visual requirement `UNVERIFIED`, and disclose that the AI did not inspect screenshots.
A new commit expires that approval.

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
through the automatic route while required simulator or physical-device screenshot proof is
missing. The human route may proceed after explicit exact-head repository-owner approval with that
gap disclosed.

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
proof screenshot that Codex actually captured or used in the final response, even if it was shown
in commentary; a filesystem path, `.xcresult`, PR link, or summary alone is not delivery. Never ask
the user to upload screenshots. For `human-approved` evidence, report the exact-head approval and
absent AI-screenshot boundary instead. Never claim an unexecuted simulator, extension, gateway,
device, signing, deployment, or release path.

## Private live identity evidence

Follow `docs/LIVE_EVIDENCE_PRIVACY.md`: exact task/seed/selected-model comparisons remain local;
public evidence retains canonical role-bound assertions and outcomes only. Do not publish model
names, identity hashes, credentials, endpoints, prompts, responses, or timing fingerprints. Inspect
local enforcement and its redacted result independently; GitHub assertion acceptance is not proof
of provider identity or runtime acceptance. Keep exact-head review, normal-runtime/human approval,
and all protected checks. Require the trusted base to support the private schema; reject legacy bases without
candidate fallback or compatibility projections. Never invent measurements to satisfy a legacy field.
