# Open Keyboard Product Completion Plan

Updated: 2026-06-05

## Current honest status

The keyboard foundation is working, but the product is not yet a useful AI keyboard.

Verified:
- custom keyboard extension installs/registers
- keyboard appears in switcher
- custom UI loads
- Allow Full Access path works
- app-to-extension config sharing works
- AI action buttons can be visible/enabled
- gateway/Apfel can return corrected text

Not yet verified/complete:
- actual keyboard action replacement end-to-end
- Rewrite/Summarize end-to-end
- AI suggestion cards while typing
- polished in-keyboard correction UX
- key storage/privacy hardening

## Active blocker

`Fix Grammar` must work end-to-end in the actual keyboard:

```text
type text → tap Fix Grammar → text changes in host input
```

Active host request:

```text
/app/workspace/clawd-coder/requests/clawmaster/2026-06-05T150836-openkeyboard-functional-typed-context-rerun.md
```

## Milestones and rough estimates

### M1 — One action actually works: Fix Grammar
Estimate: 0.5–1 day if current typed-context rerun is close; 1–2 days if UIKit host/proxy context redesign is needed.

Tasks:
- verify `documentContextBeforeInput` sees typed text
- gateway call fires from actual keyboard
- replacement applies safely
- preserve spaces/newlines/graphemes
- pass functional UI test

### M2 — All manual actions work
Estimate: 1–2 days after M1.

Tasks:
- Rewrite end-to-end
- Summarize end-to-end
- empty text state
- gateway unavailable/invalid key/timeout states
- loading/error UI polish

### M3 — Better keyboard UX
Estimate: 2–4 days.

Tasks:
- correction preview card inside keyboard
- before/after preview
- Accept / Dismiss
- compact status area
- polished test screen
- screenshot pass on small/large devices

### M4 — Suggestions while typing
Estimate: 3–6 days.

Tasks:
- observe typed context
- debounce input
- call gateway for lightweight suggestions
- cancel stale requests
- suggestion chips/cards
- tap to apply
- rate limiting and latency handling

### M5 — Security/privacy hardening
Estimate: 1–3 days.

Tasks:
- move API key to shared Keychain access group or document interim risk
- gateway URL validation/warnings for non-HTTPS public URLs
- Full Access privacy disclosure
- reduce API key display in app UI

### M6 — Release readiness
Estimate: 2–4 days.

Tasks:
- full test suite
- real device/manual QA
- reviewers
- commit/docs/screenshots
- TestFlight prep if desired

## Why the full queue was not active

Coder was incorrectly treating the immediate blocker as the whole queue. The real product queue should be tracked separately from the current failing test. Going forward, this file is the product queue, while ClawMaster request files track host-side blockers.

## Weekend execution mode — 2026-06-05

Maneesh explicitly asked Coder to work full-time to finish as soon as possible this weekend.

Priority order:
1. Finish M1 Fix Grammar end-to-end.
2. Immediately add Rewrite/Summarize end-to-end tests once replacement path works.
3. Add preview/accept/dismiss UX only after manual actions are reliable.
4. Run review gates and commit each stable slice.

Operating rule:
- Do not wait silently on stale host requests.
- If a host request has no result for ~30–60 minutes, re-read it, report stale state, and queue a narrower continuation/fallback request.
- Keep code changes small and verified.
