# Open Keyboard CI Log Index

Last updated: 2026-05-25

Purpose: keep raw CI logs as file artifacts while preserving concise, durable summaries in docs/context. Do not paste full logs into chat or review packets.

Path convention: all recorded project artifact paths are relative to the repository root. Historical verifier request IDs are identifiers only; their external records and Xcode's machine-local DerivedData may not exist on another machine. Never add usernames, home-directory paths, container checkout paths, or other absolute machine-specific locations to this index.

## Latest verified green run

### 2026-05-25 15:21 — Fresh pre-commit verification

- Status: PASS
- Commands:

```sh
./scripts/local-ci.sh --quick
./scripts/local-ci.sh --ui
./scripts/local-ci.sh --screenshots
```

- Verifier request ID: `2026-05-25T152101-openkeyboard-fresh-precommit-verify`
- The combined external verifier log was not stored in this repository; the durable summary is retained below.

- Project CI logs:

```text
.ci-results/local-ci_20260525_152646.log
.ci-results/local-ci_20260525_152735.log
```

- Latest Xcode result bundle was stored in the machine-selected DerivedData directory and is not a portable repository artifact.

- Summary:

```text
--quick passed: core package tests passed with 1 live test skipped; iOS app/extension build passed on iPhone 16.
--ui passed on iPhone 16.
--screenshots passed on iPhone 16 and iPhone SE.
```

### 2026-05-23 13:04 — Xcode UI screenshot harness

- Status: PASS
- Commands:

```sh
./scripts/local-ci.sh --quick
./scripts/local-ci.sh --ui
./scripts/local-ci.sh --screenshots
```

- Verifier request ID: `2026-05-23T130408-openkeyboard-ui-test-harness`

- Project CI logs:

```text
.ci-results/local-ci_20260523_130431.log
.ci-results/local-ci_20260523_130452.log
.ci-results/local-ci_20260523_130531.log
```

- Xcode result bundles were stored in the machine-selected DerivedData directory and are not portable repository artifacts.

- Summary:

```text
--quick passed: 48 core tests executed, 1 skipped, 0 failures; iOS app build succeeded.
--ui passed: OpenKeyboardUITests/OnboardingScreenshotUITests ran on iPhone 16, 1 test, 0 failures.
--screenshots passed: screenshot UI tests ran on iPhone 16 and iPhone SE (3rd generation), both 1 test, 0 failures.
Xcode screenshot attachment name: onboarding-welcome-iPhone.
```

### 2026-05-22 02:39 — Onboarding UI visual fix

- Status: PASS
- Command:

```sh
./scripts/local-ci.sh --quick
```

- Host log:

```text
.ci-results/local-ci_20260522_023923.log
```

- Screenshot:

```text
.ci-results/onboarding-first-page-20260522_023923.png
```

- Verifier request ID: `2026-05-22T023906-openkeyboard-onboarding-ui-fourth-rerun`

- Summary:

```text
Core package tests passed
** BUILD SUCCEEDED **
✅ iOS app build passed
✅ OpenKeyboard local CI complete
Visual verification passed: complete title/subtitle, all three feature rows visible, page indicator not overlapping.
```

### 2026-05-22 02:01 — User-flow tests

- Status: PASS
- Command:

```sh
./scripts/local-ci.sh --quick
```

- Host log:

```text
.ci-results/local-ci_20260522_020159.log
```

- Verifier request ID: `2026-05-22T020131-openkeyboard-ci-user-flow-tests`

- Summary:

```text
UserFlowTests passed: 4 tests, 0 failures
LiveGatewayTests skipped cleanly without env vars
OpenKeyboardCorePackageTests passed: 45 tests, 1 skipped, 0 failures
All tests passed: 45 tests, 1 skipped, 0 failures
✅ Core package tests passed
** BUILD SUCCEEDED **
✅ iOS app build passed
✅ OpenKeyboard local CI complete
```

## Previous notable runs

### 2026-05-21 16:27 — Edge-case backend tests

- Status: PASS
- Project log:

```text
.ci-results/local-ci_20260521_162709.log
```

- Verifier request ID: `2026-05-21T162651-openkeyboard-ci-edge-tests`

- Summary:

```text
GatewayClientTests passed: 9 tests, 0 failures
KeyboardInputReducerTests passed: 13 tests, 0 failures
WritingActionTests passed: 7 tests, 0 failures
LiveGatewayTests skipped cleanly without env vars
OpenKeyboardCorePackageTests passed: 41 tests, 1 skipped, 0 failures
All tests passed: 41 tests, 1 skipped, 0 failures
✅ Core package tests passed
** BUILD SUCCEEDED **
✅ iOS app build passed
✅ OpenKeyboard local CI complete
```

### 2026-05-21 16:17 — Live smoke scaffold

- Status: PASS
- Project log:

```text
.ci-results/local-ci_20260521_161741.log
```

- Summary: live gateway smoke test compiled and skipped cleanly without env vars; core tests and iOS build passed.

### 2026-05-21 16:16 — Live smoke async assertion failure

- Status: FAIL
- Project log:

```text
.ci-results/local-ci_20260521_161624.log
```

- Failure:

```text
LiveGatewayTests.swift: async call in an autoclosure that does not support concurrency
XCTAssertTrue(try await client.checkHealth())
```

- Fix: store awaited value first, then assert `XCTAssertTrue(isHealthy)`.

### 2026-05-21 16:14 — Keyboard reducer tests

- Status: PASS
- Project log:

```text
.ci-results/local-ci_20260521_161444.log
```

- Summary: keyboard reducer/context tests passed; iOS build passed.

### 2026-05-21 16:13 — Chat fixes

- Status: PASS
- Project log:

```text
.ci-results/local-ci_20260521_161313.log
```

- Summary: chat/gateway/writing-action tests passed; iOS build passed.

## Log handling rule

For each future CI run:

1. Store raw logs under `.ci-results/` by default and record the repository-relative path here. If `OPEN_KEYBOARD_ARTIFACT_DIR` points outside the repository, record only the artifact name and durable summary, not its machine-specific absolute path.
2. Extract status, command, test counts, key failure lines, and next action.
3. If the log is large/noisy and separate log-review agents are available, use one with the artifact path. Otherwise review it in the current session.
4. Keep `docs/TDD_STATUS.md`, `docs/WORK_QUEUE.md`, and this index synchronized.
