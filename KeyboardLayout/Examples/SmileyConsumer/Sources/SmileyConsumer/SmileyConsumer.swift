import KeyboardLayout
#if canImport(SwiftUI)
import SwiftUI

/// Independent consumer: no OpenKeyboard/AI import, no bundled emoji catalogue.
public struct SmileyConsumer: View {
    @State private var state = SmileyState(snapshot: .init(sections: [
        .init(id: "custom", label: "Custom", items: [.init(id: "smile", text: ":-)", label: "Smile")])
    ]))
    @State private var text = ""
    @State private var isOpen = true

    public init() {}

    public var body: some View {
        VStack {
            TextField("Text", text: $text)
            if state.isSearching {
                TextField("Search Emoji", text: Binding(get: { state.searchQuery }, set: { _ = state.send(.setSearchQuery($0)) }))
            }
            if isOpen {
                SmileyKeyboardView(state: state, showsSystemKeyboardSwitch: false) { action in
                    switch state.send(action) {
                    case .insertText(let value, _, _): text.append(value)
                    case .deleteBackward: if !text.isEmpty { text.removeLast() }
                    case .returnToTyping: isOpen = false
                    case .nextSystemKeyboard, nil: break
                    }
                }.frame(height: 216)
            } else {
                Button("Emoji") { isOpen = true }
            }
        }
    }
}
#endif
