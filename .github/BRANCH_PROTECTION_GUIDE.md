# Branch Protection Guide

Protect `main` with a branch ruleset or branch protection rule:

1. Require a pull request before merging.
2. Require at least one approval for product changes when multiple maintainers are available.
3. Require conversation resolution.
4. Require branches to be up to date before merging.
5. Require these status checks:
   - `Required checks`
   - `Required live verification`
6. Block force pushes and branch deletion.
7. Disable bypass for administrators if the repository should enforce one merge path.

Recommended repository merge settings:

- Allow squash merge.
- Delete head branches automatically after merge.
- Allow auto-merge, but enable it deliberately per reviewed PR.

The live policy status is secretless. Gateway-impacting pull requests run
`./scripts/check-live.sh gateway` locally and record the full tested head SHA in the PR body.
Any new commit invalidates that evidence until the local check and PR body are refreshed.

Protect the `app-store-connect` environment with required reviewers. Keep all signing and App
Store Connect secrets in that environment, not as ordinary CI inputs.
