# Open Keyboard TDD Backend Plan

Goal: lock down the non-UI behavior with tests before building the production UI.

## Approach

Use a Swift Package (`OpenKeyboardCore`) for UI-independent logic so it can be tested quickly with `swift test` and later imported by the iOS app and keyboard extension.

## Test-first milestones

### 1. Shared configuration storage
- [ ] `GatewayConfig` validates gateway URL and API key.
- [ ] `GatewayConfigStore` saves/loads config from an injectable key-value store.
- [ ] Missing/invalid config returns a clear typed error.

### 2. Gateway client contract
- [ ] Builds authorized `/health` and `/v1/models` requests.
- [ ] Maps 200/401/403/429/5xx/network failures to typed errors.
- [ ] Parses model lists from OpenAI-compatible `/v1/models` responses.

### 3. AI writing use cases
- [ ] Define `WritingAction`: continue, rewrite, fix grammar, summarize, translate, custom.
- [ ] Generate deterministic prompts for each built-in action.
- [ ] Build OpenAI-compatible chat completion requests through the gateway.
- [ ] Parse successful chat completion responses.
- [ ] Handle invalid JSON, empty choices, cancellation, timeout, unauthorized, rate limit.

### 4. Keyboard text logic
- [ ] Pure `KeyboardInputReducer` handles character, shift, space, return, delete.
- [ ] Replacement/append strategy for AI actions is deterministic and tested.
- [ ] Context extraction respects configurable character limits.

### 5. Live backend smoke tests
- [ ] Keep unit tests offline and deterministic by default.
- [ ] Add opt-in live tests gated by environment variables:
  - `OPEN_KEYBOARD_LIVE_GATEWAY_URL`
  - `OPEN_KEYBOARD_LIVE_API_KEY`
  - optional `OPEN_KEYBOARD_LIVE_MODEL`
- [ ] Live tests cover health/models/chat action round trip without committing keys.

## Commands

```bash
swift test --package-path OpenKeyboardCore
OPEN_KEYBOARD_LIVE_GATEWAY_URL=http://host.docker.internal:8080 \
OPEN_KEYBOARD_LIVE_API_KEY=... \
swift test --package-path OpenKeyboardCore --filter LiveGatewayTests
```

## Done criteria for this phase

- [ ] Offline test suite passes from Docker/host.
- [ ] At least one live gateway smoke can pass when credentials are supplied.
- [ ] iOS UI remains buildable.
- [ ] No secrets committed.
