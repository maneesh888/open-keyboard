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
- Honor the latest explicit `local only`, `do not commit`, `do not push`, `do not create a PR`, `keep draft`, or `do not merge` instruction.
- Do not request another confirmation between requested lifecycle stages.
- Deployment remains outside the implementation lifecycle and requires explicit authorization.
- Never bypass branch protection, hooks, scanners, required checks, environment approval, or review findings.

## Establish the exact target

1. Resolve the repository and inspect the worktree without disturbing unrelated work.
2. Resolve the PR number, base, full head SHA, draft state, changed files, mergeability, reviews, unresolved threads, and checks using available read-only GitHub tools.
3. Use an isolated clean worktree when the current checkout is not the exact PR head.
4. Read `AGENTS.md`, the PR brief, the root diff, and only the relevant requirement and acceptance sources.
5. Treat any head change as invalidating prior local, CI, live, and independent-review evidence.

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
4. Treat correctness, security, data-loss, extension-contract, signing, missing-material-test, and false-evidence findings as blockers.
5. Produce a requirement-coverage table with `VERIFIED` or `UNVERIFIED` for every in-scope row. A row is verified only by the proof type its acceptance criterion requires.
6. Treat skipped, missing, stale, fallback, wrong-target, wrong-model, or contributor-attested-only material evidence as `UNVERIFIED`. An exact-model requirement must execute that exact model without substitution.
7. Treat every `UNVERIFIED` in-scope row as a blocker. Residual proof limits may contain explicitly authorized out-of-scope behavior only.
8. For release readiness, run `./scripts/check.sh --full` on the clean exact head.
9. If `./scripts/live-impact.sh` selects `gateway`, require `./scripts/check-live.sh gateway` on that same exact head and refresh the PR evidence.
10. Confirm GitHub reports `Required checks` and `Required live verification` as successful for the reviewed head.

The reviewer must never claim that unknown defects are impossible. "No findings" means all stated
in-scope requirements are verified within the named evidence boundary, not that the software is
mathematically guaranteed to contain no undiscovered error.

The report must copy each ledger row's observable acceptance criterion and required proof type
verbatim into a six-column table: `ID | Observable acceptance | Required proof | Evidence inspected
| Status | Independent assessment`. This makes omitted requirements and proof substitutions
machine-detectable when the report is retained on GitHub. It must also contain exactly one
`Reviewer`, `Exact reviewed head`, `Review requirement coverage`, `Review unverified requirements`,
`Blocking findings`, and `Conclusion` field. Use `requirements-complete` only for a fully verified
report; otherwise use `blocked` and name every unverified requirement.

Review-only work reports findings and stops. During an autonomous implementation lifecycle, the
root agent fixes in-scope blockers while the PR remains draft. Every new commit invalidates local
Release evidence, live evidence, independent review, and GitHub gate conclusions. If the PR was
already ready, immediately disable any auto-merge request and return it to draft, then refresh the
PR brief and repeat the exact-head cycle.

## Readiness gate

Before marking a PR ready or merging it, require:

1. a current PR brief and neutral reviewer packet bound to the full head SHA, with every in-scope requirement listed separately;
2. independently reviewed SHA equal to GitHub's current head;
3. successful `./scripts/check.sh --full` for that SHA;
4. successful applicable exact-head live evidence;
5. 100% requirement coverage, with no `UNVERIFIED` in-scope row, substitution, ambiguity, or material uncertainty;
6. a durable GitHub `COMMENTED` review submission containing the independent report and a PR-brief link to that review;
7. no blocking finding, requested change, or unresolved review thread;
8. at least one approving GitHub review from a human who is neither the PR author nor an identifiable implementing contributor, with stale-review dismissal enabled;
9. an in-scope diff with no secret or generated-artifact violation;
10. no conflict and compliance with the base-update policy;
11. successful exact-head `Required checks` and `Required live verification`; and
12. effective base protection requiring pull requests, at least one approval, stale-review dismissal, strict checks, and conversation resolution.

Pending, skipped, missing, cancelled, timed-out, stale, or failed mandatory evidence blocks
readiness and merge.

The root agent must post the independent review result as a durable GitHub `COMMENTED` review
submission without secrets or raw gateway output, link that review from the PR brief, and run the
repository PR-requirement validators before readiness. The root may summarize but must not weaken,
omit, or reclassify a reviewer's blocker.

## Guarded merge

If the latest instruction says `keep draft`, leave the PR draft. If it says `do not merge`, a clean
head may become ready but must remain unmerged.

Otherwise:

1. Refresh the head, required checks, independent review result, reviews, threads, protection, mergeability, scope, and latest user instruction.
2. Confirm all evidence remains bound to the same full reviewed and locally verified SHA.
3. Mark the draft ready.
4. Refresh the same state once more. On any head, gate, protection, mergeability, scope, or review mismatch, disable any queued auto-merge, return the PR to draft when applicable, and restart the exact-head cycle or report the blocker. On a late `keep draft`, disable auto-merge, return the PR to draft, verify it remains unmerged, and stop. On a late `do not merge`, disable auto-merge, verify the PR remains unmerged, and stop.
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
taken, and residual proof limits.
