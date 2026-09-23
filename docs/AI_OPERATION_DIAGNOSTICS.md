# AI operation diagnostics

## Schema and privacy boundary

The shared App Group key `aiOperationDiagnostics.v1` contains a JSON array of schema-version `1`
records. Every record has a randomly generated UUID trace ID, a closed operation enum, a closed
origin enum, start/update timestamps, app version, build version, OS version, a bounded list of
typed events, and an optional typed outcome and failure.

Each event contains only its closed stage enum, attempt number, elapsed/duration milliseconds,
an optional HTTP *category* (`1xx` through `5xx`), and optional request/response byte counts. The
allowed stages are context capture, prompt construction, transport, decoding, validation, retry,
cancellation, stale-result suppression, and final outcome. The schema intentionally has no
free-form text field and no model, endpoint, header, authorization, or credential field.

Consequently, neither the keyboard's Copy Details action nor the host-app export can include:

- Typed source/context text or generated model text.
- API keys, authorization headers, gateway URLs, host names, paths, or query strings.
- Private model identifiers or provider error strings.

Native `Logger` and `OSSignposter` output follows the same boundary: it emits only the random
trace ID, closed operation/stage/outcome values, and no request or response content.

The Universal AI Connector owns the underlying URL session, so the app does not invent or retain
`URLSessionTaskMetrics` it cannot observe. Instead, the adapter records the safe transport timing,
byte counts, and HTTP status category available at that boundary; the native signpost spans the
entire operation.

## Retention

The ledger keeps at most 48 traces, with at most 64 events per trace. Records expire seven days
after their latest update. Every read and write prunes expired records and enforces those limits;
diagnostics are intentionally lossy rather than an audit log.

## Incident classification

The final typed failure is the support-facing classification. Transport with no usable gateway
response is `gateway_nonresponse`; a deadline or connector timeout is `transport_timeout`; a
decoded connector payload that is malformed or incomplete is `malformed_response`; a result that
fails the app's output checks is `validation_rejected`; an exhausted retry is `retry_failed`;
task cancellation is `cancelled`; and a response prevented from mutating newer keyboard state is
`stale_result_suppressed`. HTTP failures retain only their status category and use
`gateway_rejected`.

When terminal UI handling supplies a broad `validation_rejected` category, the ledger retains a
more specific failure already recorded at a lower stage (for example, a connector decoding
failure). A genuine app output-validator rejection already has a `validation_rejected` validation
event and remains classified that way. The connector response contract does not expose raw HTTP
status or raw response bytes for malformed decoded payloads, so those fields stay absent rather
than being inferred.

The keyboard creates one trace for each manual action, action-panel action, automatic grammar
analysis, and explicit grammar review. Services add the lower-level prompt, transport, decoding,
validation, and retry stages under that trace. The view model owns the final outcome because it is
the only layer that can tell whether a completed response was accepted or safely suppressed as
stale.
