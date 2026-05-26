import Foundation

public struct KeyboardInputState: Equatable, Sendable {
    public var text: String
    public var isShiftEnabled: Bool

    public init(text: String = "", isShiftEnabled: Bool = false) {
        self.text = text
        self.isShiftEnabled = isShiftEnabled
    }
}

public enum KeyboardInputAction: Equatable, Sendable {
    case character(String)
    case space
    case returnKey
    case deleteBackward
    case toggleShift
}

public enum KeyboardInputReducer {
    public static func apply(_ action: KeyboardInputAction, to state: inout KeyboardInputState) {
        switch action {
        case .character(let character):
            state.text.append(state.isShiftEnabled ? character.uppercased() : character)
            state.isShiftEnabled = false
        case .space:
            state.text.append(" ")
        case .returnKey:
            state.text.append("\n")
        case .deleteBackward:
            guard !state.text.isEmpty else { return }
            state.text.removeLast()
        case .toggleShift:
            state.isShiftEnabled.toggle()
        }
    }
}

public enum KeyboardContextExtractor {
    public static func contextBeforeCursor(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        return String(text.suffix(limit))
    }
}

public enum AITextReplacementStrategy: Equatable, Sendable {
    case replaceAll
    case appendToCursor

    public func apply(original: String, replacement: String) -> String {
        switch self {
        case .replaceAll:
            return replacement
        case .appendToCursor:
            return original + replacement
        }
    }
}
