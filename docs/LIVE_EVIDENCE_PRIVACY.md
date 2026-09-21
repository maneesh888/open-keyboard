# Private live-evidence contract

The public record describes roles and outcomes. Model identity remains a private local input.
`check-live.sh` compares an explicit model requirement, when supplied, to the guarded seed and
compares the differential runner's actual profile identities to that same selection. The runner
rechecks each role when loading its seed before injection. Both roles must be complete and distinct.
The gate rejects substitution, reversed roles, missing results, stale/dirty heads, a successful LOW
boundary, failed HIGH execution, and diagnostic-only results. No model hash is published.

## Public schema

Use the `Live gateway evidence` section in the PR template. Copy only validated role assertions:

| Field | Ordinary gateway | Differential |
| --- | --- | --- |
| Live model requirement | exact or model-agnostic | exact |
| Live model identity matches | reference=true | low=true, high=true |
| Live model role distinctness | not required | true |
| Live-model substitutions | none | none |
| Live plain-text grammar verification | verified | verified |
| Live baseline outcomes | not required | low=passed, high=passed |
| Live differential outcomes | not required | low=expected-model-capability, high=passed |
| Live follow-up outcomes | not required | low=passed, high=passed |
| Live summarize outcomes | not required | low=passed, high=passed |
| Live continue-writing outcomes | not required | low=passed, high=passed |
| Live operation-scoped warning contracts | not required | verified |

The pass, target, exact SHA, retention boundary, and trust boundary fields remain mandatory. Public
fields never contain model names, hashes, credentials, private URLs, prompts, responses, or timings.
Unknown live-section payload and legacy identity fields fail validation. A validator cannot recognize
an arbitrary private string hidden in unrelated prose; secret scanning and human/agent review of the
entire publication remain necessary. Do not paste raw private evidence into any section or review.

GitHub receives contributor-attested assertions. It does not independently know which private
model ran or whether a provider served that model. Independent review inspects the actual local
checks and redacted execution result; syntax validation alone does not verify a live requirement.
Automated regression evidence, transport, semantic outcomes, and normal simulator runtime proof
remain separate. Human approval must name the exact head and retains the absent AI-proof boundary.

## Trusted-base validation

Current main already supports the private assertion schema. The live workflow loads both the
classifier and validator directly from the exact PR base, requires the schema marker, and fails
closed when either file is missing or the base uses a legacy schema. It never executes a candidate
bootstrap, adapts legacy input, or fabricates identity or timing fields. Positive and negative
workflow tests exercise trusted, legacy, missing, and malicious-candidate cases.

No new protected environment or repository-security setting is needed. The existing read-only
`live-policy` job and all branch protection, independent review, exact-head authorization, and
immutable-event/current-snapshot checks remain mandatory. A stale base must be reconciled with
current main; it cannot opt into a migration bypass.

## Universal AI Connector integration

Main contains the pinned Universal AI Connector integration. This policy change preserves its
product code and requires `Live provider exact bindings`, `Live provider Test Connection outcomes`,
and `Live provider diagnostic outcomes` in canonical openai/anthropic/openrouter/gateway order.
All bindings must be true and all outcomes passed for every live-impacting head. No-impact records
may use only `not required`. This policy PR's automated evidence is not normal UI runtime proof.

Connector gitlinks, bootstrap scripts, Settings model selection, and service adapters require the
model-differential gate. Canonical prompt-contract ownership and exact pinned package checks remain
unchanged. New adapter behavior must preserve exact model/request/response-target matching,
no generation fallback for discovery, strict parsing, retries, and operation-scoped warnings.

## Haptics classifier assessment

`KeyboardViewModel.swift` owns local key actions and semantic request, retry, warning, and result
state. File-level classification cannot establish that a haptic call leaves those contracts intact.
A keyword or changed-line exemption would miss control-flow and numeric changes. This PR retains
its differential classification, with a regression for a haptic-only edit. Safe separation would
require a separately reviewed product refactor with explicit dependency boundaries; it is outside
this rules task. There is no general skip switch.

## Revalidation after adoption

Every changed head requires fresh full/live evidence, independent review, and protected checks.
Other tasks retain their own required normal runtime proof or exact-head human approval. This
policy change does not grant verification or merge authority for another task.
