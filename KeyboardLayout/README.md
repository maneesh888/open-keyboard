# KeyboardLayout: number-pad slice

A source-only package containing the bounded number-pad slice of the accepted M1
boundary. It has no dependencies on OpenKeyboard, AI, persistence, or a text proxy.
The remaining typing engine, panel extraction, smiley surface, and adaptive
platform milestones are separate work.

`NumberPadConfiguration` selects digits, decimal (exact host-supplied separator),
or phone. The core grid is `1 2 3 / 4 5 6 / 7 8 9 / auxiliary 0 delete`.
The phone auxiliary inserts `+`; `*` and `#` occupy the utility row. Configuration
controls submit label/visibility/enablement and the system-switch affordance.
The package inserts exact strings; it does not parse numbers, reject duplicate
separators, or reformat leading zeros.

`NumberPadView` receives configuration, colors, a stable field/session interaction
UUID, and an intent callback. Hosts apply insert/delete/submit intents and own
mode return, haptics, document state, and system switching. The iOS delete control
repeats after 400 ms at approximately 80 ms cadence, cancelling on release, drag
outside, touch cancellation, disappearance, inactive scene, or identity/variant
change. Hosts must change interaction identity when focus or selection changes,
and reject callbacks from old identities. Layout width is capped at 480 pt; the
five rows (four numeric plus one utility) occupy 264 pt. The minimum supported
content width is 308 pt, leaving at least 44 pt per phone utility control.

OpenKeyboard retains the mixed `123` layer and exposes `Pad` there. Back returns
to the previous letters/symbols mode. Numeric field traits choose digits/decimal;
manual variant selection persists within the field. Phone variants can be used
in ordinary supported fields; iOS phonePad/namePhonePad fields may substitute the
system keyboard. Submit delegates to the existing newline proxy operation: its
host-supplied label does not guarantee arbitrary app navigation or dismissal.
Number-pad typing does not schedule automatic analysis or show AI controls.

Run `swift test --package-path KeyboardLayout`. The regular core gate also runs
these tests. `swift build --package-path KeyboardLayout --product NumberPadDemo`
builds an independent SwiftUI consumer; its macOS delete is tap-only. iOS extension
behavior requires normal Simulator proof, separate from the package tests/demo.
