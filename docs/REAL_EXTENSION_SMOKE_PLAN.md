# Real Keyboard Extension Smoke Plan

Last updated: 2026-07-03

## Goal

Keep one focused host-side smoke route that proves the real iOS keyboard extension lifecycle still works:

1. install/enable Open Keyboard in the simulator;
2. focus a real host-app text input;
3. switch from the system keyboard/Emoji keyboard to the real OpenKeyboard extension;
4. verify the left correction status/logo lane and the right sparkle action lane independently;
5. open the real sparkle action menu;
6. capture screenshot proof from the real extension, not Preview Lab or a component harness.

This is not a broad screenshot suite. It is the release-readiness guardrail for third-party keyboard lifecycle, App Group/Keychain config visibility, Full Access behavior, correction status availability, and sparkle action menu availability.

## Toolbar workflow contract

The keyboard toolbar has two independent workflows:

- Left status/logo lane: grammar and typo correction review. The OpenKeyboard logo, issue count badge, and correction status belong to this lane. When correction results exist, tapping it opens the correction review/details flow.
- Right sparkle lane: generative writing actions. Improve, Rephrase, Summarize, and future Translate actions belong here. This lane opens the action/options panel and should not immediately replace text without an explicit user Apply step.

Real-extension proof should keep these lanes separate: a sparkle workflow pass does not prove correction review, and a correction badge pass does not prove Improve/Rephrase actions.

## Current command

Focused host command used by ClawMaster/MCP host verification:

```bash
xcodebuild test \
  -project OpenKeyboard.xcodeproj \
  -scheme OpenKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  -only-testing:OpenKeyboardUITests/AcceptanceScreenshotUITests/testRealKeyboardExtensionLogoActionMenuScreenshotOrExplicitBlocker \
  CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO
```

Expected pass attachment:

```text
acceptance-ui-test-logo-action-menu-real-extension
```

## Current state

The real-extension route should now prove these visible states independently:

- Real OpenKeyboard extension can become active from the system/Emoji keyboard path.
- QWERTY keys are visible in the real extension hierarchy.
- In configured state, the left `keyboard_openkeyboard_icon` status/logo lane is present and enabled.
- The right `ai_sparkle_action` lane is present and opens the generative action panel.
- The sparkle action panel exposes source text plus selectable Improve/Rephrase/Summarize actions.

Historical config-visibility evidence remains useful when diagnosing App Group or gateway seeding regressions:

```text
reports/real-extension-config-seed-legacy-key-20260619T1235/summary.md
reports/real-extension-config-seed-legacy-key-20260619T1235/logs/xcodebuild-real-extension-config-seed-legacy-key.log
.agent/reports/20260619T1212-real-extension-gateway-config-seed/report.md
```

## What counts as acceptance proof

A pass requires all of the following:

- real extension lifecycle, not Preview Lab/component route;
- focused host text input is active;
- OpenKeyboard extension process is active;
- seeded gateway config is visible to the extension;
- the left correction status/logo lane is present and not visually disabled in normal configured state;
- `ai_sparkle_action` or the intended real sparkle action/menu trigger is available;
- sparkle action menu opens with source text and selectable generative actions;
- screenshot attachment `acceptance-ui-test-logo-action-menu-real-extension` is exported.

## What does not count

Do not treat these as acceptance proof:

- `ProductionKeyboardStateHostView` screenshots;
- Preview Lab screenshots;
- direct production-component render routes;
- hidden/reflowed/cropped-only screenshots;
- a disabled `Gateway not configured` toolbar state.

Those can be useful diagnostics only.

## Next diagnostic step

Do not retry the same smoke blindly. Add a DEBUG-only extension-side config probe/blocker attachment that reports redacted key state from inside the keyboard extension process:

- `keyboardExtension.uiTestDebugStateEnabled`;
- gateway URL presence/redacted host;
- selected model;
- `isConfigured` raw value;
- legacy App Group API-key presence only;
- Keychain API-key presence only;
- loaded `AppConfig.isConfigured`;
- current toolbar state.

Then rerun the same focused smoke once. This should distinguish:

- wrong App Group suite;
- seed keys being cleared before extension focus;
- shared Keychain access failure;
- legacy-default fallback failure;
- stale in-memory extension config.

## CI policy

This smoke is host/simulator proof, not default GitHub CI. Normal remote CI should stay deterministic and run:

- `./scripts/ios/test.sh core`
- `./scripts/ios/test.sh build`

Real-extension smoke remains a focused host/manual-gated check until simulator setup, keyboard enablement, and proof attachment export are deterministic in CI.
