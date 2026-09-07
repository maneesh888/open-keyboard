# Universal AI Connector integration

OpenKeyboard consumes Universal AI Connector from the pinned
`Vendor/universal-ai-connector` Git submodule. The gitlink, not a branch name or an adjacent mutable
checkout, defines the API and implementation used by the app.

## Ownership boundary

Universal AI Connector owns:

- OpenAI-compatible `/v1/models` and `/v1/chat/completions` transport;
- credential resolution for each outbound request;
- provider request/response translation and body bounds;
- typed provider, protocol, transport, and truncation failures;
- provider request timeouts, concurrent operations, cancellation, and `close()`.

OpenKeyboard owns:

- the normalized gateway URL, exact selected model, and Keychain-backed credential profile;
- Settings discovery policy: exactly one list operation, exact-ID preservation, sole-model
  auto-selection, and explicit choice when multiple models are returned;
- semantic prompt rendering from the pinned prompt contract;
- local 15-second keyboard and 20-second Settings deadlines;
- strict single-output plain-text acceptance, semantic validation, grammar diffing, retry policy,
  and user-facing error presentation.

The production app, extension, and UI-test targets import only `UniversalAiConnector`. The private
`UniversalAiConnectorBridge` module is an implementation detail and is forbidden by a repository
policy test. Direct `URLSession` and `URLRequest` transport is likewise forbidden in production app,
extension, and Core sources; the old Core transport remains only in test fixtures.

## Build bootstrap

Initialize both pinned submodules and generate the connector artifact before a direct Xcode build:

```bash
git submodule update --init --recursive
./scripts/bootstrap-universal-ai-connector.sh
```

`scripts/ios/test.sh` invokes this bootstrap automatically. It refuses a connector checkout with
tracked changes, verifies the current checkout against the recorded gitlink, calls the connector's
canonical `scripts/build-xcframework.sh`, and validates the expected iOS arm64 device and Apple
Silicon Simulator slices. The artifact and its SHA stamp are ignored build outputs.

The connector package currently supports arm64 for iOS devices and Apple Silicon simulators. The
OpenKeyboard project excludes the unsupported x86_64 Simulator architecture while preserving its
normal arm64 device build.

## Runtime lifecycle

The app and keyboard extension are separate processes, so each receives its own process-local
shared adapter. Within a process, the adapter reuses one connector while provider, normalized base
URL, and credential are unchanged. A profile change swaps in a new connector and closes the old
one. Explicit adapter close and deinitialization are idempotent at the OpenKeyboard boundary, while
the connector's public `close()` cancels active work and rejects later work.

OpenKeyboard keeps its user-facing deadlines outside the connector. Winning a local deadline
cancels only that operation task; it does not close the reusable connector or cancel concurrent
grammar chunks. The connector retains its immutable validated 10,000 ms connect and 60,000 ms
whole-request timeouts.

## Response and failure mapping

OpenKeyboard sends the exact model identifier and semantic message sequence in a canonical
plain-text request. It accepts only a matching response target, `.stop` completion, and exactly one
non-empty text output at index zero. Output-limit and incomplete-response codes become a typed
truncation failure; malformed, filtered, structured, mismatched, or empty output becomes an invalid
model response.

Authentication, authorization, missing-model, rate-limit, timeout, provider status, transport, and
closed-connector failures map into stable OpenKeyboard categories before UI presentation. Raw
provider bodies and connector error messages never become product copy or logs.

## Evidence boundary

Deterministic adapter and policy tests establish request fidelity, strict response handling, typed
failure mapping, unsupported discovery without generation fallback, instance reuse, replacement
close, active-operation cancellation, and extension-safe linking. They do not establish live
provider behavior or visible keyboard acceptance. Gateway-impacting heads still require the
classifier-selected exact-head live gate and the normal simulator route in
`docs/REAL_EXTENSION_SMOKE_PLAN.md` before push/readiness.
