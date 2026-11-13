---
name: develop-openkeyboard
description: Execute bounded OpenKeyboard analysis, implementation, testing, documentation, CI, gateway, keyboard-extension, and release-hardening work through the repository's canonical workflow.
---

# Develop OpenKeyboard

Use `AGENTS.md` as the canonical execution policy. This skill supplies the compact implementation
loop; do not copy or weaken the repository's authority, evidence, secret, Simulator, git, or review
rules here.

## Enter the task

1. Resolve the repository root, inspect status and submodules without mutation, and read
   `AGENTS.md` completely.
2. Build its authority ledger before mutation. Recompute it at phase changes and before each
   material state change. Physical-device interaction remains a separate default-`NO` entry.
3. Keep one compact checkpoint: objective, changed surfaces, exclusions, required evidence, and
   current authority/gate state.
4. Use the isolated worktree selected by `AGENTS.md` when edits are authorized. Preserve unrelated
   work and initialize only task-required submodules.
5. Proceed directly for a bounded implementation. Use `$plan-openkeyboard-work-package` or
   `$plan-openkeyboard-major-milestone` only when the user asks for the matching plan, roadmap,
   milestone, or “what next” work package.
6. Read only relevant sources. Load `docs/DEVELOPMENT_WORKFLOW.md` only for route, hook, CI, Xcode,
   signing, deployment, or proof mechanics; load `docs/VERIFICATION_APPLICABILITY.md` only for a
   diff-bound alternative-proof assessment.

## Implement and verify

1. Keep edits inside the checkpoint and follow the repository's MVVM, theme, App Group, Keychain,
   extension, gateway, semantic-contract, and secret boundaries.
2. Use `$audit-openkeyboard-ui` for UI audit work and `$write-openkeyboard-product-copy` for
   user-visible wording work as routed by `AGENTS.md`; source inspection never establishes rendered
   or runtime acceptance.
3. Add focused regression coverage for changed behavior. During diagnosis and implementation, run
   affected tests only; do not repeatedly run cumulative gates after small edits.
4. When the bounded change is ready, freeze it, run `git diff --check`, inspect the intended diff,
   validate or regenerate any diff-bound applicability manifest against that complete diff, install
   hooks, stage only task files, and inspect staged names/content. Let the mandatory commit hook run
   the proportional staged gate. If it passes and staged content stays unchanged, use that result
   instead of immediately rerunning the same command manually.
5. After the final commit freezes the exact head, run one classifier-selected aggregate gate:
   `./scripts/check.sh --hygiene` for a strictly classified documentation-only diff and
   `./scripts/check.sh --full` otherwise. When push is authorized, let the mandatory pre-push hook
   supply this result instead of running the same command immediately beforehand. If push is
   unavailable and local evidence is required, run it once manually and disclose that a later push
   hook must repeat it. Run applicable live/runtime gates, then perform one exact-head independent
   review.
6. Any later edit or commit invalidates the exact-head evidence and begins a new final cycle. Never
   carry old-SHA deterministic, live, review, GitHub, or human approval forward. Only the narrow
   normal-Simulator test-only exception in `AGENTS.md` may carry forward after its verifier passes.

Proof-first work remains read-only until its requested result is reported and implementation is
clearly authorized. A required live outage remains `LIVE_UNVERIFIED`; do not replace it with
speculative edits or unrelated deterministic tests.

## Xcode and runtime routing

Use repository Simulator routes so their shared lock and owned disposable-device cleanup apply.
Never mutate a pre-existing or user-open Simulator, and never discover or operate a physical device
without explicit physical-device authority.

Xcode MCP is an optional focused accelerator, not a repository gate. Before using it, load
`AGENTS.md#xcode-mcp-acceleration` and
`docs/DEVELOPMENT_WORKFLOW.md#xcode-mcp-acceleration`. Bind calls to the active worktree, keep
toolchain selection scoped, prefer repository scripts when an action cannot target the exact owned
Simulator without device enumeration, and keep automated tests, previews, normal runtime proof,
and extension proof accurately classified.

For proof-sensitive UI, extension-lifecycle, Apply/Copy/Back/Rerun, or result-presentation changes,
follow the normal-runtime hierarchy in `AGENTS.md` and `docs/REAL_EXTENSION_SMOKE_PLAN.md`. Retain
valid evidence and escalate only the missing part. Human verification asks for an exact-head
approve/reject decision, never a screenshot upload. Do not call behavior fixed or working while an
applicable live or runtime requirement remains unverified.

## Lifecycle and handoff

Use `$review-verify-merge-pr` only after the final head is frozen, except when an explicit review-only
request requires it earlier. Advance through authorized lifecycle stages only as their mandatory
gates become ready; active opt-outs, deployment, and destructive cleanup keep their separate
authority boundaries.

Report the worktree/branch, changed areas, checks, exact evidence classes, proof gaps, exact head and
PR state, and commit ID. Render or attach required proof screenshots captured or used by Codex. For
human-approved evidence, report the exact-head approval and absent AI-screenshot boundary instead.
Keep private live identity details local under `docs/LIVE_EVIDENCE_PRIVACY.md`.
