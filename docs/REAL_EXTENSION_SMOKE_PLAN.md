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
- Right sparkle lane: generative writing actions. Improve, Rephrase, and Translate belong here. Summarize remains implemented but is intentionally omitted from the visible carousel. Opening the lane selects Improve and immediately makes one Improve request, matching the established keyboard UX. Tapping Rephrase immediately makes one generic rewrite request; tapping a named rewrite style invalidates that request/result and makes one request for the selected style. Translate waits for an explicit target-language choice. A result never replaces text without an explicit user Apply step.

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
  test -f "$SCREENSHOT_DIR/04-real-keyboard-translate-arabic-malayalam.png"
  test -f "$SCREENSHOT_DIR/05-real-keyboard-translate-indian-languages.png"
  echo "Screenshot: $SCREENSHOT_DIR/04-real-keyboard-translate-arabic-malayalam.png"
  echo "Screenshot: $SCREENSHOT_DIR/05-real-keyboard-translate-indian-languages.png"
)
```

Expected pass attachment:

```text
04-real-keyboard-translate-arabic-malayalam.png
05-real-keyboard-translate-indian-languages.png
```

### Focused action carousel layout command

This separate focused route directly seeds the action panel with disposable UI-test gateway placeholders. It does not use real credentials or make a gateway request.

```bash
(
  set -euo pipefail
  SIMULATOR_ID="$(xcrun simctl list devices available | sed -n 's/^[[:space:]]*iPhone 17 Pro (\([0-9A-F-]*\)) (.*$/\1/p' | head -n 1)"
  test -n "$SIMULATOR_ID"
  SCREENSHOT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openkeyboard-action-carousel-smoke.XXXXXX")"
  cleanup_action_carousel_smoke() {
    xcrun simctl spawn "$SIMULATOR_ID" launchctl unsetenv OPEN_KEYBOARD_REAL_SCREENSHOT_DIR >/dev/null 2>&1 || true
  }
  trap cleanup_action_carousel_smoke EXIT

  xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$SIMULATOR_ID" -b >/dev/null
  xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv OPEN_KEYBOARD_REAL_SCREENSHOT_DIR "$SCREENSHOT_DIR"
  xcodebuild test \
    -project OpenKeyboard.xcodeproj \
    -scheme OpenKeyboard \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -configuration Debug \
    -only-testing:OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardActionCarouselScreenshotWhenExplicitlyRequested \
    CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO
  test -f "$SCREENSHOT_DIR/06-real-keyboard-actions-start.png"
  test -f "$SCREENSHOT_DIR/07-real-keyboard-actions-styles.png"
  echo "Screenshot: $SCREENSHOT_DIR/06-real-keyboard-actions-start.png"
  echo "Screenshot: $SCREENSHOT_DIR/07-real-keyboard-actions-styles.png"
)
```

This route proves only that the real extension renders Improve, simple Rephrase, Translate, and the 15 independent rewrite actions in one 44-point horizontal carousel while keeping the bottom controls fixed, Summarize hidden, and contextual sub-carousels absent. Because it directly seeds the action panel, it does not prove the default Improve selection/request, sparkle navigation, gateway availability, a live rewrite response, or Apply behavior. Use `testRealKeyboardExtensionShowsConfiguredAIControlsWhenSharedConfigSeeded` to verify that tapping the real sparkle button opens the panel and immediately enters Improve loading state. That test seeds only a nonblocking background-analysis warning and a nonresponsive reserved test endpoint to prevent unrelated automatic grammar work or a fast transport failure from replacing the observable loading state; it does not seed the action panel, action selection, request, or result.

## Focused Translate screenshot scope

The focused Translate command proves only these visible states:

- Real OpenKeyboard extension can become active from the system/Emoji keyboard path.
- The seeded Translate action panel renders inside the real extension process.
- Translate exposes a 15-language starter catalog—including Arabic, Malayalam, Urdu, Hindi, Bengali, Marathi, Telugu, and Tamil—in a carousel directly above the action carousel without changing the fixed keyboard viewport.
- The fresh Arabic/Malayalam and Indian-language screenshots come from the current test invocation.

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
- the directly seeded Translate panel shows a selected Arabic result with Malayalam immediately visible, the language carousel directly above the Improve/Rephrase/Translate carousel, and fixed bottom controls;
- screenshots `04-real-keyboard-translate-arabic-malayalam.png` and `05-real-keyboard-translate-indian-languages.png` are exported and inspected.

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

## Capability-warning and post-edit typing proof

Capability-sensitive changes additionally run the focused installed-extension test below. It uses a
deterministic debug state for the warning presentation; it does not claim the live low model emitted
that warning during the screenshot run.

```bash
xcodebuild test \
  -project OpenKeyboard.xcodeproj \
  -scheme OpenKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  -only-testing:OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardAutomaticModelFailureKeepsKeysTappable \
  CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO
```

Acceptance requires the real extension to show the nonblocking toolbar warning, preserve the host
document, keep representative letter/space/shift keys hittable, accept a real edit, and retain the
keyboard panel after that edit. Export and inspect both `real-keyboard-automatic-model-warning-keys`
and `real-keyboard-automatic-model-warning-after-edit` attachments. Live transport/model evidence
remains separate through `./scripts/check-live.sh gateway-differential`; Preview Lab is not proof.
