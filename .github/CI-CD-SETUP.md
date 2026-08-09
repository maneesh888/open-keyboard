# OpenKeyboard CI/CD Setup

## Workflow

```text
Pull request
  -> Exact-head local full gate
  -> Independent read-only PR reviewer
  -> GitHub repository hygiene
  -> GitHub OpenKeyboardCore tests
  -> GitHub iOS app + keyboard extension build
  -> Required checks
  -> Required live verification
     -> pass immediately when gateway runtime is unaffected
     -> otherwise require exact-head local gateway evidence in the PR
  -> Human approval and protected merge

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

Record the full reviewed SHA and whether blocking findings remain in the PR description. Any new
commit invalidates the review. This process gate complements GitHub approval and required checks;
it does not create a GitHub status or replace maintainer review.

## Repository automation set

The CI/CD files are paired with the complete repository-owned Codex automation set:

- `$develop-openkeyboard`: implementation routing and proportional verification.
- `work-package-planner` plus `$plan-openkeyboard-work-package`: read-only, digest-bound planning.
- `pr-reviewer` plus `$review-verify-merge-pr`: independent exact-head review and guarded readiness.

The planner and reviewer are sandboxed read-only. GitHub Actions remain the remote enforcement
layer; these agents cannot replace required checks, approvals, protected environments, signing, or
deployment evidence.

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

OpenKeyboard requires separate App Store provisioning profiles for:

- `com.maneesh.openkeyboard`
- `com.maneesh.openkeyboard.keyboard`

## Release operation

Use a production version tag only after the exact commit is merged to `main`:

```bash
git tag v1.0.0 <main-commit-sha>
git push origin v1.0.0
```

The protected environment approval is the final human deployment gate. Manual dispatch may archive
and validate without upload; set `upload_to_app_store_connect` only for an intentional upload.

## Auto-merge

Enable GitHub's repository-level auto-merge setting if desired, then enable it deliberately on an
individual reviewed pull request. This repository does not use an Actions workflow with write
permissions to enable auto-merge for every PR.
