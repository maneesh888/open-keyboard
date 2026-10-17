import Foundation

public enum KeyboardInputMode: Equatable, Sendable {
    case letters
    case numbers
    case symbols

    public var topRowKeys: [String] {
        switch self {
        case .letters:
            return ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
        case .numbers:
            return ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        case .symbols:
            return ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
        }
    }

    public var middleRowKeys: [String] {
        switch self {
        case .letters:
            return ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
        case .numbers:
            return ["-", "/", ":", ";", "(", ")", "$", "&", "@"]
        case .symbols:
            return ["_", "\\", "|", "~", "<", ">", "$", "£", "€", "•"]
        }
    }

    public var bottomRowKeys: [String] {
        switch self {
        case .letters:
            return ["z", "x", "c", "v", "b", "n", "m"]
        case .numbers:
            return [".", ",", "?", "!", "'", "\"", "_"]
        case .symbols:
            return [".", ",", "?", "!", "'"]
        }
    }

    public var leadingBottomKeyLabel: String {
        switch self {
        case .letters: return "⇧"
        case .numbers: return "#+="
        case .symbols: return "123"
        }
    }

    public var bottomControlKeyLabel: String {
        self == .letters ? "123" : "ABC"
    }

    public var usesMiddleRowInset: Bool {
        self != .symbols
    }

    public var togglingNumbers: KeyboardInputMode {
        self == .letters ? .numbers : .letters
    }

    public var togglingSymbols: KeyboardInputMode {
        switch self {
        case .letters: return .letters
        case .numbers: return .symbols
        case .symbols: return .numbers
        }
    }
}

/// Local state only. The consumer performs emitted edits against its own document.
public struct KeyboardTypingState: Equatable, Sendable {
    public var mode: KeyboardInputMode
    public var isShiftEnabled: Bool
    public init(mode: KeyboardInputMode = .letters, isShiftEnabled: Bool = false) {
        self.mode = mode; self.isShiftEnabled = isShiftEnabled
    }
    public mutating func send(_ action: KeyboardTypingAction) -> KeyboardTypingIntent? {
        switch action {
        case .character(let text):
            let output = isShiftEnabled ? text.uppercased() : text
            isShiftEnabled = false
            return .insertText(output)
        case .shift: isShiftEnabled.toggle()
        case .numbers: mode = mode.togglingNumbers; isShiftEnabled = false
        case .symbols: mode = mode.togglingSymbols; isShiftEnabled = false
        case .space: return .space
        case .return: return .return
        case .deleteBackward: return .deleteBackward
        case .smileys: return .showSmileys
        case .nextKeyboard: return .nextKeyboard
        }
        return nil
    }
}

public enum KeyboardTypingAction: Equatable, Sendable {
    case character(String), shift, numbers, symbols, space, `return`, deleteBackward, smileys, nextKeyboard
}

public enum KeyboardTypingIntent: Equatable, Sendable {
    case insertText(String), space, `return`, deleteBackward, showSmileys, nextKeyboard
}
