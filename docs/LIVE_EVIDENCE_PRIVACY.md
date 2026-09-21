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

## Trusted-base migration

The first privacy PR still uses the trusted base classifier. A supported legacy validator has Git
blob `249c196c6eb2ca94a397896e7cfd448463f463ca` (source code, not a model hash). The only allowed legacy base SHA is
`6619f0bb1f3aa8306a4b1dc94b2fdd514ee1f6f6`. Before candidate checkout, the migration requires an
actual owner-approved GitHub run through the dedicated `live-policy-migration` environment.
Its required reviewer must be the repository owner; configure it with admin bypass disabled.
The ordinary `live-policy` environment is not an approval boundary (its protection rules were empty
when this migration was prepared). The reviewed bootstrap validates the full private assertion
schema and also runs the trusted validator. Its only source accommodation is to permit the literal `withheld`
for differential timings. No measurement is synthesized. The temporary legacy input maps confirmed
roles to fixed `LOW`, `HIGH`, or `REFERENCE` aliases and copies actual head/target/outcome fields.
Those aliases express roles in the old string-equality grammar; they are not claimed model IDs.
The temporary record is mode 600 and deleted on exit/signals. Unknown legacy sources fail closed.

The routing job reads environment configuration before selecting it. Missing or unprotected
configuration never starts the separate approval job; the independent required root check fails
before candidate checkout. The protected `Required live verification` job has no prerequisite and
cannot be hidden by cancellation of a dependency. During migration it fails until approval is
recorded. After the owner approves the separate environment job, rerun the failed required job in
that same exact-head run; its approval history is then available. No polling or check waiver is used. This prevents GitHub from implicitly creating an unprotected
migration environment. The guard requires real approval history by the owner, for this environment
and workflow run, whose head matches the exact PR head. Codex must not manufacture this approval.
External environment setup requires explicit owner authorization; it is not part of a normal code
commit. A new candidate head needs fresh run approval. The live workflow runs on opened,
synchronize, reopened, and body-edited events; draft/readiness changes alone do not alter live
evidence and do not start another live run. The independent review/checks workflow still validates
readiness and exact-head authorization.

After merge, workflows load the bootstrap, classifier, and validator from the trusted base and use
the private schema directly. There is no environment switch to enable migration, skip live checks,
downgrade classification, or accept unknown legacy code. Required protection, event/current snapshot
checks, independent review, and exact-head authorization remain in force throughout migration.

## Universal AI Connector integration

The separate adapter task owns provider-neutral transport, model discovery, typed errors, instance
replacement/cancellation, and its pinned connector build. This rules PR imports none of that product
code. The actual integration at `fa0109f` also proposes role-bound identity assertions and a four-provider
Settings/diagnostics matrix. It must rebase these rules and retain its provider-specific binding and
outcome checks. This schema supports `Live provider exact bindings`, `Live provider Test Connection
outcomes`, and `Live provider diagnostic outcomes` in canonical openai/anthropic/openrouter/gateway
order. All bindings must be true and all outcomes passed. A live-impacting exact head containing
`Vendor/universal-ai-connector` requires all three fields; earlier heads may omit the group or use
three `not required` values. Any supplied claim is validated in full. Do not treat this policy
PR's gateway-only evidence as adapter verification.

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

Haptics and connector branches must resolve policy conflicts on their own branches, commit a fresh
head, and rerun the full gate and their classified live coverage. Old full/live evidence and review
cannot carry forward. Each task must retain its own required normal runtime proof or exact-head
human approval and complete independent review and protected checks. This rules merge neither
verifies nor merges those features.
