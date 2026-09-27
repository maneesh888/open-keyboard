# AI operation diagnostics

The app and extension share a bounded App Group ledger. It records real production operations;
no diagnostic state substitutes for an AI response or changes retry, validation, or correction behavior.

## Metadata and reproduction context

Metadata is collected without phrase/response capture: random trace ID, operation and origin,
start time, app/build and OS versions, executable UUID (identifies the exact app or extension binary),
provider and exact model ID, pinned prompt-contract version, effective sampling preferences,
output-token limit, app request timeout, attempt, and per-request UUID. Request IDs correlate concurrent
chunks and retries to their events. At most eight request contexts and 64 events are kept per trace;
omitted request contexts are counted explicitly. At most 48 traces are retained for seven days.

The executable UUID is a binary fingerprint, not a Git SHA. Provider/model configuration can itself
be sensitive; the diagnostics screen discloses that it is included in metadata exports.
Only validated, bounded model identifiers are accepted. Configuration credentials, authentication
headers and gateway addresses are never passed to the ledger.

Connector success is recorded as `connector_response_accepted=true`, not an inferred HTTP 200.
An exact HTTP status is recorded only when the connector supplies it in structured error metadata.
Timings cover the connector call, not an isolated network request. Closed rejection subreasons
preserve known decoder, contract, local output-shape, truncation, and incomplete-response failures.
An upstream `malformed_provider_response` can still aggregate multiple provider-wire checks;
it must not be presented as the exact upstream cause.

## Explicit text consent

Text capture is OFF by default. The **Capture Text** switch enables a ten-minute capture session.
Its footer explains local collection of AI phrases and responses, including automatic checks and
text from other apps. Nothing is uploaded automatically.
The host app writes a random, expiring consent session shared with the keyboard extension.
Only operations begun during that session may capture text. Every write rechecks the same active
session. Enabling capture cannot retroactively capture an in-flight operation; expiry or revocation
prevents late responses from retaining text, even if another session is later enabled.

The ledger can retain the original phrase plus individual user-message/decoded-response pairs.
Each text field is capped at 4,096 UTF-8 bytes, preserving valid Unicode and marking truncation.
Only the eight newest consented operations retain text, for at most 24 hours. Expired text is purged
on the next ledger read/write. A maximum of eight request contexts per operation bounds storage.
Raw HTTP bodies, arbitrary provider error messages, and headers are never collected. If the connector
rejects a wire response before exposing decoded text, that response text remains unavailable.
User-provided phrases may themselves contain sensitive information; the share confirmation warns of this.

Turning **Capture Text** off revokes consent and deletes all retained text while keeping
metadata. **Delete All Diagnostics** clears all records and consent. Writes and deletion use shared
file coordination, and content never goes to OSLog or signposts.

## Review and sharing

**Share Diagnostics** opens an **OK / Cancel** confirmation explaining that selected reports may
include sensitive captured phrases and AI responses. Cancel exports nothing. OK revalidates the
selected report snapshot and opens the native iOS share sheet with the actual diagnostic text.
Changed, deleted, or expired reports invalidate pending sharing. The keyboard's **Copy Details**
remains metadata-only. No analytics collector or automatic upload is added. JSON quoting prevents
captured text from forging diagnostic lines. A missing trace ID exports zero records.

Records retain the v1 storage key/schema; additive optional fields decode old exports without migration.
Old records have unknown provider/model/request context, and absent values must never be guessed.

## Verification

`AIOperationDiagnosticsTests` covers legacy decoding, metadata, consent, expiry, cross-instance
revocation/deletion, late replies, default redaction, explicit text exports, UTF-8 bounds, retention,
missing-trace isolation, available rejected responses, and no fabricated HTTP success status.
Normal simulator verification additionally covers the visible consent, ordinary keyboard operation,
share confirmation, cancellation, the native share sheet, and disabling capture. These diagnostics do not by themselves establish
that the original correction/recheck failure is fixed.

## Selecting reports

Capture and sharing controls are at the top, followed by the recent-operations list. All, Errors, and Warnings
segmented tabs filter the list. Errors contains failed operations. Warnings contains cancelled or
ignored operations and non-failed operations with a recorded failure, including recovered failures.
Clean successful or in-progress operations remain available under All.

Checkboxes choose individual reports. Sharing includes only checked, visible reports; an empty
selection cannot be shared. Switching tabs selects that tab's reports. After manual selection,
newly arriving reports are not silently added. A single Capture Text switch replaces the expanded
capture controls. A pending share is invalidated if its backing reports change or their text is
deleted or expires, and the user must confirm again before sharing.
