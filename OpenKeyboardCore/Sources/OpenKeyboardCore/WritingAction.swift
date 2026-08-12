import Foundation
import SemanticPromptContract

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

    public var requiresStructuredJSON: Bool {
        if case .custom = self { return false }
        return true
    }
}

public enum WritingPromptBuilder {
    public static let contractVersion = SemanticPromptContract.version
    public static let structuredSystemPrompt = SemanticPromptContract.writingSystemInstruction

    public static func prompt(for action: WritingAction, text: String) -> String {
        let operationID: String
        let parameters: [String: String]
        switch action {
        case .continueWriting:
            operationID = "continue_writing"
            parameters = [:]
        case .rewrite:
            operationID = "rewrite_core"
            parameters = [:]
        case .fixGrammar:
            operationID = "fix_grammar"
            parameters = [:]
        case .summarize:
            operationID = "summarize"
            parameters = [:]
        case .translate(let language):
            operationID = "translate"
            parameters = ["target_language": language]
        case .custom(_, _, let promptTemplate):
            return promptTemplate.replacingOccurrences(of: "{{text}}", with: text)
        }
        guard let rendering = try? SemanticPromptContract.renderWriting(
            operationID: operationID,
            input: text,
            parameters: parameters
        ), let userMessage = rendering.messages.last else {
            preconditionFailure("semantic-prompt-contract \(contractVersion) cannot render \(operationID)")
        }
        return userMessage.content
    }
}
