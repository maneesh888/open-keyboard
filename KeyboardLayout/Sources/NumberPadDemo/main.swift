import SwiftUI
import KeyboardLayout

// Independent consumer: no OpenKeyboard, AI, proxy, persistence, or gateway dependency.
@main
struct NumberPadDemo: App {
    var body: some Scene { WindowGroup { Demo() } }
}

private struct Demo: View {
    @State private var text = ""
    @State private var configuration = NumberPadConfiguration(decimalSeparator: ".")
    @State private var session = UUID()
    var body: some View {
        VStack {
            Text(text.isEmpty ? "Type a number" : text).textSelection(.enabled)
            NumberPadView(configuration: configuration, interactionID: session) { intent in
                switch intent {
                case .insertText(let value): text += value
                case .deleteBackward: if !text.isEmpty { text.removeLast() }
                }
            }
        }.padding().frame(minWidth: 320, minHeight: 330)
    }
}
