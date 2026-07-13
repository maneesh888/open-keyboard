# OpenKeyboard Default Workflow

## Purpose

Use this workflow for OpenKeyboard coding, testing, screenshots, gateway, keyboard extension, CI, optional MCP/ClawMaster verification, and commit work. Keep each session focused, repo-aware, tied to the real scripts/proof routes, and safe to commit when the user allows it.

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
6. If the user gives plain text, convert it internally into a bounded work order:
   - objective
   - likely files/modules
   - out-of-scope areas
   - verification required
   - whether screenshots or real simulator proof are needed
   - whether commit/push is allowed
7. Ask only when scope, destructive action, credentials, external deployment, base branch, dirty-checkout ownership, or commit/push permission is ambiguous.

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

- Default deterministic CI: `./scripts/local-ci.sh --quick`
  - runs `./scripts/ios/test.sh core`
  - runs `./scripts/ios/test.sh build`
- Core package only: `./scripts/ios/test.sh core`
- iOS app + keyboard extension build: `./scripts/ios/test.sh build`
- Full OpenKeyboard UI tests on iPhone 16: `./scripts/ios/test.sh ui`
- Onboarding screenshots on iPhone 16 + iPhone SE: `./scripts/ios/test.sh screenshots`
- Opt-in live gateway service smoke: `./scripts/ios/test.sh live-gateway-smoke`
- Opt-in real keyboard extension live test: `./scripts/ios/test.sh real-keyboard-live`
- Opt-in live AI harness tests: `./scripts/ios/test.sh live-ui`

Remote GitHub CI only runs `core` and `build` from `.github/workflows/openkeyboard-ci.yml`. Do not imply remote CI proves simulator UI, screenshots, real keyboard extension behavior, or live gateway behavior.

## Coding Rules

- Follow MVVM: SwiftUI views stay presentation-focused; ViewModels own UI state and user actions; services own side effects, gateway calls, persistence, App Group defaults, Keychain, network, and file I/O.
- Prefer existing local patterns, helpers, models, and test doubles over new abstractions.
- Use `OpenKeyboardTheme` tokens in touched UI files when a token exists. Avoid raw colors/shadows/style constants unless the surrounding file already requires it.
- Keep edits tightly scoped to the task. Do not fold unrelated cleanup into the same change.
- Never print or commit API keys, Authorization headers, private env values, seed files, raw logs, `.xcresult`, generated screenshots, DerivedData, `.ci-results`, or secrets.

## Verification Rules

Run verification proportional to the change:

- Always run `git diff --check` before claiming done.
- Run targeted Swift/Xcode tests for changed ViewModel, service, parser, gateway, keyboard, or UI behavior. Prefer `./scripts/ios/test.sh ...` modes where they match the task.
- For keyboard extension, App Group, Keychain, or config sharing changes, run or request the real simulator path, not only host app tests.
- For UI changes, collect real screenshots from Xcode/simulator or ask the active MCP/ClawMaster verifier route for screenshots before claiming visual quality.
- For gateway behavior, distinguish mock tests from real gateway proof. If the user asks for real behavior, do not use mock results as proof.
- For live model/gateway work, report latency honestly and separate "transport works", "tests pass", and "the user-visible flow works".

## Screenshot And MCP/ClawMaster Rules

- If MCP/ClawMaster simulator tools are available, use them for host-side screenshots and visual acceptance when the task is UI, keyboard extension, or release-readiness related.
- If MCP/ClawMaster is not available in the current Codex surface, use the repo Xcode routes and say proof was collected directly through Xcode.
- If Xcode or the required simulator runtime is also unavailable, run the applicable platform-independent checks, report the missing UI/build verification as a blocker, and do not claim visual or simulator proof.
- For screenshot suites, prefer `./scripts/ios/test.sh screenshots`.
- For `.xcresult` bundles, export attachments with `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>` and inspect the images before sharing paths.
- Screenshot proof must be delivered back into the chat. Do not stop at "captured screenshots" or an `.xcresult` path.
- If the chat surface supports image/file attachments, attach the relevant screenshots directly. If it only supports links, export selected PNGs beneath `OPEN_KEYBOARD_ARTIFACT_DIR` when set, or beneath `${TMPDIR:-/tmp}` as a temporary fallback, and include clickable links in the final response.
- Before sending screenshots, inspect them and confirm they do not expose API keys, Authorization headers, seed values, private env values, or unrelated private content.
- If screenshots cannot be exported or attached, say that explicitly and include the failing export command/output summary.
- Never commit screenshots, `.xcresult`, `.ci-results`, DerivedData, or raw logs.
- Do not use Preview Lab as proof for real keyboard extension behavior. Preview/component screenshots are diagnostics only.

## Real Keyboard Extension Proof

Use `docs/REAL_EXTENSION_SMOKE_PLAN.md` for release-readiness or extension lifecycle proof. Acceptance requires the real extension lifecycle:

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

For live configured keyboard behavior, prefer:

```bash
./scripts/ios/test.sh real-keyboard-live
```

This uses `.agent/local-seeds/openkeyboard-gateway.env`; values must never be printed.

## Mock And Real Gateway Boundary

- Mock gateway tests are for parser, request-shape, and deterministic regression coverage.
- Real gateway diagnostics are for checking the deployed server/model contract and performance.
- If mock and real disagree, treat that as a contract issue to investigate, not as proof that the app is fine.
- For OpenKeyboard LLM operations, keep operation names aligned with the gateway-supported contract. Do not invent client-only operation names without backend support.
- Local live seed file path: `.agent/local-seeds/openkeyboard-gateway.env`.
- The only accepted simulator seed keys are `OPEN_KEYBOARD_SIMULATOR_GATEWAY_URL`, `OPEN_KEYBOARD_SIMULATOR_API_KEY`, and `OPEN_KEYBOARD_SIMULATOR_MODEL`.
- Use `scripts/ios/openkeyboard-gateway.seed.env.example` as the template. Do not commit the filled seed.

## Task Mapping

- Pure model/parser/service logic: targeted XCTest or `./scripts/ios/test.sh core`, plus `git diff --check`.
- Host settings or gateway connection UI: relevant ViewModel/service tests, then `./scripts/ios/test.sh ui` if behavior is user-facing.
- Visual/UI layout: targeted tests plus `./scripts/ios/test.sh screenshots` or MCP/ClawMaster screenshot proof.
- Keyboard extension config/action path: targeted tests plus `./scripts/ios/test.sh real-keyboard-live` or the focused smoke from `docs/REAL_EXTENSION_SMOKE_PLAN.md`.
- Live gateway contract/performance: `./scripts/ios/test.sh live-gateway-smoke`, app diagnostics, or explicit live Xcode proof. Report timing separately from correctness.
- Pre-commit broad check: `./scripts/local-ci.sh --quick`, then any task-specific UI/live/screenshot route.

## Commit And Push Rules

- Commit only when the user explicitly allows it after the task is clear.
- Before commit:
  - run `git status --short --branch` from the active session worktree
  - run `git diff --check`
  - stage only intended files
  - run `git diff --cached --name-only` and confirm every staged file belongs to the session
  - scan the staged diff for obvious secrets or generated artifacts
- Use a concise commit message that describes the functional change.
- Push only when explicitly asked. If the branch is ahead by earlier commits, say that pushing will publish all local commits ahead of origin.
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
