# Real Keyboard Extension Smoke Plan

Last updated: 2026-08-10

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
- Right sparkle lane: generative writing actions. Improve, Rephrase, Summarize, and Translate belong here. Translate requires an explicit target-language choice before requesting output. This lane opens the action/options panel and should not immediately replace text without an explicit user Apply step.

Real-extension proof should keep these lanes separate: a sparkle workflow pass does not prove correction review, and a correction badge pass does not prove Improve/Rephrase actions.

## Current command

Focused host command used by ClawMaster/MCP host verification:

```bash
(
  set -euo pipefail
  SIMULATOR_ID="$(xcrun simctl list devices available | sed -n 's/^[[:space:]]*iPhone 17 Pro (\([0-9A-F-]*\)) (.*$/\1/p' | head -n 1)"
  test -n "$SIMULATOR_ID"
  SCREENSHOT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openkeyboard-translate-smoke.XXXXXX")"
  cleanup_translate_smoke() {
    xcrun simctl spawn "$SIMULATOR_ID" launchctl unsetenv OPEN_KEYBOARD_REAL_SCREENSHOT_DIR >/dev/null 2>&1 || true
  }
  trap cleanup_translate_smoke EXIT

  xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$SIMULATOR_ID" -b >/dev/null
  xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv OPEN_KEYBOARD_REAL_SCREENSHOT_DIR "$SCREENSHOT_DIR"
  xcodebuild test \
    -project OpenKeyboard.xcodeproj \
    -scheme OpenKeyboard \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -configuration Debug \
    -only-testing:OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardTranslateModeScreenshotWhenExplicitlyRequested \
    CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO
  test -f "$SCREENSHOT_DIR/04-real-keyboard-translate-dutch.png"
  echo "Screenshot: $SCREENSHOT_DIR/04-real-keyboard-translate-dutch.png"
)
```

Expected pass attachment:

```text
04-real-keyboard-translate-dutch.png
```

## Focused Translate screenshot scope

The focused command above proves only these visible states:

- Real OpenKeyboard extension can become active from the system/Emoji keyboard path.
- The seeded Translate action panel renders inside the real extension process.
- Translate exposes Dutch, Simplified Chinese, and American English target chips in a language carousel directly above the action carousel without changing the fixed keyboard viewport.
- The fresh `04-real-keyboard-translate-dutch.png` artifact comes from the current test invocation.

Because this test directly seeds the Translate panel, it does not prove QWERTY visibility, the enabled left correction lane, the right `ai_sparkle_action` trigger, or navigation from that trigger into the action panel. Use the broader configured real-extension workflow for those states; do not cite this focused screenshot as proof of them.

Historical config-visibility evidence remains useful when diagnosing App Group or gateway seeding regressions. The original machine-local reports are not repository dependencies; retain only these artifact IDs for traceability:

```text
real-extension-config-seed-legacy-key-20260619T1235
20260619T1212-real-extension-gateway-config-seed
```

## What counts as acceptance proof

A pass of the focused Translate screenshot command requires all of the following:

- real extension lifecycle, not Preview Lab/component route;
- focused host text input is active;
- OpenKeyboard extension process is active;
- the directly seeded Translate panel shows a selected Dutch result, the language carousel directly above the action carousel, and fixed bottom controls;
- screenshot `04-real-keyboard-translate-dutch.png` is exported and inspected.

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
