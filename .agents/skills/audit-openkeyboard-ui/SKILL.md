---
name: audit-openkeyboard-ui
description: Audit OpenKeyboard SwiftUI screens and end-to-end journeys for source-evidenced layout, interaction, accessibility, state, navigation, theme, and MVVM risks. Use for UI or UX inspection and defect triage; route wording-only analysis to the product-copy skill and authorized fixes to the development skill.
---

# Audit OpenKeyboard UI

Find defects and usability risks without confusing source inspection with rendered or runtime
acceptance. Follow a target screen through the production state and navigation paths that make it
visible, then check its role in the surrounding journey.

## Set scope and evidence limits

1. Read `AGENTS.md` completely and apply its authority ledger. Treat audit, review, diagnosis, and
   recommendation requests as read-only. Do not edit tracked files, stage, commit, publish, or
   change a PR during an audit.
2. Identify the target surface, journey, user task, requested depth, and available evidence. For an
   individual screen, inspect its immediate entry and exit. For a journey, map every production
   screen, sheet, overlay, external-settings handoff, and keyboard-extension transition needed to
   complete the task.
3. State the audit's evidence ceiling before drawing conclusions. Source, previews, fixtures,
   debug hosts, tests, accessibility metadata, and XCTest attachments are useful evidence, but none
   proves the normally rendered or operated product. Never claim visual, interaction, or runtime
   acceptance from source inspection alone.
4. If the user asks to implement a fix, begin a new implementation phase through
   `$develop-openkeyboard`. Recompute authority and use the repository's automated and normal
   simulator proof requirements; do not let the earlier read-only audit silently authorize edits.
5. Keep the pinned semantic prompt contract out of UI-audit scope. Audit how semantic results are
   presented and operated, not canonical prompt wording or model schemas.

## Build the production UI trace

Do not audit a SwiftUI declaration in isolation. For each target surface:

1. Find the production app or extension entry point and the reachable call site that presents the
   view. Separate shipping paths from previews, component hosts, debug launch states, test-only
   routes, and dead or unreachable declarations.
2. Follow navigation, sheets, overlays, bindings, environment objects, focus, callbacks, and
   external URL actions into and out of the surface. Record the immediate predecessor, target,
   successor, cancellation path, and recovery path.
3. Trace every material control to its production action and observable state transition. Inspect
   its ViewModel, reducer, model, service, App Group state, controller bridge, or system API as
   applicable. A button-shaped view, accessibility identifier, or test fixture does not prove that
   a production action works.
4. Enumerate reachable states from the real state producers, including applicable default, empty,
   loading, disabled, stale, success, partial, permission-needed, offline, authentication,
   timeout, cancellation, destructive, and recovery states. Note impossible or test-only states
   instead of treating them as shipping behavior.
5. Read focused tests to learn the asserted contract and missing coverage. Treat unit, XCTest,
   XCUITest, seeded state, debug hosts, and screenshot tests as **Automated regression evidence**,
   never normal simulator runtime proof.
6. Cite exact `path:line` evidence and, for behavioral findings, the shortest useful call chain or
   state transition. Search results without production reachability are not findings.

## Classify every finding

Use exactly one of these classifications for every reported finding:

- **confirmed from code** — Direct production-source evidence establishes the behavior or
  structural violation without needing a renderer. Examples include an action wired to the wrong
  transition, a reachable state with no recovery control, side-effecting network work owned by a
  View, or an icon-only control with no accessible name. Do not use this label for inferred visual
  appearance.
- **likely visual risk** — Source establishes a credible layout or presentation hazard, but actual
  manifestation depends on rendering. Examples include rigid dimensions around variable text,
  unscrollable content under accessibility sizes, likely localization expansion, competing visual
  hierarchy, or theme combinations whose effective contrast depends on materials and context.
- **requires simulator verification** — The source cannot determine whether an important visible
  or interactive behavior is acceptable. Use this for unresolved questions such as actual
  truncation, clipping, focus, keyboard avoidance, sheet transitions, animation, touch behavior,
  VoiceOver order, or app-to-extension/system-settings continuity. Present it as an open
  verification requirement, not a confirmed defect.

Do not create extra classification labels or blend two labels in one row. Split a mixed concern
when its source-confirmed behavior and visual manifestation need different classifications.
Severity and classification are independent: uncertainty does not automatically lower impact.

Use these severities consistently:

- **Critical:** prevents a core journey, causes destructive or privacy-impacting behavior, or
  makes the essential workflow unavailable to an affected user group.
- **High:** blocks or seriously misdirects an important task with no reasonable recovery.
- **Medium:** creates recurring confusion, friction, inaccessible operation, or a substantial
  presentation failure while a workaround exists.
- **Low:** localized polish or consistency issue with limited task impact.

## Audit the target screen

### Layout and hierarchy

- Check reading order, visual priority, grouping, spacing, alignment, safe areas, scrolling,
  overlays, keyboard height constraints, and whether the primary action remains discoverable.
- Inspect fixed widths and heights, absolute font sizes, `lineLimit`, `minimumScaleFactor`,
  `fixedSize`, geometry calculations, and dense horizontal stacks against Dynamic Type, long
  values, narrow devices, keyboard-extension bounds, and localization expansion.
- Check actual interactive bounds, padding, overlap, `contentShape`, and enabled state for tap
  targets. Do not infer a reliable hit area from the visible symbol size alone.
- Distinguish structural hierarchy defects from taste. Use a **likely visual risk** or
  **requires simulator verification** classification when rendering decides the outcome.

### Interaction, navigation, and state

- Verify that every control's affordance, enabled/disabled appearance, loading behavior, action,
  success state, and retry path agree. Check duplicate submission, cancellation, stale state,
  dismissal, re-entry, and whether errors preserve a viable next step.
- Trace navigation destinations and return behavior. Confirm that modal ownership, tab/page state,
  external iOS Settings handoffs, and host-app/extension shared state do not strand the user or
  imply completion too early.
- Check that state transitions are observable in the UI and that mutually exclusive states cannot
  compete. Flag missing states as interaction gaps; do not propose copy as a substitute for absent
  behavior.

### Accessibility and adaptable presentation

- Check accessible names, values, traits, hints, grouping, focus order, and state announcements.
  An `accessibilityIdentifier` supports automation but is not a VoiceOver label.
- Inspect icon-only controls, custom gestures, color-only meaning, disabled controls, changing
  progress/results, and decorative elements. Visible and assistive behavior must describe the same
  action and state.
- Check Dynamic Type reflow, bold text, contrast, reduced motion, localization, truncation, and
  text input/focus risks. Source can confirm missing semantics, but rendered order, effective
  contrast, clipping, and VoiceOver operation usually require simulator verification.

### Theme and architecture

- Compare colors, typography, surfaces, strokes, shadows, radii, and semantic states with
  `OpenKeyboardTheme`. Report raw or duplicated styling when an existing token represents the same
  role; do not demand a token that the design system does not provide.
- Apply the repository's MVVM boundary: Views present data and may own ephemeral presentation
  state; ViewModels own UI state and actions; services own networking, persistence, App Group,
  Keychain, gateway, and file I/O. Trace ownership before flagging a violation.
- Compare the app and keyboard extension where they represent the same state or action, while
  respecting their different space and lifecycle constraints.

## Run the journey continuity pass

Read the journey in user order, not source-file order. Verify that:

- the preceding action reaches the promised destination and the destination reflects the state
  just created;
- setup, configuration, connection, model validation, keyboard permission, availability, and
  recovery advance coherently across onboarding, home, settings, playground, and extension;
- back, cancel, dismiss, retry, apply, copy, rerun, keyboard switching, and external-settings
  returns preserve state and offer a clear next step;
- component hierarchy, primary-action placement, semantic colors, and accessibility patterns stay
  consistent where the user should recognize the same concept;
- loading, partial success, error, and stale states do not disappear at a screen or process
  boundary; and
- tests cover the important state transitions and journey handoffs, with missing tests reported as
  coverage gaps rather than proof that the UI is defective.

For an isolated-screen request, inspect adjacent screens only far enough to detect broken entry,
exit, terminology, state, or interaction continuity. Report material adjacent findings separately.
Do not expand the requested deliverable or later fix scope without the user's authorization.

## Coordinate product wording

Use `$write-openkeyboard-product-copy` for wording-specific analysis: titles, labels, explanatory
text, claims, terminology, tone, and the semantic accuracy of CTA language. This skill retains
ownership of control behavior, action reachability, placement, hierarchy, layout fit,
accessibility behavior, navigation, and state transitions.

When one concern crosses both domains, keep the evidence joined but separate the recommendations.
For example, this audit can confirm that a CTA opens the wrong destination; the copy skill decides
the best label if the behavior is intentionally retained. Do not duplicate a full copy audit in a
UI-audit report.

## Deliver the audit

Lead with the highest-impact findings. Use this structure when a formal report is useful:

```text
Scope and user task:
Journey: <entry> -> <target> -> <next or exit>
Evidence reviewed:
Evidence boundary:

Findings:
| ID | Severity | Classification | Surface / state | Exact source evidence | User impact | Recommendation | Required verification |

Journey continuity findings:
Adjacent out-of-scope findings:
Coverage gaps:
Wording handoff to $write-openkeyboard-product-copy:
Overall evidence status:
```

For `Exact source evidence`, include `path:line` and the relevant production call chain or state
producer when behavior is involved. For `Required verification`, name the smallest decisive next
check: source/test correction, focused **Automated regression evidence**, accessibility inspection,
or **Normal simulator runtime proof** through the repository route. Never prescribe physical-device
work unless the user explicitly requested it and the authority ledger allows it.

If there are no findings, say that no source-supported findings were identified within the stated
scope; do not say the UI is correct, polished, accessible, or runtime-verified. A source-only audit
must explicitly leave rendered layout, touch behavior, navigation in operation, Dynamic Type,
localization, VoiceOver flow, and normal app/extension continuity unaccepted until the required
runtime evidence exists.

## Route authorized fixes

After an explicit implementation request, use `$develop-openkeyboard` and preserve the agreed
finding IDs as the work boundary. Fix only the authorized target surfaces, update focused
regression coverage, and follow `AGENTS.md` for normal simulator proof of user-visible changes.
Continue to report adjacent-screen risks without editing them unless the user expands scope or an
in-scope shared component necessarily affects them.
