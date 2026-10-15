# Smiley keyboard package

`KeyboardLayout` is the bounded smiley slice of the M1 package boundary.
It does not extract the existing typing engine or the whole panel. M2 and the
remaining M3/M4 work remain separate. The package depends on no OpenKeyboard or AI
module and bundles no catalogue, networking, search, or persistence.

## Content and actions

The host supplies `SmileySnapshot` containing ordered `SmileySection` values and
`SmileyItem` values with IDs, display/insertion strings and localized accessible
labels. Section IDs must be unique across the snapshot and item IDs unique within
each section. Empty IDs/labels/payloads and duplicate IDs are discarded (first valid
entry wins). Optional recents can be supplied as an ordinary section; storing them
is outside this implementation. OpenKeyboard supplies a small starter configuration.

Retain `SmileyState` in the consumer's ViewModel. `update` preserves an existing
category selection or falls back to the first category. `send(.selectCategory)`
changes navigation without inserting. Item activation emits one insertion intent
with item/section metadata. Host adapters must insert the exact payload once without
applying letter-case conversion. Delete, return and system switch are separate
intents. Empty snapshots retain all three controls. Return restores the host's prior
typing mode; OpenKeyboard leaves that mode and shift unchanged while the grid is open.

`SmileyKeyboardView` takes state, labels, style and an action callback. Cell widths
are bounded and based on actual available space. Category and item overflow scroll;
Back and delete remain outside the grid scroll area. The host supplies whether the
system-switch key is required. The extension controller owns `advanceToNextInputMode`
and height constraints. Width changes do not recreate navigation state.

## Independent consumer and verification

`Examples/SmileyConsumer` is an independent SwiftUI library consumer with a custom
text smiley, an editable field, and no OpenKeyboard dependencies. The normal core
route runs package tests and compiles that consumer. App/extension builds verify
the iOS integration. Host tests cover literal insertion, cursor location, grapheme
deletion, haptics, mode return, empty data, and separate system switching.

Normal runtime acceptance requires the installed extension in an ordinary host
field: open Emoji, choose categories, insert, delete, return to the prior typing
mode, and separately switch keyboards. Check compact iPhone and compact/docked iPad
layouts, VoiceOver names/focus, large text and light/dark contrast. Full floating
transition acceptance remains part of M4. Automated tests and previews do not prove
normal runtime behavior. This local UI change does not alter model requests or
responses; model comparisons add no relevant evidence. Physical devices are outside
this task's authority.
