# Prompt Evaluation Suite

Last updated: 2026-05-22

## Purpose

Open Keyboard needs tests that evaluate prompt quality, not just gateway plumbing. Normal CI should stay deterministic and offline, while real LLM quality checks should be opt-in.

## Offline prompt fixtures

Offline fixtures should verify that generated prompts include the right task instructions, preserve user text exactly, and avoid accidental regressions.

Planned coverage:

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
- Checks key rubric constraints such as “preserve meaning” and “return only the answer”.

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

Planned live test file:

```text
OpenKeyboardCore/Tests/OpenKeyboardCoreTests/LivePromptEvaluationTests.swift
```

## CI/logging safety

- Do not print API keys or Authorization headers.
- Do not print full selected/private text in CI logs.
- Store raw logs in `.ci-results/`, which must remain ignored.
- Summarize results in `docs/CI_LOG_INDEX.md`.
