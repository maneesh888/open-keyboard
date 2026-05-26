# Open Keyboard

Open Keyboard is an open-source, Grammarly-class AI writing assistant for iOS, delivered through a custom keyboard and paired with a self-hosted LLM Gateway instead of sending typed text to third-party keyboard services.

> Status: early implementation. The iOS app + keyboard extension shell is buildable, and the UI-independent backend core is being developed test-first.

## What it does

Open Keyboard aims to provide a normal iOS typing experience plus high-quality writing assistance:

- Custom iOS keyboard extension for everyday typing.
- AI suggestion bar for context-aware completions.
- Grammarly-level grammar, spelling, clarity, and rewrite assistance.
- Tone transforms such as professional, friendly, concise, assertive, and polished.
- Smart reply drafting, expansion, shortening, and summarization.
- Pairing flow for LLM Gateway URL and API key.
- Self-hosted/local model support through LLM Gateway and Ollama-compatible backends.
- Privacy-first defaults: no hardcoded keys, no bundled secrets, and user-controlled infrastructure.

## Why this exists

Most AI keyboards and writing assistants route private typing data through someone else's cloud. Open Keyboard is for people who want Grammarly-level writing help while keeping control of their gateway, keys, logs, and model backend.

## Current implementation status

### Buildable iOS shell

The project now has a buildable app and keyboard extension shell:

- `OpenKeyboard.xcodeproj`
- iOS host app target
- keyboard extension target
- App Group configuration plumbing
- basic keyboard shell with letters, shift, globe, delete, space, and return
- host app/settings/onboarding scaffolding

Latest known build checkpoint:

```text
Commit: 692adb8 Add buildable keyboard shell
Host build: passed via devtools, run_after=false
```

### Test-first backend core

`OpenKeyboardCore` is a Swift package for UI-independent logic. Current verified host CI result:

```text
Core package tests: 48 passed, 1 skipped, 0 failed
iOS app/extension build: passed
Xcode UI screenshot harness: passed on iPhone 16 and iPhone SE (3rd generation)
Latest CI request: /app/workspace/clawd-coder/requests/clawmaster/2026-05-23T130408-openkeyboard-ui-test-harness.md
```

Covered so far:

- Gateway config validation and normalization
- Gateway config persistence via injectable key-value store
- Authorized `/health` request
- OpenAI-compatible `/v1/models` parsing
- OpenAI-compatible `/v1/chat/completions` request/response handling
- Gateway error mapping: unauthorized, forbidden, rate-limited, server error, unexpected status, invalid response
- Writing action prompt generation
- Prompt edge cases: translate, continue writing, custom templates with/without `{{text}}`
- Keyboard reducer behavior: character input, shift, space, return, delete
- Keyboard edge cases: empty delete, emoji delete, shift persistence
- Context extraction edge cases: over-limit, zero/negative limits, emoji/grapheme-safe suffix
- AI replacement strategies: replace all, append to cursor
- Offline realistic user-flow tests: config validation, model selection, prompt/chat request, and final replacement for grammar, rewrite, summarize, and continue-writing flows
- Opt-in live gateway smoke test scaffold, skipped by default without env vars

Detailed status lives in:

```text
docs/TDD_STATUS.md
docs/TDD_BACKEND_PLAN.md
docs/AI_KEYBOARD_TEST_PLAN.md
docs/AI_KEYBOARD_TODO.md
```

## LLM prompt/performance evaluation status

Current automated tests verify prompt construction and gateway plumbing. They do **not yet** measure LLM quality deeply.

Needed next:

- Golden prompt eval fixtures for grammar, rewrite, summarize, translate, tone, and continuation.
- Rubric-based scoring for meaning preservation, correctness, tone, concision, and “return only the answer”.
- Prompt injection cases where selected text says things like “ignore previous instructions”.
- Regression examples with slang, mixed language, emojis, code snippets, long text, and private-looking content.
- Model comparison across local/cloud models.
- Latency and token/cost tracking when the gateway exposes usage.

Planned docs/tests:

```text
docs/PROMPT_EVALS.md
OpenKeyboardCore/Tests/OpenKeyboardCoreTests/PromptEvaluationFixturesTests.swift
OpenKeyboardCore/Tests/OpenKeyboardCoreTests/LivePromptEvaluationTests.swift
```

Live LLM evals should stay opt-in so normal CI remains deterministic.

## Architecture

```text
iOS Host App
  - onboarding
  - settings
  - gateway URL + API key configuration
  - connection testing

Keyboard Extension
  - custom keyboard UI
  - text insertion/deletion
  - AI suggestion/actions UI
  - reads shared config from App Group

OpenKeyboardCore
  - gateway config validation
  - gateway config persistence abstractions
  - gateway HTTP client
  - writing action prompt builder
  - keyboard reducer/context/replacement logic
  - deterministic unit tests

LLM Gateway
  - authenticates API keys
  - rate limits clients
  - proxies requests to Ollama/LLM backend

Ollama / LLM Backend
  - local or hosted models
```

## Local CI

Primary local check:

```bash
./scripts/local-ci.sh --quick
```

The quick CI path runs:

- Swift package tests for `OpenKeyboardCore`
- iOS simulator build for the app/extension

Docker Coder cannot run Swift/Xcode directly because the Swift toolchain is on the host Mac. Host-side CI is coordinated through ClawMaster request files under:

```text
/app/workspace/clawd-coder/requests/clawmaster/
```

## Live gateway smoke test

Offline tests are deterministic by default. Live tests are skipped unless env vars are set:

```bash
OPEN_KEYBOARD_LIVE_GATEWAY_URL=http://localhost:8080 \
OPEN_KEYBOARD_LIVE_API_KEY=... \
OPEN_KEYBOARD_LIVE_MODEL=... \
swift test --package-path OpenKeyboardCore --filter LiveGatewayTests
```

The live smoke currently covers:

- gateway health
- model list request
- one fix-grammar chat completion round trip

## Roadmap

### Milestone 1 — Buildable shell

- [x] Create `OpenKeyboard.xcodeproj`.
- [x] Add main iOS app target.
- [x] Add keyboard extension target.
- [x] Configure shared App Group plumbing.
- [x] Build host app in Simulator.
- [x] Provide a minimal keyboard that can insert letters, space, return, and delete.

### Milestone 2 — Functional keyboard

- [ ] Complete QWERTY layout.
- [ ] Add symbols and numbers.
- [ ] Improve shift/caps behavior.
- [ ] Add dark mode polish.
- [ ] Add haptics.
- [ ] Improve key press animations and native iOS feel.

### Milestone 3 — Gateway configuration

- [x] Validate gateway URL and API key in core tests.
- [x] Add local config persistence abstraction.
- [x] Test API key request plumbing against LLM Gateway endpoints.
- [ ] Wire host app settings to `OpenKeyboardCore`.
- [ ] Share config safely between host app and keyboard extension.

### Milestone 4 — AI assistance

- [x] Add prompt builder for core writing actions.
- [x] Add gateway chat completion client.
- [ ] Add AI suggestion/action UI.
- [ ] Add rewrite/fix-tone/grammar actions in keyboard extension.
- [ ] Handle loading, rate limits, invalid keys, offline gateway, and Full Access permission states.
- [ ] Add prompt-performance eval suite.

### Milestone 5 — Release polish

- [ ] App icon and screenshots.
- [ ] Onboarding instructions for enabling the keyboard.
- [ ] TestFlight-ready signing and build pipeline.
- [ ] Privacy documentation.

## Privacy and security notes

- API keys must never be committed.
- Production config should stay local to the user/device.
- iOS keyboard extensions require **Full Access** for network calls. Open Keyboard should explain this clearly during onboarding.
- App Group storage is planned for sharing config between the host app and keyboard extension.
- Stronger key storage options should be evaluated before production release.
- Prompt eval fixtures should avoid real private user text.

## LLM Gateway pairing

Open Keyboard is designed to pair with [LLM Gateway](../llm-gateway). The gateway is the required backend layer for authentication, rate limits, model routing, and safe access to Ollama-compatible LLM backends.

Planned pairing flow:

1. User creates an API key in LLM Gateway admin.
2. User enters or scans the gateway URL and API key in Open Keyboard.
3. Open Keyboard tests the key with health/model/chat requests.
4. The host app stores the configuration locally and shares it with the keyboard extension through App Group storage.
5. The keyboard extension uses that gateway pairing for suggestions, rewrites, and writing actions.

## License

This project is released under the MIT License. See [LICENSE](LICENSE).
