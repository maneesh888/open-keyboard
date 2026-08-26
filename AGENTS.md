# OpenKeyboard Default Workflow

## Purpose

Use this workflow for OpenKeyboard coding, testing, screenshots, gateway, keyboard extension, CI, independent pull-request review, optional MCP/ClawMaster verification, and commit work. Keep each session focused, repo-aware, tied to the real scripts/proof routes, and safe to commit when the user allows it.

## Start Every Task

1. Resolve the repository root with `git rev-parse --show-toplevel` and treat that directory as the integration checkout. Interpret repository paths in this file relative to that root; never assume a username, home directory, or fixed checkout location.
2. Inspect `git status --short --branch` in the integration checkout before edits.
3. For new feature, bug-fix, or UI coding sessions, create a per-session Git worktree unless the user explicitly asks to work in the current checkout:
   - Worktree root: use `OPEN_KEYBOARD_WORKTREE_ROOT` when set; otherwise derive a sibling `open-keyboard-worktrees` directory from the repository root.
   - Branch name: `codex/<session-slug>` unless the user requests another branch name.
   - Default remote/base: use `OPEN_KEYBOARD_REMOTE` and `OPEN_KEYBOARD_BASE_REF` when set; otherwise use `origin/main`. Use local `main` only when the user explicitly wants to build on unpushed local commits.
   - Command shape:

     ```bash
     REPO_ROOT="$(git rev-parse --show-toplevel)"
     WORKTREE_ROOT="${OPEN_KEYBOARD_WORKTREE_ROOT:-$(dirname "$REPO_ROOT")/open-keyboard-worktrees}"
     REMOTE_NAME="${OPEN_KEYBOARD_REMOTE:-origin}"
     BASE_REF="${OPEN_KEYBOARD_BASE_REF:-$REMOTE_NAME/main}"
     SESSION_SLUG="describe-task"
     mkdir -p "$WORKTREE_ROOT"
     git -C "$REPO_ROOT" fetch "$REMOTE_NAME"
     git -C "$REPO_ROOT" worktree add -b "codex/$SESSION_SLUG" "$WORKTREE_ROOT/$SESSION_SLUG" "$BASE_REF"
     ```

   - Run implementation, verification, staging, and commits from that worktree path.
   - If the default sibling directory is not writable, set `OPEN_KEYBOARD_WORKTREE_ROOT` to a writable location for that machine. If the configured remote, network, or base ref is unavailable, report that constraint and ask before falling back to a different local base.
4. If the integration checkout has uncommitted or staged changes, do not commit them from the integration checkout. Ask whether those changes belong to the current task, or create a clean worktree and leave them untouched.
5. Preserve unrelated user or agent changes. Do not revert, restage, or clean files you did not intentionally touch.
6. If the user asks what to do next or explicitly requests a plan, invoke the read-only `work-package-planner` without inherited conversation. It uses `$plan-openkeyboard-work-package` and returns a digest-bound work order.
7. If the user gives a clear implementation request, use `$develop-openkeyboard` and convert it internally into a bounded work order without adding a planning gate:
   - objective
   - likely files/modules
   - out-of-scope areas
   - verification required
   - whether automated screenshots, normal simulator runtime proof, or physical-device proof are needed
   - whether commit/push is allowed
8. Ask only when scope, destructive action, credentials, external deployment, base branch, dirty-checkout ownership, or commit/push permission is ambiguous.

## Session Worktree Cleanup

- Keep each session's changes isolated to its worktree branch.
- Before committing, confirm `git status --short --branch` in the active worktree and `git diff --cached --name-only` contain only files for that session.
- After the branch is merged or the user confirms the work is no longer needed, remove the temporary worktree with:

  ```bash
  REPO_ROOT="$(git rev-parse --show-toplevel)"
  WORKTREE_ROOT="${OPEN_KEYBOARD_WORKTREE_ROOT:-$(dirname "$REPO_ROOT")/open-keyboard-worktrees}"
  git -C "$REPO_ROOT" worktree remove "$WORKTREE_ROOT/<session-slug>"
  ```

- After removing a merged worktree, delete the local branch with `git branch -d codex/<session-slug>` and run `git worktree prune` if needed.
- Never remove a worktree that has uncommitted changes or an unmerged branch unless the user explicitly approves that destructive cleanup.

## Actual Workflow Tools

Use the repo scripts before hand-written commands unless a targeted command is clearly narrower:

- Repository implementation workflow: `$develop-openkeyboard`
- Read-only source-bound planner: project `work-package-planner` via `$plan-openkeyboard-work-package`
- Repository hygiene: `./scripts/check.sh --hygiene`
- Standard deterministic gate: `./scripts/check.sh --quick`
- Exact-head release gate: `./scripts/check.sh --full`
- Deterministic UI-target tests: `./scripts/ios/test.sh deterministic-ui`
- Default deterministic CI: `./scripts/local-ci.sh --quick`
  - runs `./scripts/ios/test.sh core`
  - runs `./scripts/ios/test.sh build`
- Core package only: `./scripts/ios/test.sh core`
- iOS app + keyboard extension build: `./scripts/ios/test.sh build`
- Full OpenKeyboard UI tests on iPhone 16: `./scripts/ios/test.sh ui`
- Onboarding screenshots on iPhone 16 + iPhone SE: `./scripts/ios/test.sh screenshots`
- Opt-in live gateway service smoke: `./scripts/ios/test.sh live-gateway-smoke`
- Targeted low/high live-model matrix: `./scripts/ios/test.sh live-model-differential`
- Exact-head live gateway gate: `./scripts/check-live.sh gateway`
- Exact-head differential/pre-release gate: `./scripts/check-live.sh gateway-differential`
- Opt-in automated real-extension regression test with a live gateway: `./scripts/ios/test.sh real-keyboard-live`
- Opt-in live AI harness tests: `./scripts/ios/test.sh live-ui`
- Independent exact-head PR review: project `pr-reviewer` via `$review-verify-merge-pr`

Remote GitHub CI runs hygiene, `core`, semantic-contract validation, and `build` from `.github/workflows/ci.yml`, then reports `Required technical checks`. Every review/body metadata event creates the fixed protected `Required checks` root job; every live-evidence body event creates the fixed protected `Required live verification` root job. These jobs do not use capped concurrency queues. They validate both the immutable event snapshot and the current exact-head GitHub state, so an out-of-order stale event can over-block but cannot turn invalid current evidence into a pass. The initial project-review submission is expected to fail while the PR body still lacks its link. After linking the report, submit one clearly labeled non-approval COMMENTED revalidation trigger on the same head so the `pull_request_review` event family also has a current valid result. The PR must link the newest same-head project-reviewer COMMENTED report; the trigger must not identify itself as that reviewer. `.github/workflows/live.yml` enforces retained exact-head local evidence for gateway-impacting changes without receiving credentials. Do not imply remote CI proves simulator UI, screenshots, real keyboard extension behavior, live gateway execution, signing, or deployment.

## Coding Rules

- Follow MVVM: SwiftUI views stay presentation-focused; ViewModels own UI state and user actions; services own side effects, gateway calls, persistence, App Group defaults, Keychain, network, and file I/O.
- Prefer existing local patterns, helpers, models, and test doubles over new abstractions.
- Use `OpenKeyboardTheme` tokens in touched UI files when a token exists. Avoid raw colors/shadows/style constants unless the surrounding file already requires it.
- Keep edits tightly scoped to the task. Do not fold unrelated cleanup into the same change.
- Never print or commit API keys, Authorization headers, private env values, seed files, raw logs, `.xcresult`, generated screenshots, DerivedData, `.ci-results`, or secrets.

## Shared Semantic Prompt Contract

- Treat the pinned `Vendor/semantic-prompt-contract` Git submodule as the only canonical home for semantic operation identifiers, prompt wording, parameters, rendering rules, response-format requirements, schemas, examples, and contract fixtures.
- Initialize submodules before planning or verification. Confirm the submodule worktree matches the recorded gitlink; never build against an adjacent mutable checkout or an unrecorded package commit.
- Keep UI, networking, gateway URL/key handling, model selection, persistence, parsing compatibility, and response presentation in OpenKeyboard. Do not move them into the contract package.
- Do not add fallback or copied canonical prompt wording to Swift sources or tests. Generated adapters must derive from the canonical JSON and remain synchronized through the package generator.
- For a contract change, update and test the shared package first, classify the semantic-version impact, inspect golden rendering changes, advance the consumer gitlink intentionally, and run `./scripts/check-semantic-prompt-contract.sh`.
- Treat `.gitmodules`, the contract gitlink, generated-adapter wiring, and semantic prompt request changes as gateway-impacting. They require the same exact-head live gateway evidence and proof boundaries as other production prompt changes.
- The gateway may consume package-owned diagnostic fixtures, but it must preserve exact client messages and must not regain production OpenKeyboard prompt construction.

## Evidence Classes

Keep these three evidence classes explicit in plans, requirement ledgers, PRs, and reports:

1. **Automated regression evidence:** unit tests, XCTest, XCUITest, mocked gateway tests, debug
   launch states, seeded UI/result states, component hosts, and `XCTAttachment` screenshots. This
   includes XCUITest routes that install and activate the real keyboard extension.
2. **Normal simulator runtime proof:** a normally installed and launched app, without
   `--uitesting`, debug-state injection, seeded result panels, or test-host shortcuts. Exercise the
   actual keyboard extension through an ordinary host-app text field, invoke the action through the
   visible production UI, and capture screenshots directly from Simulator or Xcode outside XCTest.
3. **Physical-device proof:** the exact signed build installed on the configured device, exercised
   through the normal keyboard-extension lifecycle, with screenshots captured directly from that
   device.

Automated evidence is required for development and regression coverage, but XCTest/XCUITest cannot
by itself authorize a proof-sensitive push, PR readiness, release readiness, or a claim that a
user-visible workflow works. Test-seeded loading, success, warning, and failure states are
diagnostics only; they do not prove that a production request produced that state. Simulator
evidence never satisfies a physical-device requirement.

## Verification Rules

Run verification proportional to the change:

- Always run `git diff --check` before claiming done.
- Run targeted Swift/Xcode tests for changed ViewModel, service, parser, gateway, keyboard, or UI behavior. Prefer `./scripts/ios/test.sh ...` modes where they match the task.
- XCTest/XCUITest may be used freely while implementing and diagnosing changes; label its results as
  automated regression evidence even when the installed extension process was active.
- Changes affecting UI, keyboard-extension lifecycle, Apply/Copy/Back/Rerun behavior, live gateway
  behavior, or result presentation require normal simulator runtime proof before push.
- Normal simulator runtime proof must use the actual app and extension, an ordinary host-app text
  input, visible production UI, and the configured live gateway when semantic behavior is being
  verified. It must not use test-only launch arguments, debug-state injection, seeded result
  panels, component/test hosts, or `XCTAttachment` screenshots.
- Record the exact Git SHA, build configuration, simulator model, OS version, action, source text,
  and observed result. Capture screenshots directly from Simulator/Xcode and keep credentials and
  private configuration out of screenshots and logs.
- If Codex can operate the normal simulator confidently, collect the runtime proof directly. If
  normal interaction is unavailable, unreliable, or ambiguous, stop before push or readiness,
  identify the unverified behavior, and ask for manual testing with a short exact checklist and
  expected screenshots. Additional XCTest runs do not replace missing runtime proof.
- Physical-device requirements require the exact signed build on the configured device. When that
  device is unavailable, report device proof as blocked and request manual verification; Simulator
  and XCTest are not substitutes.
- Report automated test results, transport success, semantic acceptance, and visual/runtime
  acceptance separately.

## Screenshot And Simulator Interaction Rules

- If MCP/ClawMaster simulator tools are available, use them to operate the normally launched app and
  capture direct Simulator screenshots for runtime acceptance when the task is proof-sensitive.
- If MCP/ClawMaster is unavailable, interact through Simulator/Xcode directly when reliable. Repo
  XCUITest routes remain automated regression evidence and do not become normal runtime proof.
- If Xcode or the required simulator runtime is also unavailable, run the applicable platform-independent checks, report the missing UI/build verification as a blocker, and do not claim visual or simulator proof.
- For automated screenshot regression suites, prefer `./scripts/ios/test.sh screenshots`.
- For `.xcresult` bundles, export attachments with `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>` and inspect the images before sharing paths. Label them
  `XCTAttachment` automated regression artifacts, never manual or normal simulator proof.
- Screenshot proof must be delivered back into the chat. Do not stop at "captured screenshots" or an `.xcresult` path.
- If the chat surface supports image/file attachments, attach the relevant screenshots directly. If it only supports links, export selected PNGs beneath `OPEN_KEYBOARD_ARTIFACT_DIR` when set, or beneath `${TMPDIR:-/tmp}` as a temporary fallback, and include clickable links in the final response.
- Before sending screenshots, inspect them and confirm they do not expose API keys, Authorization headers, seed values, private env values, or unrelated private content.
- If screenshots cannot be exported or attached, say that explicitly and include the failing export command/output summary.
- Never commit screenshots, `.xcresult`, `.ci-results`, DerivedData, or raw logs.
- Do not use Preview Lab, component hosts, debug launch states, or test-seeded panels as normal
  runtime proof. Those screenshots are diagnostics only.

## Keyboard Extension Evidence Routes

Use `docs/REAL_EXTENSION_SMOKE_PLAN.md` for both evidence routes. The focused command below is
automated real-extension regression evidence because XCUITest launches and controls the flow. It is
not manual or normal simulator runtime proof, even when the real extension process is active:

- host app text input focused
- OpenKeyboard extension active
- gateway config visible inside the extension when relevant
- real AI logo/sparkle/action menu available
- screenshot attachment from the real extension, not Preview Lab

Focused command from the plan:

```bash
xcodebuild test \
  -project OpenKeyboard.xcodeproj \
  -scheme OpenKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  -only-testing:OpenKeyboardUITests/AcceptanceScreenshotUITests/testRealKeyboardExtensionLogoActionMenuScreenshotOrExplicitBlocker \
  CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO
```

For credentialed automated real-extension regression coverage, use:

```bash
./scripts/ios/test.sh real-keyboard-live
```

This reads `<primary-checkout>/.agent/local-seeds/openkeyboard-gateway.env` directly, including
when invoked from a linked worktree; values must never be printed. Before a proof-sensitive push,
also complete the normal simulator runtime route in the plan through an ordinary host-app text
field and retain direct Simulator screenshots plus the required run record.

## Mock And Real Gateway Boundary

- Mock gateway tests are for parser, request-shape, and deterministic regression coverage.
- Real gateway diagnostics are for checking the deployed server/model contract and performance.
- If mock and real disagree, treat that as a contract issue to investigate, not as proof that the app is fine.
- For OpenKeyboard LLM operations, keep operation names aligned with the gateway-supported contract. Do not invent client-only operation names without backend support.
- Canonical per-machine live seed: `<primary-checkout>/.agent/local-seeds/openkeyboard-gateway.env`.
  Live scripts resolve the primary checkout through Git's common directory and read this file
  directly; they never copy credentials into linked worktrees.
- Git does not synchronize ignored files. Each machine and clone needs its own mode-`600` seed in
  a current-user-owned directory chain that is not writable by group or other users and has no
  extended ACL entries; a trusted secret manager may materialize it at the canonical path when
  cross-machine synchronization is desired, but agents must not transport it through Git or
  disposable worktrees.
- The seed accepts complete `LOW` and `HIGH` URL/API-key/model triples for targeted differential verification. The existing `OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL`, `OPEN_KEYBOARD_SIMULATOR_API_KEY`, and `OPEN_KEYBOARD_SIMULATOR_MODEL` triple remains a complete legacy fallback for ordinary verification. Partial profiles, duplicates, unknown keys, unsafe model IDs, role reversal, substitution, and silent low-profile fallback are rejected.
- Never hardcode profile model IDs or credentials in committed source, fixtures, documentation, or skills. Exact model identities belong in the ignored local seed and retained exact-head evidence.
- Use `scripts/ios/openkeyboard-gateway.seed.env.example` as the template. Do not commit the filled seed.

## Task Mapping

- Pure model/parser/service logic: targeted XCTest or `./scripts/ios/test.sh core`, plus `git diff --check`.
- Host settings or gateway connection UI: relevant ViewModel/service tests, then `./scripts/ios/test.sh ui` if behavior is user-facing.
- Visual/UI layout: targeted tests plus automated screenshot regression, then normal simulator
  runtime proof before push.
- Keyboard extension config/action path: targeted tests plus
  `./scripts/ios/test.sh real-keyboard-live` as automated real-extension regression evidence, then the normal simulator
  runtime route from `docs/REAL_EXTENSION_SMOKE_PLAN.md` before push.
- Live gateway contract/performance: automated live gateway checks plus normal simulator runtime
  proof when user-visible semantic behavior is affected. Report transport, semantic acceptance, and
  visual/runtime acceptance separately.
- Model-capability classification, long-input handling, parser compatibility, retry behavior, automatic-analysis warnings, manual action error scope, or Translate warning scope: run `./scripts/ios/test.sh live-model-differential` after deterministic prerequisites. The runner builds once and reuses safe artifacts; it must not run the full suite per model.
- Pre-commit broad check: `./scripts/check.sh --quick`, then any task-specific automated route.
- Local commits may proceed after deterministic tests. Before push, run `./scripts/check.sh --full`
  and the applicable exact-head live gate; proof-sensitive changes also require successful normal
  simulator runtime proof. Missing runtime proof stops push unless the user explicitly authorizes
  proceeding with the gap disclosed.

## Pull Request Review

- Use `$review-verify-merge-pr` for independent PR review and release-readiness assessment.
- The project `pr-reviewer` is read-only and must review the exact GitHub head without inherited implementation context.
- Give every in-scope user requirement a stable ID, observable acceptance criterion, required proof type, exact evidence, and `VERIFIED` or `UNVERIFIED` status. Do not combine independent requirements.
- Treat ambiguous, skipped, missing, stale, fallback, wrong-target, wrong-model, or contributor-attested-only material evidence as `UNVERIFIED`. Every unverified in-scope requirement is a blocker, not a residual proof limit.
- Exact-model requirements must run that exact model without catalog fallback or substitution. A different working model proves only that different model.
- For an exact single-model requirement, run `OPEN_KEYBOARD_LIVE_REQUIRED_MODEL=<exact-id> ./scripts/check-live.sh gateway`. For a differential requirement, run `OPEN_KEYBOARD_LIVE_REQUIRED_MODELS='low=<exact-id>, high=<exact-id>' ./scripts/check-live.sh gateway-differential`. Required and tested roles must match in canonical low/high order with no substitution. A diagnostic or intermittent low boundary remains `UNVERIFIED` and blocks merge.
- Run the independent review and GitHub checks concurrently where practical.
- Any new commit invalidates the previous review, local full gate, GitHub check conclusions, and exact-head human merge authorization.
- A bounded implementation request starts the normal autonomous lifecycle through commit, push, PR publication, in-scope review fixes, readiness, and guarded merge. Do not request separate confirmations between those stages while the exact-head independent reviewer reports operational confidence of exactly `100%`.
- Honor the latest explicit opt-out: `local only`, `do not commit`, `do not push`, `do not create a PR`, `keep draft`, or `do not merge`.
- Planning, review-only work, readiness assessment, and blocker requests remain read-only and do not authorize state changes.
- Never mark a PR ready or merge while required normal simulator or physical-device proof is
  missing. Explicit authorization to push with a disclosed proof gap does not convert that gap into
  verified evidence and does not authorize readiness or merge.
- Before a guarded merge, always re-fetch and validate the current body, linked review, head, threads, and current check rollup; require a durable linked independent-review report, the exact reviewed head to pass `./scripts/check.sh --full`, and the exact-head `Required technical checks`, `Required checks`, and `Required live verification` results to be successful with no pending, canceled, skipped, or failing required entry. Re-run the validators locally against current GitHub metadata and require `gh pr checks <number> --required` to exit successfully immediately before merge; checking only the newest result by name can miss a failed `pull_request_review` event family. Automatic authorization additionally requires every in-scope requirement `VERIFIED`, no material uncertainty, and exact reviewer confidence of `100%`. Otherwise keep the PR draft and require explicit repository-owner approval for that exact SHA after all unverified requirements and blockers are disclosed; never infer or carry that approval across a new head.
- Never claim that unknown defects are impossible. A clean review means all stated requirements are verified within the named evidence boundary and no material uncertainty remains.
- Deployment remains a separate external state change and requires explicit authorization plus protected-environment approval.

## Repository Automation

- `$develop-openkeyboard` routes bounded implementation through the correct local checks and proof boundaries.
- `$plan-openkeyboard-work-package` creates compact digest-bound plans only when planning is requested.
- The project `work-package-planner` is read-only and cannot edit, test, access GitHub, or invoke other agents.
- `$review-verify-merge-pr` prepares exact-head evidence and invokes the read-only project `pr-reviewer`.
- Custom-agent output never substitutes for GitHub required checks, conditional exact-head owner approval, live proof, signing, deployment, or App Review.

## Commit And Push Rules

- Commit and push are part of the normal autonomous lifecycle for a bounded implementation unless the user opts out.
- Install the committed hooks with `./scripts/install-hooks.sh` before the first commit or push in a worktree. Never bypass them with `--no-verify`.
- Before commit:
  - run `git status --short --branch` from the active session worktree
  - run `git diff --check`
  - stage only intended files
  - run `git diff --cached --name-only` and confirm every staged file belongs to the session
  - scan the staged diff for obvious secrets or generated artifacts
- Use a concise commit message that describes the functional change.
- Local implementation and commits may proceed after deterministic tests. For proof-sensitive
  user-facing changes, do not push or create/update a readiness PR until normal simulator runtime
  proof succeeds unless the user explicitly authorizes the push with the missing proof disclosed.
- If the branch is ahead by earlier unrelated commits, say that pushing will publish them and stop when their ownership or scope is ambiguous.
- Do not batch-commit dirty files from the integration checkout. If existing dirty files need to be included, they must be explicitly assigned to the current session or moved into the session worktree intentionally.

## Reporting

Final responses should be short and concrete:

- what changed
- files or areas touched
- verification run and pass/fail result
- screenshot attachments or clickable screenshot links when screenshots were required or requested
- remaining risks or blockers
- commit id if committed

Do not overstate. A green build is not the same as verified app functionality.
