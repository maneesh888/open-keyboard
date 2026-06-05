//
//  KeyboardReplacementPlanner.swift
//  OpenKeyboardExtension
//

import Foundation

struct KeyboardReplacementPlan: Equatable {
    let textToDelete: String
    let textForAI: String
    let leadingWhitespace: String
    let trailingWhitespace: String

    func replacementText(from aiOutput: String) -> String {
        let trimmedOutput = aiOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else { return "" }
        return leadingWhitespace + trimmedOutput + trailingWhitespace
    }
}

enum KeyboardReplacementPlanner {
    static func plan(for contextBeforeInput: String?) -> KeyboardReplacementPlan? {
        guard let contextBeforeInput, !contextBeforeInput.isEmpty else { return nil }

        let suffix = contextBeforeInput.components(separatedBy: "\n").last ?? contextBeforeInput
        guard !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let leadingWhitespace = String(suffix.prefix { $0.isWhitespace })
        let trailingWhitespace = String(suffix.reversed().prefix { $0.isWhitespace }.reversed())
        let textForAI = suffix.trimmingCharacters(in: .whitespacesAndNewlines)

        return KeyboardReplacementPlan(
            textToDelete: suffix,
            textForAI: textForAI,
            leadingWhitespace: leadingWhitespace,
            trailingWhitespace: trailingWhitespace
        )
    }
}
