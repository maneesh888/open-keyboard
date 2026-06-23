# Open Keyboard Release Hardening

Last updated: 2026-06-19

This checklist tracks the release-risk items that must be solved before Open Keyboard is treated as production-ready.

## UI-test environment injection

The UI test target can run deterministic simulator flows without storing gateway secrets in the repo. Keep live gateway values outside source control and inject them only into the test process.

### Preferred local pattern

1. Build the app/UI-test bundle normally with Xcode or `xcodebuild`.
2. Generate or edit the UI-test `.xctestrun` file on the host machine.
3. Add environment variables under the UI test target only:

```text
OPEN_KEYBOARD_LIVE_GATEWAY_URL=https://<gateway-host>
OPEN_KEYBOARD_LIVE_API_KEY=<ephemeral-test-key>
OPEN_KEYBOARD_LIVE_MODEL=<model-id>
```

4. Run the UI tests from the configured `.xctestrun` file.
5. Save screenshots/logs under `.ci-results/ui/` and do not print API keys in logs.

### Guardrails

- Use a short-lived or low-scope test key when possible.
- Never commit `.xctestrun` files that contain `OPEN_KEYBOARD_LIVE_API_KEY`.
- Redact key values in debug assertions; checking key length/presence is enough.
- Keep normal quick CI deterministic: live flows must skip cleanly when env vars are absent.
- Treat live prompt/UI runs as smoke tests, not as required offline unit-test dependencies.
- UI-test keyboard debug persistence is DEBUG-build gated; production builds must not enable typed/composing text persistence through App Group defaults.

## Full Access and network privacy copy

Apple keyboard extensions need **Allow Full Access** before they can make network requests. Open Keyboard should be explicit and calm about this permission.

Implemented in the current hardening slice:

- Onboarding Step 2 explains: basic typing stays local; AI actions send bounded text/context to the configured gateway.
- Settings includes a Privacy & Full Access section with the same behavior in plain language.
- Keyboard unavailable state explains that Full Access is required only for AI network actions.

Release copy direction:

> Open Keyboard needs Allow Full Access only for AI actions that contact your configured gateway. Normal typing stays local. When you use an AI action, the selected text/context needed for that action is sent to your gateway so the model can respond.

### Privacy commitments for release

- Basic keyboard input/reducer behavior should work without network calls.
- AI actions should send only the selected text and bounded surrounding context needed for the requested action.
- The app should disclose that text sent to the configured gateway is subject to that gateway/model provider's logging policy.
- Gateway API keys must be stored in shared Keychain, not App Group `UserDefaults`.
- Logs, screenshots, and UI-test artifacts must never include raw API keys or full private user text beyond deliberate test fixtures.

## Remaining release blockers

- [x] Move gateway API key storage to shared Keychain access group.
- [x] Add a visible Full Access/network permission state in the app/keyboard UI.
- [x] Wire the privacy copy into onboarding/settings/error states.
- [x] Make UI-test typed/composing debug persistence production-impossible with a DEBUG-build gate.
- [x] Keep local/remote CI entry points documented for deterministic core tests and app/extension build.
- [ ] Run host-side Xcode verification for shared Keychain/app group behavior on simulator before release. Current real-extension smoke still shows `Gateway not configured`; see `docs/REAL_EXTENSION_SMOKE_PLAN.md`.
- [ ] Add DEBUG-only extension-side config probe before retrying logo/action-menu proof, so failures report exact App Group/Keychain/defaults state without exposing secrets.
