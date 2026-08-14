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
  -> Required checks (passes only with complete event-and-current exact-head review evidence)
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

Review and live-policy CI do not use a per-PR concurrency queue: [GitHub caps such queues and does
not guarantee dispatch-order execution](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).
Instead, every relevant metadata event creates the fixed
protected root job immediately. `Required checks` validates the immutable event body (plus the event
review overlay when present) and independently validates the current body and current review list.
`Required live verification` applies the same event-and-current rule to retained live evidence.
Both jobs verify that the current head still equals the event head.

The initial COMMENTED review or synchronize event is expected to fail the protected name while the
PR body still lacks its exact-head evidence. The later body-edit event must produce the newer passing
result. A canceled, pending, stale, or invalid latest event remains visible under the protected name
and blocks. If GitHub schedules an older event late, current-state validation makes it fail rather
than authorizing invalid current metadata; this may conservatively require a fresh valid body event,
but it cannot convert invalid current evidence into a pass. Technical jobs aggregate independently
as `Required technical checks`; branch protection requires that name plus `Required checks` and
`Required live verification`.

The linked COMMENTED submission must be the newest same-head report that identifies itself as the
isolated project reviewer; a later blocking report always supersedes an older positive report.
Immediately before readiness and merge, the guarded agent re-fetches the current body, reviews,
head, threads, and check rollup, reruns the trusted validators, and requires the newest protected
results to be completed successes. GitHub platform refusal to create a workflow run is outside an
Actions workflow's enforcement ability; if current metadata is newer than the successful run or
cannot be inspected, the guarded agent stops instead of inferring authorization.

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
