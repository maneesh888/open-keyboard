# OpenKeyboard Workflow

## Straight-line task flow

Follow this order. Load a detailed document or specialized skill only when the matching step needs
it.

1. **Inspect without mutation.** Resolve the integration checkout with
   `git rev-parse --show-toplevel`, inspect `git status --short --branch` and submodule status, and
   preserve unrelated changes. Do not fetch, create a branch/worktree, initialize a submodule, edit,
   stage, or commit until authority is resolved.
2. **Resolve authority.** Build the authority ledger below from the complete conversation. Apply
   every sticky constraint before deciding whether the task is planning, proof-first
   experimentation, implementation, or publication. Ask when a later instruction is ambiguous
   rather than treating it as permission.
3. **Isolate authorized coding work.** Only when repository edits are authorized, fetch the
   configured remote, create a session worktree, and initialize its submodules unless the user
   explicitly requests the current checkout. Use
   `OPEN_KEYBOARD_REMOTE` and `OPEN_KEYBOARD_BASE_REF` when set; otherwise base
   `codex/<session-slug>` on fresh `origin/main`. Put worktrees under
   `OPEN_KEYBOARD_WORKTREE_ROOT`, or a sibling `open-keyboard-worktrees` directory when unset. Do
   not fall back to a stale or different base without asking.
4. **Bound or phase the task.** Record the objective, affected surfaces, exclusions, verification
   level, required evidence class, and authority ledger. Route explicit major-milestone, roadmap,
   long-horizon, or multi-phase planning to the read-only `major-milestone-planner` through
   `$plan-openkeyboard-major-milestone`. Route one bounded plan or a concise "what next" request to
   the read-only `work-package-planner` through `$plan-openkeyboard-work-package`. For a clear
   implementation request, use `$develop-openkeyboard` without adding either planning gate.
5. **Implement narrowly.** Read only the sources and focused plans needed for the task. Reuse local
   patterns, add focused regression coverage for changed behavior, and preserve files outside the
   work order.
6. **Verify and commit only when authorized.** Run affected tests, `git diff --check`, and the
   proportional repository gate below. Recheck the authority ledger before staging and again
   before committing. Install hooks with `./scripts/install-hooks.sh`; never use `--no-verify`.
   Stage only intended files and inspect `git diff --cached --name-only` plus the staged diff for
   secrets or generated artifacts.
7. **Collect runtime proof when required and authorized.** Proof-sensitive user-facing changes
   require normal simulator runtime proof before push. Physical-device interaction remains
   prohibited until the user explicitly requests it; a device-specific requirement creates a
   blocker, not permission to connect to a device. Follow the evidence and interaction rules below.
8. **Publish and review.** Recheck the authority ledger before any push or PR mutation. Before an
   authorized push, run `./scripts/check.sh --full` and the
   classifier-selected exact-head live gate. Open a draft PR, keep a requirement ledger, and use
   `$review-verify-merge-pr` for exact-head review, readiness, and guarded merge.
9. **Finish safely.** Report exact evidence boundaries. After merge, inspect relevant `main` CI.
   Remove a session worktree and delete its merged branch only after confirming it is clean and no
   longer needed; never destructively clean uncommitted or unmerged work without explicit approval.

Ask only when progress needs a material choice about scope, destructive action, credentials,
external deployment, base branch, dirty-work ownership, or state-change authority.

## User authority and proof-first mode

Before the first mutation, internally record and retain this ledger:

```text
Objective:
Current objective/phase:
Requested activity:
Active constraints (scope and expiry):
Read-only activity authorized: YES/NO
Edits authorized: YES/NO
Production-code edits authorized: YES/NO
Physical-device interaction authorized: YES/NO
Commit authorized: YES/NO
Push authorized: YES/NO
PR authorized: YES/NO
Merge authorized: YES/NO
Lifecycle gates: commit/push/PR/readiness/merge WAITING|READY|BLOCKED|COMPLETE
Required evidence:
Current blockers:
```

Recheck it before the first tracked edit, staging, commit, push, PR mutation, readiness change, or
merge, and recompute it whenever the objective or phase changes, a scoped constraint expires, or
new evidence changes a lifecycle gate. An authority `NO` is a hard prohibition for that action. A
`WAITING` or `BLOCKED` lifecycle gate means the action is authorized but its required evidence is
not yet sufficient. When a constrained task needs user visibility, report one compact checkpoint:
`AUTHORITY: <mode> | read-only <YES/NO> | edits <YES/NO> | production edits <YES/NO> | physical device <YES/NO> | commit <YES/NO> | push <YES/NO> | PR <YES/NO> | merge <YES/NO>`.
When gate state explains progress, add a separate compact checkpoint:
`GATES: commit <state> | push <state> | PR <state> | readiness <state> | merge <state>`.

A clear bounded implementation request grants standing conditional authority for the normal
repository lifecycle: read and inspect, make scoped edits, change production code when the task
requires it, stage and commit, push, create or update a draft PR, fix in-scope review findings,
mark ready, and guarded-merge. Initialize the applicable ledger fields to `YES`; the user does not
need to enumerate or separately authorize those ordinary stages. Conditional authority means each
state change still waits for its required deterministic, live, runtime, exact-head, review, and
GitHub gates. Those gates decide whether the workflow may advance; they are not prompts for a new
permission. As evidence and exact-head review confidence satisfy a gate, mark it `READY` and
advance to the next authorized lifecycle stage without asking again. Deployment and destructive
cleanup remain outside this standing authority.

- User constraints are sticky within their independently recorded scope. Assign every explicit
  constraint the narrowest scope supported by the user's words and conversation: a named
  experiment/checkpoint, the current objective or phase, or the whole task. `For this test`,
  `begin read-only`, and a request to `report, then stop and wait` create phase-scoped constraints
  when they describe a bounded test checkpoint. Preserve those constraints through that
  checkpoint, then mark them expired—without erasing their history—when its result is delivered
  and a clear implementation request starts the next phase. A constraint stated for the whole
  task, branch, or implementation, or reinforced with `still`, `throughout`, `never`, or equivalent
  wording, remains active until the user explicitly revokes it. An active opt-out overrides
  standing lifecycle authority for that action and dependent later actions. Silence about commit,
  push, PR, readiness, or merge is not an opt-out.
- Recompute authority at every real phase transition. `Correct it`, `Fix it`, and `Implement the
  proposed change now` are clear implementation requests when they follow a completed diagnostic
  or proof-first checkpoint. They end that checkpoint's read-only/no-publication constraints and
  initialize normal standing lifecycle authority unless a separately scoped task-wide opt-out is
  still active. Do not carry `NO` values forward merely because they appeared in an earlier ledger.
  Confidence does not override an active constraint; it advances lifecycle gates after authority
  has been recomputed.
- Physical-device interaction defaults to `NO` and is independently sticky. Do not enumerate,
  inspect, connect to, install on, launch on, sign for, run tests on, capture from, or otherwise
  operate a physical device until the user explicitly requests physical-device work. Simulator
  authorization, a required device evidence row, normal lifecycle autonomy, and merge permission
  do not grant physical-device authority.
- Ambiguous or exploratory wording never revokes a sticky constraint. `Try`, `investigate`,
  `evaluate`, `diagnose`, `measure`, `see whether it works`, `find out`, `give it a test`, `report
  the results`, and `try chunks` request read-only experimentation unless the user explicitly
  authorizes implementation. Use existing test routes or temporary non-repository harnesses; do
  not modify any tracked file.
- Activate proof-first mode when the user requests results before implementation, asks to test
  before changes, or requests model comparison before changing anything. While it is active, all
  tracked repository mutation—including production, test, documentation, staging, and commit
  changes—is prohibited. Report the result, then wait for explicit implementation authorization.
- In proof-first mode, an HTTP `503` or other required-gateway availability failure leaves the task
  `LIVE_UNVERIFIED`. Report the gateway unavailable and stop without inferring model capability,
  implementing a speculative solution, or substituting deterministic tests.
- `Test this and report before implementing` followed by `Try chunks` remains read-only: no tracked
  edits and no commit. `Do not commit` followed by a clear `Fix the issue` may authorize scoped
  edits, but staging, commit, and dependent publication remain blocked when `Do not commit` applies
  to the continuing objective rather than only a completed checkpoint. After the requested
  proof-first result has been reported, `Implement the proposed change now` ends proof-first mode
  and starts the normal autonomous lifecycle unless another explicit sticky constraint remains.
- `Perform a workflow-authority test only; begin read-only; do not edit, commit, push, create a PR,
  or merge; report and wait` scopes those prohibitions to that test phase. After its report,
  `Correct it` starts an implementation phase: recompute edit, commit, push, PR, and merge authority
  to `YES` under the standing conditional lifecycle, and let evidence gates advance the work. Do
  not resurrect the completed test phase's `NO` values.
- A clear `Implement this feature` request enters normal implementation mode and grants standing
  conditional authority through guarded merge when no sticky no-edit, no-implementation,
  local-only, no-commit, no-push, no-PR, keep-draft, or no-merge constraint remains. It never grants
  deployment or destructive-cleanup authority.
- Planning, diagnosis, review-only work, readiness assessment, and blocker requests are read-only.
- Deployment and destructive cleanup are separate external actions and require explicit authority.
- Below exact-head independent-review confidence of `100%`, keep the PR draft and require explicit
  repository-owner approval for that exact SHA. Approval accepts disclosed risk; it cannot bypass a
  mandatory gate or relabel missing proof as verified.
- A new commit invalidates prior full/live evidence, independent review, GitHub gate conclusions,
  and human merge authorization. It also invalidates normal simulator evidence unless the narrow
  test-only carry-forward rule below is verified; that exception applies to normal simulator
  evidence only.

## Engineering boundaries

- Follow MVVM: SwiftUI views present; ViewModels own UI state and actions; services own side
  effects, persistence, App Group defaults, Keychain, network, gateway, and file I/O.
- Prefer existing helpers and test doubles. Use `OpenKeyboardTheme` tokens in touched UI when a
  token exists. Do not mix unrelated cleanup into the task.
- Never print or commit API keys, authorization headers, private environment values, filled seed
  files, raw gateway output/logs, `.xcresult`, screenshots, DerivedData, or `.ci-results`.

## Shared Semantic Prompt Contract

- The pinned `Vendor/semantic-prompt-contract` submodule is the only canonical home for semantic
  operation identifiers, prompt wording, parameters, rendering rules, response schemas, examples,
  and contract fixtures.
- Confirm its checkout matches the recorded gitlink. Never validate against an adjacent mutable
  checkout or unrecorded package commit.
- Keep UI, networking, gateway URL/key handling, model selection, persistence, parser
  compatibility, and result presentation in OpenKeyboard. Do not copy canonical prompts into Swift
  sources or tests; generated adapters must derive from canonical JSON.
- For a contract change, update and test the package first, classify semantic-version impact,
  inspect golden changes, advance the consumer gitlink intentionally, and run
  `./scripts/check-semantic-prompt-contract.sh`.
- Treat `.gitmodules`, the gitlink, adapter wiring, semantic request changes, schemas, and diagnostic
  fixtures as gateway-impacting. The gateway may use package diagnostics but must preserve exact
  client messages and must not rebuild production prompts.

## Evidence classes

Use exactly these classes in plans, PR ledgers, and reports:

1. **Automated regression evidence:** unit tests, XCTest, XCUITest, mocked gateway tests, debug
   launch states, seeded UI/result states, component hosts, and `XCTAttachment` screenshots. This
   includes XCUITest routes that install and activate the real keyboard extension.
2. **Normal simulator runtime proof:** a normally installed and launched app with no `--uitesting`,
   debug-state injection, seeded result panels, component/test hosts, or test-host shortcuts. Use
   the actual extension through an ordinary host-app text field and visible production UI. Capture
   screenshots directly from Simulator/Xcode outside XCTest.
3. **Physical-device proof:** the exact signed build installed on the configured device, exercised
   through the normal keyboard-extension lifecycle, with screenshots captured directly from that
   device.

Automated evidence remains required, but XCTest/XCUITest cannot by itself authorize a
proof-sensitive push, PR readiness, release readiness, or a claim that the user-visible workflow
works. Test-seeded states are diagnostics and do not prove a production request produced that
state. Simulator evidence never satisfies a physical-device requirement.

### When runtime proof is required

Changes affecting UI, keyboard-extension lifecycle, Apply/Copy/Back/Rerun, live gateway behavior,
or result presentation require normal simulator runtime proof before push. Normal proof must:

- use the actual app and extension through an ordinary host-app text field;
- invoke the action through visible production UI with no test-only state or interaction;
- use the configured live gateway when semantic behavior is being verified;
- capture direct Simulator/Xcode screenshots, never `XCTAttachment` artifacts;
- record the capture Git SHA, current verified Git SHA, build configuration, simulator model, OS
  version, action, source text, and observed result; and
- keep credentials and private configuration out of screenshots and logs.

Collect normal runtime proof using this escalation hierarchy. Stop at the first tier that produces
all required evidence; retain valid evidence from an earlier tier and escalate only the missing or
ambiguous requirements:

1. **Simulator accessibility/control:** use a purpose-built, generically named Simulator-control integration;
   inspect the normally launched app's accessibility hierarchy, operate discoverable controls,
   type, tap, swipe, and capture direct Simulator screenshots. Accessibility metadata and action
   success alone are not visual proof; inspect the resulting visible state and deliver the required
   screenshots.
2. **Computer Use:** use Computer Use or equivalent host UI automation when the
   accessibility/control route is unavailable or cannot establish a required system-level
   interaction or visual result; inspect and operate the normal Simulator and capture direct
   screenshots.
3. **Human verification:** when the first two tiers remain unavailable, unreliable, or ambiguous,
   ask the user to perform the exact manual checklist and supply the required screenshots and
   runtime record.

An interaction-tool error applies to that route only. A Computer Use report that the host is locked
or Simulator is unavailable is a route-level failure, not a terminal runtime-proof conclusion. If
Computer Use was selected, refresh its app state once and retry Simulator with the canonical bundle
identifier `com.apple.iphonesimulator` when bundle targeting is supported; then try any other
available non-XCTest Simulator accessibility/control route before falling back to human
verification. Do not loop on a genuinely locked host. `simctl` may install, launch, inspect device
state, and capture the current framebuffer, but those operations alone do not prove that the
required visible interaction occurred.

Tool availability does not change the proof standard. If interaction is unavailable, unreliable,
or ambiguous, stop before push/readiness, state exactly what remains unverified, and provide the
short checklist and expected screenshots from `docs/REAL_EXTENSION_SMOKE_PLAN.md`.
Additional XCTest runs do not replace missing runtime proof.

### Test-only normal-runtime evidence carry-forward

A new screenshot run is not required solely because a later commit changes non-shipping test-target
files. Prior complete normal simulator evidence may verify the current head only when all of these
conditions hold:

- the screenshot capture SHA is an ancestor of a clean current `HEAD`;
- `./scripts/verify-runtime-proof-carry-forward.sh <capture-sha> <current-sha>` passes;
- every intervening path is under `OpenKeyboardCore/Tests/`, `OpenKeyboardTests/`, or
  `OpenKeyboardUITests/`, and the verifier reports an identical non-test Git-tree digest;
- the prior proof already contains every required interaction, visible result, screenshot, runtime
  configuration, simulator model, and OS record; and
- the current requirement ledger records the capture SHA, current SHA, verifier output, runtime
  content digest, and intervening paths.

Keep each image labeled with its original capture SHA and describe it as verified test-only
carry-forward evidence; never claim that it was captured from the current SHA. Any runtime,
resource, project, dependency, configuration, gateway, script, documentation, workflow, unknown,
renamed, or dirty-worktree change requires fresh runtime proof. This exception never carries
forward physical-device proof, full/live gates, independent review, GitHub conclusions, or human
merge authorization.

Physical-device proof requires both explicit physical-device interaction authority and the exact
signed build on the configured device. Without that authority, do not query or touch connected
devices; report device proof blocked and request direction. If an authorized device is unavailable,
report device proof blocked and request manual verification. Simulator and XCTest are not substitutes.

After inspecting them for private content, render or attach every screenshot used as required proof
in the final response. When a local image is available, use an inline Markdown image with its
absolute non-repository path; use the available media-preview mechanism for remote artifacts. A
path, `.xcresult`, PR link, summary, or image shown only in earlier commentary is not final proof
delivery. If a required image cannot be delivered, report the delivery blocker, keep the affected
requirement and runtime status unverified, and provide the exact manual screenshot checklist.
Exported `XCTAttachment` images must stay labeled automated artifacts. Never commit proof artifacts.

Report automated test results, transport success, semantic acceptance, and visual/runtime
acceptance separately.

### Task evidence status

Use every applicable task-status label exactly:

- `EXPERIMENTAL`
- `DETERMINISTIC_VERIFIED`
- `LIVE_UNVERIFIED` or `LIVE_VERIFIED`
- `RUNTIME_UNVERIFIED` or `RUNTIME_VERIFIED`

These task labels do not replace PR requirement-row `VERIFIED`/`UNVERIFIED`. Never describe a task
as fixed or working while a required live or runtime status remains unverified.

## Verification routes

Prefer repository scripts to equivalent hand-written commands:

| Need | Command / evidence |
|---|---|
| Hygiene or policy-only change | `./scripts/check.sh --hygiene` |
| Standard deterministic gate | `./scripts/check.sh --quick` |
| Default local CI (`core` + `build`) | `./scripts/local-ci.sh --quick` |
| Exact-head release/pre-push gate | `./scripts/check.sh --full` |
| Core model/parser/service | `./scripts/ios/test.sh core` |
| App + keyboard-extension build | `./scripts/ios/test.sh build` |
| Deterministic UI targets | `./scripts/ios/test.sh deterministic-ui` |
| Broader automated UI regression | `./scripts/ios/test.sh ui` |
| Automated screenshot regression | `./scripts/ios/test.sh screenshots` |
| Automated live gateway smoke | `./scripts/ios/test.sh live-gateway-smoke` |
| Automated live AI harness | `./scripts/ios/test.sh live-ui` |
| Automated low/high model matrix | `./scripts/ios/test.sh live-model-differential` |
| Automated real-extension regression | `./scripts/ios/test.sh real-keyboard-live` |
| Exact-head live gateway gate | `./scripts/check-live.sh gateway` |
| Exact-head differential/pre-release gate | `./scripts/check-live.sh gateway-differential` |
| Normal extension runtime | `docs/REAL_EXTENSION_SMOKE_PLAN.md` |

XCTest/XCUITest routes may be used freely while implementing and diagnosing. Always label them
automated regression evidence, even when the real extension process was active. Automated runtime
proof does not replace regression coverage.

Simulator-backed repository test routes are serialized across the repository's worktrees on a
host. Each live workflow may restart, shut down, and delete only the exact disposable simulator
UDID it created and recorded as its own; never mutate a pre-existing or user-open Simulator. Never
terminate Simulator.app or CoreSimulator processes globally, and never use broad `simctl` cleanup
such as `shutdown all`, `delete all`, or `erase all`. Do not bypass the repository lock with
parallel hand-written `xcodebuild` or `simctl` commands against the same device.

Repository test and local-validation automation must remain Simulator-only. Repository automation
must not invoke `devicectl`, `ios-deploy`, target a concrete physical device through an iOS
destination with a device name or identifier, or use any equivalent physical-device discovery,
install, launch, or test route. A separately authorized release/deployment workflow may compile,
sign, and archive against `generic/platform=iOS`; that generic SDK destination does not enumerate,
connect to, install on, launch on, or test a physical device and does not grant physical-device
authority. Physical-device commands are manual, per-request actions executed only after the
authority ledger records an explicit user request.

The canonical per-machine live seed is
`<primary-checkout>/.agent/local-seeds/openkeyboard-gateway.env`. Live scripts resolve it through
Git's common directory. Keep it ignored, untracked, mode `600`, current-user-owned, free of extended
ACLs, and never copy it into a worktree. Use
`scripts/ios/openkeyboard-gateway.seed.env.example` as the template.

The seed accepts either one complete legacy URL/key/model profile or complete, distinct LOW and
HIGH profiles. Reject partial/unknown/duplicate keys, unsafe model IDs, reversed roles, fallback,
or substitution. Never hardcode or print credentials or exact local model identities. Exact-model
work must run the exact required model. Use `OPEN_KEYBOARD_LIVE_REQUIRED_MODEL=<id>` for a single
model or `OPEN_KEYBOARD_LIVE_REQUIRED_MODELS='low=<id>, high=<id>'` for the matrix. A successful or
intermittent low boundary remains diagnostic/`UNVERIFIED` when the expected boundary is not
established.

Remote `Required technical checks` prove deterministic checks only. `Required checks` validates
the PR/review ledger, and `Required live verification` validates retained exact-head live evidence.
None proves normal simulator UI, physical-device behavior, signing, deployment, or App Review.

## Commit, PR, and exact-head gate

- Before commit, verify the active worktree status, run `git diff --check`, stage only task files,
  inspect `git diff --cached --name-only`, and scan the staged diff for secrets/artifacts.
- Recheck `Commit authorized` before staging and committing. `Commit authorized: NO` blocks both
  unless the user explicitly requests staging without a commit.
- Before push, stop if the branch would publish earlier unrelated commits whose ownership or scope
  is ambiguous.
- Local implementation and commits may proceed after deterministic tests for a bounded
  implementation request under standing lifecycle authority, or under separate explicit edit and
  commit authority, when no active proof-first or commit opt-out remains.
  Proof-first model-capability, long-input, parser, retry, or semantic-behavior work requires the
  explicitly requested live evaluation and later implementation authority before production edits
  or commit. For other proof-sensitive
  user-facing changes, do not push or create/update a readiness PR until normal simulator runtime
  proof succeeds unless the user explicitly authorizes the push with the missing proof disclosed.
  That exception never authorizes readiness or merge.
- Do not use a fix-style subject such as `Fix`, `Handle`, or `Make ... work` for behavior whose
  required live/runtime evidence is missing. If the user explicitly authorizes an experimental
  commit, begin its subject with `Experimental:` or `Diagnostic:`. This naming rule never grants
  commit authority.
- Draft PRs must list every in-scope requirement separately with a stable ID, observable acceptance
  criterion, required proof, exact evidence, and `VERIFIED`/`UNVERIFIED`. Ambiguous, skipped,
  missing, stale, fallback, wrong-target, wrong-model, or contributor-attested-only material
  evidence is `UNVERIFIED` and blocks automatic authorization.
- Use the read-only project `pr-reviewer` through `$review-verify-merge-pr`. Bind its report, the
  full gate, live/runtime evidence, and all GitHub checks to the same exact head. Post the report as
  a durable GitHub `COMMENTED` review and link the newest same-head report from the PR body.
- After linking the report, submit the skill-specified non-approval revalidation trigger on the
  same head. Before readiness and merge, re-fetch the head, body, linked review, threads,
  protection, mergeability, and complete check rollup; rerun trusted validators and require
  `gh pr checks <number> --required` to succeed.
- Never mark ready or merge with missing normal simulator or physical-device proof, a failed or
  pending mandatory check, unresolved requested changes/threads, conflicts, secret violations, or
  stale evidence. If guarded auto-merge queues instead of completing, disable it immediately.

`$review-verify-merge-pr` owns the exact report schema, revalidation wording, event-family check
handling, automatic-versus-human authorization record, and guarded merge command. Do not duplicate
or improvise those mechanics here.

## Reporting

Lead with the outcome. Include changed areas, checks and pass/fail results, evidence class and proof
limits, exact SHA/PR state for published work, remaining blockers, and commit ID when committed.
The final response must render or attach every required proof screenshot even when it appeared in
earlier commentary. A green build is not verified app functionality.
