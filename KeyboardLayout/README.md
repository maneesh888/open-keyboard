# KeyboardLayout

A source Swift package for reusable keyboards on iOS 17+ and macOS 13+.
It has no application, AI, network, text-document-proxy, credential, or App Group dependency.

## Products

- `KeyboardLayout`: typing layouts and state, touch geometry, number pad, generic smiley browser,
  styling, and a container with host-supplied views.
- `KeyboardEmoji`: optional bundled Unicode catalogue and opt-in recent-selection storage.
  Supply your own `SmileySnapshot` to use `KeyboardLayout` without this product.

`KeyboardEmoji` replaces the earlier product name `OpenKeyboardEmoji`. Update imports and SPM
product dependencies. `EmojiHistoryStore` accepts a storage key; existing consumers should pass
their previous key explicitly to retain history. The default is `keyboard.emoji.recent.v1`.

## Host integration

The host owns its document and ViewModel. `KeyboardTypingState.send` resolves one-shot shift and
letters/numbers/symbols transitions and returns an intent. The host performs insertion, deletion,
return, or system-keyboard switching. Keep a separate typing state for emoji search so searching
never edits the document. `SmileyState.send` resolves browsing/search/variants and returns exact
selected strings. Do not apply typing-case conversion to smiley payloads.

`TypingKeyboardView` renders typing alone. `KeyboardContentView` composes typing, the generic
smiley browser, search typing, and an optional `NumberPadConfiguration`. State and callbacks are
explicit. The host chooses numeric fields from its own field traits, invalidates `interactionID`
on field changes, and rejects stale number-pad callbacks. The iOS number-pad delete repeats;
typing delete and the macOS number pad retain tap behavior.

```swift
KeyboardSurface(
    layout: .init(contentHeight: 216, toolbarHeight: 36, spacing: 6),
    style: .init(border: .blue, borderWidth: 1)
) {
    TypingKeyboardView(state: model.typing, onAction: model.type)
} toolbar: {
    MyFormattingToolbar()
}
```

The named `accessory`, `toolbar`, and `replacement` builders accept ordinary SwiftUI views. Their
state and side effects belong to the host. Set `showsReplacement` to replace the keys while
preserving the content extent. Omitted slots have zero height and add no spacing. Slot heights
are explicit; content should fit or scroll within them. This avoids a measurement/height-constraint
feedback loop inside keyboard extensions. The package never knows what a host toolbar does.

## Viewport and styling

Width is read from the actual containing view, never a screen/device lookup. Typing rows fit the
available width; the number pad is centered and capped at 480 points. Widths below a practical
keyboard viewport still remain bounded, but cannot provide normal touch-target widths. Consumers
should provide at least 288 points for the standard ten-key layout. Row heights have a 44-point
minimum. `KeyboardMetrics` configures row/cap heights and horizontal/vertical spacing; `KeyboardStyle`
configures key/control/foreground colors, the shift-highlight fill (`accent`), letter/control/symbol
fonts, background, shadow, radius, and border. Emoji controls inherit the foreground and key/control
palette. Supply `smileyStyle` for separate emoji key, selected-category, primary, and secondary
colors. Injected host views retain their own styling responsibilities.

`KeyboardSurfaceLayout.preferredHeight` is the sum of content, visible slots, their spacing, and
padding. For an extension, the host applies this value to its `UIInputViewController` height
constraint. iOS owns window width/placement and system chrome; the host owns safe-area integration.
Do not add system-owned insets again as package padding. The consumer decides the height of emoji
browsing/search and replacement panels. A constrained host should scroll a larger panel or select
appropriate metrics rather than clip its controls.

Number-pad variants retain the four-row arrangement
`1 2 3 / 4 5 6 / 7 8 9 / auxiliary 0 delete`. Digits leave the auxiliary cell blank; decimal fields
use the exact supplied separator without parsing or reformatting. The default pad is 234 points
high. The host supplies an iOS system-switch control outside that grid when required.

## Independent example and checks

`Examples/CompleteKeyboardConsumer` is an independent SwiftUI executable with a local editor,
letters/symbols, emoji search/variants, number pad, accessory count, custom toolbar, and replacement
panel. It imports only the two package products. On macOS:

```sh
swift test --package-path KeyboardLayout
swift run --package-path KeyboardLayout/Examples/CompleteKeyboardConsumer
```

The same views can be embedded in an iOS app or extension. Build the example with `swift build`
when a window is not needed. `Examples/SmileyConsumer` demonstrates custom content without the
bundled catalogue. Automated builds/tests and examples are separate from normal simulator proof
of an installed keyboard extension.

The package currently lives in this repository as a local SPM dependency. It can be copied with
its own `Package.swift`, `Sources`, `Tests`, `Examples`, and `LICENSE`; it has no paths pointing to
consumer sources. A separate remote repository and versioned release are not created by this
extraction. The bundled Unicode resources retain their Unicode license.
