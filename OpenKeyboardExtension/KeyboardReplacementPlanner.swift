//
//  KeyboardReplacementPlanner.swift
//  OpenKeyboardExtension
//

import Foundation

struct KeyboardReplacementPlan: Equatable {
    let textToDelete: String
    let textAfterCursorToDelete: String
    let textForAI: String
    let leadingWhitespace: String
    let trailingWhitespace: String

    init(
        textToDelete: String,
        textAfterCursorToDelete: String = "",
        textForAI: String,
        leadingWhitespace: String,
        trailingWhitespace: String
    ) {
        self.textToDelete = textToDelete
        self.textAfterCursorToDelete = textAfterCursorToDelete
        self.textForAI = textForAI
        self.leadingWhitespace = leadingWhitespace
        self.trailingWhitespace = trailingWhitespace
    }

    var textToReplace: String {
        textToDelete + textAfterCursorToDelete
    }

    func replacementText(from aiOutput: String) -> String {
        let trimmedOutput = aiOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else { return "" }
        return leadingWhitespace + trimmedOutput + trailingWhitespace
    }
}

enum KeyboardReplacementPlanner {
    static func plan(for contextBeforeInput: String?) -> KeyboardReplacementPlan? {
        plan(contextBeforeInput: contextBeforeInput, contextAfterInput: nil)
    }

    static func plan(contextBeforeInput: String?, contextAfterInput: String?) -> KeyboardReplacementPlan? {
        guard contextBeforeInput?.isEmpty == false || contextAfterInput?.isEmpty == false else { return nil }

        let suffix = contextBeforeInput?.components(separatedBy: "\n").last ?? ""
        let afterCursor = contextAfterInput?.components(separatedBy: "\n").first ?? ""
        let line = suffix + afterCursor
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let leadingWhitespace = String(line.prefix { $0.isWhitespace })
        let trailingWhitespace = String(line.reversed().prefix { $0.isWhitespace }.reversed())
        let textForAI = line.trimmingCharacters(in: .whitespacesAndNewlines)

        return KeyboardReplacementPlan(
            textToDelete: suffix,
            textAfterCursorToDelete: afterCursor,
            textForAI: textForAI,
            leadingWhitespace: leadingWhitespace,
            trailingWhitespace: trailingWhitespace
        )
    }
}
