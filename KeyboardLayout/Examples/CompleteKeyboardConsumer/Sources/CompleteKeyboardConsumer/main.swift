import SwiftUI
import KeyboardLayout
import KeyboardEmoji

@MainActor
final class EditorModel: ObservableObject {
    @Published var text = ""
    @Published var typing = KeyboardTypingState()
    @Published var searchTyping = KeyboardTypingState()
    @Published var smileys = SmileyState(snapshot: EmojiCatalogue.standard.snapshot())
    @Published var showsSmileys = false
    @Published var showsNumberPad = false
    @Published var showsReplacement = false
    @Published var interactionID = UUID()

    var searching: Bool { showsSmileys && smileys.isSearching }
    var layout: KeyboardSurfaceLayout {
        .init(contentHeight: showsNumberPad ? 234 : (searching ? 380 : (showsSmileys ? 267 : 216)),
              accessoryHeight: 24, toolbarHeight: 36, spacing: 6, horizontalPadding: 6,
              topPadding: 6, bottomPadding: 6)
    }
    func type(_ action: KeyboardTypingAction) {
        let wasSearching = searching
        let intent = wasSearching ? searchTyping.send(action) : typing.send(action)
        switch intent {
        case .insertText(let value): insert(value)
        case .space: insert(" ")
        case .return:
            if wasSearching { _ = smileys.send(.endSearch) } else { text += "\n" }
        case .deleteBackward: delete()
        case .showSmileys:
            if wasSearching { _ = smileys.send(.endSearch) } else { showsSmileys = true }
        case .nextKeyboard, nil: break
        }
    }
    func smiley(_ action: SmileyAction) {
        guard showsSmileys else { return }
        if action == .beginSearch { searchTyping = .init() }
        switch smileys.send(action) {
        case .insertText(let value, _, _): text += value
        case .deleteBackward: delete()
        case .returnToTyping: showsSmileys = false
        case .nextSystemKeyboard, nil: break
        }
    }
    func number(_ action: NumberPadIntent) {
        guard showsNumberPad else { return }
        switch action {
        case .insertText(let value): text += value
        case .deleteBackward: if !text.isEmpty { text.removeLast() }
        }
    }
    func togglePad() {
        interactionID = UUID()
        _ = smileys.send(.endSearch)
        showsSmileys = false
        showsNumberPad.toggle()
    }
    private func insert(_ value: String) {
        if searching { _ = smileys.send(.setSearchQuery(smileys.searchQuery + value)) }
        else { text += value }
    }
    private func delete() {
        if searching { _ = smileys.send(.setSearchQuery(String(smileys.searchQuery.dropLast()))) }
        else if !text.isEmpty { text.removeLast() }
    }
}

struct EditorView: View {
    @StateObject private var model = EditorModel()
    var body: some View {
        VStack {
            ScrollView { Text(model.text.isEmpty ? "Type using the keyboard below" : model.text)
                .frame(maxWidth: .infinity, alignment: .leading).padding() }
            KeyboardSurface(layout: model.layout,
                            style: .init(border: .blue.opacity(0.5), borderWidth: 1),
                            showsReplacement: model.showsReplacement) {
                KeyboardContentView(typing: model.typing, smileys: model.smileys,
                    showsSmileys: model.showsSmileys, searchTyping: model.searchTyping,
                    numberPad: model.showsNumberPad ? .init(decimalSeparator: ".") : nil,
                    interactionID: model.interactionID,
                    onTyping: model.type, onSmiley: model.smiley, onNumberPad: model.number)
            } accessory: {
                Text("\(model.text.count) characters").font(.caption)
            } toolbar: {
                HStack {
                    Button(model.showsNumberPad ? "Letters" : "Number pad", action: model.togglePad)
                    Spacer()
                    Button("Custom panel") { model.showsReplacement = true }
                }
            } replacement: {
                VStack {
                    Text("This panel belongs to the consuming app.")
                    Button("Back to keyboard") { model.showsReplacement = false }
                }.frame(maxHeight: .infinity)
            }
        }.padding()
    }
}

@main
struct CompleteKeyboardConsumerApp: App {
    var body: some Scene { WindowGroup { EditorView().frame(minWidth: 320, minHeight: 600) } }
}
