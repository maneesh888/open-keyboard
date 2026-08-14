# Pull-request proof audit — 2026-08-14

## Scope

Read-only audit of the 12 most recent merged OpenKeyboard pull requests: #9–#20. The audit
evaluates retained proof quality, not whether every merged implementation is known to be defective.

## Systemic findings

1. All 12 pull requests have zero formal GitHub review submissions. Current `main` protection
   requires zero approving reviews, so an implementing account can merge after status checks without
   either a durable 100%-confidence independent report or an explicit exact-head owner decision.
2. Independent Codex review results were recorded only as editable PR-body claims, when recorded at
   all. No reviewed report was retained as a linked GitHub review submission.
3. `Required live verification` checked an exact commit and generic `gateway` target, but did not
   bind evidence to the model required by the task.
4. The live Test Connection smoke seeded a preferred model but asserted only that a non-empty model
   was ultimately selected. Catalog fallback could therefore pass while exercising a different
   model.
5. Gemma live evaluations are optional and skip when the authenticated catalog lacks Gemma. A skip
   was correctly disclosed in some PRs but was not automatically treated as a model-specific merge
   blocker.
6. Real-extension and screenshot claims in #10, #11, #12, #13, and #18 have no retained artifact
   link in the PR body, review, or comments. They may have been inspected locally or delivered in a
   private task, but a later independent auditor cannot verify them from GitHub.

## Recent-merge classification

| PR | Claim area | Retained proof assessment |
| --- | --- | --- |
| #9 | CI, live-test, deployment, and merge automation | Deterministic checks are retained. Real-keyboard execution and independent review are contributor-attested only; formal approval is absent. |
| #10 | Keyboard geometry and action-panel UI | Deterministic checks are retained. Claimed real-extension screenshots are not linked or retained in the PR. |
| #11 | Live Translate and Apply flow | Deterministic checks are retained. The real-keyboard translation result and screenshot are local attestations without a durable PR artifact. |
| #12 | Translation ordering and Malayalam flow | Deterministic checks are retained. Malayalam live Apply and screenshot proof are not independently retained in the PR. |
| #13 | Independent rewrite actions | Deterministic behavior and layout claims are covered, but the PR explicitly excludes live response and Apply proof for every style; screenshots are not retained in the PR. |
| #14 | Cross-worktree live-seed safety | Strong deterministic safety-policy coverage is retained. Independent review and credentialed live execution remain contributor-attested. |
| #15 | Client-owned semantic prompt generation | Exact-head Gemma execution is claimed, but the exact Gemma model ID and raw or sanitized result artifact are not retained. |
| #16 | Shared semantic prompt contract | The PR records `gemma4:latest`, timings, deterministic parity, and exact heads. The live result and independent review still remain contributor-attested. |
| #17 | Atomic correction suggestions | Client-side rejection and deterministic tests are strong. Live proof covers an unspecified selected model and explicitly does not cover every model. |
| #18 | Gateway health versus model capability | Deterministic limited-capability behavior and host UI are covered. The screenshot scenario used `gemma2:2b`, but live proof did not reproduce that model-format failure or a real extension lifecycle. |
| #19 | Keyboard model-incompatibility errors | Deterministic taxonomy and simulator evidence are retained, but the PR explicitly says live Gemma 4 behavior is unconfirmed and its screenshot is not a live incompatible-model reproduction. It has no formal review or approval. |
| #20 | Lightweight-model correction prompt | The PR explicitly states that `gemma2:2b` returned HTTP 502 and was not tested. It should have remained blocked for the stated exact-model objective. |

## Corrective standard

- Every in-scope requirement is a separate ledger row with an observable acceptance criterion and
  required proof type.
- Only exact, inspectable evidence marks a row `VERIFIED`.
- Missing, skipped, stale, fallback, wrong-target, wrong-model, ambiguous, or contributor-attested-
  only material evidence is `UNVERIFIED` and blocks readiness.
- Exact-model live smoke rejects catalog fallback and records both required and tested models.
- The independent report is retained as a linked GitHub `COMMENTED` review submission. Automatic
  authorization requires every row verified, no material uncertainty, and exact reviewer confidence
  of `100%`; otherwise the PR stays draft until the owner explicitly authorizes that exact SHA after
  reviewing the disclosed gaps.
- Residual proof limits contain explicitly authorized out-of-scope work only.

This standard guarantees complete coverage of stated requirements within the recorded evidence
boundary. It does not claim that unknown software defects are impossible.
