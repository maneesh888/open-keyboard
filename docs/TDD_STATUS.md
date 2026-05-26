# Open Keyboard TDD Status

Last updated: 2026-05-22

## Local CI

Host command:

```bash
./scripts/local-ci.sh --quick
```

Current verified host result:

- Core package tests: 48 passed, 1 skipped, 0 failed
- iOS app/extension build: passed
- Onboarding first-page visual verification: passed on iPhone 16 simulator
- Xcode UI screenshot harness: passed on iPhone 16 and iPhone SE (3rd generation)
- Latest verified ClawMaster request: `/app/workspace/clawd-coder/requests/clawmaster/2026-05-23T130408-openkeyboard-ui-test-harness.md`

## Completed TDD slices

- [x] `OpenKeyboardCore` Swift package scaffold
- [x] `GatewayConfig` validation and normalization
- [x] `GatewayConfigStore` injectable key-value persistence
- [x] Local CI runner inspired by Just Spent
- [x] `GatewayClient` request building and status-code error mapping
- [x] `/health` request/auth test
- [x] `/v1/models` parsing test
- [x] Writing action prompt builder
- [x] `/v1/chat/completions` request/response tests
- [x] Pure keyboard reducer for character/shift/space/return/delete
- [x] Keyboard reducer edge cases: shift persistence, empty delete, emoji delete
- [x] Context-before-cursor extraction
- [x] Context edge cases: over-limit, zero/negative limits, emoji/grapheme-safe suffix
- [x] AI text replacement strategies
- [x] Realistic offline user-flow tests: config/model/prompt/chat/replacement flows
- [x] Gateway edge cases: 403, unexpected status, invalid health JSON
- [x] Prompt edge cases: translate, continue-writing, custom template without placeholder
- [x] Offline prompt evaluation fixture tests
- [x] Onboarding first-page layout fix verified by simulator screenshot
- [x] Xcode UI test target and screenshot harness for iPhone 16 + iPhone SE

## Live smoke scaffold

- [x] `URLSessionHTTPClient`
- [x] Opt-in `LiveGatewayTests` compile and skip cleanly without env vars

## Live gateway smoke test

Offline tests remain deterministic by default. Live tests are skipped unless these env vars are set:

```bash
OPEN_KEYBOARD_LIVE_GATEWAY_URL=http://localhost:8080 \
OPEN_KEYBOARD_LIVE_API_KEY=... \
OPEN_KEYBOARD_LIVE_MODEL=... \
swift test --package-path OpenKeyboardCore --filter LiveGatewayTests
```

The live smoke covers:

- gateway health
- model list request
- one fix-grammar chat completion round trip

## Next TDD TODO

1. Add before/after cursor context and replacement range tests.
2. Add prompt quality/performance eval docs and offline fixtures.
3. Add opt-in live prompt eval tests for real LLM quality/model comparison/latency.
4. Add timeout, cancellation, offline/network resilience tests.
5. Wire app/extension code to consume `OpenKeyboardCore` only after backend tests stay green.
