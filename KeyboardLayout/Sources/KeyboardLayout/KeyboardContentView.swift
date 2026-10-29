import SwiftUI

/// Composes the supplied local state into typing, smiley browsing/search, or a numeric field.
/// Hosts retain state and route actions through their ViewModel. No document or persistence is read here.
public struct KeyboardContentView: View {
    public let typing: KeyboardTypingState
    public let smileys: SmileyState
    public let showsSmileys: Bool
    public let searchTyping: KeyboardTypingState
    public let numberPad: NumberPadConfiguration?
    public let interactionID: UUID
    public let showsSystemKeyboardSwitch: Bool
    public let style: KeyboardStyle
    public let metrics: KeyboardMetrics
    public let onTyping: (KeyboardTypingAction) -> Void
    public let onSmiley: (SmileyAction) -> Void
    public let onNumberPad: (NumberPadIntent) -> Void

    public init(typing: KeyboardTypingState, smileys: SmileyState = .init(snapshot: .init(sections: [])),
                showsSmileys: Bool = false, searchTyping: KeyboardTypingState = .init(),
                numberPad: NumberPadConfiguration? = nil, interactionID: UUID,
                showsSystemKeyboardSwitch: Bool = false, style: KeyboardStyle = .init(),
                metrics: KeyboardMetrics = .init(),
                onTyping: @escaping (KeyboardTypingAction) -> Void,
                onSmiley: @escaping (SmileyAction) -> Void = { _ in },
                onNumberPad: @escaping (NumberPadIntent) -> Void = { _ in }) {
        self.typing = typing; self.smileys = smileys; self.showsSmileys = showsSmileys
        self.searchTyping = searchTyping; self.numberPad = numberPad; self.interactionID = interactionID
        self.showsSystemKeyboardSwitch = showsSystemKeyboardSwitch; self.style = style; self.metrics = metrics
        self.onTyping = onTyping; self.onSmiley = onSmiley; self.onNumberPad = onNumberPad
    }
    public var body: some View {
        if let numberPad {
            NumberPadView(configuration: numberPad,
                          style: .init(key: style.key, control: style.control, foreground: style.foreground),
                          interactionID: interactionID, onIntent: onNumberPad)
        } else if showsSmileys {
            VStack(spacing: 4) {
                SmileyKeyboardView(state: smileys, showsSystemKeyboardSwitch: showsSystemKeyboardSwitch,
                                   style: style.resolvedSmileyStyle,
                                   labels: .init(back: backLabel, backAccessibility: backLabel + ", back to typing"),
                                   onAction: onSmiley)
                    .frame(maxHeight: .infinity)
                if smileys.isSearching { typingView(searchTyping, returnLabel: "done") }
            }
            .padding(6)
        } else { typingView(typing, returnLabel: "return") }
    }
    private func typingView(_ state: KeyboardTypingState, returnLabel: String) -> some View {
        TypingKeyboardView(state: state, showsSystemKeyboardSwitch: showsSystemKeyboardSwitch,
                           returnLabel: returnLabel, style: style, metrics: metrics, onAction: onTyping)
    }
    private var backLabel: String {
        switch typing.mode {
        case .letters: return "ABC"
        case .numbers: return "123"
        case .symbols: return "#+="
        }
    }
}
