# Prompt Evaluation Suite

Last updated: 2026-08-12

## Purpose

Open Keyboard needs tests that evaluate prompt quality, not just gateway plumbing. Normal CI should stay deterministic and offline, while real LLM quality checks should be opt-in.

## Offline prompt fixtures

Offline fixtures should verify that generated prompts include the right task instructions, preserve user text exactly, and avoid accidental regressions.

Deterministic coverage:

- Grammar correction
- Rewrite for clarity
- Summarization
- Translation
- Continue writing
- Custom templates
- Prompt-injection strings embedded in selected text

Offline fixture tests should live in:

```text
OpenKeyboardCore/Tests/OpenKeyboardCoreTests/PromptEvaluationFixturesTests.swift
```

Acceptance:

- No network calls.
- No real private user text.
- Stable pass/fail behavior in normal CI.
- Proves every built-in prompt requests exactly one JSON object with the canonical result contract.
- Checks operation-specific rules, including granular grammar items, meaning preservation,
  facts-only summaries, translation fidelity, and continuation-only output.

## Playground and smoke phrase fixtures

The curated playground and gateway smoke phrases must be synthetic and meaningful enough to demonstrate grammar correction, Improve, and Rephrase behavior. Each phrase should:

- be long enough to show a real rewrite, not just a tiny typo fix.
- include multiple obvious spelling typos.
- include at least one grammar mistake.
- avoid real private user text, secrets, credentials, or production conversation content.

## Live prompt evals

Live prompt evals should be skipped unless explicit env vars are set:

```bash
OPEN_KEYBOARD_LIVE_GATEWAY_URL=... \
OPEN_KEYBOARD_LIVE_API_KEY=... \
OPEN_KEYBOARD_LIVE_MODEL=... \
swift test --package-path OpenKeyboardCore --filter LivePromptEvaluationTests
```

Live evals should track:

- response quality
- meaning preservation
- whether the model added unwanted explanation
- prompt-injection resistance
- model name
- latency
- token usage/cost if the gateway exposes usage

Implemented live test file:

```text
OpenKeyboardCore/Tests/OpenKeyboardCoreTests/LivePromptEvaluationTests.swift
```


Current live harness coverage:

- Grammar correction sanity check.
- Gemma-specific complete plain-text multi-error grammar correction checks.
- Gemma-specific valid structured JSON checks for rewrite, summarize, translate, and continue writing.
- Rewrite clarity sanity check.
- Prompt-injection-as-input summarization check.
- Broad latency budget tracking per scenario.
- Forbidden phrase checks for meta commentary, auth/API-key leakage, and obvious instruction leakage.

The shared live scenarios intentionally use broad assertions because model output is non-deterministic.
The Gemma cases add a stable minimum-detail rubric and skip when the configured model is not Gemma.
Normal CI compiles the file and skips live execution unless all live env vars are set.

Live eval fixtures must use synthetic, non-sensitive text only. Do not add real private user text, secrets, API keys, Authorization headers, or production conversation content to live eval scenarios.

## CI/logging safety

- Do not print API keys or Authorization headers.
- Do not print full selected/private text in CI logs.
- Store raw logs in `.ci-results/`, which must remain ignored.
- Summarize results in `docs/CI_LOG_INDEX.md`.
