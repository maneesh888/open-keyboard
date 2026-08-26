# Keyboard Extension Evidence Plan

Last updated: 2026-08-26

## Purpose

This plan keeps automated real-extension regression evidence separate from final runtime proof.
The existing XCTest/XCUITest commands remain useful and unchanged, but none of them is normal
simulator or physical-device proof.

## Evidence classes

### Automated real-extension regression evidence

This class includes unit tests, XCTest, XCUITest, mocked or credentialed gateway tests, debug launch
states, seeded loading/success/warning/failure states, component hosts, and `XCTAttachment`
screenshots. It may install, activate, and exercise the real keyboard extension process. It proves
only the behavior asserted by the automated route.

Do not call an XCUITest screenshot “manual simulator proof” or “normal simulator runtime proof.” A
test-seeded result panel proves that the panel can render; it does not prove that a production
request produced the result.

### Normal simulator runtime proof

This class uses a normally installed and launched app and bundled extension. It has no
`--uitesting`, debug-state injection, seeded result panel, component host, or test-host shortcut.
The operator focuses an ordinary host-app text field, activates OpenKeyboard through the normal
keyboard lifecycle, invokes an action through visible production UI, and captures screenshots
directly from Simulator/Xcode outside XCTest.

Use the configured live gateway when verifying semantic behavior. This is the minimum final proof
before pushing changes that affect UI, extension lifecycle, Apply/Copy/Back/Rerun behavior, live
gateway behavior, or result presentation.

### Physical-device proof

This class requires the exact signed build installed on the configured physical device. Exercise
the normal keyboard-extension lifecycle and capture screenshots directly from the device.
Simulator or XCTest evidence cannot satisfy a physical-device requirement.

## Toolbar workflow contract

The keyboard toolbar has two independent workflows:

- Left status/logo lane: grammar and typo correction review. The OpenKeyboard logo, issue count
  badge, and correction status belong to this lane. When correction results exist, tapping it opens
  the correction review/details flow.
- Right sparkle lane: generative writing actions. Improve, Rephrase, and Translate belong here.
  Summarize remains implemented but is intentionally omitted from the visible carousel. Translate
  requires an explicit target-language choice before requesting output. This lane opens the
  action/options panel and must not replace text without an explicit Apply action.

A sparkle workflow pass does not prove correction review, and a correction badge pass does not
prove Improve/Rephrase/Translate behavior.

## Automated real-extension regression routes

The preserved command `./scripts/ios/test.sh real-keyboard-live` runs credentialed XCUITest against
an installed real extension on a disposable simulator. It provides automated lifecycle,
request/response, and replacement regression evidence. Because XCTest controls the run and the
route injects configuration, it is not final runtime proof.

```bash
./scripts/ios/test.sh real-keyboard-live
```

### Focused Translate screenshot regression command

This preserved XCUITest recipe directly seeds the Translate action panel. Its screenshots are
automated regression artifacts, not normal simulator runtime proof.

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
  echo "Automated regression artifact: $SCREENSHOT_DIR/04-real-keyboard-translate-arabic-malayalam.png"
  echo "Automated regression artifact: $SCREENSHOT_DIR/05-real-keyboard-translate-indian-languages.png"
)
```

### Focused action-carousel screenshot regression command

This preserved XCUITest recipe directly seeds the action panel and makes no gateway request. It is
automated layout regression evidence only.

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
  echo "Automated regression artifact: $SCREENSHOT_DIR/06-real-keyboard-actions-start.png"
  echo "Automated regression artifact: $SCREENSHOT_DIR/07-real-keyboard-actions-styles.png"
)
```

The focused installed-extension screenshot command is also automated regression evidence:

```bash
xcodebuild test \
  -project OpenKeyboard.xcodeproj \
  -scheme OpenKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  -only-testing:OpenKeyboardUITests/AcceptanceScreenshotUITests/testRealKeyboardExtensionLogoActionMenuScreenshotOrExplicitBlocker \
  CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO
```

Focused Translate and action-carousel XCUITests may seed panels and export
`04-real-keyboard-translate-arabic-malayalam.png`,
`05-real-keyboard-translate-indian-languages.png`, `06-real-keyboard-actions-start.png`, or
`07-real-keyboard-actions-styles.png`. Label these as `XCTAttachment` automated regression
artifacts. They can prove layout assertions inside the installed extension process, but not sparkle
navigation, production gateway output, Apply behavior, or normal simulator acceptance.

The capability-warning/post-edit XCUITest is likewise diagnostic automated evidence because it
uses deterministic debug state:

```bash
xcodebuild test \
  -project OpenKeyboard.xcodeproj \
  -scheme OpenKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  -only-testing:OpenKeyboardUITests/KeyboardExtensionConfiguredUITests/testRealKeyboardAutomaticModelFailureKeepsKeysTappable \
  CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO
```

Live transport/model checks remain separate automated evidence through
`./scripts/check-live.sh gateway` or `./scripts/check-live.sh gateway-differential`.

## Normal simulator runtime procedure

Use a clean simulator appropriate to the change and the exact commit intended for push.

1. Build and install the app normally from Xcode using the required build configuration. Do not
   pass `--uitesting` or any debug-state/result-seeding arguments.
2. Launch OpenKeyboard normally. Configure the gateway through the production settings UI when
   semantic behavior is in scope. Never expose the key or private endpoint in proof artifacts.
3. Enable OpenKeyboard through normal Simulator Settings if needed.
4. Open an ordinary host app with a text field, focus it, and switch to OpenKeyboard using the
   system keyboard control.
5. Enter the recorded source text and invoke the requested action through visible production UI.
6. For result workflows, exercise the affected controls—Apply, Copy, Back, and Rerun as applicable—
   and verify the host text and presented state after each action.
7. Capture screenshots directly with Simulator/Xcode or `xcrun simctl io <udid> screenshot
   <non-repo-path>`. Do not export the screenshots from an `.xcresult`.
8. Inspect screenshots for credentials, private gateway configuration, and unrelated private
   content before sharing them.

### Required runtime record

Record all of the following:

```text
Evidence class: normal simulator runtime proof
Git SHA: <full SHA>
Build configuration: <Debug/Release>
Simulator model: <model>
OS version: <version>
Action performed: <action and controls exercised>
Source text: <deliberate non-private fixture>
Observed result: <exact visible behavior>
Gateway semantic check: <not required | model/behavior accepted without secrets>
Screenshots: <direct Simulator/Xcode artifact paths or attachments>
```

Expected screenshots for a keyboard action are:

- ordinary host-app text field with OpenKeyboard active before invoking the action;
- visible production result panel after the live request, when a result is expected;
- final host text or state after Apply/Copy/Back/Rerun, as applicable.

The screenshots and record must bind to the same exact Git SHA. Report transport success,
semantic acceptance, and visual/runtime acceptance separately.

## Manual handoff when Codex cannot verify runtime

If normal simulator control is unavailable, unreliable, or the observed result is ambiguous, stop
before push/readiness and ask the user to perform this exact checklist:

1. Install and normally launch the exact-SHA build without test arguments.
2. Open an ordinary host-app text field and activate OpenKeyboard through the system keyboard UI.
3. Enter the supplied non-private source text and invoke the specified production action.
4. Exercise the specified Apply/Copy/Back/Rerun controls and note the exact observed result.
5. Send the three direct screenshots listed above plus simulator model, OS version, build
   configuration, and exact Git SHA.

Do not run more XCTest as a substitute for the missing runtime proof.

## Physical-device procedure

Install the exact signed build on the configured device and repeat the ordinary host-app lifecycle.
Capture the corresponding before/result/after screenshots directly from the device and record the
device model and OS version. If the device or signed build is unavailable, label physical-device
proof `BLOCKED` and request manual verification; Simulator evidence cannot close the gap.

## Push and readiness policy

Automated tests remain required in addition to runtime proof. Local implementation and commits may
proceed after deterministic tests. For proof-sensitive changes, do not push or create/update a
readiness PR until normal simulator runtime proof succeeds unless the user explicitly authorizes a
push with the missing proof disclosed. Such authorization does not make the proof verified.

Never mark a PR ready or merge while required normal simulator or physical-device proof is missing.

## Historical evidence boundary

Historical XCUITest request IDs and screenshots remain useful for regression diagnosis only. For
example, `real-extension-config-seed-legacy-key-20260619T1235` and
`20260619T1212-real-extension-gateway-config-seed` are automated evidence references, not current
normal runtime proof.
