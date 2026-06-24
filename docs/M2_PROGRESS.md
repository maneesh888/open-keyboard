# Open Keyboard M2 Progress Tracker

Last updated: 2026-06-19 12:55 Asia/Dubai

## Goal
Make Open Keyboard feel closer to a polished iOS keyboard plus high-quality writing-assistant UX while preserving the verified M1 gateway Fix Grammar path.

## Current status

Status: In progress, not committed.

Current working tree has broad dirty changes across product, proof routes, CI/docs, and generated artifacts. Do not push/commit until the dirty tree is split into scoped branches and each lane has verification evidence.

## Completed

- M1 real keyboard Fix Grammar path verified and committed.
  - Commit: `764c6e6 Add real keyboard AI functional path`
  - Latest real keyboard verification: `/app/workspace/clawd-coder/requests/clawmaster/20260606T022442-openkeyboard-uitest-debug-flag-rerun.md`
- Release hardening docs committed.
  - Commit: `7a3438d Document Open Keyboard release hardening`
- iPhone 17 Pro simulator App Group entitlement issue diagnosed and fixed by reinstall.
  - Request: `/app/workspace/clawd-coder/requests/clawmaster/20260608T132414-openkeyboard-iphone17-entitlements-reinstall.md`
- Private third-party/iOS keyboard references were removed from repo tracking; use only neutral local references outside git:
  - `docs/design/artifacts/`
- M2 design notes appended to:
  - `docs/KEYBOARD_PRODUCT_COMPLETION_PLAN.md`
- Settings polish started:
  - model is read-only;
  - model loads from gateway;
  - button says `Test Connection & Load Models`.
- Added first toolbar state model/tests:
  - `OpenKeyboardExtension/KeyboardToolbarState.swift`
  - `OpenKeyboardUITests/KeyboardToolbarStateTests.swift`
- ClawMaster M2 compact toolbar verification passed:
  - Request: `/app/workspace/clawd-coder/requests/clawmaster/20260608T155232-openkeyboard-m2-toolbar-build-screenshot.md`
  - Build: PASS
  - Targeted tests: PASS, 12 tests / 0 failures
  - Screenshot: `reports/clawmaster/20260608T155232-openkeyboard-compact-toolbar.png`

## User decisions

- Do not build local idle prediction.
- Do not fake iOS predictive text.
- Top keyboard bar should be AI-only.
- Existing actions should move out of the top bar and into sparkle overlay.
- Use original, neutral writing-assistant UX references.
- Write tests for all behavior slices.

## Active blockers / issues

- Real keyboard switcher helper is narrowed: host proof can activate the real OpenKeyboard extension and QWERTY keys are visible.
- Real logo/action-menu acceptance is still blocked because the real extension reports `Gateway not configured`, so `ai_sparkle_action` is absent.
- Next diagnostic is extension-side config-state instrumentation; see `docs/REAL_EXTENSION_SMOKE_PLAN.md`.
- Dirty default worktree is broad; use scoped branches/commits only after lane split.

## Next implementation slice

### M2.1 — Correct toolbar/action split

Planned:
- Top bar becomes minimal:
  - left app/status icon;
  - center status/correction summary;
  - right sparkle button.
- Remove permanent `Fix / Rewrite / Summarize` buttons from top bar.
- Sparkle opens action overlay replacing key grid.
- Overlay actions:
  - `Improve` -> current Fix Grammar;
  - `Rephrase` -> current Rewrite;
  - `Summarize` -> current Summarize;
  - `Translate` hidden/disabled for now.

Tests required:
- Toolbar state tests for idle/status/sparkle action entry.
- Overlay state tests.
- Accessibility IDs:
  - `ai_toolbar`
  - `ai_sparkle_action`
  - `ai_action_panel`
  - `ai_action_fixGrammar`
  - `ai_action_rewrite`
  - `ai_action_summarize`
  - `back_to_keyboard`

Verification required:
- `git diff --check`
- targeted Xcode tests
- iPhone 17 Pro screenshot
- real Fix Grammar functional test still passes or documented blocker

## Next after M2.1

### M2.2 — Correction complete panel

Planned:
- After correction apply, show panel:
  - `You did it!`
  - `There are no more suggestions.`
  - `Back to Keyboard`
- Keyboard panel state replaces key grid, matching the compact writing-assistant target.

### M2.3 — Correction detail overlay

Planned:
- Tapping issue count opens expanded correction detail overlay.
- Accept/Dismiss/Back-to-keyboard controls.

## Commit rules

- Do not commit until:
  - build passes;
  - tests pass;
  - screenshot reviewed;
  - real keyboard behavior is verified or blocker documented;
  - security/privacy regressions checked.
