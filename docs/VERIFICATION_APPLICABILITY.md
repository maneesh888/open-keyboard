# Verification applicability

Select evidence for the behavior changed, not every capability of the files touched. Live model
calls, normal Simulator UI proof, and automated regression evidence answer different questions.
A Full Access hint in AppConfig needs cross-process/UI evidence; it does not need a model boundary
comparison. Diagnostics filtering needs filtering/export tests and the affected normal UI flow;
it does not prove the original correction failure resolved. A parser or retry change still needs
live evidence for that behavior. The independent reviewer checks this reasoning.

## Default and assessed impact

`scripts/live-impact.sh BASE HEAD` keeps conservative defaults for shipping paths and reports
`none`, `gateway`, or `gateway-differential`. Policy-only changes to the classifier, validators,
CI workflow, PR template, hooks, and documentation need deterministic policy regression and review,
not a model call. Runtime test harnesses, seeds, dependencies, and production files retain defaults.

When inspection shows the default over-selects, commit `.github/verification-assessment.json`.
This is a reviewable claim, not an approval or waiver. It contains:

- schema version 1 and the merge-base commit;
- the appropriate `live_impact` target;
- a specific rationale explaining affected behavior, dependencies, and why the larger test adds
  no relevant evidence;
- the alternative `proof` and a named PR `requirement_id`;
- every changed path except the assessment itself, with exact before/after Git blob IDs and modes
  (null for absent files).

Generate a draft from committed work. Replace the example rationale and proof with the actual
analysis; the command writes JSON to stdout and does not modify the repository:

```bash
python3 scripts/verification-assessment.py --draft . origin/main HEAD none R2 \
  'Only the Full Access hint and Home visibility change; requests, parsing and model selection are unchanged.' \
  'Focused handoff regression and normal Settings/keyboard-to-Home observation prove the requested visibility behavior.' \
  > /tmp/openkeyboard-verification-assessment.json
```

Inspect it, copy it to `.github/verification-assessment.json`, and commit. The helper ignores that
file when binding the diff, avoiding a self-referential hash. Run the classifier again. Regenerate
and review after any changed path, blob, mode, or merge base. Modified assessments with missing,
extra, duplicated, malformed, or stale content fail closed. An inherited assessment is ignored for
a new PR; deleting it restores default classification. Uncommitted files never affect committed
classification. Contract/gitlink changes cannot be reduced below differential verification.

In the PR requirements table, add the named assessment requirement with an observable criterion
such as “Verification covers the changed behavior without unrelated model calls.” Include the
assessment's full Git blob ID in that row's Exact evidence cell:

```bash
git rev-parse HEAD:.github/verification-assessment.json
```

The live workflow loads both classifier and helper from the trusted base. It validates complete
bindings and the named evidence row in both immutable event and current PR bodies. The existing
Required checks gate binds that row and its acceptance/proof to the newest same-head independent
review. The reviewer must inspect the actual diff, dependencies, rationale, and alternative evidence;
merely echoing the manifest is insufficient. An unjustified reduction is a blocking finding.
The assessment does not bypass deterministic checks, required review, branch protection, runtime
proof that is relevant, privacy tests, or a requested exact-model evaluation.

## Evidence and scope

Record non-applicable evidence as **not applicable**, with its reason, in the verification summary.
The existing live-evidence fields use `not required` when the classifier returns `none`; do not
claim `LIVE_VERIFIED` for an unexecuted call. Requirement rows remain VERIFIED/UNVERIFIED for actual
acceptance criteria. An applicability decision is itself reviewed; irrelevant tests do not become
new requirements. Accept equivalent routes that demonstrate the same observable result at the
required evidence class. Keep genuine gaps explicit, including a first-grant transition that has
only been observed after typing, or a production failure that has not been reproduced.

Normal UI proof should exercise the changed app surface. Require the real keyboard/host field
only for extension or handoff requirements. Require a live model only for affected semantic or
provider behavior. Keep privacy/consent regression coverage even when live model calls add no value.

## Rolling out policy changes

A candidate cannot replace its trusted-base classifier/helper to approve its own assessment.
The live workflow additionally contains a narrow, literal policy-file allowlist. This is an
explicit change to the workflow trust boundary: a complete policy-only diff can select no live
execution even when the base classifier selects differential. The old live test is not claimed as
executed or passed. This corrects the rollout requirement itself instead of requiring unrelated
model calls to introduce the correction.

The rule checks the entire merge-base-to-head diff with NUL-delimited paths and rename detection
disabled. Existing allowlisted files must remain regular blobs with identical modes. Only the
four explicitly designated documentation/helper/test files may be added, at their expected modes.
Deletions, mode/type changes, unknown paths, shipping code, dependencies, runtime configuration,
seeds, live runners, and assessment manifests cannot use this rule. Invalid Git objects or diff
output fail the job; they never select a fallback. Every other diff uses the trusted-base result.
Trusted classifier failures still fail the job, and evidence validators remain base-loaded.
The inline boundary interpreter uses isolated mode so checkout modules and PYTHONPATH cannot
replace its standard-library imports before the diff is checked.

Path membership proves scope, not safety. Policy scripts can execute commands, so independent
exact-head review must inspect their full contents and dependencies and explicitly assess this
boundary. Full deterministic verification, protected technical and requirement checks, retained
independent review, and guarded merge remain mandatory. The applicability rule grants no merge
authorization. Do not disable protection, forge live assertions, or invent human approval.
