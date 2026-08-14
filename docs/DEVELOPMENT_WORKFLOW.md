# Development Workflow

## Semantic prompt contract changes

`Vendor/semantic-prompt-contract` is a pinned Git submodule and the only canonical home for writing
and bounded-suggestion prompt wording, semantic operation identifiers, parameter rules, response
schemas, fixtures, and deterministic rendering metadata. OpenKeyboard owns UI, networking,
authentication, persistence, parser compatibility, and response presentation.

Initialize submodules before building. For a contract upgrade, change the contract repository first,
run its Node and Swift suites, inspect golden rendering changes, update the OpenKeyboard gitlink, and
run `./scripts/check-semantic-prompt-contract.sh`. Contract or adapter changes are gateway-impacting
and require the normal exact-head live gateway evidence before release. Generated adapters must
derive from canonical JSON; do not edit them or add fallback prompt copies in this repository.

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

## Persistent local configuration

The only repository-local, Git-ignored credential file consumed by OpenKeyboard scripts is the
per-machine simulator gateway seed:

```text
<primary-checkout>/.agent/local-seeds/openkeyboard-gateway.env
```

`scripts/check-live.sh gateway`, `scripts/ios/test.sh live-gateway-smoke`,
`scripts/ios/test.sh real-keyboard-live`, and `scripts/ios/seed-simulator-gateway-config.sh` all use
the shared safety helper to resolve it. The helper derives Git's common directory, validates the
primary checkout, and accepts only a current-user-owned regular, ignored, untracked file below the
canonical `.agent/local-seeds/` directory with no group or other access or extended ACL entries.
The trusted directory chain must also be current-user-owned, non-writable by group or other users,
and free of extended ACL entries. The helper rejects any `..` traversal, external paths, unsafe
symlinks, files tracked by either the primary or executing worktree, unexpected variables, and
overly broad permissions without logging values. The optional
`OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE` override remains confined to that same directory.

Ignored files are not synchronized by Git and are not copied into linked worktrees. Each machine
and clone therefore needs its own canonical seed. A trusted secret manager may synchronize the
values across machines by materializing a mode-`600` file at the canonical path on each machine;
Git and disposable worktrees must not transport it. Protected release signing uses GitHub
environment secrets instead of a local ignored file. Other live test routes that accept environment
variables do not persist them in the repository.

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
- Gateway-impacting pushes additionally run `./scripts/check-live.sh gateway`. Credentials stay in
  `<primary-checkout>/.agent/local-seeds/openkeyboard-gateway.env`, which live scripts resolve from
  Git's common directory and read directly from every linked worktree. The seed is never copied to
  a linked worktree or sent to GitHub. An alternate
  `OPEN_KEYBOARD_SIMULATOR_GATEWAY_SEED_FILE` must remain beneath that same canonical directory.
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
It validates the requirement ledger and durable independent-review link, then runs repository
hygiene, OpenKeyboardCore tests, semantic-contract checks, and the iOS app/extension build. The
stable `Required checks` job is the ordinary branch-protection status. A structurally valid ledger
does not prove its own claims; the exact-head independent report and conditional automatic-or-human
authorization remain required.

`.github/workflows/live.yml` uses the classifier from the trusted base commit. For a gateway
runtime change, the pull request must retain unique canonical pass, target, retention, trust, and
exact-tested-SHA fields. It must also record required live-model coverage, the exact models actually
tested, and that no substitution occurred. Exact model requirements must match the tested-model
list byte-for-byte; model-agnostic gateway work may name `model-agnostic` as the requirement but
must still record the actual tested model. The stable `Required live verification` job rejects
duplicate, contradictory, fallback, and wrong-model fields and validates only that retained
evidence. Local execution is contributor-attested; GitHub never receives the credential or gateway
response.

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
proof claims. Its packet and result use a requirement ledger: every in-scope requirement has a
stable ID, observable acceptance criterion, required proof type, exact evidence, and a `VERIFIED`
or `UNVERIFIED` status. Skipped, missing, stale, fallback, wrong-target, wrong-model, ambiguous, or
contributor-attested-only material evidence is unverified. A generic model cannot satisfy an exact
model requirement. An in-scope unverified row is always a blocker and cannot be moved into residual
proof limits.

The reviewer reports findings but cannot edit, approve, comment, change PR state, deploy, or merge.
The root agent posts the review report as a durable GitHub `COMMENTED` review and links it from the
PR brief without weakening any blocker. A new commit invalidates the result and requires a fresh
exact-head review.

This is a two-phase gate. Before composing the report, the reviewer inspects all exact-head
technical evidence and the trusted validator source. `Requirement evidence` and the aggregate
`Required checks` status depend on that report being retained and linked, so they are intentionally
post-report gates. After the root posts the report and updates the PR brief, both aggregate required
statuses must pass on the same head before readiness or merge.

Independent review is a repository process gate, not a GitHub Actions status. Record its reviewed
SHA, N/N row assessment, operational confidence, merge recommendation, and durable review link in
the PR brief. Automatic authorization exists only when every row is verified, no blocker or
material uncertainty remains, and the reviewer reports exactly `100%`. Any lower confidence keeps
the PR draft until the repository owner explicitly authorizes that exact SHA after reviewing the
disclosed gaps. The required `Requirement evidence` CI job validates these fields but cannot
establish human authorship by itself.

No review can prove that unknown bugs are mathematically impossible. The fail-closed standard is
that `100%` means every stated in-scope requirement is verified with the correct proof and every
material uncertainty is reported as a blocker. It is operational proof confidence, not a claim
that unknown defects are impossible.

## Autonomous lifecycle and guarded merge

A bounded implementation request continues through branch preparation, implementation, checks,
commit, push, draft PR publication, in-scope review fixes, readiness, and guarded merge without a
confirmation at every stage only when the reviewer reports `100%`. Below 100%, the root reports the
exact head and every gap, then waits for explicit owner approval of that SHA. The latest `local
only`, `do not commit`, `do not push`, `do not create a PR`, `keep draft`, or `do not merge`
instruction stops the corresponding state change.

After every exact-head gate and the selected authorization route pass, the root agent may invoke
GitHub's native squash auto-merge with head-SHA matching. Human authorization never relabels an
unverified row and never bypasses failed checks, live evidence, conflicts, requested changes, or
unresolved threads. Any new commit expires review confidence and human approval. The root
immediately inspects the merge result. If GitHub queues the merge instead of completing it, the
agent disables auto-merge and reports the blocker; queued unattended merging is not permitted.
Ordinary GitHub Actions remain read-only and never merge pull requests.

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
signing material, archive, export, validate, and optionally upload. The deployment job revalidates
its source after environment approval and before reading deployment secrets.

Production `v*` tags must point to commits contained in `main`. Manual dispatch defaults
to validation without upload. The deployment workflow does not prove App Review acceptance or a
successful public release.
