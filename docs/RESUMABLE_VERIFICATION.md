# Resumable same-head verification

An unchanged clean head can reuse a previously passed verification stage and rerun only failed or
missing stages. This is local evidence reuse, not a skip switch. Every required stage still needs
an inspected passing result, and a changed head always starts fresh. No prior log or contributor
statement can be imported as a pass.

## Commands and retry scope

Use the existing commands:

```bash
./scripts/check.sh --full
./scripts/check-live.sh gateway-differential
```

The same commands resume automatically. To force execution again:

```bash
./scripts/check.sh --full --fresh
./scripts/check-live.sh gateway-differential --fresh
```

`OPEN_KEYBOARD_VERIFICATION_FRESH=1` has the same effect for a hook or nested invocation. It only
forces execution; it cannot accept missing proof. Hygiene, policy/negative tests, secret scanning,
and working/staged/committed whitespace checks always execute. Contract checks, core tests,
app/extension builds, and deterministic UI suites retain separate receipts. Live verification
retains independent provider rows, warning-contract prerequisites, and LOW/HIGH profiles. A failed
suite or profile reruns its complete connected scenarios; individual assertions within it are not
stitched together. The ordinary gateway smoke has separate receipts for its selected LOW/HIGH/legacy role, so a
passing smoke for one role cannot satisfy another.

For example, if all four provider rows and LOW pass but HIGH fails because its server is
unavailable, retrying the same unchanged head reuses those five successful rows and executes HIGH.
The aggregate remains LIVE_UNVERIFIED until every required result is valid. A successful LOW
capability-boundary request remains diagnostic and cannot create a passing LOW receipt.
Diagnostic differential mode invalidates receipts for the stages it executes and neither consumes
nor creates verification receipts. A later diagnostic failure cannot fall back to an older pass.

## Binding and invalidation

Receipts are valid for at most 24 hours. Their private keyed binding covers:

- the exact clean HEAD and comparison base, with every recursive submodule initialized at its
  recorded gitlink and clean regardless of local submodule-ignore settings;
- Xcode/Swift, host/Python, Node/Java version results, available Simulator runtime identifiers and
  build versions, and supported compiler/build environment controls;
- the guarded seed file contents for the live route, including profile/model/endpoint/credential
  changes; and
- the specific canonical stage or provider/profile role.

Changed, dirty, expired, incomplete, corrupted, substituted, or role-swapped state cannot be
reused. Deterministic runs on a dirty tree execute normally without creating reusable receipts;
the live parent gate still requires a clean committed head. Bindings are checked again after an
executed stage, so a concurrent head, seed, or toolchain change cannot mint a pass. Seed validation,
role distinctness, selected-model comparisons, complete outcome classification, and final exact-head
validation still run. Use `--fresh` after an external service, model implementation, or custom build
input changes in a way not observable through the recorded configuration/version inputs.

Draft-only PR transitions do not start CI or live-policy workflows: they change neither the head,
body, nor reviews and must not restart the guarded readiness handoff. Opened, synchronized,
reopened, and edited PR events still validate their exact-head evidence; submitted, edited, and
dismissed reviews still create the protected review check. Strict required checks and native
exact-head merge protection remain mandatory. This event filter does not reuse a result across
commits or suppress a head/body/review change.

The mandatory pre-push hook still invokes the full classified deterministic and live commands.
Receipts do not carry between commits, replace GitHub checks or independent review, or authorize
readiness/merge. Runtime screenshots and human approvals keep their existing independent rules.
The KMP candidate and its earlier results cannot acquire receipts retroactively: the new policy
must land first, and its eventual integration creates a new head requiring an initial full run.

## Private storage and concurrency

Receipts live under the Git common directory in `openkeyboard-verification-cache/`, shared by the
repository's worktrees. The directory is owner-only mode 700; keys, locks, and records are mode 600.
Symlinks, hard-linked private files, foreign ownership, permissive modes, and extended macOS ACLs
are rejected. Records are atomically written and authenticated with a local random key. They contain
only stage outcomes, an internal timestamp, and opaque keyed binding/authentication values. They
contain no credentials, model identities, private endpoints, prompts, responses, or raw test logs.
Never publish records, their keyed values, or the local key. Per-run seed paths/context are kept in
the existing private temporary live workspace and deleted with it; the seed itself is never copied.

Metadata locks are short-lived. Deterministic executions have separate stage locks, so they cannot
hold the metadata lock while waiting on the repository Simulator lock. Live row access stays inside
that existing Simulator lock; lazy builds allocate only workflow-owned disposable Simulators, and
the existing cleanup still owns deletion. No physical-device route is introduced.

## Evidence boundary

A reused pass is reported as `Reusing same-head passing verification: <stage>` in sanitized local
output. Public live fields retain their existing role/outcome-only schema; cached diagnostic outcomes
are preserved exactly rather than reconstructed as stronger outcomes. Local receipt authentication
supports evidence integrity, not remote identity proof. Independent review still inspects the
runner, guards, redacted execution results, and applicability; GitHub validation of assertions does
not prove that a remote provider served the declared model.
