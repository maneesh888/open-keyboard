# Milestone: reusable touch keyboard layout package

Status: planned. This document authorizes no package migration or product change by itself.
Source baseline inspected: `origin/main` at `457b3c6c8e644488f8c1a7a391eb1e0a233b253a`.

## Outcome and success measures

Create a separate, source-based Swift package for OpenKeyboard's complete rendered
keyboard panel and local typing experience. It should work as an iOS/iPadOS custom
keyboard on supported iPhones, iPads, and iPhone Duo, and as a reusable view in an
independent consumer. The package owns the panel frame, key layouts, hit regions,
typing state, and customizable spaces for accessory and emoji experiences. It has no
dependency on OpenKeyboard's AI connector, gateway, credentials, or product panels.

Success means a second consumer can render and type with the package without linking
OpenKeyboard AI code; the OpenKeyboard extension retains its current typing and AI
behavior; and normal Simulator proof shows the real extension on compact iPhone,
docked iPad, and floating iPad layouts. Duo outer/inner acceptance follows the
device-specific evidence gate below.

## Boundary and current state

| Owner | Responsibility |
| --- | --- |
| Layout package | Rendered panel background and inset border; keys, touch targets, shift/symbol/return/delete behavior and repeat; adaptive compact/wide arrangements; configurable accessory, suggestion, emoji, and optional action slots; styling and key-event API. |
| OpenKeyboard extension | `UIInputViewController`, `textDocumentProxy` adapter, height constraints, next-input-mode action, haptics, Full Access, host configuration, AI ViewModels and services, and content injected into slots. |
| iOS/iPadOS | Placement and size of the keyboard window, floating/docked transition, and system-managed areas outside the extension's view. |

The package's "whole panel" is the entire UI inside the bounds supplied to the
extension, including reserved space for optional content. It cannot take ownership
of the system's lower strip or move the floating keyboard window. A distinct border
and gap must remain visible between the rendered panel and surrounding system UI.
Emoji entry is a customizable slot/action contract, not a bundled emoji picker.

Today, `KeyboardView` measures available width for `KeyboardKeyPositions`, while
`KeyboardPanelLayout` supplies fixed row and panel heights. `KeyboardViewModel`
mixes typing with OpenKeyboard AI state, so moving it wholesale would violate the
package boundary. The local UniversalAiConnector package is a binary-wrapper
integration example, not a requirement that this visual package be binary.

The separate `codex/keyboard-border` worktree has the 2-point inset teal border at
`632586547010616d66f8552408602c8a264c5ba6`; it is not part of this plan-only
change. Earlier direct Simulator screenshots covered the docked iPad appearance,
but floating iPad typing and Duo extension behavior remain `RUNTIME_UNVERIFIED`.

The local `main` commit `f087933b388444d98679ca5e8fd4aaaadaad4ce1` is not
an ancestor of the inspected remote-tracking `main`. Its macOS plan has the same
Git blob on both branches, and its added TODO requirements are already present
upstream. Refresh the remote and compare content before implementation; do not
merge that commit into the keyboard package branch merely to preserve its ancestry.

## Scope and exclusions

In scope: the package boundary and API, typing and visual extraction, panel slots,
border, iPhone layouts, iPad docked/floating behavior, Duo width transitions,
independent consumer, tests, and integration proof. Apple Watch, macOS, visionOS,
gateway or semantic-contract changes, a built-in emoji library, deployment, and
ownership of system keyboard chrome are outside this milestone. The package may be
portable to another platform later, but only iOS/iPadOS custom-keyboard use is an
acceptance target now.

## Critical path and work packages

### M1 — Establish the visible and dependency boundary

- **Deliverables:** Annotate direct iPhone and iPad Simulator screenshots to show
  package-owned panel, border, optional slots, host-owned adapter, and system-owned
  gap/window. Inventory imports, source dependencies, target membership, and current
  input actions; specify the package's public intents and slot contract.
- **Entry:** Refresh `origin/main`, reconcile the existing border change and the
  content of local `main` without importing unrelated history.
- **Exclusions:** No layout migration, new emoji UI, or behavior change.
- **Verification:** Source/object-digest audit and inspected direct screenshots.
  **GO** when every visible region and dependency has an owner; **REWORK** if the
  proposed package still depends on the AI connector or `UIInputViewController`;
  **BLOCKED** if the base or ownership of existing work cannot be resolved.
- **Risk/containment:** An inaccurate screenshot boundary would move system UI into
  the API. Keep the screenshot and dependency map as reviewable evidence before code.

### M2 — Package the typing engine and key geometry

- **Deliverables:** Source Swift package for keys, hit regions, local typing state,
  shift/symbol modes, delete repeat, space and return behavior, and semantic key
  intents. Host adapters apply intents to `textDocumentProxy` and handle haptics.
  Add a small independent consumer that needs no OpenKeyboard AI component.
- **Entry:** M1 package contract is accepted. **Exclusions:** AI state, network,
  persistence, Keychain, App Group, and system window control.
- **Verification:** Focused package tests over compact and regular widths, typing
  regression tests, independent-consumer build, and app/extension build.
  **GO** when the package stands alone and phone typing remains equivalent;
  **REWORK** for lost keys, unsafe touch regions, or leaked product dependencies.
- **Risk/containment:** `KeyboardViewModel` is large and mixed-purpose. Extract the
  typing slice behind intents incrementally; retain the extension adapter until
  parity is demonstrated.

### M3 — Package the panel and customization slots

- **Deliverables:** Move the rendered panel shell, key view, and border into the
  package. Expose configurable theme, spacing, toolbar/accessory and emoji spaces,
  and optional actions. Inject OpenKeyboard's AI toolbar and panels from the host.
  Keep the border around the full panel, with a visible inset from its outer edge.
- **Entry:** M2 typing API is stable. **Exclusions:** AI feature implementations
  and a bundled emoji picker.
- **Verification:** Slot/default/empty-state tests and normal Simulator screenshots
  of the actual extension in an ordinary host text field. **GO** when the sample
  renders without AI and OpenKeyboard's controls remain usable; **REWORK** for
  clipping, lost accessibility, or a border overlapping system chrome.
- **Risk/containment:** Panel height and host constraints can disagree. Keep height
  negotiation explicit in the extension adapter and revert the UI switch if the
  normal extension no longer fits.

### M4 — Adaptive iPad experience

- **Deliverables:** Use the phone-style compact arrangement when iPadOS supplies
  a floating width; use a deliberate wide arrangement with bounded key sizes when
  docked. Reflow slots and height as width changes, preserving typing state.
- **Entry:** M3 integrated panel. **Exclusions:** Programmatically forcing the
  floating window or copying the system's emoji keyboard.
- **Verification:** Geometry and transition tests plus direct portrait, landscape,
  docked, floating, typing, and return-to-docked screenshots from the normally
  installed extension. **GO** only when those real transitions are visible and
  usable; **REWORK** for stretched keys, clipped slots, or lost text state;
  **BLOCKED** if iPadOS does not offer the transition in the chosen test host.
- **Risk/containment:** Width can change while visible. Select from actual layout
  space rather than the device model, and keep one typing engine across layouts.

### M5 — Adaptive iPhone Duo experience

- **Deliverables:** Exercise compact outer, regular inner, split-width, orientation,
  and live-resize cases without hard-coded Duo dimensions. Preserve input and panel
  state when the available width changes.
- **Entry:** M4 responsive layout. **Exclusions:** A separate keyboard for each
  physical pose or hinge geometry inferred from screen size.
- **Verification:** Deterministic width/height transition tests, then normal
  extension proof where Xcode permits it. Apple's Xcode 27.1 beta notes say running
  and debugging most app extensions is unavailable in the Duo Simulator. If that
  applies, mark extension runtime `RUNTIME_UNVERIFIED` and use the repository's
  exact-head human verification route rather than presenting previews as proof.
  **GO** with required evidence; **REWORK** for layout/state failures;
  **BLOCKED** while material extension behavior cannot be verified.
- **Risk/containment:** Simulator capability may change. Recheck the current Xcode
  release notes before the work package and keep device-only claims qualified.

### M6 — Integrate, verify, and publish

- **Deliverables:** Pin the package dependency, remove duplicate layout code,
  document its public API and platform matrix, and complete exact-head review.
- **Entry:** M2–M5 acceptance and a clean integration base. **Exclusions:** App
  deployment and destructive cleanup.
- **Verification:** Affected regression tests, `./scripts/check.sh --full`, the
  classifier-selected live gate when applicable, normal Simulator proof for
  user-facing changes, independent exact-head review, and required GitHub checks.
  **GO** for guarded merge only when every applicable gate passes or the documented
  human route explicitly accepts an evidence gap; otherwise **REWORK/BLOCKED**.
- **Risk/containment:** A package upgrade can change extension startup, size, or
  signing. Measure the final linked extension and roll back the package pin if it
  regresses the normal keyboard lifecycle.

M4 and M5 test matrices can be prepared in parallel after M2. M3 and the actual
responsive integrations remain on the critical path. Each phase is a separate,
bounded implementation work package, not authorization to start the next one.

## Evidence and completion

Automated regression evidence covers package logic, geometry, and host adapters.
Normal simulator runtime proof covers the actual installed extension, visible
typing, panel, and docked/floating transitions. A component preview or XCTest
attachment cannot replace normal runtime proof. Physical-device interaction is
not authorized by this plan; add it only after an explicit request. Live model
evidence is not applicable to layout-only changes unless an implementation diff
also changes request, response, model, or semantic behavior.

The milestone is complete when an independent consumer compiles and types without
OpenKeyboard AI dependencies, OpenKeyboard preserves its typing and injected AI
controls, the border and host gap are visually correct, iPad compact and wide
transitions are verified, Duo evidence is resolved or explicitly qualified, and
all applicable exact-head release gates pass.

## Sources and refresh points

Requirement source: the keyboard package, border, iPad, floating, Duo, and
customization requests in the 2026-09-29 through 2026-10-01 conversation.
Repository source digests at the baseline above (Git blob SHA prefixes):

| Source | Digest |
| --- | --- |
| `AGENTS.md` | `b73622d8` |
| `README.md` | `4c77e62f` |
| `docs/AI_KEYBOARD_TODO.md` | `af3adb79` |
| `docs/KEYBOARD_PRODUCT_COMPLETION_PLAN.md` | `b2175bc9` |
| `docs/DEVELOPMENT_WORKFLOW.md` | `ac9c9aef` |
| `OpenKeyboardExtension/KeyboardView.swift` | `71346794` |
| `OpenKeyboardExtension/KeyboardViewController.swift` | `ef68835e` |
| `OpenKeyboardExtension/KeyboardTouchLayout.swift` | `895202e0` |
| `OpenKeyboardExtension/KeyboardToolbarState.swift` | `7a9f45fc` |
| `OpenKeyboardExtension/KeyboardViewModel.swift` | `e00b8673` |
| `OpenKeyboard.xcodeproj/project.pbxproj` | `7c74e353` |
| `Vendor/universal-ai-connector/swift-package/Package.swift` | `2904ebdb` |

Apple references: [Creating a custom keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard), [Configuring a custom keyboard interface](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface), [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo), and [Xcode 27.1 beta release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes). Refresh release-note and source-dependent phases if those inputs change.

**First executable work package:** M1, the annotated boundary screenshot,
dependency map, and public API sketch. Do not start the extraction before M1's
GO decision.
