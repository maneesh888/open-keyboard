---
name: review-verify-merge-pr
description: Independently review OpenKeyboard pull requests and verify exact-head readiness. Use for PR review and for autonomous implementation lifecycles reaching guarded readiness and merge; honor explicit draft or merge opt-outs.
---

# Review, Verify, and Safely Merge an OpenKeyboard PR

Bind every review conclusion and state change to one exact pull-request head.

## Authority

- Review, readiness assessment, and blocker requests are read-only.
- A bounded implementation request starts the normal autonomous repository lifecycle through guarded merge.
- Only the root agent may fix findings, commit, push, update the PR, change readiness, or merge.
- The independent `pr-reviewer` is always read-only.
- Apply the sticky authority ledger from `AGENTS.md`. Honor active edit, implementation, commit,
  push, PR, readiness, and merge constraints; do not resurrect a completed checkpoint's
  phase-scoped constraints after a clear implementation transition. Objective- or task-wide
  constraints remain active until explicitly revoked, and ambiguous later wording does not revoke
  them.
- Physical-device interaction remains separately denied until the user explicitly requests it.
  Review, release, readiness, or merge work and a physical-device evidence requirement never
  authorize device discovery, connection, installation, launch, testing, signing, or capture.
- Do not request another confirmation between normal lifecycle stages while their gates pass and
  the independent reviewer reports operational confidence of exactly `100%`. The user does not
  need to name commit, push, PR, readiness, or merge separately. Below 100%, explicit human
  authorization for the current exact head is mandatory before readiness or merge.
- Deployment remains outside the implementation lifecycle and requires explicit authorization.
- Never bypass branch protection, hooks, scanners, required checks, environment approval, or review findings.

## Establish the exact target

1. Resolve the repository and inspect the worktree without disturbing unrelated work.
2. Resolve the PR number, base, full head SHA, draft state, changed files, mergeability, reviews, unresolved threads, and checks using available read-only GitHub tools.
3. Use an isolated clean worktree when the current checkout is not the exact PR head.
4. Read `AGENTS.md`, the PR brief, the root diff, and only the relevant requirement and acceptance sources.
5. Treat any head change as invalidating prior local, CI, live, independent-review evidence, and
   human merge authorization. Normal-Simulator evidence is the only exception: it may carry from
   an ancestor capture SHA when the current clean head passes the repository's test-only
   carry-forward verifier and the record retains both SHAs, the runtime digest, and intervening
   paths.

## Prepare neutral review context

Immediately before independent review, assemble a neutral packet containing:

- PR identity, base, and full exact head SHA;
- every requested behavior as a stable requirement ID with its durable source;
- one observable acceptance criterion and required proof type for every in-scope requirement;
- changed files and root diff;
- verification results and their exact proof boundaries; and
- only behavior the user or a durable requirement source explicitly authorized as out of scope.

The packet must include a requirement ledger. Do not combine independent requirements into one row.
If the request, source, acceptance criterion, or required proof is missing or ambiguous, keep that
row `UNVERIFIED`; do not silently narrow the task so the pull request can pass.

Do not include expected findings or a desired conclusion. Keep secrets, gateway response bodies,
private user text, generated artifacts, and raw logs out of the packet.

## Review and verify

1. Spawn the project `pr-reviewer` with no inherited conversation when available. Pass only the PR identity, exact SHA, neutral packet, diff, and source paths.
2. Run independent review and GitHub checks concurrently where practical.
3. Inspect correctness, error behavior, concurrency, cancellation, MVVM ownership, persistence, App Group and Keychain boundaries, gateway behavior, extension lifecycle, accessibility, tests, CI and deployment security, documentation claims, generated artifacts, and unrelated changes.
   Flag a fix-style commit subject for live/runtime-sensitive behavior when its required evidence is
   missing; an authorized unverified commit must be clearly experimental or diagnostic.
4. Treat correctness, security, data-loss, extension-contract, signing, missing-material-test, and false-evidence findings as blockers.
5. Produce a requirement-coverage table with `VERIFIED` or `UNVERIFIED` for every in-scope row. A row is verified only by the proof type its acceptance criterion requires.
6. Treat skipped, missing, stale, fallback, wrong-target, wrong-model, or contributor-attested-only material evidence as `UNVERIFIED`. An exact-model requirement must execute that exact model without substitution.
7. Classify unit tests, XCTest/XCUITest, mocks, debug or seeded UI states, component hosts, and
   `XCTAttachment` screenshots as automated regression evidence. An XCUITest that activates the
   installed extension is not normal simulator runtime proof. For proof-sensitive UI, extension
   lifecycle, Apply/Copy/Back/Rerun, live gateway, or result-presentation changes, require an
   exact-head normal runtime record from a normally launched app, ordinary host-app text field,
   visible production UI, and direct Simulator/Xcode screenshots. A complete ancestor-capture
   record may satisfy the current head only when
   `./scripts/verify-runtime-proof-carry-forward.sh <capture-sha> <current-sha>` passes on the clean
   head and the reviewer independently inspects both SHAs, the identical non-test Git-tree digest,
   every intervening test-only path, and the original screenshots. Require explicit physical-device
   interaction authority plus exact signed-build device evidence for physical-device rows;
   Simulator/XCTest cannot satisfy them. Without that authority, do not inspect connected devices.
8. Treat every `UNVERIFIED` in-scope row as a blocker and tie every material finding or uncertainty to an `UNVERIFIED` row. Residual proof limits may contain explicitly authorized out-of-scope behavior only.
9. For release readiness, run `./scripts/check.sh --full` on the clean exact head.
10. Follow the exact classifier result on the same head: `gateway` requires
   `./scripts/check-live.sh gateway`; `gateway-differential` requires
   `./scripts/check-live.sh gateway-differential`. Exact single-model work sets
   `OPEN_KEYBOARD_LIVE_REQUIRED_MODEL`; differential work sets the canonical
   `OPEN_KEYBOARD_LIVE_REQUIRED_MODELS='low=<id>, high=<id>'` mapping. Missing, substituted,
   reversed, malformed, stale, or diagnostic-only profile evidence is `UNVERIFIED`. A low success
   at the candidate boundary or intermittent low outcome cannot be promoted to a passing gate.
11. Before the report, confirm the exact-head technical jobs that do not depend on retaining that
    report are successful. Inspect the trusted requirement validators, but do not require the
    report-dependent `Required checks` status to be green
    before the report exists. After the root posts and links the report, require exact-head
    `Required technical checks`, `Required checks`, and `Required live verification` before readiness or merge.

The reviewer must never claim that unknown defects are impossible. "No findings" means all stated
in-scope requirements are verified within the named evidence boundary, not that the software is
mathematically guaranteed to contain no undiscovered error.

The report must copy each ledger row's observable acceptance criterion and required proof type
verbatim into a six-column table: `ID | Observable acceptance | Required proof | Evidence inspected
| Status | Independent assessment`. This makes omitted requirements and proof substitutions
machine-detectable when the report is retained on GitHub. It must also contain exactly one
`Reviewer`, `Exact reviewed head`, `Review requirement coverage`, `Review unverified requirements`,
`Blocking findings`, `Reviewer confidence`, `Merge recommendation`, and `Conclusion` field.
Coverage records rows assessed and must be N/N even when a row is unverified. Use exactly
`Reviewer confidence: 100%`, `Merge recommendation: automatic`, and
`Conclusion: requirements-complete` only when every row has the exact required proof and no
material uncertainty remains. Otherwise use exactly `Reviewer confidence: below 100%`,
`Merge recommendation: human-review-required`, and `Conclusion: human-review-required`, and name
every unverified requirement and blocker.

Review-only work reports findings and stops. During an autonomous implementation lifecycle, the
root agent fixes in-scope blockers while the PR remains draft. Every new commit invalidates local
Release evidence, live evidence, independent review, human authorization, and GitHub gate
conclusions. Normal-Simulator proof survives only through the verified test-only carry-forward
record described above. If the PR was already ready, immediately disable any auto-merge request and
return it to draft, then refresh the PR brief and repeat the exact-head cycle.

## Readiness gate

Before marking a PR ready or merging it, always require:

1. a current PR brief and neutral reviewer packet bound to the full head SHA, with every in-scope requirement listed separately;
2. independently reviewed SHA equal to GitHub's current head;
3. successful `./scripts/check.sh --full` for that SHA;
4. successful applicable exact-head live evidence;
5. successful exact-head normal simulator runtime proof for every proof-sensitive changed surface,
   or a verified test-only carry-forward record bound to the current head; and successful exact
   signed-build device proof collected under explicit physical-device interaction authority for
   every physical-device requirement;
6. a durable GitHub `COMMENTED` review submission containing the independent report and a PR-brief link to that review;
7. no undisclosed finding, current-head requested change, or unresolved review thread;
8. an in-scope diff with no secret or generated-artifact violation;
9. no conflict and compliance with the base-update policy;
10. successful exact-head `Required technical checks`, `Required checks`, and `Required live verification`; and
11. effective base protection requiring pull requests, strict checks, and conversation resolution.

Inspect every exact-head run, including pending, canceled, skipped, failed, and rerun attempts.
GitHub retains the latest check suite separately for `pull_request` and `pull_request_review`
events, so a later body-edit success does not by itself replace the expected failure created when
the project-reviewer report was submitted before its PR-body link existed. After the report is
linked and the current validators pass, submit exactly one same-head COMMENTED review whose body is
`Review-evidence revalidation trigger for exact head <full-sha>. This COMMENTED submission is not
an approval, an independent-review report, or merge authorization.` The trigger must not contain
the project-reviewer identity marker and must never be submitted as `APPROVED`. Wait for its
`pull_request_review` run to pass against both the event and current snapshots.

Require the current rollup for `Required checks` and `Required live verification` to point to
completed successful root jobs with no newer non-success, then run:

```bash
gh pr checks <number> --required
```

The command must exit successfully; checking only the newest result grouped by protected name is
insufficient because it can hide an unsuperseded failed event family. Re-run the trusted validators
locally against the freshly fetched current body and reviews before readiness and merge. Keep the
PR draft throughout report/body/revalidation handoff. The linked submission must be the newest
same-head COMMENTED report declaring the isolated project-reviewer identity; the revalidation
trigger is not that report, and any later project-reviewer report supersedes the linked one even
before the PR body is updated.

Then require exactly one authorization route:

- **Automatic:** every in-scope row is `VERIFIED`; the reviewer inspected N/N requirements, reports
  `Reviewer confidence: 100%`, reports no blocking finding or material uncertainty, and recommends
  `automatic`. Record `Merge authorization route: automatic` and set every human-approval field to
  `not-required`.
- **Human:** the reviewer reports `below 100%` and `human-review-required`; every unverified row and
  blocker remains visible; and the repository owner explicitly authorizes merge for the current
  full SHA in the active task after performing whatever local test and review they judge necessary.
  Only then may the root record `Merge authorization route: human`, `Human approval status:
  approved`, the exact `Human-approved head`, and `Human approval evidence: explicit
  repository-owner approval for this exact head in the active Codex task`.

Human authorization accepts the disclosed evidence risk; it does not relabel an unverified row as
verified and never bypasses failed mandatory checks, live evidence, conflicts, requested changes,
unresolved threads, secret controls, branch protection, or missing required normal simulator/device
proof. The root must not infer approval from
the implementation request, PR authorship, prior approval of another SHA, silence, or a general
statement about policy. If confidence is below 100% and current-head human approval is absent, keep
the PR draft, present the exact SHA and every blocker to the user, ask for their decision, and stop.

Pending, skipped, missing, cancelled, timed-out, stale, or failed mandatory technical gates block
readiness and merge in both routes. A missing requirement-specific proof prevents automatic
authorization and remains disclosed if the owner chooses the human route. Missing required normal
simulator or physical-device proof blocks readiness and merge in both routes.

The root agent must post the independent review result as a durable GitHub `COMMENTED` review
submission without secrets or raw gateway output, link that review from the PR brief, and run the
repository PR-requirement validators before readiness. The root may summarize but must not weaken,
omit, or reclassify a reviewer's blocker. The AI reviewer never submits a GitHub approval, and the
root never manufactures a human approval; the exact-head owner instruction is a separate authority
boundary.

## Guarded merge

If any active sticky constraint says `keep draft`, leave the PR draft. If any active sticky
constraint says `do not merge`, a clean head may become ready but must remain unmerged. A later
ambiguous or unrelated instruction does not supersede either constraint.

Otherwise:

1. Refresh the head, required checks, independent review result, reviews, threads, protection,
   mergeability, scope, and every active sticky authority constraint. Require
   `gh pr checks <number> --required` to exit successfully so no failed event-family result is
   hidden by a newer check with the same name.
2. Confirm all evidence and the selected automatic or human authorization route remain bound to the same full reviewed and locally verified SHA. If the reviewer is below 100% and explicit current-head owner approval is absent, keep the PR draft, ask the owner to review the named gaps, and stop.
3. Mark the draft ready.
4. Refresh the same state once more. On any head, gate, protection, mergeability, scope, review, or
   active-authority mismatch, disable any queued auto-merge, return the PR to draft when applicable,
   and restart the exact-head cycle or report the blocker. When `keep draft` becomes or remains an
   active sticky constraint, disable auto-merge, return the PR to draft, verify it remains unmerged,
   and stop. When `do not merge` becomes or remains an active sticky constraint, disable
   auto-merge, verify the PR remains unmerged, and stop.
5. Run GitHub's native guarded squash merge with exact-head matching:

   ```bash
   gh pr merge <number> --auto --squash --match-head-commit <reviewed-head-sha>
   ```

6. Inspect PR state immediately. If GitHub queues auto-merge instead of completing the merge, disable it, verify the PR remains unmerged, and report the unsatisfied gate.
7. If the head changes before completion, disable auto-merge, return the PR to draft when applicable, and restart the exact-head cycle.

Never force, use administrator bypass, dismiss valid feedback, leave a deployment running, or add a
write-enabled unattended merger. Never leave queued auto-merge active.

## After merge

Record the PR URL and squash commit. Inspect resulting `main` CI when the change affects workflow,
verification, signing, deployment, or another claim that depends on the resulting base branch.

## Reporting

Lead with blockers or state that none remain. Include the PR, exact reviewed head, local verification,
independent-review result, required checks, unresolved threads, protection, mergeability, action
taken, and residual proof limits. Render or attach every screenshot used as required proof in the
final response, even when it appeared in commentary or is linked from the PR. A path, `.xcresult`,
review link, or summary alone is not delivery. If a required screenshot cannot be delivered, keep
its requirement unverified and do not mark the PR ready or merge it.
