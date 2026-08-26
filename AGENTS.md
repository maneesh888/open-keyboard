# OpenKeyboard Workflow

## Straight-line task flow

Follow this order. Load a detailed document or specialized skill only when the matching step needs
it.

1. **Set up.** Resolve the integration checkout with `git rev-parse --show-toplevel`, inspect
   `git status --short --branch`, and initialize submodules. Preserve unrelated changes.
2. **Isolate coding work.** For a feature, fix, or UI change, fetch the configured remote and create
   a session worktree unless the user explicitly requests the current checkout. Use
   `OPEN_KEYBOARD_REMOTE` and `OPEN_KEYBOARD_BASE_REF` when set; otherwise base
   `codex/<session-slug>` on fresh `origin/main`. Put worktrees under
   `OPEN_KEYBOARD_WORKTREE_ROOT`, or a sibling `open-keyboard-worktrees` directory when unset. Do
   not fall back to a stale or different base without asking.
3. **Bound the task.** Record the objective, affected surfaces, exclusions, verification level,
   required evidence class, and the latest commit/push/PR/merge opt-outs. If the user explicitly
   asks for a plan or what to do next, use the read-only `work-package-planner` through
   `$plan-openkeyboard-work-package`. For a clear implementation request, use
   `$develop-openkeyboard` without adding a planning gate.
4. **Implement narrowly.** Read only the sources and focused plans needed for the task. Reuse local
   patterns, add focused regression coverage for changed behavior, and preserve files outside the
   work order.
5. **Verify and commit.** Run affected tests, `git diff --check`, and the proportional repository
   gate below. Local commits may proceed after deterministic checks. Install hooks with
   `./scripts/install-hooks.sh`; never use `--no-verify`. Stage only intended files and inspect
   `git diff --cached --name-only` plus the staged diff for secrets or generated artifacts.
6. **Collect runtime proof when required.** Proof-sensitive user-facing changes require normal
   simulator runtime proof before push. Device-specific requirements also require physical-device
   proof. Follow the evidence and interaction rules below.
7. **Publish and review.** Before an authorized push, run `./scripts/check.sh --full` and the
   classifier-selected exact-head live gate. Open a draft PR, keep a requirement ledger, and use
   `$review-verify-merge-pr` for exact-head review, readiness, and guarded merge.
8. **Finish safely.** Report exact evidence boundaries. After merge, inspect relevant `main` CI.
   Remove a session worktree and delete its merged branch only after confirming it is clean and no
   longer needed; never destructively clean uncommitted or unmerged work without explicit approval.

Ask only when progress needs a material choice about scope, destructive action, credentials,
external deployment, base branch, dirty-work ownership, or state-change authority.

## Authority and stopping rules

- A bounded implementation request normally includes worktree preparation, edits, tests, commit,
  push, draft PR, in-scope review fixes, readiness, and guarded merge.
- Honor the latest explicit opt-out: `local only`, `do not commit`, `do not push`, `do not create a
  PR`, `keep draft`/`do not mark ready`, or `do not merge`.
- Planning, diagnosis, review-only work, readiness assessment, and blocker requests are read-only.
- Deployment and destructive cleanup are separate external actions and require explicit authority.
- Below exact-head independent-review confidence of `100%`, keep the PR draft and require explicit
  repository-owner approval for that exact SHA. Approval accepts disclosed risk; it cannot bypass a
  mandatory gate or relabel missing proof as verified.
- A new commit invalidates prior full/live evidence, independent review, GitHub gate conclusions,
  and human merge authorization.

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
- record exact Git SHA, build configuration, simulator model, OS version, action, source text, and
  observed result; and
- keep credentials and private configuration out of screenshots and logs.

Collect normal runtime proof using the first reliable route:

1. a purpose-built, generically named Simulator-control integration;
2. Computer Use or equivalent host UI automation that can reliably inspect and operate the normal
   Simulator and capture direct screenshots; or
3. manual verification by the user.

Tool availability does not change the proof standard. If interaction is unavailable, unreliable,
or ambiguous, stop before push/readiness, state exactly what remains unverified, and provide the
short checklist and expected screenshots from `docs/REAL_EXTENSION_SMOKE_PLAN.md`.
Additional XCTest runs do not replace missing runtime proof.

Physical-device proof requires the exact signed build on the configured device. If that device is
unavailable, report device proof blocked and request manual verification; Simulator and XCTest are not substitutes.

Deliver required screenshots in the chat or through clickable non-repository artifact links after
inspecting them for private content. An `.xcresult` path alone is not delivery. Exported
`XCTAttachment` images must stay labeled automated artifacts. Never commit proof artifacts.

Report automated test results, transport success, semantic acceptance, and visual/runtime
acceptance separately.

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
- Before push, stop if the branch would publish earlier unrelated commits whose ownership or scope
  is ambiguous.
- Local implementation and commits may proceed after deterministic tests. For proof-sensitive
  user-facing changes, do not push or create/update a readiness PR until normal simulator runtime
  proof succeeds unless the user explicitly authorizes the push with the missing proof disclosed.
  That exception never authorizes readiness or merge.
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
limits, screenshots when required, exact SHA/PR state for published work, remaining blockers, and
commit ID when committed. A green build is not verified app functionality.
