# Advisory Code Review and security review

## Route and authority

Use the app's **Code Review** plugin on the PR as the routine advisory route. Open the exact PR,
inspect Summary and Changes, and investigate it in the existing chat beside the PR. Record the
base/head before and after review. If a completed automatic GitHub Code Review already covers that
same revision and scope, inspect and reuse it instead of starting another general review. Record
that substitution explicitly. App review and automatic GitHub review are distinct runs; opening a
diff or reading checks is not a completed review.

Use one general review per revision/scope, plus deeper security review when triggered below. Do
not automatically run app review, local `/review`, and `@codex review` on the same diff. Local
`/review` is an explicitly recorded fallback for an unavailable app PR route, not the Code Review
plugin and not the project reviewer. Refresh affected reviews after changes; an old report can
inform investigation but cannot claim current-head coverage.

This is an advisory rollout. Keep deterministic CI, secret scans, requirement ledgers, the isolated
project `pr-reviewer`, draft/readiness rules, exact-head evidence, and guarded merge mandatory.
Optional service unavailability does not independently block merge and never means a clean result.
A validated correctness, security, data-loss, or false-evidence finding remains a blocker under the
existing rules regardless of which reviewer found it. No findings proves neither security nor
normal runtime acceptance. An in-scope acceptance criterion that expressly requires a scan still
needs that evidence; advisory status cannot silently remove it. Partial findings from failed or
pending runs must still be retained privately in the reviewer packet and investigated; the
incomplete record cannot declare completed coverage or discard a known issue.

Repository guidance does not enable account settings. Installation, account-wide review settings,
recurring Cloud scans, branch protection changes, separately purchased usage, and publishing
vulnerability reports need explicit authority. Do not post `@codex review`, `@codex security review`,
or provider review comments without applicable explicit authorization. The existing skill-authorized
project-reviewer COMMENTED report and revalidation trigger keep their existing lifecycle authority;
they are not provider review triggers. Never publish private scan details, local infrastructure,
credentials, text samples, report paths, or private artifact URLs in public PRs.

## Security selection

Assess the complete diff and directly supporting code, including renames and mode changes. Request
a deeper security review for authentication/authorization, credentials, network or endpoint handling,
storage/privacy, command execution, dependencies, signing, or CI permissions and gate policy.
Record the triggering behavior and affected paths. Unknown scope requires investigation; it is not
`not-applicable`. A pure ordinary guide can be `not-applicable` with a concrete rationale.

Prefer a local, scoped **Codex Security** Changes scan for the exact PR base/head when the installed
capability and authorized included usage are available. Read the current plugin instructions and
verify its revision/coverage artifacts. Do not substitute a full repository scan for every PR.
GitHub **Security Review** is a distinct, deeper PR review and is an alternative only after account
eligibility, repository access, reporting visibility, and trigger authorization are verified. Its
comments inherit PR visibility, and an absent comment can simply mean no finding met the posting
threshold. Inspect the full private report before claiming completion.

**Codex Security Cloud** is a separate connected-repository product. Local plugin access does not
prove Cloud access or GitHub Security Review eligibility. Prepare baseline context using
[SECURITY_THREAT_MODEL.md](SECURITY_THREAT_MODEL.md); do not silently enable Cloud monitoring.

As documented on 2026-10-15, GitHub Security Review supports Enterprise, Business, Edu, and Pro,
not Plus, and consumes included Codex allowance or credits. Recheck official documentation and the
actual account before relying on eligibility, prices, triggers, or artifact schemas. Do not infer
eligibility from a visible tool or plugin. If access/usage cannot be established, record
`unavailable` with the reason and continue mandatory local checks without claiming a scan passed.

## Private evidence and findings

Keep a small JSON record outside every Git worktree in a private directory (directory mode 700,
file mode 600). Use schema version 1 with this shape; replace placeholders with observed values:

```json
{
  "schema_version": 1,
  "base": "<full base SHA>",
  "head": "<full current head SHA>",
  "reviews": [
    {
      "kind": "code-review",
      "route": "app-code-review",
      "status": "pending",
      "scope": "Entire PR diff and directly supporting code",
      "reason": "Routine PR review selected",
      "report_reference": null,
      "inspected": false,
      "coverage": null,
      "findings": []
    },
    {
      "kind": "security-review",
      "route": "local-security",
      "status": "unavailable",
      "scope": "Changed verification policy and supporting hooks",
      "reason": "Local security plugin access not established",
      "report_reference": null,
      "inspected": false,
      "coverage": null,
      "findings": []
    }
  ]
}
```

Use `pending`, `completed`, `failed`, `unavailable`, or `not-applicable` exactly. Failed means an
attempt failed; unavailable means capability, authorization, or access was not established. A
completed record requires an inspected report reference and coverage description including excluded
or deferred surfaces. Completion is not approval. Record each finding as `id`, `disposition`
(`open`, `fixed`, or `rejected`), `rationale`, `evidence`, and `requirement_id`. Keep all finding
content private. An accepted unresolved finding stays `open`; a rejection needs independent
code/evidence reasoning, and `fixed` requires current-head regression evidence. Map material
findings to existing requirement rows, adding a row when necessary. An empty list is legitimate
only after inspecting a completed result; it makes no exhaustive security claim.

Validate the record before handing it to the independent reviewer:

```bash
python3 -I scripts/validate-advisory-review.py /private/path/review.json <base-sha> <head-sha>
```

This local helper validates structure and exact revision binding only. It does not launch reviews,
read referenced artifacts, establish authenticity/completeness, approve findings, or authorize
merge. Its exit status cannot be used as a substitute protected check. It prints status/counts,
never private record contents. A new head or base makes the record stale: retain it as history and
create a fresh record, initially pending, for refreshed affected review. Do not merely retag an old
report. Independent review checks the report's own revision and coverage, supporting source,
findings, and dispositions; contributors cannot self-certify external review evidence.

Pass private references through the local neutral reviewer packet only. In the public PR brief,
record sanitized service status, exact base/head, scope, and disposition summary. If a material
security blocker cannot safely be described publicly, keep the PR draft and arrange an authorized
private remediation path. Do not publish vulnerability details to satisfy the ledger. The custom
project-reviewer report must remain a separate independently authored report with its existing
identity, schema, and exact-head validity.

## Merged workflow adoption

These OpenKeyboard improvements are retained, not reimplemented. Sibling repositories should map
applicable process rules to their own contracts, architecture, evidence classes, and tools.

| Improvement | Decision and merged source | OpenKeyboard destination |
| --- | --- | --- |
| Phase-scoped authority, independent device authority | Already present: #38 `00ecb91`, refined #40 `f8b35c6` | AGENTS.md; development/review skills |
| Human exact-head runtime decision, equivalent proof | Already present: #40 `f8b35c6`, #59 `a0889a0` | AGENTS.md; docs/VERIFICATION_APPLICABILITY.md |
| Behavior-scoped proof and trusted assessment | Already present: #59 `a0889a0` | scripts/live-impact.sh; scripts/verification-assessment.py; live.yml |
| Proportional docs, stage-specific checks, fail-closed classification | Adopt merged #63 `8f50cb5` as base | scripts/verification-scope.py; hooks; check.sh; ci.yml |
| Exact-head independent report, guarded merge | Retain existing mandatory contract | review skill; .codex/agents/pr-reviewer.toml; PR validators |
| Avoid redundant checks/reviews | Retain cumulative gate selection; add one advisory route | docs/DEVELOPMENT_WORKFLOW.md; this guide |
| App/Cloud distinction, private findings, advisory status | Adopt in this change | AGENTS.md; review skill/agent; PR template; local record validator |
| Swift/UI/model and physical-device proof in sibling projects | Not applicable to wholesale transfer | Each destination's own policy; no sibling edits here |

PR #63 was verified MERGED at `8f50cb5af294c967c5b32274b5f6c8474cf91ef1`, reachable from freshly
fetched origin/main before this implementation. No later merged workflow changes were present at
that base. Policy/CI changes themselves still classify as full; do not label this integration an
ordinary docs-only change. Existing positive/negative classifier and trusted-base tests stay active.

Sources: [#38](https://github.com/maneesh888/open-keyboard/pull/38),
[#40](https://github.com/maneesh888/open-keyboard/pull/40),
[#59](https://github.com/maneesh888/open-keyboard/pull/59),
[#63](https://github.com/maneesh888/open-keyboard/pull/63).

Official product references checked 2026-10-15:
[Code Review](https://learn.chatgpt.com/docs/code-review),
[GitHub integration](https://learn.chatgpt.com/docs/third-party/github),
[Security Review](https://learn.chatgpt.com/docs/security/security-review),
[local Security plugin](https://learn.chatgpt.com/docs/security/plugin), and
[scoped changes scans](https://learn.chatgpt.com/docs/security/plugin/code-changes).
