# Branch Protection Guide

Protect `main` with a branch ruleset or branch protection rule:

1. Require a pull request before merging.
2. Require conversation resolution.
3. Require branches to be up to date before merging.
4. Require these status checks:
   - `Required technical checks`
   - `Required checks`
   - `Required live verification`
5. Block force pushes and branch deletion.
6. Disable bypass for administrators if the repository should enforce one merge path.

For a solo-maintainer repository, the required GitHub approval count may remain zero because a
pull-request author cannot approve their own PR. The repository's conditional authorization rule
still applies: automatic merge requires an exact-head independent reviewer result of operational
confidence `100%`; any lower result requires explicit repository-owner authorization for that
exact head after the reviewer discloses every gap. Organizations with a second maintainer should
add a required independent GitHub approval as an additional gate.

Before an intentional merge, also run `$review-verify-merge-pr`, post its requirement-coverage
report as a durable GitHub `COMMENTED` review, and link that review plus its exact reviewed SHA from
the PR description. Skipped, missing, stale, fallback, wrong-target, or wrong-model evidence remains
`UNVERIFIED`; it prevents automatic authorization and forces the explicit human route. Human
authorization accepts the disclosed risk but never bypasses the required statuses above.

The status checks do not themselves establish normal simulator or physical-device proof. For UI,
keyboard-extension lifecycle, Apply/Copy/Back/Rerun, live gateway, or result-presentation changes,
the PR ledger must retain exact-head normal runtime evidence from a normally launched app and
direct Simulator/Xcode screenshots. XCTest/XCUITest, seeded states, and `XCTAttachment` screenshots
remain automated regression evidence. Required physical-device proof must come from the exact
signed build on the configured device. Missing required simulator/device proof blocks readiness and
merge under both automatic and human authorization routes.

Every review/body event creates the fixed `Required checks` root job, and every live-evidence body
event creates the fixed `Required live verification` root job. The first project-review submission
normally fails because its immutable PR body cannot yet link the newly created review. GitHub keeps
the latest `pull_request_review` and `pull_request` check suites separately, so the completed body
event cannot replace that review-event failure. After linking the report, submit a same-head
COMMENTED revalidation trigger that explicitly says it is not an approval, independent-review
report, or merge authorization. That review event must pass both immutable and current validation.
The trigger must not contain the project-reviewer identity marker. The workflows do not use capped
concurrency queues. Each run validates both its immutable event snapshot and current exact-head
GitHub metadata, so late or canceled work blocks or conservatively over-blocks instead of
authorizing invalid current state. The PR must link the newest same-head project-reviewer COMMENTED
report; a later blocker report supersedes every older positive report.

Before merge, re-fetch the current body, reviews, head, threads, and current check rollup; rerun the
trusted validators locally and require the current `Required checks` and `Required live verification`
results to be completed successes with no pending, canceled, skipped, or failing required entry.
Run `gh pr checks <number> --required` and require a successful exit; a newest-by-name query alone
can hide an older failed event family. If a GitHub event was not created, current metadata is newer
than the passing run, or freshness cannot be established, do not merge automatically.

Recommended repository merge settings:

- Allow squash merge.
- Delete head branches automatically after merge.
- Allow auto-merge so the guarded root-agent lifecycle can invoke it for an exact reviewed head.

This is not an unattended merger. The root agent may invoke GitHub's native auto-merge only after
all exact-head gates pass and either the reviewer reports `100%` or the owner has explicitly
authorized the current SHA. When reviewer confidence is below 100%, the root must keep the PR draft,
ask the owner, and stop. It must disable auto-merge immediately if GitHub queues rather than
completes the merge. Ordinary pull-request workflows remain read-only and cannot merge.

GitHub cannot distinguish a human from an agent when both operate through the same user account and
credential. The skills therefore treat the owner's current-task message as an authority boundary
and forbid an agent from manufacturing the corresponding PR fields. If platform-enforced human
presence is required, remove merge permission from agent credentials and have the owner click Merge
in GitHub; that is stronger than any text field or same-account API action.

The live policy status is secretless. Gateway-impacting pull requests run
`./scripts/check-live.sh gateway` locally and record the full tested head SHA in the PR body.
Any new commit invalidates that evidence, reviewer confidence, and human authorization until the
exact-head cycle and PR body are refreshed.

Protect the `app-store-connect` environment with required reviewers. Keep all signing and App
Store Connect secrets in that environment, not as ordinary CI inputs. Restrict its deployment refs
to `main` and protected `v*` tags, and use a tag ruleset to limit `v*` creation to release maintainers
while blocking tag updates and deletion.
