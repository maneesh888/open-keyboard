# AI Keyboard Project - Current TODO

**Last Updated:** 2026-09-09

**Migration entry added:** 2026-09-05

**Connector sample staging updated:** 2026-09-09

This file is a current-state guide for choosing the next OpenKeyboard implementation slice. It replaces the older April phase checklist; items are marked from repo/docs inspection only. Anything not proven by current docs/source is labeled **needs verification** rather than complete.

---

## Current repo state

### Main app

- [x] Xcode project exists with main app and keyboard extension targets.
- [x] Main SwiftUI app shell exists (`OpenKeyboardApp`, `ContentView`, `SettingsView`, `OnboardingView`).
- [x] Gateway settings screen exists with gateway URL/API-key entry, connection test, model loading, onboarding reset, and setup/status copy.
- [x] Onboarding flow exists with UI-test launch arguments and stable accessibility identifiers.
- [x] App Group entitlements are present for app and extension.
- [x] Gateway config moved toward shared Keychain/App Group storage; legacy App Group API-key fallback is tracked for compatibility.
- [ ] App icon / release media — needs verification.
- [ ] App Store bundle/license/release metadata — needs verification.

### Keyboard extension

- [x] Keyboard extension target and SwiftUI/UIKit bridge exist.
- [x] QWERTY-style key grid exists with shift, delete, return, space, globe/next-keyboard behavior, and toolbar state.
- [x] Basic typing reducer/context logic exists in `OpenKeyboardCore` with tests for character input, shift, delete, grapheme-safe context, and replacement strategies.
- [x] AI toolbar/action panel exists with compact sparkle entry and Improve/Rephrase/Summarize actions.
- [x] Real keyboard Fix Grammar has automated XCUITest end-to-end regression coverage; current
  normal simulator runtime proof still needs verification before a proof-sensitive push/release.
- [ ] Rewrite and Summarize end-to-end in the actual keyboard — needs verification.
- [ ] Suggestions while typing / suggestion chips — not implemented as a verified product feature.
- [ ] Polished correction preview / accept-dismiss UX — pending.
- [ ] Full release-quality iOS keyboard polish across small/large devices — in progress, not complete.

### AI integration

- [x] Gateway client/config core exists (`GatewayClient`, `GatewayConfig`, `GatewayConfigStore`, `URLSessionHTTPClient`).
- [x] Main app connection testing and model loading exist.
- [ ] Rename the developer-facing `Fast plain-text grammar` diagnostic to `Grammar correction`;
  keep the short, one-attempt plain-text explanation in supporting copy.
- [x] Keyboard AI service supports Fix Grammar, Rewrite, and Summarize requests.
- [x] Structured suggestion/action result parsing exists.
- [x] Offline prompt/user-flow tests and opt-in live gateway tests exist.
- [ ] Remove structured model responses from Summarize, Translate, and Continue Writing. Migrate
  their canonical response contracts to operation-specific validated plain text, omit
  `response_format` from every built-in writing-action request, and preserve safe input/parameter
  boundaries. Follow `docs/plans/plain-text-writing-responses.md`.
- [ ] Streaming/SSE responses — needs verification; do not assume complete.
- [ ] Debounced suggestions while typing — pending.
- [ ] Timeout/cancellation/network resilience coverage — next queue item, partially present in tests but needs current verification before marking complete.
- [ ] Long-text Fix Grammar model differential and rate-limit-safe chunking — future work.
  Proof-first live evaluation on `91315578e4211f7343ccd62995530bc5b74358b5` used one
  synthetic 11,430-character document with 20 known errors: the low profile returned the complete
  text unchanged (`0/20` corrections), while the high profile corrected all `20/20` errors in one
  request and preserved all 21 paragraphs. The existing approximately 120-character production
  strategy generated 104 chunks for the same document and received HTTP `429` on chunk 13 when
  running two requests concurrently, so that chunked outcome remains live-unverified. Before
  implementation, evaluate sentence/paragraph-aligned chunks around 1,500–2,000 characters,
  initially processed sequentially; require exact-order reassembly, preserved whitespace and
  paragraph structure, per-chunk validation, no partial application, and a permanent live-model
  differential test where high-profile long correction is required and low-profile support is
  diagnostic/optional.
- [ ] Shared Keychain release hardening and privacy copy — in progress; see `docs/RELEASE_HARDENING.md` and `docs/TDD_STATUS.md`.

### Testing and verification

- [x] Swift package core tests exist under `OpenKeyboardCore/Tests/OpenKeyboardCoreTests`.
- [x] Xcode UI test target exists under `OpenKeyboardUITests`.
- [x] Onboarding screenshot/UI harness exists.
- [x] Keyboard extension evidence plan separates automated regression, normal simulator runtime,
  and physical-device proof.
- [x] Local CI/test scripts are documented in repo docs.
- [ ] Current full quick CI/build status — needs fresh verification before release or code work; this doc refresh intentionally ran static inspection only.
- [ ] Automated real-extension logo/action-menu regression is currently blocked by extension config visibility (`Gateway not configured`); normal runtime proof remains separate.

### Documentation

- [x] TDD/backend status docs exist (`docs/TDD_STATUS.md`).
- [x] Product completion plan exists (`docs/KEYBOARD_PRODUCT_COMPLETION_PLAN.md`).
- [x] Work queue exists (`docs/WORK_QUEUE.md`).
- [x] Release hardening doc exists.
- [x] Prompt eval doc exists.
- [ ] README/setup/troubleshooting/release docs — needs current verification before marking complete.

---

## Current next recommended slice

**Next slice: add DEBUG-only config-state instrumentation, rerun the automated real-extension
regression once, then collect separate normal simulator runtime proof.**

Why this is the smallest safe next step:

- The current automated-regression blocker is narrow: XCUITest can activate the installed extension
  and show QWERTY keys, but cannot reach the AI action menu because the extension reports
  `Gateway not configured`. This does not establish or replace normal runtime acceptance.
- Product code already has the app/extension config pipeline, shared Keychain/App Group pieces, and UI tests; another broad UI redesign or blind smoke retry would not isolate the failure.
- A redacted DEBUG-only config probe can distinguish wrong App Group suite, seed cleanup, Keychain access failure, legacy fallback failure, or stale in-memory config without exposing secrets.
- This unblocks automated lifecycle diagnosis; final product acceptance still requires the normal
  host-app runtime route without debug injection or test control.

Reference plan: `docs/REAL_EXTENSION_SMOKE_PLAN.md`.

## Planned compatibility migration

**Plain-text responses for all built-in writing actions**

- Priority: high; removes an avoidable compatibility requirement for OpenAI-compatible gateways
  and smaller/local models.
- Status: planned; no production implementation or live verification has been performed.
- Scope: convert Summarize, Translate, and Continue Writing from the legacy JSON result envelope to
  operation-specific validated plain text. Grammar, Rewrite, and Improve are already plain text.
- Connector dependency: complete this before Universal AI Connector adoption so the generic
  connector does not need an OpenKeyboard-specific `json_object` response mode; preserve the
  cross-repository ownership and parity requirements in the detailed plan.
- Canonical order: update, test, version, and release `semantic-prompt-contract` first; then advance
  the OpenKeyboard gitlink and update both clients, parsers, diagnostics, tests, and documentation.
- Required proof: contract JavaScript/Swift parity, OpenKeyboard contract-sync and deterministic
  gates, exact-model gateway differential evidence, and normal simulator runtime proof for visible
  Translate behavior before publication/readiness.
- Detailed plan: `docs/plans/plain-text-writing-responses.md`.

**Universal AI Connector sample and migration staging**

- Current boundary: OpenKeyboard already has host-owned Gateway configuration, connection testing,
  model loading, and model-selection UI. Universal AI Connector already has deterministic iOS,
  Android, and Kotlin/JVM console samples. The first missing workflow is live provider/Gateway
  configuration, model loading, exact selection, and connection testing in the existing iOS
  sample; do not replace or duplicate OpenKeyboard's settings UI while adding that workflow.
- [ ] **Stage 1 — make the Universal AI Connector standalone sample a complete iOS integration
  harness.** Keep provider/Gateway configuration host-owned and credentials in secure iOS storage.
  Load models through the connector's existing `listModels` API and present loading, supported,
  empty, unsupported-discovery, authentication, timeout, malformed-response, cancellation, retry,
  and configuration-change states. Require exact model selection, with explicit manual model entry
  only for providers that report unsupported discovery. Define **Test Connection** as exactly one
  discovery request followed by one minimal `respond` request using the selected model. Never
  silently fall back to generation for discovery or substitute a provider, endpoint, credential,
  or model.
  - Automated regression evidence: deterministic sample tests cover state transitions, retry and
    cancellation, connector replacement after configuration changes, exact selection/manual-entry
    rules, the two-call connection flow, and the no-fallback/no-substitution boundary.
  - Live evidence: an opt-in route must exercise the actual iOS sample against at least two exact,
    explicitly selected models and record discovery, transport, generation, and exact-model
    identity separately. A mocked host or library-only harness does not satisfy this requirement.
  - Runtime evidence: collect normal simulator runtime proof from the normally launched sample.
    Separately, Stage 1 acceptance requires the exact signed sample build to install and launch on
    a physical iPhone, visibly load models, select an exact model, and complete **Test Connection**
    through the sample UI; collect physical-device proof for that interaction. Neither sample route
    proves keyboard extension compatibility; retain a separate application-extension consumer
    build and normal OpenKeyboard extension proof.
- [ ] **Stage 2 — upgrade the existing Android sample.** After Stage 1 acceptance, add
  provider/Gateway configuration plus model discovery/loading, exact selection, and the same
  two-step **Test Connection** flow to the existing deterministic Android sample. Require
  deterministic state/request tests and separate Android emulator and signed physical-device
  lifecycle evidence for installation, launch, cancellation/backgrounding, model loading, and
  connection validation.
- [ ] **Stage 3 — extend Kotlin/JVM and add Compose desktop.** Add the same public discovery,
  exact-model selection, and `respond` flow to the existing Kotlin/JVM console sample, then add a
  Compose desktop sample on macOS, Windows, and Linux. Require shared deterministic contract tests
  plus runtime evidence collected on each matching host; evidence from one desktop OS does not
  stand in for another.
- [ ] **Stage 4 — close shared cross-platform parity.** Across iOS, Android, Kotlin/JVM console,
  and Compose desktop, verify equivalent supported/empty/unsupported/authentication/timeout/
  malformed states, retry and cancellation, connector replacement after configuration changes,
  exact requested/returned model identity, and no provider/model/endpoint/credential fallback or
  substitution. Keep JavaScript, Wasm, and new native targets demand-driven and outside the current
  supported-host plan.
- OpenKeyboard extension adoption follows connector sample confidence. Preserve its independent
  application-extension build, shared-configuration checks, resource measurements, and normal
  extension runtime proof; connector sample parity cannot satisfy those requirements.

---

## Useful source/docs inspected for this refresh

- `OpenKeyboard/OpenKeyboardApp.swift`
- `OpenKeyboard/Models/AppConfig.swift`
- `OpenKeyboard/ViewModels/SettingsViewModel.swift`
- `OpenKeyboard/Views/ContentView.swift`
- `OpenKeyboard/Views/OnboardingView.swift`
- `OpenKeyboard/Views/SettingsView.swift`
- `OpenKeyboardExtension/KeyboardView.swift`
- `OpenKeyboardExtension/KeyboardViewController.swift`
- `OpenKeyboardExtension/KeyboardViewModel.swift`
- `OpenKeyboardExtension/KeyboardAIService.swift`
- `OpenKeyboardExtension/KeyboardToolbarState.swift`
- `OpenKeyboardCore/Sources/OpenKeyboardCore/*`
- `OpenKeyboardCore/Tests/OpenKeyboardCoreTests/*`
- `OpenKeyboardUITests/*`
- `docs/TDD_STATUS.md`
- `docs/WORK_QUEUE.md`
- `docs/KEYBOARD_PRODUCT_COMPLETION_PLAN.md`
- `docs/M2_PROGRESS.md`
- `docs/REAL_EXTENSION_SMOKE_PLAN.md`
- `docs/RELEASE_HARDENING.md`
- `docs/CI_LOG_INDEX.md`
