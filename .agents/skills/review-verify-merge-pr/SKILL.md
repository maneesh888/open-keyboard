---
name: review-verify-merge-pr
description: Independently review OpenKeyboard pull requests and verify exact-head readiness. Use for PR review, release readiness, and guarded merge only when the user explicitly requests the corresponding state change.
---

# Review, Verify, and Safely Merge an OpenKeyboard PR

Bind every review conclusion and state change to one exact pull-request head.

## Authority

- Review and readiness assessment are read-only.
- Publishing an implementation pull request does not authorize marking it ready or merging it.
- Only the root agent may fix findings, commit, push, update the PR, change readiness, or merge.
- The independent `pr-reviewer` is always read-only.
- Require an explicit user request before changing draft state, enabling auto-merge, merging, or deploying.
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
- requested behavior and durable requirement sources;
- observable acceptance criteria and material design decisions;
- changed files and root diff;
- verification results and their exact proof boundaries; and
- explicitly out-of-scope behavior.

Do not include expected findings or a desired conclusion. Keep secrets, gateway response bodies,
private user text, generated artifacts, and raw logs out of the packet.

## Review and verify

1. Spawn the project `pr-reviewer` with no inherited conversation when available. Pass only the PR identity, exact SHA, neutral packet, diff, and source paths.
2. Run independent review and GitHub checks concurrently where practical.
3. Inspect correctness, error behavior, concurrency, cancellation, MVVM ownership, persistence, App Group and Keychain boundaries, gateway behavior, extension lifecycle, accessibility, tests, CI and deployment security, documentation claims, generated artifacts, and unrelated changes.
4. Treat correctness, security, data-loss, extension-contract, signing, missing-material-test, and false-evidence findings as blockers.
5. For release readiness, run `./scripts/check.sh --full` on the clean exact head.
6. If `./scripts/live-impact.sh` selects `gateway`, require `./scripts/check-live.sh gateway` on that same exact head and refresh the PR evidence.
7. Confirm GitHub reports `Required checks` and `Required live verification` as successful for the reviewed head.

Review-only work reports findings and stops. During an implementation follow-up, the root agent may
fix in-scope blockers while the PR remains open. Every new commit requires a fresh exact-head review
and verification cycle.

## Readiness gate

Before marking a PR ready or merging it, require:

1. a current PR brief and neutral reviewer packet bound to the full head SHA;
2. independently reviewed SHA equal to GitHub's current head;
3. successful `./scripts/check.sh --full` for that SHA;
4. successful applicable exact-head live evidence;
5. no blocking finding, requested change, or unresolved review thread;
6. an in-scope diff with no secret or generated-artifact violation;
7. no conflict and compliance with the base-update policy;
8. successful exact-head `Required checks` and `Required live verification`; and
9. effective base protection requiring pull requests, strict checks, and conversation resolution.

Pending, skipped, missing, cancelled, timed-out, stale, or failed mandatory evidence blocks
readiness and merge.

## Guarded merge

Run this section only when the user explicitly asks to merge.

1. Refresh the head, required checks, independent review result, reviews, threads, protection, mergeability, and scope.
2. Confirm all evidence remains bound to the same full SHA.
3. Use GitHub's protected squash merge with head-SHA matching where supported.
4. If GitHub queues auto-merge without an explicit request to leave it queued, disable it and report the blocker.
5. If the head or any gate changes, stop and restart the exact-head cycle.

Never force, use administrator bypass, dismiss valid feedback, or leave a deployment running.

## Reporting

Lead with blockers or state that none remain. Include the PR, exact reviewed head, local verification,
independent-review result, required checks, unresolved threads, protection, mergeability, action
taken, and residual proof limits.
