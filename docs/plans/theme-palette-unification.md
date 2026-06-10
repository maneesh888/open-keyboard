# Theme Palette Unification Plan

## Status
Implemented and visually verified on 2026-06-09. Pending commit at time of update.

## User request
Use the new AI icon as the source for the Open Keyboard visual identity. Extract a single color palette from it and update app/keyboard UI to use that palette instead of scattered ad-hoc colors. Use recursive screenshot verification with ClawMaster and add tests so the palette remains single-source-of-truth.

## Goal
Create a central theme/palette layer for Open Keyboard with:
- primary blue from the icon
- secondary green from the icon
- neutral black/white/gray shades
- semantic colors for AI ready, warning/error, panels, keys, toolbar, text

Then update existing similar blue/green/accent/gray usage to use the palette consistently across app UI and keyboard UI. Do not force colors everywhere; replace equivalent scattered colors with palette references.

## Constraints
- Keep M2 keyboard UI behavior stable.
- Do not introduce hardcoded color literals in views when a palette token exists.
- App target and keyboard extension target must both be able to use the palette safely.
- The palette should support light/dark mode where practical.
- Visual verification must be recursive: patch, screenshot, critique, repeat until acceptable.

## Likely files
- `OpenKeyboard/Views/...`
- `OpenKeyboardExtension/...`
- new shared palette file, likely `OpenKeyboardShared/OpenKeyboardTheme.swift` or equivalent source included in app + extension targets
- `OpenKeyboard.xcodeproj/project.pbxproj`
- UI tests for palette/source usage where feasible
- docs/screenshots if useful

## Test plan
- Unit/static tests:
  - palette exposes expected core tokens
  - palette colors are non-default and distinct enough
  - source files do not introduce obvious scattered `Color.blue`, `Color.green`, raw RGB duplicates in touched UI files where palette tokens should be used
- Build/tests through ClawMaster:
  - app/extension simulator build
  - targeted tests
  - screenshot verification for main settings, keyboard preview grid, action overlay, correction complete
- Recursive visual loop:
  - ClawMaster screenshots + critique
  - patch exact issues
  - rerun until accepted

## Review gates
Because this is an architecture-sensitive theming/refactor slice:
- Pre-implementation architecture review recommended if scope gets large.
- Final architecture and security reviews required before commit.

## Acceptance criteria
- Central palette exists and is used by app + keyboard extension UI for equivalent colors.
- New icon-derived blue/green are reflected in toolbar/action states and app accents where appropriate.
- Screenshots pass recursive visual verification.
- Tests/build pass.
- Security/architecture reviewers mark safe to commit.

## 2026-06-10 visible icon/color refresh note

The approved icon asset is now committed in `OpenKeyboard/OpenKeyboardAssets.xcassets` as both `OpenKeyboardBrandIcon` and `AppIcon`. `OpenKeyboardBrandMark` renders the real asset directly/as-is, with only an outside shadow so screenshots match the approved icon while nearby surfaces use the shared palette.
