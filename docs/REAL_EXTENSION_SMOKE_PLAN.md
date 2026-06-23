# Real Keyboard Extension Smoke Plan

Last updated: 2026-06-19

## Goal

Keep one focused host-side smoke route that proves the real iOS keyboard extension lifecycle still works:

1. install/enable Open Keyboard in the simulator;
2. focus a real host-app text input;
3. switch from the system keyboard/Emoji keyboard to the real OpenKeyboard extension;
4. open the real AI logo/action menu;
5. capture screenshot proof from the real extension, not Preview Lab or a component harness.

This is not a broad screenshot suite. It is the release-readiness guardrail for third-party keyboard lifecycle, App Group/Keychain config visibility, Full Access behavior, and AI action menu availability.

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

The switcher blocker has been narrowed:

- Real OpenKeyboard extension can become active from the system/Emoji keyboard path.
- QWERTY keys are visible in the real extension hierarchy.
- `ai_toolbar` appears as disabled Button elements in current failing proof runs.

Current blocker:

```text
The real extension still reports `Gateway not configured`; `ai_sparkle_action` is absent, so the logo/action menu cannot open.
```

Latest evidence:

```text
reports/real-extension-config-seed-legacy-key-20260619T1235/summary.md
reports/real-extension-config-seed-legacy-key-20260619T1235/logs/xcodebuild-real-extension-config-seed-legacy-key.log
```

Coder report:

```text
.agent/reports/20260619T1212-real-extension-gateway-config-seed/report.md
```

## What counts as acceptance proof

A pass requires all of the following:

- real extension lifecycle, not Preview Lab/component route;
- focused host text input is active;
- OpenKeyboard extension process is active;
- seeded gateway config is visible to the extension;
- `ai_sparkle_action` or the intended real action/menu trigger is available;
- action menu opens;
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
