import Foundation

public enum WritingAction: Equatable, Sendable {
    case continueWriting
    case rewrite
    case fixGrammar
    case summarize
    case translate(language: String)
    case custom(id: String, title: String, promptTemplate: String)

    public var operationName: String {
        switch self {
        case .continueWriting:
            return "continue_writing"
        case .rewrite:
            return "rewrite"
        case .fixGrammar:
            return "fix_grammar"
        case .summarize:
            return "summarize"
        case .translate:
            return "translate"
        case .custom(let id, _, _):
            return id
        }
    }

    public var title: String {
        switch self {
        case .continueWriting:
            return "Continue Writing"
        case .rewrite:
            return "Rewrite"
        case .fixGrammar:
            return "Fix Grammar & Spelling"
        case .summarize:
            return "Summarize"
        case .translate(let language):
            return "Translate to \(language)"
        case .custom(_, let title, _):
            return title
        }
    }
}

public enum WritingPromptBuilder {
    public static func prompt(for action: WritingAction, text: String) -> String {
        switch action {
        case .continueWriting:
            return """
            Continue writing from the text below. Match the tone and style. Return only the continuation.

            Text:
            \(text)
            """
        case .rewrite:
            return """
            Rewrite the text below for better clarity, flow, and readability. Preserve the original meaning. Return only the rewritten text.

            Text:
            \(text)
            """
        case .fixGrammar:
            return """
            Operation: fix_grammar
            Analyze the text below and return structured JSON with a results array.
            Each result item should include type, title, text, replacement, explanation, range, and confidence when applicable.
            Preserve the original meaning and tone.

            Text:
            \(text)
            """
        case .summarize:
            return """
            Summarize the text below clearly and concisely. Return only the summary.

            Text:
            \(text)
            """
        case .translate(let language):
            return """
            Translate the text below to \(language). Return only the translated text.

            Text:
            \(text)
            """
        case .custom(_, _, let promptTemplate):
            return promptTemplate.replacingOccurrences(of: "{{text}}", with: text)
        }
    }
}
