# Open Keyboard

Open Keyboard is a privacy-focused, open-source iOS keyboard with AI writing tools, paired with a self-hosted LLM Gateway. Basic typing stays local. When the user chooses an AI action, the keyboard sends the needed text/context to the gateway configured by the user and inserts the model response back into the current app.

> Status: complete working prototype in active hardening. The app, keyboard extension, shared configuration, gateway pairing, grammar correction, and first AI writing tools are implemented and buildable. Current work is focused on keyboard polish, selected-text and paragraph handling, real-device validation, and release preparation.

## Screenshots

Public screenshot assets are served from the project page to keep this repository free of generated image artifacts.

<table>
  <tr>
    <td align="center">
      <img src="https://myadidi.com/projects/open-keyboard-simulator-gateway-ready.png" alt="Open Keyboard app showing verified gateway configuration and selected model." width="180">
      <br>
      <sub>Gateway-ready app state</sub>
    </td>
    <td align="center">
      <img src="https://myadidi.com/projects/open-keyboard-simulator-playground.png" alt="Open Keyboard playground with a text field and custom keyboard extension active." width="180">
      <br>
      <sub>Keyboard playground</sub>
    </td>
    <td align="center">
      <img src="https://myadidi.com/projects/open-keyboard-simulator-grammar-review.png" alt="Open Keyboard grammar review flow with correction suggestions and accept controls." width="180">
      <br>
      <sub>Grammar review</sub>
    </td>
    <td align="center">
      <img src="https://myadidi.com/projects/open-keyboard-simulator-improve-action.png" alt="Open Keyboard AI writing action flow with generated improvement text and action controls." width="180">
      <br>
      <sub>AI writing action</sub>
    </td>
  </tr>
</table>

## What It Does

Open Keyboard is built for people who want AI writing help while keeping control of the client, gateway, keys, model backend, and logging policy.

- Provides a custom iOS keyboard extension for everyday typing.
- Connects to a user-controlled LLM Gateway using a gateway URL and API key.
- Loads the selected model from the configured gateway.
- Separates grammar and typo correction from broader AI writing tools such as Improve, Rephrase, and Summarize.
- Stores the gateway API key in a shared Keychain access group.
- Shares non-sensitive gateway settings with the keyboard extension through App Group storage.
- Supports local/self-hosted model backends through LLM Gateway and Ollama-compatible routes.
- Keeps normal CI deterministic with offline mocks; live model tests are opt-in.

## Why This Exists

Keyboards sit directly in the path of private writing: messages, notes, searches, addresses, work drafts, and personal details. Many AI keyboard products route that text through an app-owned service by default, which means the user has limited control over where text is processed, how requests are logged, and which model provider receives the data.

Open Keyboard is built around a different privacy model. The keyboard client is open source, the backend gateway is user-controlled, and AI routing is explicit. Normal typing stays local. AI actions only run after the user has configured a gateway and enabled the iOS permissions needed for network access.

The goal is not to claim that text never leaves the device. The goal is to put that decision under the user's control: local model, home server, private cloud, or another backend chosen by the user.

## Privacy Model

- The iOS keyboard client is open source and does not include a bundled service endpoint.
- Basic typing does not require network access.
- AI actions require Full Access because iOS keyboard extensions need it for network calls.
- AI-action text is sent to the user-configured gateway, not to a hardcoded third-party keyboard service.
- The user controls gateway deployment, API keys, model backend, and logging policy.
- If the gateway routes to a local model, requests can stay within the user's own device or network.
- If the gateway routes to a hosted model, that provider may still receive the text according to the user's gateway configuration.

## Current Implementation

### iOS App

The host app currently includes:

- onboarding for gateway setup and iOS keyboard enablement
- settings for gateway URL and API key entry
- connection testing against the configured gateway
- model discovery through the gateway
- visible Full Access and privacy copy
- link-out to the gateway admin UI when a gateway URL is configured
- shared Keychain storage for the API key
- App Group storage for gateway URL, selected model, and configured state

### Keyboard Extension

The keyboard extension currently includes:

- SwiftUI keyboard UI
- basic letter, number, symbol, space, return, delete, shift, and globe-key behavior
- Full Access and gateway-configuration state in the toolbar
- separate toolbar workflows for correction review and AI writing actions:
  - grammar and typo correction shows loading, correction suggestions, no-issue results, or recoverable error states.
  - AI writing tools handle Improve, Rephrase, and Summarize without mixing those actions into the correction review flow.
- an AI writing workflow with source text, selectable actions, generated suggestion text, selected operation state, retry, copy, back, and accept controls
- rewrite/improvement options that are shown before replacement, with selected option state
- replacement of the current line/context before the cursor through the replacement planner after the user accepts a selected correction or rewrite
- debug-only state persistence for UI tests

Next focus: broader selected-text, paragraph, and multi-action workflows beyond the current line/context replacement path.

### OpenKeyboardCore

`OpenKeyboardCore` contains UI-independent logic:

- gateway URL/API key validation and normalization
- gateway config persistence abstractions
- OpenAI-compatible `/v1/models` parsing
- OpenAI-compatible `/v1/chat/completions` request/response handling
- typed gateway error mapping
- prompt builders for grammar fixing, rewrite, summarize, translate, continue writing, and custom templates
- keyboard reducer behavior
- context extraction and replacement strategies
- deterministic unit tests

### LLM Gateway

Open Keyboard is designed to pair with LLM Gateway, a separately installed companion backend that:

- authenticates gateway API keys
- applies per-key rate limits
- manages keys through an admin API/UI
- lists available models
- proxies OpenAI-compatible `/v1/*` requests to Ollama-compatible backends
- can route selected models to an optional Apfel backend

The gateway is the trust boundary for model access, API keys, rate limits, logs, and upstream model routing.

## Pairing Flow

1. Run LLM Gateway locally or on a host reachable by the iPhone/simulator.
2. Create an API key in the LLM Gateway admin UI/API.
3. Enter the gateway URL and API key in Open Keyboard settings.
4. Test the connection and load available models.
5. Enable Open Keyboard in iOS Settings.
6. Enable Allow Full Access for AI network actions.
7. Use keyboard AI actions in any app that allows custom keyboards.

## API Contract

Open Keyboard expects the gateway to provide:

```text
GET  /health
GET  /v1/models
POST /v1/chat/completions
```

Authenticated gateway calls use:

```http
Authorization: Bearer <gateway-api-key>
```

The keyboard sends text/context only when an AI action is requested by the user.

## Local CI

Primary local check:

```bash
./scripts/local-ci.sh --quick
```

The quick CI path runs:

- Swift package tests for `OpenKeyboardCore`
- iOS simulator build for the app and keyboard extension

Individual checks:

```bash
./scripts/ios/test.sh core
./scripts/ios/test.sh build
./scripts/ios/test.sh ui
./scripts/ios/test.sh screenshots
```

Live gateway tests are opt-in:

```bash
OPEN_KEYBOARD_LIVE_GATEWAY_URL=http://localhost:8080 \
OPEN_KEYBOARD_LIVE_API_KEY=... \
OPEN_KEYBOARD_LIVE_MODEL=... \
swift test --package-path OpenKeyboardCore --filter LiveGatewayTests
```

Do not commit live keys, local config, `.xctestrun` files containing secrets, or live logs.

## Current Verification

Recent local verification:

- `git diff --check`: passed
- `xcodebuild -scheme OpenKeyboard -destination 'generic/platform=iOS Simulator' -derivedDataPath "${TMPDIR:-/tmp}/openkeyboard-derived" build-for-testing`: passed
- `KeyboardSuggestionModelsTests`: passed
- `KeyboardViewModelActionErrorTests`: passed
- real extension configured smoke test for AI controls: passed

The project still needs broader real-device, live-gateway, prompt-quality, release-signing, and App Store readiness verification before release. See `docs/REAL_EXTENSION_SMOKE_PLAN.md` for the focused simulator smoke route.

## Roadmap

### Keyboard Experience

- [x] Buildable host app and keyboard extension
- [x] Basic typing keys, delete, space, return, shift, number/symbol toggle, and globe-key switching
- [x] Grammar correction review flow in the keyboard extension
- [x] AI writing workflow in the keyboard extension
- [ ] More complete keyboard layout and native-feeling key behavior
- [ ] Haptics, animations, and dark-mode polish
- [ ] Better selected-text and paragraph-level replacement behavior

### Gateway Pairing

- [x] Gateway URL and API key entry
- [x] Connection testing
- [x] Model discovery
- [x] Shared App Group config for non-sensitive settings
- [x] Shared Keychain storage for gateway API key
- [x] Simulator smoke coverage for configured gateway state inside the keyboard extension
- [ ] Broader real-device verification for shared Keychain/App Group behavior

### AI Writing

- [x] Core prompt builders for grammar, rewrite, summarize, translate, continue writing, and custom templates
- [x] Gateway chat-completion client in core
- [x] Extension workflows for grammar correction, Improve/Rephrase, and Summarize
- [x] Suggestion selection, retry, copy, and accept controls for AI-generated writing improvements
- [x] Regression coverage for grammar loading and correction replacement behavior
- [ ] Continue writing and translate actions in the extension UI
- [ ] Broader offline, rate-limit, invalid-key, and guidance polish
- [ ] Prompt-quality evaluation suite
- [ ] Latency and quality checks across local and hosted models

### Release Readiness

- [x] Full Access and network privacy copy in onboarding/settings/keyboard states
- [x] API key migration away from App Group `UserDefaults`
- [x] App icon asset
- [x] Minimal GitHub Actions for core Swift tests and app/extension build
- [ ] TestFlight-ready signing and build pipeline
- [ ] App Store privacy details
- [ ] Real-device testing
- [ ] Public setup guide with gateway hardening notes

## Privacy and Security Notes

- Privacy is centered on user control: the user controls both the keyboard client and the gateway it calls.
- Basic typing should work without network calls.
- AI actions require iOS keyboard Full Access because they call the configured gateway.
- AI actions send the selected text or bounded context needed for that action to the configured gateway.
- Text sent to the gateway is subject to that gateway and model backend's logging policy.
- API keys must never be committed.
- Gateway API keys are stored in shared Keychain, not App Group `UserDefaults`.
- Prompt fixtures, screenshots, logs, and UI-test artifacts should avoid private user text and raw API keys.
- Public gateway deployments need HTTPS, strong admin credentials, protected config files, and careful reverse-proxy rules.

## License

This project is released under the MIT License. See [LICENSE](LICENSE).
