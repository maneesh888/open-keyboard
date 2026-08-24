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
- Separates grammar and typo correction from the visible AI writing tools Improve, Rephrase, and Translate; Summarize support remains implemented but is hidden from the keyboard carousel.
- Stores the complete versioned gateway profile (URL, exact model, API key, and validation metadata) as one item in a shared Keychain access group.
- Uses App Group storage only for non-authoritative configured/revision hints and transient connection or UI-test metadata; both production targets load the runtime profile from Keychain.
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
- atomic shared Keychain storage for the complete gateway profile used by both the app and keyboard extension
- migration from earlier split App Group/Keychain profiles without publishing a partially replaced runtime configuration

### Keyboard Extension

The keyboard extension currently includes:

- SwiftUI keyboard UI
- basic letter, number, symbol, space, return, delete, shift, and globe-key behavior
- Full Access and gateway-configuration state in the toolbar
- separate toolbar workflows for correction review and AI writing actions:
  - grammar and typo correction shows loading, correction suggestions, no-issue results, or recoverable error states.
  - AI writing tools expose Improve, simple Rephrase, Translate, and independent rewrite-style actions without mixing them into the correction review flow; Summarize support remains available internally but is omitted from the carousel.
- typed keyboard errors keep gateway transport, authentication, missing-model, and per-operation model-capability failures distinct; an incompatible correction result does not disable unrelated writing actions.
- automatic grammar-analysis failures stay as nonblocking toolbar warnings: the key grid and typed text remain available, and analysis retries after the next edit; manual AI-action failures remain scoped to the action that failed.
- interactive keyboard AI requests stop after 15 seconds, preserve the user's text, and show a retryable timeout instead of leaving the keyboard waiting indefinitely; the Settings model check uses at most two 20-second attempts.
- an AI writing workflow with source text, selectable actions, generated suggestion text, selected operation state, retry, copy, back, and accept controls
- a Translate workflow with explicit Arabic, Dutch, Simplified Chinese, American English, Hindi, Malayalam, Urdu, Bengali, Marathi, Telugu, Tamil, Spanish, French, Portuguese, and Russian target selection before any request is sent
- a single action carousel with Improve, simple Rephrase, Translate, Shorten, Friendly, Formal, Compassionate, Confident, Engaging, Fluent, Diplomatic, Empathetic, Exciting, Cooperative, Assertive, Detailed, Casual, and Professional; only Translate opens a second carousel for target selection
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

The pinned semantic prompt package owns the operation-specific instructions, response contract
metadata, and deterministic message rendering. Open Keyboard owns request transport, local grammar
diffing, response parsing, and UI behavior. Grammar correction returns one complete plain-text
correction with no explicit temperature or response format; the client derives selectable edits
locally. Other structured actions send the package-rendered messages with
`response_format: {"type":"json_object"}` where the selected backend supports it. The gateway is
the trust boundary for model access, API keys, rate limits, logs, and upstream model routing; it
does not inject Open Keyboard prompts or rebuild the message conversation.

### Shared semantic prompt contract

Canonical writing-action and bounded-suggestion semantics live in the pinned
`Vendor/semantic-prompt-contract` Git submodule at contract version `3.1.0`. This path is a checkout
of a separate repository, and the consumer repository's immutable gitlink pins it to one exact
commit/version. `OpenKeyboardCore` consumes its Swift package product, while the app, extension,
and UI tests compile the same generated Swift adapter. UI, request transport, gateway
authentication, model routing, response parsing, and product presentation remain local.

For a fresh checkout, clone with the submodule initialized:

```bash
git clone --recurse-submodules https://github.com/maneesh888/open-keyboard.git
```

For an existing clone, or if `Vendor/semantic-prompt-contract` is empty, recover the pinned checkout
from the OpenKeyboard repository root:

```bash
git submodule update --init --recursive
```

Contract validation requires Git, npm with Node.js `^22.12.0` or `^24.0.0`, and a Swift toolchain
provided by Xcode. Do not edit the vendored checkout directly. Make contract changes in the
standalone `semantic-prompt-contract` repository, validate and version them there, then deliberately
advance this repository's submodule gitlink after reviewing the changelog and
rendering-equivalence fixtures. Run `./scripts/check.sh --full` and the applicable live gateway gate
after an upgrade. Never copy canonical prompt wording back into an OpenKeyboard source file.

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

The quick and full repository checks are deterministic and credential-free. Credential-gated
simulator routes instead read one persistent per-machine file:

```text
<primary-checkout>/.agent/local-seeds/openkeyboard-gateway.env
```

Create it from `scripts/ios/openkeyboard-gateway.seed.env.example` in the primary checkout, set the
file to mode `600`, and keep its current-user-owned directory chain non-writable by group or other
users and free of extended ACL entries. Git-ignored files are not copied into linked worktrees or
synchronized by Git. The live scripts derive the primary checkout from
`git rev-parse --path-format=absolute --git-common-dir`, so
the same canonical file is used from the primary checkout and every linked worktree without copying
credentials. Every machine and clone needs its own file. For cross-machine synchronization, use a
trusted secret manager to materialize the allowlisted values into this path on each machine; never
commit or copy the seed through disposable worktrees.

These commands use the canonical seed and are credential-gated:

```bash
./scripts/check-live.sh gateway
./scripts/check-live.sh gateway-differential
./scripts/ios/test.sh live-gateway-smoke
./scripts/ios/test.sh live-model-differential
./scripts/ios/test.sh real-keyboard-live
```

The seed may contain complete `LOW` and `HIGH` URL/API-key/model triples for targeted model
comparison. Every configured role must be complete, model IDs must pass the strict safety grammar,
and the parser rejects duplicate or unknown variables. Ordinary gateway verification selects the
high profile when present; otherwise it accepts the documented complete legacy triple. It never
silently substitutes the low profile. The committed seed example documents both formats without
containing real endpoints, keys, or model IDs.

`live-model-differential` builds the test artifacts once, runs the deterministic operation-scoped
warning prerequisites once, then executes only the baseline, fixed long-text boundary, and
post-boundary follow-up on isolated low and high profiles. Low success on the boundary is recorded
as diagnostic—not converted into a flaky pass—and exact-head policy rejects it as verified matrix
evidence. High-profile structural success remains independently required. Per-profile wall-clock
latency is retained without response bodies. The same private result bundles retain a sanitized
attachment for each role with separate transport, grammar, rewrite, and translation pass/fail plus
per-capability latency; the live runner validates and reports those fields before deleting the
temporary attachments.

`./scripts/check-live.sh gateway` proves the exact model stored in the seed and rejects silent
catalog fallback. When a task requires a named model, set
`OPEN_KEYBOARD_LIVE_REQUIRED_MODEL=<exact-model-id>`; the check fails before testing if the seed does
not match. Model-specific pull requests must record the required and exact tested model IDs, and a
different working model does not satisfy that evidence.

Changes to model-capability classification, long-input handling, parser compatibility, retry
behavior, automatic-analysis warnings, manual-action error scope, or Translate warning scope use
`./scripts/check-live.sh gateway-differential`. Pre-release verification uses the same targeted
matrix; unrelated pull requests continue to run deterministic checks once and do not run the
matrix.

`OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE` may select another regular, ignored, untracked, private
file, but it must remain under the primary checkout's `.agent/local-seeds/` directory. Direct Swift
package live tests remain opt-in through ephemeral environment variables:

```bash
OPEN_KEYBOARD_LIVE_GATEWAY_URL=http://localhost:8080 \
OPEN_KEYBOARD_LIVE_API_KEY=... \
OPEN_KEYBOARD_LIVE_MODEL=... \
swift test --package-path OpenKeyboardCore --filter LiveGatewayTests
```

Do not commit live keys, local config, `.xctestrun` files containing secrets, or live logs. Missing
seed diagnostics report the dynamically resolved expected path, never values.

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
- [x] Extension workflows for grammar correction, Improve/Rephrase, Summarize, and Translate
- [x] Suggestion selection, retry, copy, and accept controls for AI-generated writing improvements
- [x] Regression coverage for grammar loading and correction replacement behavior
- [x] Translate action with explicit target-language selection in the extension UI
- [ ] Continue writing action in the extension UI
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
