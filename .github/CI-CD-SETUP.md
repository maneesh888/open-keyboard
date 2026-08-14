# OpenKeyboard CI/CD Setup

## Workflow

```text
Pull request
  -> Exact-head local full gate
  -> Independent read-only PR reviewer
  -> GitHub repository hygiene
  -> GitHub OpenKeyboardCore tests
  -> GitHub iOS app + keyboard extension build
  -> Required technical checks
  -> Required checks (complete exact-head review evidence only)
  -> Required live verification
     -> pass immediately when gateway runtime is unaffected
     -> otherwise require exact-head local gateway evidence in the PR
  -> Conditional exact-head merge authorization
     -> automatic only at independent reviewer confidence 100%
     -> otherwise explicit repository-owner approval for that exact SHA
  -> Protected merge

Version tag or manual deployment
  -> Reusable OpenKeyboard CI
  -> Protected app-store-connect environment
  -> Signed archive and IPA export
  -> App Store Connect validation
  -> Upload for version tags or explicit manual upload
```

Normal CI is read-only and secretless. It does not run live gateway calls or receive gateway
credentials. GitHub Actions are pinned to full commit SHAs.

## Independent reviewer

OpenKeyboard includes `.codex/agents/pr-reviewer.toml` and the `$review-verify-merge-pr` project
skill. For release readiness, invoke the skill with the PR identity and a neutral exact-head packet.
The reviewer is sandboxed read-only and cannot mutate GitHub or the checkout.

Record the full reviewed SHA, requirement coverage, confidence, recommendation, and every blocking
finding in the PR description. Any new commit invalidates the review. This process gate complements
required checks and creates no GitHub status by itself. In the solo-maintainer configuration,
reviewer confidence exactly `100%` authorizes the automatic route; below 100%, it does not replace
the repository owner's explicit approval for the same exact SHA.

Review-submission CI re-reads current pull-request metadata and retries the review/body handoff for
at most 60 seconds. Live-policy CI similarly allows at most 120 seconds for a pushed exact head's
already-completed local live evidence to be recorded in the pull-request body. Each workflow uses
one retained serialized queue per pull request, so review, body-edit, dismissal, and live-evidence
events cannot cancel one another. Every run re-fetches current exact-head metadata rather than
trusting dispatch order. This prevents a frozen event snapshot or cancellation from leaving obsolete
evidence effective; validation still fails if either exact-head record never becomes complete.

Incomplete review metadata emits a deliberately different `Incomplete review evidence` failure.
The protected `Required checks` name is emitted only after the trusted validators accept the
complete exact-head record. GitHub retains every failed check run on a commit in its combined
rollup, so this name separation prevents an expected pre-review failure from permanently poisoning
an otherwise completed review. Technical jobs aggregate independently as `Required technical
checks`; branch protection requires both names plus `Required live verification`.

After `Required checks` has succeeded once for a SHA, the workflow treats that protected name as a
one-way latch. It inspects all prior check runs for the SHA before choosing a name. Any later invalid
or uninspectable review state emits a failed `Required checks`, and any prior non-success under that
name keeps the SHA permanently failed even if the mutable PR metadata is restored. Recovery requires
a new commit and a complete new exact-head full, live, review, and authorization cycle. This closes
the complete-to-incomplete stale-success path without reintroducing the expected pre-review poison.

## Repository automation set

The CI/CD files are paired with the complete repository-owned Codex automation set:

- `$develop-openkeyboard`: implementation routing and proportional verification.
- `work-package-planner` plus `$plan-openkeyboard-work-package`: read-only, digest-bound planning.
- `pr-reviewer` plus `$review-verify-merge-pr`: independent exact-head review and guarded readiness.

The planner and reviewer are sandboxed read-only. GitHub Actions remain the remote enforcement
layer; these agents cannot replace required checks, the explicit owner approval required below
100% confidence, protected environments, signing, or deployment evidence.

## Required environments

Create `live-policy` with no secrets and no required reviewer. It records the policy deployment
used by the stable `Required live verification` status.

Create `app-store-connect` with required reviewers. Scope these environment secrets to it:

- `APPLE_TEAM_ID`
- `KEYCHAIN_PASSWORD`
- `IOS_CERTIFICATES_P12_BASE64`
- `IOS_CERTIFICATES_PASSWORD`
- `IOS_APP_PROVISIONING_PROFILE_BASE64`
- `IOS_EXTENSION_PROVISIONING_PROFILE_BASE64`
- `APP_STORE_CONNECT_API_KEY_KEY_ID`
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_P8`

Set the environment's deployment branch/tag policy to **Selected branches and tags** and allow only:

- branch `main`
- protected release tags matching `v*`

Add a repository tag ruleset for `v*` that restricts creation to release maintainers and blocks tag
updates and deletion. The workflow also fails closed: manual dispatch must run from the exact current
`main`, and every `v*` tag must resolve to a commit contained in `origin/main` before the protected
environment job can start. The protected deployment job repeats that validation after approval and
before reading deployment secrets, so approval wait time cannot stale the earlier result.

OpenKeyboard requires separate App Store provisioning profiles for:

- `com.maneesh.openkeyboard`
- `com.maneesh.openkeyboard.keyboard`

## Release operation

Use a production version tag only after the exact commit is merged to `main`:

```bash
git tag v1.0.0 <main-commit-sha>
git push origin v1.0.0
```

The protected environment approval is the final human deployment gate. Run manual dispatch only
from `main`; it may archive and validate without upload. Set `upload_to_app_store_connect` only for
an intentional upload.

## Auto-merge

Enable GitHub's repository-level auto-merge setting. During an autonomous implementation lifecycle,
the root agent invokes native squash auto-merge only after the exact head passes local Release
verification, applicable live proof, independent review, required GitHub checks, thread resolution,
mergeability, and branch-protection validation. Automatic authorization additionally requires the
reviewer to report operational confidence of exactly `100%`. Below 100%, the PR remains draft until
the repository owner explicitly authorizes that exact SHA after reviewing every disclosed gap. If
GitHub queues instead of immediately completing the merge, the agent disables auto-merge and
reports the unsatisfied gate; it never leaves an unattended merge queued.

This repository does not use an Actions workflow, write-enabled pull-request token, or PAT to merge
pull requests.
