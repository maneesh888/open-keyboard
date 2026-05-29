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

public struct KeyboardDocumentContext: Equatable, Sendable {
    public var textBeforeCursor: String
    public var selectedText: String
    public var textAfterCursor: String

    public init(
        textBeforeCursor: String,
        selectedText: String = "",
        textAfterCursor: String = ""
    ) {
        self.textBeforeCursor = textBeforeCursor
        self.selectedText = selectedText
        self.textAfterCursor = textAfterCursor
    }

    public var hasSelection: Bool {
        !selectedText.isEmpty
    }

    public var fullText: String {
        textBeforeCursor + selectedText + textAfterCursor
    }

    public var promptSourceText: String {
        hasSelection ? selectedText : textBeforeCursor
    }
}

public enum KeyboardContextExtractor {
    public static func contextBeforeCursor(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        return String(text.suffix(limit))
    }

    public static func contextAfterCursor(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        return String(text.prefix(limit))
    }

    public static func contextAroundCursor(
        textBeforeCursor: String,
        textAfterCursor: String,
        beforeLimit: Int,
        afterLimit: Int
    ) -> KeyboardDocumentContext {
        KeyboardDocumentContext(
            textBeforeCursor: contextBeforeCursor(textBeforeCursor, limit: beforeLimit),
            textAfterCursor: contextAfterCursor(textAfterCursor, limit: afterLimit)
        )
    }
}

public enum AITextReplacementStrategy: Equatable, Sendable {
    case replaceAll
    case appendToCursor
    case replaceSelected
    case insertAtCursor
    case replaceLastSentence
    case replaceLastParagraph

    public func apply(original: String, replacement: String) -> String {
        switch self {
        case .replaceAll:
            return replacement
        case .appendToCursor:
            return original + replacement
        case .replaceSelected, .insertAtCursor, .replaceLastSentence, .replaceLastParagraph:
            return apply(to: KeyboardDocumentContext(textBeforeCursor: original), replacement: replacement)
        }
    }

    public func apply(to context: KeyboardDocumentContext, replacement: String) -> String {
        switch self {
        case .replaceAll:
            return replacement
        case .appendToCursor:
            return context.fullText + replacement
        case .replaceSelected:
            return context.textBeforeCursor + replacement + context.textAfterCursor
        case .insertAtCursor:
            return context.textBeforeCursor + replacement + context.selectedText + context.textAfterCursor
        case .replaceLastSentence:
            let prefix = Self.prefixBeforeLastSentence(in: context.textBeforeCursor)
            return prefix + replacement + context.textAfterCursor
        case .replaceLastParagraph:
            let prefix = Self.prefixBeforeLastParagraph(in: context.textBeforeCursor)
            return prefix + replacement + context.textAfterCursor
        }
    }

    private static func prefixBeforeLastSentence(in text: String) -> String {
        let scalars = text.unicodeScalars
        let punctuation = CharacterSet(charactersIn: ".!?")

        var searchEnd = scalars.endIndex
        while searchEnd > scalars.startIndex {
            let previous = scalars.index(before: searchEnd)
            guard CharacterSet.whitespacesAndNewlines.contains(scalars[previous]) else { break }
            searchEnd = previous
        }

        guard searchEnd > scalars.startIndex else { return "" }

        var boundarySearchEnd = searchEnd
        let lastMeaningful = scalars.index(before: searchEnd)
        if punctuation.contains(scalars[lastMeaningful]) {
            boundarySearchEnd = lastMeaningful
        }

        guard let previousPunctuation = scalars[..<boundarySearchEnd].lastIndex(where: { punctuation.contains($0) }) else {
            return ""
        }

        let prefixEnd = scalars.index(after: previousPunctuation)
        return String(scalars[..<prefixEnd]) + Self.trailingWhitespace(after: prefixEnd, before: searchEnd, in: text)
    }

    private static func prefixBeforeLastParagraph(in text: String) -> String {
        guard let range = text.range(of: "\n\n", options: .backwards) else {
            return ""
        }
        return String(text[..<range.upperBound])
    }

    private static func trailingWhitespace(
        after scalarIndex: String.UnicodeScalarView.Index,
        before endIndex: String.UnicodeScalarView.Index,
        in text: String
    ) -> String {
        var index = scalarIndex
        var whitespace = ""
        while index < endIndex {
            let scalar = text.unicodeScalars[index]
            guard CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
            whitespace.append(String(scalar))
            index = text.unicodeScalars.index(after: index)
        }
        return whitespace
    }
}
