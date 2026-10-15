# Emoji browser packages

`KeyboardLayout` owns content-independent emoji presentation and state. The separate
`OpenKeyboardEmoji` product owns OpenKeyboard's bundled Unicode catalogue and local
recent-selection storage. Neither product imports an AI module or makes network calls.
The existing typing engine and other keyboard panels remain in the host.

## Content and actions

The host supplies `SmileySnapshot` with ordered categories, symbols, emoji, descriptive
names and optional skin-tone variants. Empty IDs, names and payloads are rejected;
duplicate IDs within a category use the first entry. Base IDs must identify the same
content across categories. The generic renderer supports custom text smileys too.

`SmileyState` preserves category selection on snapshot updates. Category changes do
not insert text. Activation emits one exact insertion payload; the host never applies
letter-case conversion to it. Long-press opens a bounded horizontal strip for the base emoji and skin tones,
inside the browser. It does not create a system context menu above the typing keys.
Search is local, case/diacritic-insensitive and matches all words against English
Unicode names. It is not Apple's multilingual search or ranking engine.

OpenKeyboard uses its own typing keys for emoji search. Search letters, spaces and
Delete change only the query, never the host document or AI composing buffer. Done
and Cancel end search; emoji selection inserts into the host document. The original
letters/numbers/symbols mode and shift state survive this temporary search mode.
ABC, 123 or #+= restores that original mode. The globe remains a separate system switch.

The view uses horizontal rows of system-rendered emoji, a search bar, category title,
and bottom category strip. Controls remain outside the emoji scrolling region.
The host hides its AI toolbar while browsing emoji and expands the viewport while
showing search keys. Actual available width controls scrolling on compact/docked layouts.

## Catalogue and recent selections

The catalogue includes 1,906 base emoji and 1,875 skin-tone variants from Unicode
Emoji 16.0's fully qualified sequences. Unicode order is preserved inside categories;
Smileys & Emotion and People & Body share Smileys & People. This is an Apple-style
browser, not a pixel-identical copy of Apple's private keyboard or proprietary order.
System fonts provide Apple's artwork on iOS. No Apple artwork is bundled.
Emoji newer than the supported iOS version are filtered (15.0 before iOS 17.4,
15.1 before iOS 18.4, then 16.0). See the adapter's CATALOGUE.md and bundled license.
Memoji, stickers and Genmoji are outside this browser.

`EmojiHistoryStore` accepts only catalogue IDs, deduplicates to the latest selection,
and retains at most 40 IDs for 30 days. It persists no search or document text. The
host injects App Group defaults when available, otherwise extension-local defaults.
Expired/unknown entries are removed on read; `clear()` removes the stored history.
Recently Used refreshes when opened, without moving targets during repeated selection.

## Verification boundaries

`Examples/SmileyConsumer` compiles independently with custom content and a host-owned
search field. Package tests cover content integrity, OS filtering, search, variant
activation and history retention. Host regression tests cover cursor insertion,
grapheme deletion, prior-mode restoration, independent search input and system switching.

Normal runtime acceptance requires the installed extension in an ordinary host field:
open emoji, browse categories and horizontal overflow, search, select a skin tone,
insert/delete, inspect recent selections and restore the prior typing mode. Also inspect
compact iPhone and docked iPad, large text, light/dark contrast and accessible control
names. Full floating transitions remain M4. Automated tests do not prove runtime UI.
This local feature changes no model requests, responses or semantic contracts; live
model comparisons are not applicable. Physical-device operation is not authorized.
The prior starter grid was rejected; its screenshots do not accept this revision.
