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

## Universal AI Connector consumption

`Vendor/universal-ai-connector` is a second pinned Git submodule. OpenKeyboard links only the public
`UniversalAiConnector` Swift package product from its `swift-package/` directory. Never import the
private bridge or consume an adjacent checkout, branch tip, local modification, or uncommitted API.

After initializing submodules, run `./scripts/bootstrap-universal-ai-connector.sh` before a direct
Xcode build. Repository iOS test routes call it automatically. The bootstrap verifies the checkout
against the recorded gitlink, refuses tracked connector modifications, invokes the connector's
canonical XCFramework build, and validates its arm64 iOS device and Simulator slices. Connector
gitlink changes require the exact-head differential live matrix. Bootstrap, package-project,
adapter, model-discovery, and generation-pipeline changes default to live verification, subject to
behavior-scoped assessment. Normal simulator proof applies when acceptance includes a user-visible
workflow; nonvisual gateway criteria may use relevant live evidence.
See `docs/UNIVERSAL_AI_CONNECTOR.md` for the runtime ownership boundary.

## Purpose

OpenKeyboard uses proportional local checks and exact-head release evidence. `AGENTS.md` is the
canonical straight-line workflow. This file is the detailed verification reference loaded only
when a task needs route selection, hooks, CI, signing, deployment, or proof details.

Repository automation is split across `$develop-openkeyboard`, the read-only compact
`$plan-openkeyboard-work-package` route, the read-only phased
`$plan-openkeyboard-major-milestone` route, the UI-audit specialist `$audit-openkeyboard-ui`, the
product-language specialist `$write-openkeyboard-product-copy`, and `$review-verify-merge-pr`.
These skills route work but do not weaken the proof requirements below.

## Authority and proof-first mode

`AGENTS.md` is the sole authority for the ledger, sticky constraints, proof-first transitions,
physical-device denial, lifecycle autonomy, and task-status labels. Apply it before mutation and at
every phase or state transition. Authority and readiness are separate: authorization permits a
stage, while the proportional deterministic, live, runtime, exact-head, review, and GitHub evidence
decides when that stage is ready. This reference only supplies the mechanics below.

## Evidence classes and claims

Use the three evidence classes and exact claim boundaries defined in `AGENTS.md`. The routes below
implement those classes; they never promote automated or diagnostic output into normal simulator
or physical-device proof.

## Modes and cumulative gates

Run targeted tests while editing. Do not repeatedly run cumulative gates after small evidence or
wording changes. When the bounded diff is ready, freeze it and use the highest gate required by the
next state. Validate or regenerate any diff-bound applicability manifest against the complete
intended diff before the proportional hook or aggregate gate:

| Mode | Final gate | Use |
|---|---|---|
| Fast | Affected tests, then `./scripts/check.sh --hygiene` | Bounded local change |
| Standard | `./scripts/check.sh --hygiene` for classified documentation-only changes; `--quick` otherwise | Normal completed implementation or commit |
| Release | `./scripts/check.sh --hygiene` for classified documentation-only changes; `--full` otherwise, on exact `HEAD` | PR readiness, tag, or release |

Calling `./scripts/check.sh` without an argument runs `--full`.

The mandatory commit hook supplies the proportional staged Standard result; do not immediately
duplicate that same command while the staged content is unchanged. After the final commit, run the
Release gate once on the clean exact head, then perform the applicable live/runtime work and one
independent review. When push is authorized, the mandatory pre-push hook is that Release run; do
not manually run the same gate immediately before it. When push is unavailable, a manual local run
does not exempt a later push from its hook. Any edit or commit starts a new exact-head cycle. No
deterministic hook result substitutes for live/runtime evidence, GitHub checks, or review.

Release readiness additionally requires exact-head GitHub checks and an independent review through
`$review-verify-merge-pr`; the local deterministic gate alone is insufficient.

- `--hygiene`: environment preflight, shell/YAML syntax, secret and policy regressions,
  tracked and untracked whitespace.
- `--quick`: hygiene, OpenKeyboardCore tests, and app plus keyboard-extension build.
- `--full`: quick plus deterministic UI-target tests on iPhone 16.

The staged commit and complete branch diff are classified by `scripts/verification-scope.py`.
Regular Markdown under `docs/` qualifies as documentation-only, including new ordinary guides.
The root `README.md`, active policy documents, and policy-named paths are excluded.
Empty, mixed, unknown non-documentation, source,
dependency, build, workflow, policy, unusual-mode, and malformed diffs use the full route.
Documentation-only work still runs environment, shell/YAML, secret, working/staged/committed
whitespace, and policy checks. The committed check uses the complete base-to-head diff on a clean
checkout, including in GitHub CI.

The deterministic UI gate uses one worktree-scoped Xcode session with parallel testing disabled
for its fixed iPhone 16 destination.

Automated screenshots, automated real-extension tests, normal simulator runtime proof, and live
gateway verification remain separate. The runtime proof does not replace XCTest coverage, and an
`XCTAttachment` does not become normal simulator proof because the installed extension was active.

The explicit `./scripts/ios/test.sh ui` route remains broader than `--full`. It includes
credential- and simulator-state-dependent classes, so it is diagnostic rather than a mandatory
credential-free push gate.

## Xcode MCP acceleration

Xcode 27+ can expose the open workspace through `xcrun mcpbridge`. Require Xcode Intelligence
permission, pass the active worktree's absolute path as `workspaceIdentifier`, and use
`XcodeListWorkspaces` to confirm that exact workspace is open before the first call and after any
Xcode-window change. Another checkout's Xcode window is not a substitute.

Use discovery, build logs, documentation search, focused builds/tests, and previews only for their
named purpose. Builds prove builds; MCP tests are automated regression evidence; previews are
diagnostic. Xcode MCP tools supplement; they never replace repository scripts, diff classification,
exact-head full/live gates, independent review, protected checks, or human approval. MCP writes are
ordinary repository mutations and retain the same authority, diff, secret, hook, and verification
requirements.

### Xcode 27 Device Hub preflight

Bind each attempt to one Xcode installation with command-scoped `DEVELOPER_DIR`; record the app
path, `xcodebuild -version`, release channel, runtime/build, and exact owned UUID. Never change or
depend on global `xcode-select`. Treat opening Device Hub's unfiltered sidebar as physical-device discovery
because it can reveal paired-device inventory. With physical-device authority `NO`, do not open that sidebar:
use the exact-UUID structured Simulator route below, or another route proven
to constrain discovery to Simulators before presenting inventory. Only when physical-device
discovery is explicitly authorized, or a simulator-only view is established first, select the
intended row and match its Info UUID and OS to the owned Simulator. Distinguish host-window control,
sidebar visibility, CoreSimulator state, and app runtime state.

The sidebar is curated, not a complete inventory. Xcode 27 notes say parallel-test Simulators may
be hidden and describe pasteboard timeout/synchronization changes; neither a hidden row nor paste
failure proves a lock or authorization failure. These release notes do not establish the cause of an
older `DTServiceHub` or lockdown error without direct evidence. Allow Xcode 27.1 several minutes for
first launch. Its Duo runtime does not support most app extensions, so use a supported non-Duo
Simulator unless Duo behavior is the acceptance criterion; never convert a physical-device
limitation into physical-device authority.

Device Hub can capture a full-device-resolution screenshot, but it becomes normal runtime proof
only after production interaction, visible-state inspection, privacy review, complete runtime
record, and delivery. It never upgrades a preview, automated test, or seed. Do not weaken trust,
certificates, permissions, or secret handling to make this route work.

#### Automated gates are not Device Hub interaction

Device Hub availability is not an XCTest prerequisite. Repository scripts own exact Simulator
selection, validated result-bundle handling, cleanup, and automated-evidence labeling; never replace
them with manual interaction or relabel XCTest as normal runtime proof. For new-Xcode compatibility,
record version/build/channel and use scoped `DEVELOPER_DIR`, a compatible runtime, and an exact owned
UUID. An installed prerelease proves only its named build and channel, not the current stable release.

Official policy sources: [Device Hub management](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub),
[interaction](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub),
[capture](https://developer.apple.com/documentation/xcode/capturing-screenshots-and-videos-from-devices),
[Xcode 27](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes),
[Xcode 27.1](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes), and
[testing](https://developer.apple.com/documentation/xcode/testing).

### Simulator and device-interaction safety

Hold the repository's shared Simulator lock for the full Xcode MCP device-interaction session.
Create and record a fresh disposable UUID, require `deviceIsSimulator == true` plus an exact UUID
match before interaction, end the session before releasing the lock, and delete only that owned
Simulator. Never use best-match or a pre-existing/user-open device.

Physical-device authority remains separately default-denied. Avoid discovery that may enumerate
connected devices, including `XcodeListRunDestinations`. Destination-implicit build/test/run/preview
calls may inherit a physical destination; use repository scripts when they cannot accept the exact
owned UUID. If a returned `skillToTrigger` is unavailable, end the session and escalate instead of
bypassing it with direct event synthesis. Hierarchies and successful actions are not self-verifying:
normal proof still needs a normal launch, production interaction, screenshot inspection, runtime
record, and artifact delivery.

### Structured Xcode interaction route

When available, use structured device state rather than guessing host coordinates:

1. Confirm the exact worktree with `XcodeListWorkspaces`.
2. Keep the repository-created UUID unless discovery can be constrained to Simulators.
3. Start `DeviceInteractionStartWorkspaceSession`; require Simulator type and exact UUID match.
4. Call `DeviceInteractionInstallAndRun` with no `--uitesting`, mock, debug-state, or seed arguments.
5. Follow the returned `skillToTrigger`; if unavailable, end the session and escalate.
6. For each state change, derive interaction from a fresh hierarchy and inspect the direct result.
7. Call `DeviceInteractionEndSession` on success, failure, or abandonment before releasing the
   lock, then delete only the owned Simulator.

Record capture SHA, Xcode version/build/channel, runtime/build/UUID, action, visible result, mock or
live data path, and app/extension coverage. App-only screenshots do not prove extension activation,
cross-process handoff, or normal extension behavior; use the real extension in an ordinary host
text field. Preview variants remain diagnostic only.

## Targeted routing

Select the smallest route that covers the acceptance criterion. These are starting points, not
blanket requirements for every edit in a shared file; apply verification applicability first.

| Changed surface | Targeted verification |
|---|---|
| Model, parser, or core service | `./scripts/ios/test.sh core` |
| Host app or extension compilation | `./scripts/ios/test.sh build` |
| Host app user flow | Focused affected UI regression; normal simulator proof of the affected flow |
| Visual layout | `./scripts/ios/test.sh screenshots` for automated regression; direct Simulator screenshots from a normal launch before push |
| Keyboard extension/App Group behavior | Focused extension/persistence regression and normal handoff proof; `real-keyboard-live` only when verifying live AI behavior |
| Gateway runtime or contract | `./scripts/check-live.sh gateway` for automated transport/contract evidence; normal runtime proof when user-visible semantic behavior changes |
| Parser compatibility or retry | Relevant live schema/semantic/failure evidence; assess whether the gateway or differential route fits the changed behavior |
| Model capability boundary, model-role comparison, or requested matrix | `./scripts/check-live.sh gateway-differential` on committed exact `HEAD` |
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

The exact-head gateway gate also runs the four-provider Settings/connector matrix from the pinned
connector's guarded ignored live seed. OpenAI, Anthropic, OpenRouter, and OpenAI-compatible Gateway
must each preserve their exact provider/model binding and pass Test Connection plus diagnostics.
Private provider values and model identities exist only in the local process, mode-600 temporary
`.xctestrun`/evidence state, and disposable result bundles, all of which are cleaned on exit. The
retained PR record contains only canonical binding/match booleans, requirement class,
no-substitution state, required outcomes, and exact head. GitHub validates those non-sensitive
assertions; local execution attests the comparisons against the private seeds.

The targeted differential runner performs automated deterministic prerequisites and
`build-for-testing` once, then reuses the compiled `.xctestrun` for isolated low and high disposable
simulators. It runs one small baseline/boundary/follow-up test per role and removes both simulators,
injected environment, DerivedData, result bundles, summaries, and temporary evidence on exit. The
default command is verification and exits nonzero unless the exact required low/high outcomes are
verified. `--diagnostic` is the only permissive exploratory mode; an unverified diagnostic may exit
zero but must report `LIVE_UNVERIFIED` and `diagnostic run complete`, never green verification
success. A low-model success at the candidate boundary is retained as
`diagnostic-boundary-not-established`, not promoted to passing evidence.
Before cleanup, the runner exports one sanitized text attachment per role and requires separate
transport, grammar, rewrite, and translation status rows in canonical order. The
attachment grammar rejects extra content so credentials and response bodies cannot enter the
retained summary.

## Hooks

Enable committed hooks once per clone or worktree before the first commit or push:

```bash
./scripts/check-environment.sh --full
./scripts/install-hooks.sh
git config --local --get core.hooksPath
```

The path must be `.githooks`.

- Pre-commit requires an exact staged candidate and runs `./scripts/check.sh --hygiene` for
  classified documentation-only changes, or `--quick` otherwise. It can
  establish `DETERMINISTIC_VERIFIED` only; it cannot grant commit authority or establish
  `LIVE_VERIFIED`/`RUNTIME_VERIFIED`.
- Pre-push requires a clean exact `HEAD`, runs `./scripts/check.sh --hygiene` for a classified
  documentation-only branch diff, or `--full` otherwise, and
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
- Repository test and local-validation automation is Simulator-only. Repository automation must
  not use `devicectl`, `ios-deploy`, a concrete physical-device name/identifier destination, or an
  equivalent device discovery/install/launch/test command. A separately authorized release or
  deployment workflow may compile, sign, and archive against `generic/platform=iOS`; this generic
  SDK destination does not operate a physical device or grant physical-device authority.
- Live routes create a fresh disposable simulator with the selected device type and runtime. Each
  process records ownership of the returned UDID and may restart, shut down, or delete only that
  exact device. They never terminate Simulator.app or CoreSimulator processes, never use broad
  `simctl` cleanup, and never modify the selected existing simulator. The automated real-keyboard
  route seeds and restarts only its disposable simulator, then deletes it on exit.
- Never use `--no-verify`. A missing toolchain or credential is a blocker for the affected gate.
- The exact-head impact classifier selects `gateway-differential` only for changes touching
  model-capability classification, long-input handling, parser compatibility, retry behavior,
  automatic-analysis warnings, manual-action scope, Translate warning scope, or runtime matrix
  execution itself. Policy-only classification is covered by deterministic tests. Pre-release verification invokes `./scripts/check-live.sh gateway-differential`
  explicitly. Unrelated pull requests do not run the two-profile matrix.

## Normal simulator and device proof gate

Changes affecting UI, keyboard-extension lifecycle, Apply/Copy/Back/Rerun behavior, or result
presentation require normal simulator runtime proof of the affected surface before push. Nonvisual
gateway criteria may use relevant live transport/schema/semantic evidence without an unrelated UI
walkthrough. Local
implementation and commits may proceed after deterministic tests only when explicitly authorized
and no proof-first constraint remains. Proof-first model-capability, long-input, parser, retry, or
semantic-behavior work requires the requested live result and later implementation authority before
production edits or commit.

Normal simulator runtime proof must:

- install and normally launch the actual app; exercise its bundled extension when relevant;
- avoid `--uitesting`, debug-state injection, seeded result panels, component/test hosts, and
  XCTest-driven interaction;
- for extension requirements, focus an ordinary host-app text field and activate OpenKeyboard
  through the normal keyboard lifecycle; otherwise exercise the affected normal app surface;
- invoke the action through visible production UI and use the configured live gateway when
  semantic behavior is being verified;
- capture screenshots directly from Simulator/Xcode, never from `XCTAttachment`;
- record capture and current verified Git SHAs, build configuration, simulator model, OS version,
  action, source text, and observed result without exposing credentials or private configuration.

Required artifact-backed screenshot proof captured or used by Codex must be inspected and then
rendered or attached in the final response. For local images, use inline Markdown with absolute
non-repository paths. Do not treat a filesystem path, `.xcresult`, PR/review link, summary, or an
image shown only in earlier commentary as final delivery. Never ask the user to upload or transfer
screenshots. When Codex cannot capture the artifact, offer the human approval route below and
preserve the absent AI-evidence boundary.

If Codex can interact with the normal simulator confidently, it collects this proof directly using
the following escalation hierarchy. Stop when one tier closes every requirement; preserve valid
evidence and escalate only the missing or ambiguous proof:

1. **Simulator accessibility/control:** use a purpose-built, generically named integration to
   inspect the normal app's accessibility hierarchy, operate discoverable controls, type, tap,
   swipe, and capture direct Simulator screenshots. Accessibility metadata or successful actions
   without inspection of the resulting visible state and delivery of the required screenshots do
   not establish visual acceptance.
2. **Computer Use:** use Computer Use or equivalent host UI automation when tier one is unavailable
   or cannot establish a required system-level interaction or visual result.
3. **Human verification:** use the exact manual checklist in
   `docs/REAL_EXTENSION_SMOKE_PLAN.md` only when the first two tiers remain unavailable, unreliable,
   or ambiguous. Request an exact-head approve/reject decision, never a screenshot upload.

A Computer Use report that the host is locked or Simulator is unavailable is a route-level failure,
not a terminal runtime-proof conclusion. Refresh its app state once. For Xcode 27 or newer, first
target Device Hub from the same recorded Xcode installation and verify the exact owned UUID;
otherwise, or when Device Hub cannot be targeted, retry Simulator with bundle identifier
`com.apple.iphonesimulator` when supported. Then try any other available non-XCTest Simulator
accessibility/control route. Do not loop on a genuinely locked host. `simctl` setup or framebuffer
capture may support the proof session but does not establish the required visible interaction by
itself. If interaction is still unavailable, unreliable, or ambiguous, stop before push/readiness
and state the unverified behavior. Running more XCTest does not resolve the blocker, and asking the
user to upload screenshots is not a fallback.

### Human runtime approval

If neither automated Simulator tier can finish the runtime check, or if physical-device behavior
needs a human decision, show the repository owner the exact current head and the missing AI
screenshot/device evidence once. Ask only whether they approve or reject that exact head based on
their own verification. Do not request screenshots, paths, device details, or a structured
attestation.

An explicit exact-head approval records `Runtime evidence mode: human-approved`, satisfies the
runtime/device decision gate, and authorizes the workflow to continue through every remaining
standing lifecycle stage without another runtime, readiness, or merge confirmation for that head.
Qualify `RUNTIME_VERIFIED` as `human-approved` and disclose that the AI did not inspect screenshots.
The independent reviewer may retain the affected requirement as `UNVERIFIED`; human approval
accepts that disclosed risk. It does not bypass failed mandatory checks, conflicts, requested
changes, secrets, or other non-runtime blockers. A new commit expires the approval.

### Test-only runtime-proof carry-forward

Do not repeat a complete normal-Simulator interaction solely because a later commit changes only a
non-shipping test target. From the clean current head, run:

```bash
./scripts/verify-runtime-proof-carry-forward.sh <capture-sha> <current-sha>
```

The verifier requires the capture SHA to be an ancestor of current `HEAD`, every intervening path
to remain under `OpenKeyboardCore/Tests/`, `OpenKeyboardTests/`, or `OpenKeyboardUITests/`, and the
non-test Git-tree digest to remain identical. A passing record must retain both SHAs, the digest,
the intervening paths, the prior runtime configuration, and all required original screenshots.
Label every image with its capture SHA and call it verified test-only carry-forward evidence, not a
current-head capture.

Any verifier failure, dirty worktree, rename, unknown path, runtime/resource/project/dependency/
configuration/gateway/script/documentation/workflow change, incomplete prior screenshot set, or
changed runtime environment requires fresh proof. Physical-device proof, full/live gates,
independent review, GitHub results, and human authorization never carry forward through this rule.

Codex-operated physical-device proof requires explicit physical-device interaction authority plus
the exact signed build installed on the configured device. Human approval does not require or grant
Codex device authority. A Simulator or XCTest run cannot satisfy AI physical-device proof. When
authority is absent, do not inspect connected devices; offer the exact-head human approval route.

A user instruction limited to a proof-sensitive push with missing runtime proof disclosed does not
authorize PR readiness or merge. Never use the automatic route while required simulator/device
screenshot proof is missing. The separate human route may proceed after explicit exact-head owner
approval, with the missing AI evidence disclosed.

## GitHub checks

`.github/workflows/ci.yml` checks out the exact pull-request head with read-only permissions.
It validates the requirement ledger and durable independent-review link, then classifies the
exact-head diff against the base-owned classifier. Repository hygiene always runs. For a
documentation-only diff, Core tests, semantic-contract checks, and app/extension builds are
skipped; every other diff requires all three. The stable `Required technical checks` job validates
the expected result for the selected scope. Every review/body
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
exact-tested-SHA fields. Exact provider and model identities are compared only inside the local
live-gate process against ignored mode-600 seeds. The retained body records the model requirement
class, exact-identity match booleans, role distinctness, no-substitution result, and the canonical
four-provider binding/Test Connection/diagnostic outcomes; it never records raw model identifiers,
private base URLs, credentials, or opaque commitments. Exact-model runs pass the private requirement
through `OPEN_KEYBOARD_LIVE_REQUIRED_MODEL` or `OPEN_KEYBOARD_LIVE_REQUIRED_MODELS`. Every exact-model
or model-agnostic run must verify the seeded model through the production plain-text grammar flow;
a connected-but-unverified `.limited` result is not passing live evidence. Every live-evidence body
event creates the stable `Required live verification` root job. It rejects duplicate,
contradictory, reordered, missing, false, fallback, and wrong-binding fields in both the immutable
event body and the current exact-head body. Local execution attests the secret-backed comparisons;
GitHub receives only the non-sensitive assertions.

For `gateway-differential`, retained identity evidence uses canonical `low=true, high=true` order
and separately records that the private role-bound identifiers were distinct. Separate canonical
fields record baseline outcomes, long-text differential outcomes, follow-up outcomes,
and operation-scoped warning verification. The validator rejects missing
roles, stale heads, duplicates, reversed or malformed mappings, substitutions, low success
presented as a capability boundary, high failure, unverified scenarios, and contradictory
evidence. GitHub still receives no credentials, model identifiers, private URLs, or response
bodies.

The exact trusted base must expose the private-schema marker. Missing and legacy validators
fail closed without candidate fallbacks, compatibility projections, or fabricated measurements.

The classifier keeps conservative defaults for shipping paths, with diff-bound assessments for
changes whose actual behavior needs a smaller gate. Policy-only classifier, validator, workflow,
hook, and documentation changes do not themselves require model calls. See
[Verification applicability](VERIFICATION_APPLICABILITY.md) for assessment creation, freshness,
independent review, and trusted-base rollout. Runtime proof follows the affected surface: a local
app screen does not require an unrelated extension or gateway interaction.

## Advisory Code Review and security review

Follow [Advisory review workflow](ADVISORY_REVIEW_WORKFLOW.md) for one routine PR Code Review
route, security-trigger assessment, private exact-revision records, and independent disposition
of findings. [Security threat model](SECURITY_THREAT_MODEL.md) supplies the initial repository
context and baseline scan route. This rollout changes neither mandatory checks nor branch
protection. Optional service status and actual account activation must be reported separately.

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

A bounded implementation request itself grants standing conditional authority through branch
preparation, implementation, checks, commit, push, draft PR publication, in-scope review fixes,
readiness, and guarded merge without confirmation at every stage when the applicable gates pass
and the reviewer reports `100%`. Below 100%, the root reports the exact head and every gap, then
waits for explicit owner approval of that SHA. Any active sticky
`local only`, `do not commit`, `do not push`, `do not create a PR`, `keep draft`, or `do not merge`
constraint stops the corresponding state change until the user explicitly revokes that constraint.

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

`$develop-openkeyboard` is the direct route for a bounded implementation. Do not add routine
planning or delegation. Use `$audit-openkeyboard-ui` for UI audits and
`$write-openkeyboard-product-copy` for user-visible wording as routed by `AGENTS.md`.

Use the read-only `$plan-openkeyboard-work-package` only for an explicitly requested bounded plan or
“what next” package. Use `$plan-openkeyboard-major-milestone` only for an explicitly requested
roadmap, long-horizon milestone, or multi-phase plan. Neither planner mutates the repository or
grants later lifecycle authority.

## Deployment

`.github/workflows/deploy-ios.yml` is separate from pull-request CI. It reruns the reusable
deterministic CI workflow, then enters the protected `app-store-connect` environment to import
signing material, archive, export, validate, and optionally upload. The deployment job revalidates
its source after environment approval and before reading deployment secrets.

Production `v*` tags must point to commits contained in `main`. Manual dispatch defaults
to validation without upload. The deployment workflow does not prove App Review acceptance or a
successful public release.

## Private evidence and trusted policy

See `docs/LIVE_EVIDENCE_PRIVACY.md` for the public assertion schema and local identity boundary.
The live workflow requires the private schema on its exact trusted base, with no candidate
fallback, legacy projection, synthetic timings, or separate migration environment. Both event
and current snapshots must pass; four-provider outcomes and exact-head independent review remain
mandatory. Unknown fields in the live-evidence section fail closed.

## Resuming unchanged-head verification

The existing full/live commands reuse authenticated same-head passing stages and rerun failed or
missing stages. Use `--fresh` after an external service or otherwise unobserved build-input change.
See [Resumable verification](RESUMABLE_VERIFICATION.md) for the 24-hour expiry, input bindings,
provider/profile granularity, private receipt storage, and unchanged publication gates. Hygiene and
policy/negative checks remain fresh. A new commit requires fresh execution; no historic log can be
imported as a cached pass.
