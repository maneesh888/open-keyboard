# Open Keyboard Work Queue

Last updated: 2026-05-27

## Current verified baseline

```text
Core package tests: 48 passed, 1 skipped, 0 failed
iOS app/extension build: passed
Onboarding first-page visual verification: passed on iPhone 16 simulator
Latest verified CI request: /app/workspace/clawd-coder/requests/clawmaster/2026-05-22T023906-openkeyboard-onboarding-ui-fourth-rerun.md
```

## Queue

### 1. Dedicated iOS UI test + screenshot harness

Status: Done

Goal: stop relying on ad-hoc manual simulator screenshots for onboarding/UI quality. Build a repeatable UI-test harness using Just Spent's iOS UI test setup as reference.

Reference project:

```text
/Users/maneesh/Documents/Hobby/just-spent/ios/JustSpent/JustSpentUITests
```

Useful Just Spent patterns to copy/adapt:

- `BaseUITestCase` common setup.
- `TestDataHelper` launch-argument helpers.
- Launch args such as `--uitesting`, `--show-onboarding`, `--skip-onboarding`.
- Accessibility identifiers on SwiftUI views.
- `XCTAttachment(screenshot:)` with `keepAlways` for artifacts.
- Simulator/device skips for hardware-only cases.

Open Keyboard tasks:

- Add `OpenKeyboardUITests` Xcode target.
- Add `BaseOpenKeyboardUITestCase` and `OpenKeyboardUITestDataHelper`.
- Add app launch handling for:
  - `--uitesting`
  - `--show-onboarding`
  - `--skip-onboarding`
  - optionally `--onboarding-page=0/1/2/3`
- Add stable accessibility identifiers for onboarding:
  - `onboarding_title`
  - `onboarding_subtitle`
  - `onboarding_feature_llm_title`
  - `onboarding_feature_llm_description`
  - `onboarding_feature_privacy_title`
  - `onboarding_feature_privacy_description`
  - `onboarding_feature_ai_title`
  - `onboarding_feature_ai_description`
  - `onboarding_page_indicator`
- Add UI tests that verify:
  - required text exists on onboarding page 1
  - no critical label has ellipsis/truncation where avoidable
  - page indicator does not overlap feature content using frame checks where possible
  - screenshots are attached for review
- Add script support:
  - `./scripts/local-ci.sh --ui`
  - optionally `./scripts/local-ci.sh --screenshots`
- Run on at least:
  - iPhone SE
  - iPhone 16

Acceptance:

- Normal quick CI remains available.
- UI test command produces deterministic screenshot artifacts under `.ci-results/ui/`.
- Onboarding page screenshots are easy to compare tomorrow.
- UI tests catch truncation/overlap regressions; design quality still needs human screenshot review or approved snapshot baseline.

### 2. Realistic end-to-end user-flow tests

Status: Done

Goal: test positive user flows, not only isolated plumbing or negative cases.

Add deterministic tests for:

- config exists and validates
- model list is fetched/selected
- writing action builds prompt
- chat completion returns text
- replacement strategy applies output
- final text matches expected user-visible result

Likely files:

```text
OpenKeyboardCore/Tests/OpenKeyboardCoreTests/UserFlowTests.swift
```

Acceptance:

- Runs offline with mock HTTP client.
- Covers at least grammar fix, rewrite, summarize, and continue-writing flows.

### 3. Prompt quality/performance eval suite

Status: In progress

Goal: measure how well system/action prompts perform with real LLMs.

Add docs/tests for:

- golden prompt fixtures
- grammar/rewrite/summarize/translate/tone/continue-writing examples
- deterministic rubric checks first
- optional live LLM evals behind env vars (initial scaffold added)
- prompt injection cases: selected text tries to override instructions
- model comparison across local/cloud models
- latency and token/cost tracking when gateway exposes usage

Likely files:

```text
docs/PROMPT_EVALS.md
OpenKeyboardCore/Tests/OpenKeyboardCoreTests/PromptEvaluationFixturesTests.swift
OpenKeyboardCore/Tests/OpenKeyboardCoreTests/LivePromptEvaluationTests.swift
```

Acceptance:

- Normal CI stays deterministic.
- Live evals skip unless env vars are set; `LivePromptEvaluationTests` covers grammar, rewrite, and prompt-injection smoke scenarios.
- Results document pass/fail criteria and known weak prompts.

### 4. Before/after cursor context and replacement ranges

Status: Done

Goal: support real keyboard extension behavior where selected/context text is not always replace-all or append-only.

Added initial core slice:

- `KeyboardDocumentContext` with before-cursor, selected-text, and after-cursor fields.
- `KeyboardContextExtractor.contextAfterCursor` and `contextAroundCursor` with bounded, grapheme-safe prefix/suffix behavior.
- `AITextReplacementStrategy` cases for `replaceSelected`, `insertAtCursor`, `replaceLastSentence`, and `replaceLastParagraph` while preserving existing `replaceAll` / `appendToCursor` behavior.
- `KeyboardContextTests` covering selected replacement, insertion, last sentence/paragraph replacement, completed final sentence replacement, after-cursor preservation, and emoji/grapheme safety.

Likely follow-up files:

```text
OpenKeyboardCore/Sources/OpenKeyboardCore/KeyboardInputReducer.swift
OpenKeyboardCore/Tests/OpenKeyboardCoreTests/KeyboardContextTests.swift
```

Acceptance:

- Handles emoji/grapheme clusters correctly.
- Clear strategy enum for replacement behavior.
- Host Swift validation passed via direct ClawMaster host-path requests.

Note: devtools `ai-keyboard` mapping still points to a stale/missing host path; repair that separately from this completed core slice.

### 5. Timeout, cancellation, and network resilience tests

Status: Planned

Goal: make gateway behavior safe for keyboard UX.

Add tests for:

- request timeout mapping
- cancellation propagation
- offline/network failure mapping
- retry/no-retry decisions
- user-displayable error classification

Likely files:

```text
OpenKeyboardCore/Tests/OpenKeyboardCoreTests/GatewayNetworkResilienceTests.swift
```

Acceptance:

- Mock HTTP client can throw errors.
- Core exposes typed errors suitable for UI messages.

### 6. Documentation parity with Just Spent README style

Status: In progress

Goal: every project README should expose status, CI, test strategy, architecture, and roadmap clearly.

Already done for Open Keyboard:

```text
README.md
docs/TDD_STATUS.md
```

Remaining:

- Keep README updated after each major tested slice.
- Add prompt eval results once implemented.
- Consider README status blocks for related projects if they are stale.

### 7. Wire OpenKeyboardCore into app/extension

Status: Planned

Goal: move from tested backend core to real UI usage.

Add integration for:

- host settings using `GatewayConfig` validation/store
- keyboard extension reading shared config
- keyboard UI using reducer/context/replacement logic
- AI action buttons using `GatewayClient`
- loading/error UI states

Acceptance:

- Existing core tests remain green.
- iOS build passes.
- Manual simulator smoke can type and run at least one mocked/real action.

## Execution order

Recommended next order:

1. Dedicated UI test + screenshot harness (tomorrow review item)
2. Modern onboarding redesign using screenshot/UI-test loop
3. Cursor/replacement range tests
4. Prompt eval docs + offline fixtures
5. Live prompt eval opt-in tests
6. Timeout/cancellation/network resilience
7. Wire core into app/extension UI
