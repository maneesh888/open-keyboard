# AI Keyboard Project - Current TODO

**Last Updated:** 2026-07-03

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
- [x] Real keyboard Fix Grammar path was previously verified end-to-end through host UI proof.
- [ ] Rewrite and Summarize end-to-end in the actual keyboard — needs verification.
- [ ] Suggestions while typing / suggestion chips — not implemented as a verified product feature.
- [ ] Polished correction preview / accept-dismiss UX — pending.
- [ ] Full release-quality iOS keyboard polish across small/large devices — in progress, not complete.

### AI integration

- [x] Gateway client/config core exists (`GatewayClient`, `GatewayConfig`, `GatewayConfigStore`, `URLSessionHTTPClient`).
- [x] Main app connection testing and model loading exist.
- [x] Keyboard AI service supports Fix Grammar, Rewrite, and Summarize requests.
- [x] Structured suggestion/action result parsing exists.
- [x] Offline prompt/user-flow tests and opt-in live gateway tests exist.
- [ ] Streaming/SSE responses — needs verification; do not assume complete.
- [ ] Debounced suggestions while typing — pending.
- [ ] Timeout/cancellation/network resilience coverage — next queue item, partially present in tests but needs current verification before marking complete.
- [ ] Shared Keychain release hardening and privacy copy — in progress; see `docs/RELEASE_HARDENING.md` and `docs/TDD_STATUS.md`.

### Testing and verification

- [x] Swift package core tests exist under `OpenKeyboardCore/Tests/OpenKeyboardCoreTests`.
- [x] Xcode UI test target exists under `OpenKeyboardUITests`.
- [x] Onboarding screenshot/UI harness exists.
- [x] Real keyboard extension smoke plan exists.
- [x] Local CI/test scripts are documented in repo docs.
- [ ] Current full quick CI/build status — needs fresh verification before release or code work; this doc refresh intentionally ran static inspection only.
- [ ] Real extension logo/action-menu smoke is currently blocked by extension config visibility (`Gateway not configured`), per `docs/REAL_EXTENSION_SMOKE_PLAN.md`.

### Documentation

- [x] TDD/backend status docs exist (`docs/TDD_STATUS.md`).
- [x] Product completion plan exists (`docs/KEYBOARD_PRODUCT_COMPLETION_PLAN.md`).
- [x] Work queue exists (`docs/WORK_QUEUE.md`).
- [x] Release hardening doc exists.
- [x] Prompt eval doc exists.
- [ ] README/setup/troubleshooting/release docs — needs current verification before marking complete.

---

## Current next recommended slice

**Next slice: add DEBUG-only real-extension config-state instrumentation, then rerun the focused real-extension smoke once.**

Why this is the smallest safe next step:

- The current product blocker is narrow: the real extension can activate and show QWERTY keys, but the AI action menu proof is blocked because the extension reports `Gateway not configured`.
- Product code already has the app/extension config pipeline, shared Keychain/App Group pieces, and UI tests; another broad UI redesign or blind smoke retry would not isolate the failure.
- A redacted DEBUG-only config probe can distinguish wrong App Group suite, seed cleanup, Keychain access failure, legacy fallback failure, or stale in-memory config without exposing secrets.
- This directly unblocks the next meaningful product proof: real extension lifecycle + configured AI action menu, not a preview/component route.

Reference plan: `docs/REAL_EXTENSION_SMOKE_PLAN.md`.

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
