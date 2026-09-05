# Plain-Text Writing Responses Migration Plan

## Status

Planned. This document defines the work needed to stop requesting structured model responses for
Summarize, Translate, and Continue Writing. It does not implement the migration.

## Objective

Make every built-in writing action return only the user-visible text it produces. After the
migration, Grammar, Rewrite, Improve, Summarize, Translate, and Continue Writing must omit
`response_format` from gateway requests. No active writing-action prompt may ask the model to
construct the legacy result envelope.

This is a response-contract change, not a requirement to make every user message raw text. The
contract may continue JSON-encoding source text and validated operation parameters inside the
prompt when that provides a clear prompt-injection and parameter boundary.

## Current state and reason for the change

The semantic contract's pack-level default is `json_object`. Grammar, Rewrite, and Improve override
that default with `plain_text`; Summarize, Translate, and Continue Writing inherit it. The generated
adapter exposes `responseFormatType: "json_object"`, and both gateway clients convert that metadata
into `response_format: {"type":"json_object"}`.

The remaining structured envelope is not required by the product UI. These operations ultimately
consume one summary, translation, or continuation string. JSON mode adds provider-compatibility,
token, latency, parsing, and malformed-envelope failure risks without enforcing the package's JSON
Schema at transport time.

This is also a prerequisite for the planned Universal AI Connector migration. That connector's
generic response contract supports plain text and strict JSON Schema, but OpenKeyboard's legacy
`json_object` mode was a separate compatibility gap. Converting these operations to validated plain
text removes the reason to add generic JSON-object mode solely for OpenKeyboard. Strict JSON Schema
must not be substituted for the old envelope: the intended result is plain text, not a different
structured transport contract.

## In scope

- `summarize`, `translate`, and `continue_writing` response semantics in the canonical contract.
- Operation-specific plain-text prompts and validation policies.
- Generated JavaScript, Swift, browser, fixture, schema, and diagnostic metadata.
- OpenKeyboardCore and keyboard-extension request construction and response parsing.
- Settings diagnostics, live harnesses, deterministic tests, live model evaluation, and relevant
  documentation.
- Removal of the gateway client's implicit rule that a non-empty operation means JSON output.
- An intentional decision on whether the now-unused writing-action response schema is deleted or
  retained only as explicitly deprecated compatibility material.

## Out of scope

- The separately defined keyboard-suggestions response contract.
- Streaming, the proposed Gateway V2 protocol, provider-native JSON Schema output, and tool calls.
- UI redesign, action ordering, model selection, gateway routing, authentication, or persistence.
- Adding Continue Writing to the visible extension UI.
- Physical-device interaction unless separately requested.

## Universal AI Connector alignment

This section records the cross-repository decisions relevant to this response migration. It does
not activate the connector integration or duplicate the connector repository's implementation
roadmap. The semantic-contract release and OpenKeyboard adoption in this plan must complete first;
the later connector migration can then consume the same plain-text behavior without an
OpenKeyboard-specific response mode.

### Ownership boundaries

- `semantic-prompt-contract` remains the only owner of writing-operation identifiers, prompts,
  parameters, output instructions, validators, examples, and fixtures.
- Universal AI Connector owns provider-neutral transport, provider adapters, model discovery,
  public timeout configuration, cancellation, and stable technical errors. It must remain generic
  and must not contain OpenKeyboard operation names, prompts, UI behavior, persistence, or
  user-facing error copy.
- OpenKeyboard owns settings and model-selection UI, App Group and Keychain persistence,
  configuration reload, semantic prompt rendering, response validation, retry policy, result
  presentation, and mapping typed connector errors to user-visible actions.
- Existing settings screens, saved profiles, selected-model behavior, configuration sharing, and
  keyboard action UX must remain behaviorally compatible through the later connector migration.

### Follow-on connector integration decisions

- Map every built-in writing action to the connector's plain-text response mode. Preserve the exact
  rendered system/user messages and validate the returned text through the semantic contract; do
  not rebuild prompts or writing-result parsers inside the connector.
- Put a narrow connector-backed client behind both Settings diagnostics and
  `KeyboardAIService`. Reuse one connector instance per gateway identity and close/replace it when
  the saved URL, credential, or provider profile changes; do not construct a connector for every
  action or grammar chunk.
- Add provider-neutral `listModels(providerId)` behavior to the connector's Kotlin API and an
  equivalent Swift `async` API for OpenAI, Anthropic, OpenRouter, and configured OpenAI-compatible
  providers. Each provider adapter owns its endpoint, headers, pagination, deterministic ordering,
  duplicate handling, bounds, cancellation, response translation, and typed
  unsupported-discovery result.
- Make one successful `listModels` call the connection/discovery phase. Do not require a universal
  `/health` endpoint and do not use generation as a silent discovery fallback. In OpenKeyboard,
  remove the current duplicate model-list request, populate/validate the model picker from that one
  result, then retain the existing minimal grammar request through `respond` to prove the selected
  model can actually generate before saving a trusted configuration. A compatible gateway that
  explicitly lacks discovery may support manual model entry through a separate product decision,
  but discovery failure must not be treated as a successful connection.
- Expose the connector's connect and whole-request timeouts consistently to Kotlin and Swift with
  validated defaults of 10 and 60 seconds respectively, and apply that policy to discovery,
  response, and streaming. Preserve OpenKeyboard's explicit action-level timeout/retry behavior
  until parity evidence justifies any change.
- Keep generic authentication, permission, rate-limit, timeout, transport, malformed-response,
  unsupported-discovery, and cancellation classification in the connector. Keep save eligibility,
  field state, retry controls, logging, and user-facing copy in OpenKeyboard.
- Integrate from a pinned source revision with a reproducible local XCFramework/Swift-package
  bootstrap while formal release assets are unavailable; a connector P8 release is not a blocker.
  Keep generated binary artifacts out of Git. Treat iOS Simulator `x86_64` support as lower
  priority than ARM64 consumer and connection-validation support unless OpenKeyboard's supported
  architecture policy makes it a release gate.

### Follow-on parity and extension evidence

- Exercise equivalent provider configuration, timeout defaults, model discovery, model selection,
  response, typed-error, cancellation, and cleanup behavior through the connector's JVM, Android,
  and iOS sample apps using only public APIs and shared deterministic fixtures.
- Keep a separate minimal iOS application-extension consumer build. An iOS app sample proves the
  Swift façade but does not prove custom keyboard-extension compatibility.
- Before removing OpenKeyboard's legacy chat transport, prove request/result parity for Settings
  smoke tests and keyboard actions, concurrent grammar chunks, connector replacement after config
  changes, invalid credentials, unavailable models, rate limits, timeout, cancellation, malformed
  output, truncation, and permitted URL behavior.
- Measure the final keyboard extension's linked size, startup latency, and memory use. Verify every
  supported app/extension architecture, then collect the normal extension runtime proof required
  by the repository workflow.

## Target response contracts

### Summarize

- Return one complete summary and nothing else.
- Reject empty output, JSON objects/arrays, Markdown fences, labels, commentary, and raw errors.
- Permit output much shorter than the source; do not reuse Rewrite length or overlap thresholds.
- Define explicit behavior for already-short input instead of blindly rejecting unchanged text.
- Keep prompt-injection cases in deterministic fixtures and live evaluation.

### Translate

- Return only the complete translation.
- Preserve paragraph boundaries, punctuation, numbers, URLs, email addresses, emoji, and Markdown
  link destinations where applicable.
- Do not require source-language word overlap.
- Retain the extension's target-language/script validation and two-attempt reliability policy.
- Treat unchanged output as valid only when the source is already naturally in the target language.
- Convert validation failures into the existing operation-scoped translation capability warning;
  never expose raw JSON or gateway errors as replacement text.

### Continue Writing

- Return only newly generated continuation text.
- Reject output that repeats or wraps the complete source, plus JSON, Markdown fences, commentary,
  and raw errors.
- Define bounded expansion rules independently of complete-replacement validation.
- Preserve the existing append/continuation behavior in OpenKeyboardCore user-flow tests.

## Implementation sequence

### Phase 1: change the canonical semantic contract

1. Work in the `semantic-prompt-contract` repository first.
2. Add plain-text output instructions for the three operations while retaining JSON-safe source and
   parameter encoding where useful.
3. Set each operation's `response_format` to `plain_text`; ensure rendered response-format and
   response-schema metadata are `nil`/`null`.
4. Introduce distinct validation modes or profiles for summary, translation, and continuation.
   Avoid encoding semantic quality as brittle generic length or word-overlap heuristics.
5. Update the contract schema so every new validation field and mode is canonical and validated.
6. Change result metadata consistently. If `result_types` describes transport shape, use
   `plain_text`; if it describes semantic intent, rename or document it so diagnostics cannot
   confuse those concepts.
7. Replace structured gateway presets and valid-response fixtures with plain-text fixtures.
8. Add invalid fixtures for JSON-shaped output, fenced output, commentary, raw errors, truncation,
   unsafe token loss, wrong-language translation, source repetition, and empty output.
9. Regenerate Swift and browser adapters; do not hand-edit generated sources.
10. Remove the writing-action response schema if it has no remaining consumer. If compatibility
    requires retaining it temporarily, mark it legacy and prove that no current rendering or
    preset references it.
11. Classify and publish the change as a semantic-contract major release because observable request
    and response shapes change.

### Phase 2: adopt the contract in OpenKeyboard

1. Advance the pinned submodule gitlink intentionally to the tested contract release.
2. Update `WritingAction.requiresStructuredJSON`; remove it if it is only redundant metadata.
3. Make `GatewayClient` derive the request solely from rendered response-format metadata. All six
   built-in writing actions must encode no `response_format` field.
4. Replace structured parsing for Summarize, Translate, and Continue Writing with contract-owned
   plain-text validation and locally constructed result objects.
5. Update `CanonicalGatewayClient` so an omitted response-format argument does not infer JSON from
   the presence of `operation`. Prefer an explicit optional transport format derived from contract
   metadata over the current optional Boolean.
6. Route `KeyboardAIService` through the new validators. Preserve translation retry and language
   checks, and map invalid output to existing scoped user-facing errors.
7. Remove `RawWritingActionResult`, `isStructuredResponse`, warning-item handling, and JSON aliases
   only after confirming they have no other active consumer. Do not remove the separate keyboard
   suggestions parser.
8. Update Settings diagnostics and the live AI harness to validate the actual plain-text contracts.
9. Update README and prompt-evaluation documentation so they no longer describe mixed writing
   response formats.

### Phase 3: deterministic verification

- In the contract repository: run `npm ci`, `npm run generate`, `npm run check`, and `swift test`.
- Inspect every rendering golden and generated-adapter diff.
- In OpenKeyboard: run `./scripts/check-semantic-prompt-contract.sh`.
- Add request-body assertions proving `response_format` is absent for Summarize, Translate, and
  Continue Writing in both gateway clients and the live harness.
- Add parser/validator parity cases in package, Core, app/extension, and diagnostic tests.
- Run `./scripts/ios/test.sh core`, focused architecture/model tests, `git diff --check`, and
  `./scripts/check.sh --quick`.

### Phase 4: live and runtime verification

- Treat the change as gateway-, model-capability-, parser-, and semantic-behavior-impacting.
- Run the exact-head low/high model matrix through
  `./scripts/check-live.sh gateway-differential` with no fallback or model substitution.
- Verify Summarize, Translate, and Continue Writing independently. Record transport success,
  response-shape acceptance, semantic acceptance, latency, and exact model identity separately.
- For Translate, collect normal simulator runtime proof using the actual extension through an
  ordinary host-app text field, visible production UI, and configured live gateway. Capture and
  inspect the required direct Simulator screenshots outside XCTest.
- Summarize is currently hidden and Continue Writing is not exposed in the extension UI; verify
  them through contract/Core/live harness evidence without claiming visible extension coverage.
- Before publication/readiness, run `./scripts/check.sh --full`, the required exact-head review,
  and GitHub checks. Use the human exact-head approval route only if automated normal-runtime proof
  remains unavailable and disclose the missing AI screenshot evidence.

## Acceptance criteria

- No active built-in writing action sends `response_format`.
- Rendered Summarize, Translate, and Continue Writing metadata has no response schema or structured
  response type.
- Their prompts request exactly one plain-text result with no JSON envelope.
- Valid output reaches the same user-visible replacement/continuation behavior as before.
- JSON-shaped, fenced, empty, commentary, raw-error, truncated, wrong-language, and repeated-source
  outputs fail safely without replacing user text.
- Translation retry and target-language warnings remain operation-scoped.
- The gateway clients have no implicit `operation != nil` structured-output fallback.
- Contract generation/parity checks, OpenKeyboard deterministic gates, exact-model live checks, and
  required Translate normal-runtime proof pass on the same eligible heads.
- Documentation accurately separates plain-text writing actions from the unrelated keyboard
  suggestions contract and future Gateway V2 structured-output support.

The follow-on connector integration is not required to merge this planning change or to complete
the plain-text response migration. When that later work is activated, its acceptance evidence must
also satisfy the ownership, connection-validation, lifecycle, parity, distribution, architecture,
and extension requirements recorded above.

## Risks and mitigations

- **Weak semantic validation:** use operation-specific structural checks plus live rubrics; do not
  pretend deterministic heuristics prove summary or translation quality.
- **Prompt injection after removing the envelope:** retain explicit untrusted-data instructions and
  JSON-safe input/parameter encoding where useful.
- **Translation false rejection:** combine protected-token checks with the existing language/script
  validator and multilingual fixtures.
- **Continuation repeats source:** add deterministic repetition detection and live long/short input
  cases.
- **Contract/consumer drift:** merge and release the package first, pin its exact commit, regenerate
  adapters, and run the repository contract-sync check.
- **Legacy consumers:** use a major version, document the break, and avoid an undocumented gateway
  fallback that silently changes the requested model contract.

## Likely affected files and modules

- `Vendor/semantic-prompt-contract/contracts/writing-actions.json`
- `Vendor/semantic-prompt-contract/schemas/contract.schema.json`
- `Vendor/semantic-prompt-contract/schemas/writing-action-response.schema.json`
- `Vendor/semantic-prompt-contract/src/index.js`
- `Vendor/semantic-prompt-contract/scripts/generate-adapters.mjs`
- Contract fixtures, JavaScript tests, generated Swift/browser adapters, and Swift parity tests
- `OpenKeyboardCore/Sources/OpenKeyboardCore/WritingAction.swift`
- `OpenKeyboardCore/Sources/OpenKeyboardCore/GatewayClient.swift`
- `OpenKeyboard/Services/CanonicalGatewayClient.swift`
- `OpenKeyboard/Services/NetworkManager.swift`
- `OpenKeyboard/Models/KeyboardSuggestionModels.swift`
- `OpenKeyboardExtension/KeyboardAIService.swift`
- `OpenKeyboard/Views/LiveAITestHarnessView.swift`
- Focused Core and `OpenKeyboardUITests` request/parser/action tests
- `README.md` and `docs/PROMPT_EVALS.md`

## Plan provenance

The plan was prepared from `origin/main` at `c2b8999` with the semantic contract pinned at
`bd83537`. Source blob IDs:

- `AGENTS.md`: `ced607e82f08c5d4f9965fd40af088befd15da77`
- `README.md`: `28bcc3132f0dc5d33ebc62a04c0fc0417c277ce9`
- `docs/WORK_QUEUE.md`: `60c29e512b78d23979f71c5051143c8b1ac3fc5b`
- `docs/KEYBOARD_PRODUCT_COMPLETION_PLAN.md`: `b2175bc9e5feb817277d0767fd755ba71012870b`
- `docs/DEVELOPMENT_WORKFLOW.md`: `84d35c15f4e504450133e3008c0e7b81ed80db47`
- contract manifest/changelog/writing pack: `b73d3dfbb7011955930c656980a2e212f8143c8c`,
  `bd1b70f8071695d28d92f4526b77cf5692befd4c`,
  `6b771d8e630efa5734eb2f9ce7e058bf728ad095`
- gateway and action sources: `cbed3ea691f021692c49b8581abf6d09f1436766`,
  `7d7853d00a3121492c534fe657f555f3e9e726ea`,
  `8697dd544cd1d49047d056b49b7d1b4bef109bba`,
  `70c4252b03a60fa3d9df17c12caf76b9766bd2ea`,
  `0d9f64f268bc95cc15651dd503edba4b01ce63ee`
- focused test sources: `d2d6eadf2ffb00c9bd342b9efec7d999006967e6`,
  `84daa2e42b31be8ab8a696a6e3d1798820077924`,
  `538fac86622dea4dedaf0c8d98f54f3a5c0d9006`,
  `cdbd200c8f2b61828a63053cfcc1130352a896bf`
- prompt/runtime verification docs and contract check script:
  `ff43badafe793fb0eb51ceffe9b7bf2538fd546e`,
  `5d7059a6f2bd0160ed3a91d1b8e3ae88059a0073`,
  `119aa20160b6e18d39a2bee4625b3bd2c5d030b5`
