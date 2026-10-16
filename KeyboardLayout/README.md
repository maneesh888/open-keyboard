# KeyboardLayout: number-pad slice

A source-only Swift package with no AI, persistence, network, or text-proxy dependency.
The four-row grid matches the native number-pad arrangement:
`1 2 3 / 4 5 6 / 7 8 9 / auxiliary 0 delete`.
Digits fields leave the auxiliary cell blank; decimal fields use the exact
host-supplied decimal separator. There are no extra mode, Back, phone, or submit keys.
The host selects the pad from the focused field's keyboard traits and restores
ordinary typing when focus moves to a text field. System keyboard switching stays outside the grid: the host adds the standard
globe footer only when iOS requires the extension to supply it. The existing mixed `123` layout is unchanged.

The package emits only exact-string insertion and deletion intents. It preserves
leading zeros without parsing or reformatting. Hosts own text editing and haptics.
The iOS delete control repeats after 400 ms at approximately 80 ms cadence,
cancelling on release, drag outside, touch cancellation, disappearance, scene
change, or field identity change. Hosts reject stale interaction identities.
The four rows occupy 234 pt and the grid width is capped at 480 pt.

Number-pad typing shows no AI controls and schedules no automatic analysis.
Run `swift test --package-path KeyboardLayout` for package regression tests and
`swift build --package-path KeyboardLayout --product NumberPadDemo` for the
independent SwiftUI consumer (macOS delete is tap-only). Normal Simulator proof
of the actual extension remains separate from automated tests and the demo.
