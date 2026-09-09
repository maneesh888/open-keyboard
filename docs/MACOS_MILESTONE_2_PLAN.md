# Milestone 2: OpenKeyboard macOS App

## Objective

Add a native macOS app target to the existing OpenKeyboard project. Keep the
repository, product family, and shared source names unchanged, while providing a
desktop writing assistant for grammar correction and writing improvements. The
macOS app does not include an iOS keyboard extension.

User-facing positioning:

> OpenKeyboard is a privacy-focused writing assistant. On iOS it includes a
> keyboard extension; on macOS it provides a desktop and menu-bar writing app.

## Scope

The first macOS slice includes:

- Initial gateway setup and Test Connection flow.
- A full app window with a text editor.
- Grammar correction with reviewable correction cards.
- Improve/rewrite actions with a preview before replacement.
- A menu-bar extra with a compact text editor.
- macOS Keychain storage for the gateway API key.
- Reuse of the existing gateway URL/key contract and semantic prompt contract.

Defer global system-wide text replacement, Accessibility API integration,
browser extensions, background correction, account sync, and deployment until a
later milestone.

## Target and source layout

Keep the existing targets and add one macOS target:

```text
OpenKeyboard.xcodeproj
├── OpenKeyboard             # existing iOS app
├── OpenKeyboardExtension    # existing iOS keyboard extension
├── OpenKeyboardMac          # new macOS app and menu-bar target
└── OpenKeyboardCore         # shared logic and contract adapter
```

Reuse from `OpenKeyboardCore`:

- Gateway URL/API-key validation and networking.
- Model discovery and gateway errors.
- Semantic prompt rendering and contract versioning.
- Structured response parsing.
- Correction and rewrite models.
- Editing/replacement state logic where it is platform-neutral.

Keep macOS-specific concerns in `OpenKeyboardMac`:

- `OpenKeyboardMacApp.swift` and `MenuBarExtra` lifecycle.
- Setup, home, editor, correction, and settings views.
- macOS Keychain and local settings adapters.
- Clipboard integration, keyboard shortcuts, windows, and popovers.

Do not import iOS keyboard-extension views, App Group assumptions, or host-app
text-replacement behavior into the macOS target.

## User flows

### First launch and setup

1. Launch `OpenKeyboardMac`.
2. Show a welcome/setup screen when no valid configuration exists.
3. Enter the gateway URL and API key.
4. Validate fields locally.
5. Run Test Connection against the configured gateway.
6. Discover available models and select one.
7. Save the API key in macOS Keychain and non-sensitive settings locally.
8. Navigate to the home screen only after successful validation.

Failures must keep the user in setup, preserve the last known valid
configuration, and never mark an unverified configuration as ready.

### Home screen

The full app window contains:

- Large editable text area.
- Gateway/model readiness indicator.
- `Check Grammar`, `Improve`, `Rewrite`, and later `Summarize`/`Translate` actions.
- Correction cards or a generated-result panel.
- Apply, apply-all, dismiss, copy, retry, and undo actions.
- Settings and reconfigure controls.

Grammar corrections should be reviewable individually before changing the source
text. Improvements and rewrites should appear as a separate preview and should
not overwrite the source automatically.

### Menu-bar extra

Clicking the menu-bar icon opens a compact popover containing:

- Short text editor.
- Gateway/model readiness indicator.
- Grammar and Improve actions.
- Compact correction/result presentation.
- Apply and Copy controls.
- `Open Full App`, `Settings`, and `Quit` actions.

The menu-bar UI should reuse the same service and editing ViewModels as the full
window. Longer text or detailed correction sets should provide an `Open Full
App` escape hatch rather than forcing the popover to grow indefinitely.

## Implementation phases

### Phase 1: UX and technical design

- Confirm app-window navigation and menu-bar popover dimensions.
- Decide inline correction highlighting versus correction cards; cards are the
  recommended first implementation because they match the existing structured
  correction model.
- Define empty, loading, success, partial-result, offline, and error states.
- Produce wireframes or SwiftUI prototypes for setup, home, correction review,
  improvement preview, settings, and menu-bar flows.
- Define the shared macOS-compatible ViewModel boundary.

### Phase 2: macOS target foundation

- Add `OpenKeyboardMac` to the existing Xcode project.
- Confirm `OpenKeyboardCore` builds for macOS and identify any iOS-only APIs.
- Add app lifecycle, app icon, menu-bar icon, window restoration, and settings.
- Add macOS Keychain and local settings implementations.
- Add macOS-specific test targets and build schemes.

### Phase 3: Setup and gateway pairing

- Implement setup screen and Test Connection.
- Reuse the existing gateway client and typed error mapping.
- Add model discovery and selected-model persistence.
- Test valid, invalid, disabled-key, unavailable-gateway, and changed-draft paths.

### Phase 4: Full app writing workflows

- Implement the text editor and source-text state.
- Add grammar correction using `fix_grammar`.
- Render structured correction cards with apply/dismiss/apply-all.
- Add Improve and Rewrite preview flows.
- Add copy, retry, undo, and cancellation behavior.

### Phase 5: Menu-bar workflow

- Add the `MenuBarExtra` entry.
- Build the compact editor and result states.
- Reuse the full-app ViewModels and services.
- Add Open Full App, Settings, and Quit actions.
- Validate popover focus, dismissal, keyboard navigation, and short-text limits.

### Phase 6: Hardening and release readiness

- Add deterministic Core and macOS unit tests.
- Add macOS UI tests for setup, home, correction review, improvement preview,
  menu-bar behavior, and accessibility labels.
- Add offline/mock gateway coverage and opt-in local Gemma validation.
- Verify the macOS request path uses only the configured gateway URL and API key.
- Audit the macOS target for direct Codex access or bundled provider credentials.
- Add macOS CI build/test coverage and update contributor documentation.

## Shared state model

The platform-neutral editing state should own:

- Source text.
- Selected operation.
- Loading and cancellation state.
- Correction results.
- Generated replacement/preview.
- Apply, dismiss, retry, copy, and undo actions.
- Gateway and model readiness.

SwiftUI views should remain presentation-focused. Networking, persistence,
Keychain, parsing, and side effects belong in services or ViewModels. Platform
adapters should be injected so the same behavior can be tested without a live
macOS UI.

## Security and proof boundaries

The macOS client authenticates only with the configured gateway URL and gateway
API key. It must not contain Codex credentials or call Codex directly. Any
Codex routing remains server-side in the gateway configuration.

Local Gemma tests prove gateway integration and model behavior for the configured
route. They do not prove live Codex behavior, physical-device behavior, signing,
notarization, deployment, or production configuration. Those remain separate
release gates.

## Initial acceptance criteria

- The macOS target builds alongside the existing iOS app and keyboard extension.
- Unconfigured launches show setup; verified launches show home.
- Test Connection validates the gateway before saving readiness.
- API keys are stored only in macOS Keychain or an equivalent protected store.
- Grammar corrections are reviewable and safely applicable.
- Improvements and rewrites support preview, copy, retry, and explicit apply.
- The menu-bar editor reuses the same core behavior as the full app.
- Existing iOS targets remain behaviorally unchanged.
- Deterministic Core/macOS tests, builds, and UI checks pass.
- No direct Codex access or provider credentials are introduced in the macOS target.
- The local Gemma gateway route passes the applicable opt-in integration checks.
