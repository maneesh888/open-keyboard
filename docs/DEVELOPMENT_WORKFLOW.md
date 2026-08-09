# Development Workflow

## Purpose

OpenKeyboard uses proportional local checks and exact-head release evidence. This file owns
verification selection and proof boundaries. `AGENTS.md` owns repository behavior and
`.github/BRANCH_PROTECTION_GUIDE.md` owns the GitHub merge settings.

Repository automation is split across `$develop-openkeyboard`, the read-only
`$plan-openkeyboard-work-package` planner route, and `$review-verify-merge-pr`. These skills route
work but do not weaken the proof requirements below.

## Proof levels

Keep these claims separate:

1. **Behavior proof:** focused tests validate deterministic Swift and keyboard behavior.
2. **Build proof:** the host app and keyboard extension compile for the simulator.
3. **Deterministic UI-target proof:** non-live UI-target tests pass on the documented simulator.
4. **Real extension proof:** the installed keyboard extension completes its real lifecycle.
5. **Live gateway proof:** an exact committed head completes the local gateway smoke.
6. **Independent review proof:** the read-only reviewer finds no blocker on the same exact head.
7. **Deployment proof:** a signed archive exports, validates, and uploads through App Store Connect.

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

Release readiness additionally requires exact-head GitHub checks and an independent review through
`$review-verify-merge-pr`; the local full gate alone is insufficient.

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
- Live test runners place injected `.xctestrun`, DerivedData, and result bundles in a private
  temporary workspace and remove that workspace plus exported credential variables on every exit.
- Each live route parses its `.xcresult` and requires exactly one passing test with no failures,
  skips, or expected failures; a successful `xcodebuild` process alone is not accepted as proof.
- The real-keyboard route clones the selected simulator, immediately restores the source to its
  prior booted state when needed, seeds only the disposable clone, refreshes extension registration,
  and deletes the clone on every handled exit. Source gateway configuration is not modified.
- Never use `--no-verify`. A missing toolchain or credential is a blocker for the affected gate.

## GitHub checks

`.github/workflows/ci.yml` checks out the exact pull-request head with read-only permissions.
It runs repository hygiene, OpenKeyboardCore tests, and the iOS app/extension build. The stable
`Required checks` job is the ordinary branch-protection status.

`.github/workflows/live.yml` uses the classifier from the trusted base commit. For a gateway
runtime change, the pull request must retain the local pass marker and exact tested SHA. The stable
`Required live verification` job validates only that retained evidence. Local execution is
contributor-attested; GitHub never receives the credential or gateway response.

The classifier treats every file under `OpenKeyboard/`, `OpenKeyboardCore/Sources/`, and
`OpenKeyboardExtension/` as runtime-sensitive regardless of extension. This deliberately favors a
live recheck over allowing a new resource or configuration format to bypass gateway verification.

## Independent pull-request review

The repository-owned `.codex/agents/pr-reviewer.toml` defines a read-only reviewer specialized for
OpenKeyboard. `$review-verify-merge-pr` builds a neutral packet from the request, PR brief, exact
diff, requirement sources, and bounded evidence, then invokes that reviewer without inherited
implementation context.

The reviewer checks correctness, regressions, MVVM and persistence boundaries, gateway and secret
handling, keyboard-extension lifecycle, signing/deployment safety, test coverage, and truthful
proof claims. It reports findings but cannot edit, approve, comment, change PR state, deploy, or
merge. A new commit invalidates the result and requires a fresh exact-head review.

Independent review is a repository process gate, not a GitHub Actions status. Record its reviewed
SHA and result in the PR brief; branch protection separately enforces GitHub checks and approvals.

## Autonomous lifecycle and guarded merge

A bounded implementation request continues through branch preparation, implementation, checks,
commit, push, draft PR publication, in-scope review fixes, readiness, and guarded merge without a
confirmation at every stage. The latest `local only`, `do not commit`, `do not push`, `do not create
a PR`, `keep draft`, or `do not merge` instruction stops the corresponding state change.

After every exact-head gate passes, the root agent may invoke GitHub's native squash auto-merge with
head-SHA matching. It immediately inspects the result. If GitHub queues the merge instead of
completing it, the agent disables auto-merge and reports the blocker; queued unattended merging is
not permitted. Ordinary GitHub Actions remain read-only and never merge pull requests.

Deployment is outside this lifecycle and still requires explicit authorization plus approval in
the protected `app-store-connect` environment.

## Planning and development automation

`$develop-openkeyboard` is the default implementation route. It selects Fast, Standard, or Release
mode, keeps UI, ViewModel, service, extension, gateway, and secret boundaries explicit, and maps the
change to the repository scripts above.

When planning is explicitly requested, the read-only `work-package-planner` invokes
`$plan-openkeyboard-work-package`. It reads only current status, work-queue, completion-plan, and
directly relevant focused-plan sections, then returns a compact work order with source-object
digests. A clear implementation request bypasses this planning route.

## Deployment

`.github/workflows/deploy-ios.yml` is separate from pull-request CI. It reruns the reusable
deterministic CI workflow, then enters the protected `app-store-connect` environment to import
signing material, archive, export, validate, and optionally upload.

Production `v*` tags must point to commits contained in `main`. Manual dispatch defaults
to validation without upload. The deployment workflow does not prove App Review acceptance or a
successful public release.
