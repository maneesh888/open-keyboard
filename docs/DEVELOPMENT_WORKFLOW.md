# Development Workflow

## Purpose

OpenKeyboard uses proportional local checks and exact-head release evidence. This file owns
verification selection and proof boundaries. `AGENTS.md` owns repository behavior and
`.github/BRANCH_PROTECTION_GUIDE.md` owns the GitHub merge settings.

## Proof levels

Keep these claims separate:

1. **Behavior proof:** focused tests validate deterministic Swift and keyboard behavior.
2. **Build proof:** the host app and keyboard extension compile for the simulator.
3. **Deterministic UI-target proof:** non-live UI-target tests pass on the documented simulator.
4. **Real extension proof:** the installed keyboard extension completes its real lifecycle.
5. **Live gateway proof:** an exact committed head completes the local gateway smoke.
6. **Deployment proof:** a signed archive exports, validates, and uploads through App Store Connect.

Never infer a stronger proof level from a weaker one. Normal GitHub CI proves behavior and build,
not UI quality, real keyboard lifecycle, live gateway behavior, signing, or deployment.

## Modes and cumulative gates

Run targeted tests while editing, then run the highest cumulative gate required by the final state:

| Mode | Final gate | Use |
|---|---|---|
| Fast | Affected tests, then `./scripts/check.sh --hygiene` | Bounded local change |
| Standard | `./scripts/check.sh --quick` | Normal completed implementation or commit |
| Release | `./scripts/check.sh --full` on exact `HEAD` | PR readiness, tag, or release |

Calling `./scripts/check.sh` without an argument runs `--full`.

- `--hygiene`: environment preflight, shell/YAML syntax, secret and policy regressions,
  tracked and untracked whitespace.
- `--quick`: hygiene, OpenKeyboardCore tests, and app plus keyboard-extension build.
- `--full`: quick plus deterministic UI-target tests on iPhone 16.

Screenshots, real extension testing, and live gateway verification remain separate because they
require simulator state, human inspection, or local credentials.

The explicit `./scripts/ios/test.sh ui` route remains broader than `--full`. It includes
credential- and simulator-state-dependent classes, so it is diagnostic rather than a mandatory
credential-free push gate.

## Targeted routing

| Changed surface | Targeted verification |
|---|---|
| Model, parser, or core service | `./scripts/ios/test.sh core` |
| Host app or extension compilation | `./scripts/ios/test.sh build` |
| Host app user flow | `./scripts/ios/test.sh ui` |
| Visual layout | `./scripts/ios/test.sh screenshots` plus image inspection |
| Keyboard extension/App Group behavior | `./scripts/ios/test.sh real-keyboard-live` when configured |
| Gateway runtime or contract | `./scripts/check-live.sh gateway` on committed exact `HEAD` |
| Workflow, hooks, or security policy | `./scripts/check.sh --hygiene` |

## Hooks

Enable committed hooks once per clone or worktree before the first commit or push:

```bash
./scripts/check-environment.sh --full
./scripts/install-hooks.sh
git config --local --get core.hooksPath
```

The path must be `.githooks`.

- Pre-commit requires an exact staged candidate and runs `./scripts/check.sh --quick`.
- Pre-push requires a clean exact `HEAD`, runs `./scripts/check.sh --full`, and
  classifies gateway impact against `origin/main`.
- Gateway-impacting pushes additionally run `./scripts/check-live.sh gateway`. Credentials
  stay in the ignored local seed and are never sent to GitHub.
- Never use `--no-verify`. A missing toolchain or credential is a blocker for the affected gate.

## GitHub checks

`.github/workflows/ci.yml` checks out the exact pull-request head with read-only permissions.
It runs repository hygiene, OpenKeyboardCore tests, and the iOS app/extension build. The stable
`Required checks` job is the ordinary branch-protection status.

`.github/workflows/live.yml` uses the classifier from the trusted base commit. For a gateway
runtime change, the pull request must retain the local pass marker and exact tested SHA. The stable
`Required live verification` job validates only that retained evidence. Local execution is
contributor-attested; GitHub never receives the credential or gateway response.

## Deployment

`.github/workflows/deploy-ios.yml` is separate from pull-request CI. It reruns the reusable
deterministic CI workflow, then enters the protected `app-store-connect` environment to import
signing material, archive, export, validate, and optionally upload.

Production `v*` tags must point to commits contained in `main`. Manual dispatch defaults
to validation without upload. The deployment workflow does not prove App Review acceptance or a
successful public release.
