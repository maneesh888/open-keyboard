# Open Keyboard Release Hardening

Last updated: 2026-06-08

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

## Full Access and network privacy copy

Apple keyboard extensions need **Allow Full Access** before they can make network requests. Open Keyboard should be explicit and calm about this permission.

### In-app/onboarding copy

Suggested copy:

> Open Keyboard needs Allow Full Access only for AI actions that contact your configured gateway. Normal typing stays local. When you use an AI action, the selected text/context needed for that action is sent to your gateway so the model can respond.

### Settings/help copy

Suggested copy:

> Your gateway URL and API key are used to call your own LLM gateway. Open Keyboard does not need Full Access for basic typing, but iOS requires Full Access for the keyboard extension to reach the network. Disable Full Access anytime to stop network AI actions.

### Error copy when Full Access/network is unavailable

Suggested copy:

> AI actions need Full Access and a reachable gateway. Enable Allow Full Access in iOS Keyboard Settings, then check your gateway URL/API key.

### Privacy commitments for release

- Basic keyboard input/reducer behavior should work without network calls.
- AI actions should send only the selected text and bounded surrounding context needed for the requested action.
- The app should disclose that text sent to the configured gateway is subject to that gateway/model provider's logging policy.
- Gateway API keys must move from App Group `UserDefaults` to shared Keychain before release.
- Logs, screenshots, and UI-test artifacts must never include raw API keys or full private user text beyond deliberate test fixtures.

## Remaining release blockers

- [ ] Move gateway API key storage to shared Keychain access group.
- [ ] Add a visible Full Access/network permission state in the app/keyboard UI.
- [ ] Wire the privacy copy into onboarding/settings/error states.
- [ ] Keep UI-test env injection documented in the local CI guide once the host `.xctestrun` command is finalized.
