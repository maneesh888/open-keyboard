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

OpenKeyboard uses proportional local checks and exact-head release evidence. `AGENTS.md` is the
canonical straight-line workflow. This file is the detailed verification reference loaded only
when a task needs route selection, hooks, CI, signing, deployment, or proof details.

Repository automation is split across `$develop-openkeyboard`, the read-only
`$plan-openkeyboard-work-package` planner route, and `$review-verify-merge-pr`. These skills route
work but do not weaken the proof requirements below.

## Evidence classes and claims

Every verification artifact belongs to one of three runtime evidence classes:

1. **Automated regression evidence:** unit tests, XCTest, XCUITest, mocked gateway tests, debug
   launch states, seeded UI/result states, component hosts, and `XCTAttachment` screenshots. An
   XCUITest that installs and activates the real keyboard extension remains automated evidence.
2. **Normal simulator runtime proof:** a normally installed and launched app, without
   `--uitesting`, debug-state injection, seeded result panels, or test-host shortcuts. The actual
   extension is exercised through an ordinary host-app text field and visible production UI, with
   screenshots captured directly from Simulator/Xcode outside XCTest.
3. **Physical-device proof:** the exact signed build is installed on the configured device and
   exercised through the normal extension lifecycle, with screenshots captured directly from the
   device.

These classes support separate claims: build success, automated regression coverage, transport
success, semantic acceptance, visual/runtime acceptance, physical-device acceptance, independent
review, signing, deployment, and App Review. Never infer a stronger claim from a weaker class.
Normal GitHub CI proves deterministic behavior/build only. Automated tests—including real-extension
XCUITest—cannot alone authorize a proof-sensitive push, PR readiness, release readiness, or a claim
that the user-visible workflow works.

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

Automated screenshots, automated real-extension tests, normal simulator runtime proof, and live
gateway verification remain separate. The runtime proof does not replace XCTest coverage, and an
`XCTAttachment` does not become normal simulator proof because the installed extension was active.

The explicit `./scripts/ios/test.sh ui` route remains broader than `--full`. It includes
credential- and simulator-state-dependent classes, so it is diagnostic rather than a mandatory
credential-free push gate.

## Targeted routing

| Changed surface | Targeted verification |
|---|---|
| Model, parser, or core service | `./scripts/ios/test.sh core` |
| Host app or extension compilation | `./scripts/ios/test.sh build` |
| Host app user flow | `./scripts/ios/test.sh ui` for automated regression; normal simulator runtime proof before push |
| Visual layout | `./scripts/ios/test.sh screenshots` for automated regression; direct Simulator screenshots from a normal launch before push |
| Keyboard extension/App Group behavior | `./scripts/ios/test.sh real-keyboard-live` for automated real-extension regression; normal host-app runtime route before push |
| Gateway runtime or contract | `./scripts/check-live.sh gateway` for automated transport/contract evidence; normal runtime proof when user-visible semantic behavior changes |
| Model capability, long input, parser compatibility, retry, or operation-scoped warnings | `./scripts/check-live.sh gateway-differential` on committed exact `HEAD` |
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

The strict seed parser accepts either a complete legacy URL/API-key/model triple or complete
`LOW`/`HIGH` triples. A configured role can never be partial. Duplicate variables, unknown keys,
unsafe model IDs, missing differential roles, identical role models, reversed mappings, and silent
substitution are rejected without printing values. Ordinary checks use the high profile when it is
configured and otherwise use the legacy fallback; they never silently use the low profile.

The targeted differential runner performs automated deterministic prerequisites and `build-for-testing`
once, then reuses the compiled `.xctestrun` for isolated low and high disposable simulators. It runs one
small baseline/boundary/follow-up test per role and removes both simulators, injected environment,
DerivedData, result bundles, summaries, and temporary evidence on exit. A low-model success at the
candidate boundary is retained as `diagnostic-boundary-not-established`, not promoted to passing
evidence.

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
- Ordinary and real-keyboard live routes are automated regression evidence. They parse `.xcresult`
  and require exactly one passing test with
  no failures, skips, or expected failures. The differential route separately requires its exact
  deterministic prerequisite count and high-profile pass; a low-profile success is an explicit
  diagnostic skip that the exact-head validator refuses as passing matrix evidence. A successful
  `xcodebuild` process alone is never accepted as proof.
- Simulator-backed test modes use one repository-wide host lock so concurrent worktrees or agents
  cannot drive the same Simulator service at once.
- Live routes create a fresh disposable simulator with the selected device type and runtime. They
  never shut down, erase, delete, or modify the selected existing simulator. The automated
  real-keyboard route seeds and restarts only its disposable simulator, then deletes it on exit.
- Never use `--no-verify`. A missing toolchain or credential is a blocker for the affected gate.
- The exact-head impact classifier selects `gateway-differential` only for changes touching
  model-capability classification, long-input handling, parser compatibility, retry behavior,
  automatic-analysis warnings, manual-action scope, Translate warning scope, or the matrix workflow
  itself. Pre-release verification invokes `./scripts/check-live.sh gateway-differential`
  explicitly. Unrelated pull requests do not run the two-profile matrix.

## Normal simulator and device proof gate

Changes affecting UI, keyboard-extension lifecycle, Apply/Copy/Back/Rerun behavior, live gateway
behavior, or result presentation require normal simulator runtime proof before push. Local
implementation and commits may proceed after deterministic tests.

Normal simulator runtime proof must:

- install and normally launch the actual app and bundled keyboard extension;
- avoid `--uitesting`, debug-state injection, seeded result panels, component/test hosts, and
  XCTest-driven interaction;
- focus an ordinary host-app text field and activate OpenKeyboard through the normal keyboard
  lifecycle;
- invoke the action through visible production UI and use the configured live gateway when
  semantic behavior is being verified;
- capture screenshots directly from Simulator/Xcode, never from `XCTAttachment`;
- record exact Git SHA, build configuration, simulator model, OS version, action, source text, and
  observed result without exposing credentials or private configuration.

If Codex can interact with the normal simulator confidently, it collects this proof directly. Use
the first reliable route: a purpose-built, generically named Simulator-control integration;
Computer Use or equivalent host UI automation that can inspect and operate the normal Simulator;
or the manual checklist in `docs/REAL_EXTENSION_SMOKE_PLAN.md`. If interaction is unavailable,
unreliable, or ambiguous, stop before push/readiness and state the unverified behavior. Running
more XCTest does not resolve the blocker.

Physical-device proof requires the exact signed build installed on the configured device. A
Simulator or XCTest run cannot satisfy it. When the configured device is unavailable, report the
device requirement blocked and request manual verification.

The user may explicitly authorize a proof-sensitive push with missing runtime proof disclosed, but
that exception does not mark the evidence verified and cannot authorize PR readiness or merge.
Never mark a PR ready or merge while required simulator/device proof is missing.

## GitHub checks

`.github/workflows/ci.yml` checks out the exact pull-request head with read-only permissions.
It validates the requirement ledger and durable independent-review link, then runs repository
hygiene, OpenKeyboardCore tests, semantic-contract checks, and the iOS app/extension build. The
stable `Required technical checks` job covers the ordinary build and test gates. Every review/body
event creates the fixed protected `Required checks` root job. That job accepts only when the trusted
validators accept both the immutable event snapshot and a separately fetched current snapshot of
the exact-head requirement ledger, durable independent-review link, and selected automatic-or-human
authorization route. Initial incomplete metadata therefore fails the protected name. Because
GitHub retains `pull_request_review` and `pull_request` check suites separately, the completed body
event does not replace the expected first review-event failure. After linking the report, the root
submits a same-head COMMENTED revalidation trigger clearly labeled as neither approval,
independent-review evidence, nor merge authorization. The trigger has no project-reviewer identity
marker, and its review-event run must pass. A structurally valid ledger does not prove its own
claims; the exact-head independent report and conditional automatic-or-human authorization remain
required.

CI deliberately does not serialize metadata events because GitHub concurrency queues are capped and
dispatch-order execution is not guaranteed. A stale event that runs late also validates current
metadata, so it can conservatively block but cannot authorize invalid current state. Before merge,
the agent re-fetches current metadata, reruns the trusted validators, and requires the current check
rollup to point to completed successful root jobs. It also requires
`gh pr checks <number> --required` to exit successfully so a failed event-family result cannot be
hidden by a newer same-name check.

`.github/workflows/live.yml` uses the classifier from the trusted base commit. For a gateway
runtime change, the pull request must retain unique canonical pass, target, retention, trust, and
exact-tested-SHA fields. It must also record required live-model coverage, the exact models actually
tested, and that no substitution occurred. Exact model requirements must match the tested-model
list byte-for-byte; model-agnostic gateway work may name `model-agnostic` as the requirement but
must still record the actual tested model. Exact-model runs set
`OPEN_KEYBOARD_LIVE_REQUIRED_MODEL=<exact-id>`. Every exact-model or model-agnostic run must verify
the seeded model through the production plain-text grammar flow; a connected-but-unverified
`.limited` result is not passing live evidence. Every live-evidence body event creates the stable
`Required live verification` root job. It rejects duplicate, contradictory, fallback, and
wrong-model fields in both the immutable event body and the current exact-head body. Local execution
is contributor-attested; GitHub never receives the credential or gateway response.

For `gateway-differential`, retained model fields use canonical
`low=<exact-id>, high=<exact-id>` order. Separate canonical fields record baseline outcomes,
long-text differential outcomes, follow-up outcomes, operation-scoped warning verification, and
per-profile latency. The validator rejects missing roles, stale heads, duplicates, reversed or
malformed mappings, substitutions, low success presented as a capability boundary, high failure,
unverified scenarios, and contradictory evidence. GitHub still receives no credentials or response
bodies.

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
exact-head review. The linked submission must be the newest same-head COMMENTED report that declares
the isolated project-reviewer identity; a later report with a blocker supersedes every older positive
report. The later non-review revalidation trigger is a separate COMMENTED submission and does not
supersede the linked project-reviewer report. CI validates each immutable review/body event snapshot
and the current GitHub state without depending on event execution order. A stale run can over-block,
but it cannot validate an invalid current report.

This is a two-phase gate. Before composing the report, the reviewer inspects all exact-head
technical evidence and the trusted validator source. `Required checks` depends on that report being
retained and linked, so it is intentionally a post-report gate; `Required technical checks` can pass
before the report exists. After the root posts the report and updates the PR brief, all three
protected statuses (`Required technical checks`, `Required checks`, and `Required live
verification`) must pass on the same head before readiness or merge. The root must also submit the
same-head non-approval revalidation trigger after linking the report and require
`gh pr checks <number> --required` to succeed.

Immediately before readiness and again before guarded merge, re-fetch and revalidate the current PR
body, linked review, head, threads, and protected check rollup. Keep the PR draft during the evidence
handoff. Require all required check entries to be completed successes, run
`gh pr checks <number> --required`, and rerun the trusted validators locally; if current metadata is
newer than the passing run or freshness is unclear, stop instead of inferring authorization.

Independent review is a repository process gate, not a GitHub Actions status. Record its reviewed
SHA, N/N row assessment, operational confidence, merge recommendation, and durable review link in
the PR brief. Automatic authorization exists only when every row is verified, no blocker or
material uncertainty remains, and the reviewer reports exactly `100%`. Any lower confidence keeps
the PR draft until the repository owner explicitly authorizes that exact SHA after reviewing the
disclosed gaps. The trusted review-evidence classification validates these fields before
`Required checks` can pass, but it cannot establish human authorship by itself.

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
