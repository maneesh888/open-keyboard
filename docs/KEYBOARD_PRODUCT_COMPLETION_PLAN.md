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

## M2 direction — iOS-like keyboard + compact AI writing UX

Decision: after M1 proved the real Fix Grammar path end-to-end, the next product track is to fine-tune features and improve the keyboard experience.

Goals:
- Keep base typing UX visually and behaviorally close to Apple's iOS keyboard.
- Keep AI UX helpful, compact, and contextual rather than large app-style buttons.
- Preserve the verified M1 path: app config → extension config → gateway POST → text replacement.

M2 acceptance criteria:
- Keyboard rows mimic iOS proportions and offsets:
  - `qwertyuiop`
  - `asdfghjkl`
  - `⇧ zxcvbnm ⌫`
  - `123 / globe / space / return`
- Key styling uses iOS-like colors, corner radius, shadows, press states, and safe-area sizing.
- AI actions move into a slimmer suggestion/action strip.
- Fix Grammar remains available but less visually dominant.
- Delete repeat, shift state, return key, and numbers/symbols mode are handled well enough for normal typing.
- Screenshots on iPhone 17 Pro and a smaller simulator are visually acceptable.
- Real keyboard Fix Grammar functional test still passes after redesign.

Feature fine-tuning candidates:
- Better connection/setup state in the keyboard when gateway is missing.
- Clearer settings copy: gateway URL + API key are user-entered; model is read-only and loaded from gateway.
- Privacy copy for Full Access/network text transmission.
- Optional in-app test ground only if it does not confuse the production UX.

Next safe implementation slice:
1. First patch current settings/status polish and commit if clean.
2. Then start M2 keyboard layout redesign behind small, testable changes.

### Reference: Neutral keyboard layout benchmark

Artifact:

Observed UX details to mimic/adapt:
- Overall keyboard container is iOS-like light gray with rounded top corners.
- Top strip is compact, not tall:
  - Product icon button on left.
  - Prediction/suggestion words in the middle.
  - AI/sparkle action button on right.
- AI controls are not giant app buttons; they are integrated into a suggestion strip.
- Letter rows use iOS-like white rounded keys with soft shadows and tight spacing.
- Row offsets match iOS-style QWERTY:
  - row 2 starts inset from row 1.
  - row 3 includes shift and delete keys.
- Bottom row includes `123`, emoji, wide space, and return.
- Globe and microphone sit in the bottom safe-area area outside the main key rows.
- Visual priority is typing first, AI second.

M2 implication:
- Replace current large magenta action buttons with a compact suggestion/action strip.
- Build an iOS-like key grid with row offsets and functional modifier keys before adding more AI features.

### Reference: Neutral keyboard dark-mode benchmark

Artifact:

Observed dark-mode details:
- Keyboard container is near-black/dark gray, still with rounded top corners.
- Keys are raised dark gray rounded rectangles with lighter labels.
- Suggestion strip keeps the same structure as light mode: logo, suggestions, sparkle action.
- Separators between suggestions are subtle vertical dividers.
- Bottom row uses darker modifier keys and a wide space bar with consistent radius.
- Globe/mic stay bright enough for contrast but not visually dominant.

M2 implication:
- Implement light/dark adaptive colors explicitly.
- Keep the same geometry across modes; only tokens/colors change.

### Reference: Neutral suggestion-state toolbar benchmark

Artifact:

Observed dynamic toolbar behavior:
- The same compact toolbar changes state based on context/API suggestions.
- When typing `are`, the toolbar shows a small label:
  - `Synonyms for "are"`
- Suggestion slots become actionable replacements:
  - `exist | live | stand`
- The logo stays on the left and the sparkle/AI action stays on the right.
- The toolbar stays the same height and does not turn into a large button panel.
- This creates a state machine:
  1. Idle/prediction state: common next-word suggestions.
  2. Suggestion state: API/context label + replacement suggestions.
  3. Action state: compact AI actions such as Fix/Rephrase/Summarize.
  4. Loading/error state: small inline status, not a large alert.

M2 toolbar model:
- Implement a single `KeyboardToolbarState` rather than separate button rows.
- Keep toolbar geometry stable across states.
- Suggestions should be tappable chips/segments inside the toolbar.
- AI fetch results should update toolbar contents, not resize the keyboard.

### M2 decision: no local idle prediction for now

Decision from Maneesh 2026-06-08:
- Do not build a local/lightweight prediction engine now.
- Do not try to fake iOS predictive text.
- Apple’s native prediction is good, but unavailable to third-party custom keyboards, and rebuilding it is out of scope.

Toolbar direction:
- The top bar is AI-only for now.
- Idle state should be sophisticated but not predictive.
- Use it for compact AI entry points, status, and fetched AI suggestions/results.
- Example idle/action state:
  - `[OpenKeyboard icon] Fix Grammar | Rewrite | Summarize [sparkle]`
- Example loading state:
  - `[OpenKeyboard icon] Checking… [sparkle]`
- Example result state:
  - `[OpenKeyboard icon] Apply correction | Dismiss [sparkle]`

Rule:
- No giant buttons.
- No fake prediction words.
- Keep a compact, polished writing-assistant bar above the keyboard.

### Reference: Neutral correction-card toolbar benchmark

Artifact:

Observed correction toolbar layout:
- Left issue-count badge:
  - Rounded badge showing `1` correction.
- Primary correction card:
  - Compact rounded rectangle.
  - Top line is short explanation/truncated rule, e.g. `Correct subject-verb...`.
  - Bottom line is proposed replacement in accent color, e.g. `are`.
- Secondary chip:
  - Large rounded pill with another candidate/replacement, e.g. `Nob`.
- Original text display:
  - Quoted original word, e.g. `"nob"`.
- Right sparkle button:
  - Persistent AI/action entry.
- All of this fits in one compact toolbar row above the keys.

M2 correction-state model:
- Toolbar state should support `correction(count, explanation, replacement, originalText, alternatives)`.
- Tapping the primary card applies the replacement.
- Tapping sparkle opens more AI actions/options.
- Keep correction state compact; do not open a modal or expand keyboard height.
- For our first M2 version, we can map current `Fix Grammar` output into one correction card:
  - explanation: `Grammar suggestion`
  - replacement: corrected text or corrected current phrase
  - original: current buffer/current line
  - count: `1`

### Reference: Neutral correction detail overlay benchmark

Artifact:

Observed expanded issue-count behavior:
- Tapping the issue count opens an expanded correction detail surface that replaces the key grid area.
- It keeps the same keyboard container/safe-area shape instead of opening an app modal.
- Header row includes:
  - issue category icon/badge
  - category + rule text, e.g. `Correctness · Correct subject-verb agreement`
  - overflow/more button
- Body shows the sentence with inline diff styling:
  - removed text in red/struck-through
  - replacement in accent color
- Explanation text is concise and readable.
- Bottom actions:
  - prominent `Accept`
  - secondary `Dismiss`
  - keyboard icon to return to normal key layout
- Globe and microphone remain in the bottom safe-area row.

M2 expanded correction model:
- Add toolbar/detail state later: `correctionDetail(issue)`.
- Issue count tap should replace keys with detail overlay.
- Accept applies replacement through the existing replacement planner/proxy path.
- Dismiss returns to normal toolbar/key layout without applying.
- Keyboard icon returns to key layout while keeping current suggestion available.

Scope decision:
- First M2 slice can implement compact toolbar only.
- Expanded correction detail is M2.2 after compact toolbar + iOS-like key grid compile and screenshot cleanly.

### Reference: Neutral correction-complete benchmark

Artifact:

Observed post-correction behavior:
- After the correction is applied and no suggestions remain, the keyboard area is replaced by a completion state.
- It shows a friendly illustration, title, and message:
  - `You did it!`
  - `There are no more suggestions.`
- Primary action:
  - `Back to Keyboard`
- Globe and microphone remain in the bottom safe-area row.
- This confirms the correction flow should be treated as a set of keyboard-panel states, not just a top toolbar.

Priority adjustment:
- Implement/test this correction-complete state before broader M2 polish.
- First correction-flow target:
  1. User taps Fix Grammar.
  2. Gateway returns correction.
  3. App applies replacement.
  4. Keyboard shows `You did it! There are no more suggestions.` panel.
  5. User taps `Back to Keyboard` to return to normal key grid.

Tests required:
- Unit/state test for correction-complete toolbar/panel state.
- UI/accessibility identifiers for `correction_complete_panel` and `back_to_keyboard`.
- Host screenshot verification of the completion panel.
- Real Fix Grammar functional test still passes and can return to keyboard.

### Reference: Neutral sparkle action panel benchmark

Artifact:

Observed sparkle behavior:
- Tapping sparkle opens an AI action panel that replaces the key grid.
- Header/title explains the current AI goal, e.g. `Fix spelling errors and clarify.`
- Main text preview shows current text with highlighted issue markers.
- Action chips are horizontal and large enough to tap:
  - `Improve`
  - `Rephrase`
  - `Translate`
- Bottom controls include:
  - keyboard/back-to-keyboard button
  - compact mode/action selector in center
  - confirm/apply button on right
- Globe/mic remain in bottom safe-area row.

M2 action-panel model:
- Sparkle tap should eventually switch from key grid to `aiActionPanel`.
- Existing features map naturally:
  - `Improve` -> Fix Grammar
  - `Rephrase` -> Rewrite
  - `Translate` -> future action/not enabled yet
  - Summarize can live in the mode selector or overflow.
- First implementation can expose Improve/Rephrase/Summarize and disable/hide Translate until implemented.

### M2 correction: move action buttons out of keyboard bar

Decision from Maneesh 2026-06-08:
- The existing Fix/Rewrite/Summarize buttons are ugly when placed directly on the keyboard.
- Once the new compact bar exists, action buttons should move into the sparkle overlay/action panel.
- The keyboard bar itself should stay minimal and polished.

Updated toolbar/panel split:
- Compact top bar:
  - left app/status icon
  - short status/correction summary
  - right sparkle button
  - no permanent Fix/Rewrite/Summarize button row
- Sparkle overlay/action panel:
  - Improve -> current Fix Grammar
  - Rephrase -> current Rewrite
  - Summarize -> current Summarize
  - Translate -> future disabled/hidden until implemented

Implementation priority:
1. Remove permanent action-button look from the top keyboard bar.
2. Add tested sparkle overlay panel containing the existing actions.
3. Add correction-complete panel after successful apply.
