# Open Keyboard TDD Status

Last updated: 2026-06-07

## Local CI

Host command:

```bash
./scripts/local-ci.sh --quick
```

Current verified host result:

- Focused `KeyboardContextTests`: 12 tests, 0 failed
- Core package tests: 61 executed, 2 skipped live tests, 0 failed
- iOS app/extension build: passed on iPhone 16
- Xcode UI screenshot harness: passed on iPhone 16 and iPhone SE (3rd generation) in the previous foundation slice
- Latest full quick-CI ClawMaster request: `/app/workspace/clawd-coder/requests/clawmaster/2026-05-28T124406-openkeyboard-context-regression-verify.md`
- Latest real keyboard functional ClawMaster request: `/app/workspace/clawd-coder/requests/clawmaster/20260606T022442-openkeyboard-uitest-debug-flag-rerun.md`
- Real keyboard Fix Grammar UI test: passed against temp LLM Gateway; final host text `I have an apple.`; gateway POST observed; injected URL/key debug assertions passed without printing secrets

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
- [x] Opt-in `LivePromptEvaluationTests` scaffold for grammar/rewrite/prompt-injection live quality checks
- [x] Onboarding first-page layout fix verified by simulator screenshot
- [x] Xcode UI test target and screenshot harness for iPhone 16 + iPhone SE
- [x] Real keyboard-extension Fix Grammar functional UI test path with injected gateway credentials

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

1. Expand prompt quality/performance eval fixtures and rubric coverage.
2. Run opt-in live prompt evals against a configured gateway/model and record results.
3. Move gateway API key sharing from App Group `UserDefaults` to shared Keychain before release.
4. Wire the documented Full Access/network privacy copy into onboarding/settings/error states.
5. Add remaining rewrite/fix-tone/summarize/continue keyboard actions after Fix Grammar stabilizes.

## Release-hardening docs

Added `docs/RELEASE_HARDENING.md` with:

- UI-test `.xctestrun` environment-injection guardrails for live gateway URL/API key/model values.
- Full Access/network privacy copy for onboarding, settings/help, and unavailable-network error states.
- Release privacy commitments and remaining blockers, including shared Keychain migration for gateway API keys.

## Completed slice: context and replacement ranges

Added an initial `KeyboardDocumentContext` / replacement strategy slice for realistic keyboard behavior:

- before-cursor + selected-text + after-cursor document context
- bounded after-cursor extraction
- insert-at-cursor and selected-text replacement
- last sentence and last paragraph replacement
- completed-final-sentence regression coverage
- emoji/grapheme-safety tests

Host Swift validation passed through direct ClawMaster host-path requests. The devtools `ai-keyboard` project mapping still points to a stale/missing host path and should be repaired separately; it is not a code validation blocker for this slice.
