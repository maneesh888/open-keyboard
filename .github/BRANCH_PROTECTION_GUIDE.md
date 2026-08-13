# Branch Protection Guide

Protect `main` with a branch ruleset or branch protection rule:

1. Require a pull request before merging.
2. Require at least one approval from a human who is neither the pull-request author nor an
   identifiable implementing contributor. Enable stale-review dismissal and do not permit the
   implementing agent's self-attestation to substitute for that approval.
3. Require conversation resolution.
4. Require branches to be up to date before merging.
5. Require these status checks:
   - `Required checks`
   - `Required live verification`
6. Block force pushes and branch deletion.
7. Disable bypass for administrators if the repository should enforce one merge path.

Before an intentional merge, also run `$review-verify-merge-pr`, post its requirement-coverage
report as a durable GitHub `COMMENTED` review, and link that review plus its exact reviewed SHA from
the PR description. Every in-scope requirement must be verified; skipped, missing, stale, fallback,
wrong-target, or wrong-model evidence blocks readiness. This independent Codex review is a process
gate rather than a GitHub status check, so retain the GitHub approval requirement above.

Recommended repository merge settings:

- Allow squash merge.
- Delete head branches automatically after merge.
- Allow auto-merge so the guarded root-agent lifecycle can invoke it for an exact reviewed head.

This is not an unattended merger. The root agent may invoke GitHub's native auto-merge only after
all exact-head gates pass, and must disable it immediately if GitHub queues rather than completes the
merge. Ordinary pull-request workflows remain read-only and cannot merge.

The live policy status is secretless. Gateway-impacting pull requests run
`./scripts/check-live.sh gateway` locally and record the full tested head SHA in the PR body.
Any new commit invalidates that evidence until the local check and PR body are refreshed.

Protect the `app-store-connect` environment with required reviewers. Keep all signing and App
Store Connect secrets in that environment, not as ordinary CI inputs. Restrict its deployment refs
to `main` and protected `v*` tags, and use a tag ruleset to limit `v*` creation to release maintainers
while blocking tag updates and deletion.
