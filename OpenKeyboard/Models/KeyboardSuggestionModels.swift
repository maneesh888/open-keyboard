//
//  KeyboardSuggestionModels.swift
//  OpenKeyboard
//
//  Structured corrections + predictions for keyboard suggestion UI.
//

import Foundation
import UIKit

enum KeyboardGatewayActionContract {
    static let contractVersion = SemanticPromptContract.version
    static let structuredSystemPrompt = SemanticPromptContract.writingSystemInstruction

    static func prompt(
        operation: String,
        text: String,
        translationLanguage: String? = nil
    ) -> String {
        let normalizedOperation = operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rendering(
            operation: normalizedOperation,
            text: text,
            translationLanguage: translationLanguage
        ).messages.last!.content
    }

    static func rendering(
        operation: String,
        text: String,
        translationLanguage: String? = nil
    ) -> SemanticPromptRendering {
        let normalizedOperation = operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parameters = normalizedOperation == "translate"
            ? ["target_language": translationLanguage ?? ""]
            : [:]
        guard let rendering = try? SemanticPromptContract.renderWriting(
            operationID: normalizedOperation,
            input: text,
            parameters: parameters
        ) else {
            preconditionFailure("semantic-prompt-contract \(contractVersion) cannot render \(normalizedOperation)")
        }
        return rendering
    }

    static func maxTokens(operation: String) -> Int {
        let normalizedOperation = operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (try? SemanticPromptContract.renderWriting(operationID: normalizedOperation, input: "").maxTokens) ?? 2_000
    }
}

struct KeyboardSuggestionResponse: Equatable {
    let corrections: [KeyboardCorrectionSuggestion]
    let predictions: [KeyboardPredictionSuggestion]
    let correctedText: String?

    init(corrections: [KeyboardCorrectionSuggestion], predictions: [KeyboardPredictionSuggestion], correctedText: String? = nil) {
        self.corrections = corrections
        self.predictions = predictions
        self.correctedText = correctedText
    }
}

struct KeyboardCorrectionSuggestion: Equatable, Identifiable {
    let id: String
    let label: String
    let original: String
    let replacement: String
    let explanation: String?
    let category: String?
    let range: KeyboardTextRange?

    init(id: String = UUID().uuidString, label: String, original: String, replacement: String, explanation: String? = nil, category: String? = nil, range: KeyboardTextRange? = nil) {
        self.id = id
        self.label = label
        self.original = original
        self.replacement = replacement
        self.explanation = explanation
        self.category = category
        self.range = range
    }
}

struct KeyboardTextRange: Equatable, Decodable, Sendable {
    let start: Int
    let end: Int

    init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    enum CodingKeys: String, CodingKey {
        case start, end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let start = Self.decodeOffset(from: container, forKey: .start),
              let end = Self.decodeOffset(from: container, forKey: .end) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Text range offsets must be integers."))
        }
        self.start = start
        self.end = end
    }

    private static func decodeOffset(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        guard let value = try? container.decode(String.self, forKey: key) else { return nil }
        return Int(value)
    }
}

enum GrammarEditDecision: String, Equatable, Sendable {
    case pending
    case accepted
    case rejected
}

struct GrammarEdit: Equatable, Identifiable, Sendable {
    let id: String
    let range: KeyboardTextRange
    let originalText: String
    let replacementText: String
    var decision: GrammarEditDecision

    init(range: KeyboardTextRange, originalText: String, replacementText: String, decision: GrammarEditDecision = .pending) {
        self.range = range
        self.originalText = originalText
        self.replacementText = replacementText
        self.decision = decision
        self.id = Self.stableID(range: range, originalText: originalText, replacementText: replacementText)
    }

    var suggestion: KeyboardCorrectionSuggestion {
        let label = Self.label(original: originalText, replacement: replacementText)
        return KeyboardCorrectionSuggestion(
            id: id,
            label: label,
            original: originalText,
            replacement: replacementText,
            explanation: originalText.isEmpty
                ? "Insert \"\(replacementText)\"."
                : replacementText.isEmpty
                    ? "Remove \"\(originalText)\"."
                    : "Replace \"\(originalText)\" with \"\(replacementText)\".",
            category: label.lowercased(),
            range: range
        )
    }

    private static func label(original: String, replacement: String) -> String {
        let originalLower = original.lowercased()
        let replacementLower = replacement.lowercased()
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        let replacementIsPunctuation = !replacement.isEmpty && replacement.unicodeScalars.allSatisfy {
            punctuation.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
        }
        let originalIsPunctuation = !original.isEmpty && original.unicodeScalars.allSatisfy {
            punctuation.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
        }
        if replacementIsPunctuation || originalIsPunctuation { return "Punctuation" }
        if original.isEmpty { return "Insertion" }
        if replacement.isEmpty { return "Deletion" }
        if originalLower == replacementLower { return "Capitalization" }

        let articles: Set<String> = ["a", "an", "the"]
        if articles.contains(originalLower), articles.contains(replacementLower) { return "Article" }
        let verbFamilies: [Set<String>] = [
            ["am", "is", "are", "was", "were", "be", "been", "being"],
            ["have", "has", "had"],
            ["do", "does", "did"]
        ]
        if verbFamilies.contains(where: { $0.contains(originalLower) && $0.contains(replacementLower) }) ||
            isSimpleInflectionPair(originalLower, replacementLower) {
            return "Subject-verb agreement"
        }
        if original.split(whereSeparator: \.isWhitespace).count == 1,
           replacement.split(whereSeparator: \.isWhitespace).count == 1,
           editDistance(originalLower, replacementLower) <= max(2, max(original.count, replacement.count) / 3) {
            return "Spelling"
        }
        return "Correction"
    }

    private static func isSimpleInflectionPair(_ lhs: String, _ rhs: String) -> Bool {
        lhs + "s" == rhs || rhs + "s" == lhs || lhs + "es" == rhs || rhs + "es" == lhs ||
            (lhs.hasSuffix("y") && String(lhs.dropLast()) + "ies" == rhs) ||
            (rhs.hasSuffix("y") && String(rhs.dropLast()) + "ies" == lhs)
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous.last ?? 0
    }

    private static func stableID(range: KeyboardTextRange, originalText: String, replacementText: String) -> String {
        let value = "\(range.start):\(range.end)\u{0}\(originalText)\u{0}\(replacementText)"
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "grammar-\(range.start)-\(range.end)-\(String(hash, radix: 16))"
    }
}

struct GrammarDiffService {
    private enum TokenKind: Equatable {
        case word
        case whitespace
        case symbol
    }

    private struct Token: Equatable {
        let text: String
        let start: Int
        let end: Int
        let kind: TokenKind

        static func == (lhs: Token, rhs: Token) -> Bool {
            lhs.text == rhs.text && lhs.kind == rhs.kind
        }
    }

    static func edits(from original: String, to corrected: String) -> [GrammarEdit] {
        guard original != corrected else { return [] }
        let source = tokenize(original)
        let target = tokenize(corrected)
        let difference = target.difference(from: source)
        let removedOffsets = Set(difference.removals.compactMap { change -> Int? in
            guard case .remove(let offset, _, _) = change else { return nil }
            return offset
        })
        let insertedOffsets = Set(difference.insertions.compactMap { change -> Int? in
            guard case .insert(let offset, _, _) = change else { return nil }
            return offset
        })

        var edits: [GrammarEdit] = []
        var sourceIndex = 0
        var targetIndex = 0
        var hunkStart: Int?
        var hunkEnd: Int?
        var removed = ""
        var inserted = ""

        func appendHunk() {
            guard let start = hunkStart else { return }
            let end = hunkEnd ?? start
            if removed != inserted {
                edits.append(GrammarEdit(
                    range: KeyboardTextRange(start: start, end: end),
                    originalText: removed,
                    replacementText: inserted
                ))
            }
            hunkStart = nil
            hunkEnd = nil
            removed = ""
            inserted = ""
        }

        while sourceIndex < source.count || targetIndex < target.count {
            if sourceIndex < source.count, targetIndex < target.count, source[sourceIndex] == target[targetIndex] {
                appendHunk()
                sourceIndex += 1
                targetIndex += 1
                continue
            }

            if targetIndex < target.count, insertedOffsets.contains(targetIndex) {
                let offset = sourceIndex < source.count ? source[sourceIndex].start : original.count
                hunkStart = hunkStart ?? offset
                inserted += target[targetIndex].text
                targetIndex += 1
            } else if sourceIndex < source.count, removedOffsets.contains(sourceIndex) {
                hunkStart = hunkStart ?? source[sourceIndex].start
                hunkEnd = source[sourceIndex].end
                removed += source[sourceIndex].text
                sourceIndex += 1
            } else if sourceIndex < source.count, targetIndex < target.count {
                // Defensive fallback for an unexpected unassociated difference.
                hunkStart = hunkStart ?? source[sourceIndex].start
                hunkEnd = source[sourceIndex].end
                removed += source[sourceIndex].text
                inserted += target[targetIndex].text
                sourceIndex += 1
                targetIndex += 1
            }
        }
        appendHunk()
        return edits
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var currentText = ""
        var currentKind: TokenKind?
        var currentStart = 0
        var offset = 0

        func flush() {
            guard let kind = currentKind, !currentText.isEmpty else { return }
            tokens.append(Token(text: currentText, start: currentStart, end: offset, kind: kind))
            currentText = ""
            currentKind = nil
        }

        for character in text {
            let kind = tokenKind(for: character)
            if kind == .symbol {
                flush()
                tokens.append(Token(text: String(character), start: offset, end: offset + 1, kind: kind))
            } else if currentKind == kind {
                currentText.append(character)
            } else {
                flush()
                currentKind = kind
                currentStart = offset
                currentText = String(character)
            }
            offset += 1
        }
        flush()
        return tokens
    }

    private static func tokenKind(for character: Character) -> TokenKind {
        if character.isWhitespace { return .whitespace }
        if character.unicodeScalars.contains(where: {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
        }) {
            return .word
        }
        return .symbol
    }
}

struct GrammarCorrectionSession: Equatable {
    let originalText: String
    let documentRevision: Int
    private(set) var edits: [GrammarEdit]
    private(set) var currentEditIndex: Int

    init(originalText: String, correctedText: String, documentRevision: Int) {
        self.originalText = originalText
        self.documentRevision = documentRevision
        self.edits = GrammarDiffService.edits(from: originalText, to: correctedText)
        self.currentEditIndex = 0
    }

    var currentEdit: GrammarEdit? {
        guard edits.indices.contains(currentEditIndex), edits[currentEditIndex].decision == .pending else { return nil }
        return edits[currentEditIndex]
    }

    var isComplete: Bool { !edits.contains(where: { $0.decision == .pending }) }

    var renderedText: String {
        let characters = Array(originalText)
        var output = ""
        var cursor = 0
        for edit in edits where edit.decision == .accepted {
            let start = min(max(edit.range.start, cursor), characters.count)
            let end = min(max(edit.range.end, start), characters.count)
            output.append(contentsOf: characters[cursor..<start])
            output.append(edit.replacementText)
            cursor = end
        }
        output.append(contentsOf: characters[cursor..<characters.count])
        return output
    }

    mutating func movePrevious() {
        guard let index = edits[..<currentEditIndex].lastIndex(where: { $0.decision == .pending }) else { return }
        currentEditIndex = index
    }

    mutating func moveNext() {
        guard currentEditIndex + 1 < edits.count,
              let index = edits[(currentEditIndex + 1)...].firstIndex(where: { $0.decision == .pending }) else { return }
        currentEditIndex = index
    }

    mutating func decideCurrent(_ decision: GrammarEditDecision) {
        guard edits.indices.contains(currentEditIndex), edits[currentEditIndex].decision == .pending else { return }
        edits[currentEditIndex].decision = decision
        if let next = edits.indices.first(where: { $0 > currentEditIndex && edits[$0].decision == .pending })
            ?? edits.indices.first(where: { edits[$0].decision == .pending }) {
            currentEditIndex = next
        }
    }

    mutating func decideAll(_ decision: GrammarEditDecision) {
        for index in edits.indices where edits[index].decision == .pending {
            edits[index].decision = decision
        }
    }
}

enum GrammarCorrectionResponseError: Error, Equatable {
    case empty
    case truncated
    case commentary
    case fenced
    case malformedUnicode
    case suspiciousRewrite
}

struct GrammarCorrectionResponseValidator {
    static func validated(_ response: String, original: String) throws -> String {
        guard !response.isEmpty else { throw GrammarCorrectionResponseError.empty }
        guard !response.unicodeScalars.contains(where: { $0.value == 0xFFFD }) else {
            throw GrammarCorrectionResponseError.malformedUnicode
        }
        let inspection = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = inspection.lowercased()
        let originalLower = original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let introducesOpeningFence = lower.hasPrefix("```") && !originalLower.hasPrefix("```")
        let introducesClosingFence = lower.hasSuffix("```") && !originalLower.hasSuffix("```")
        guard !introducesOpeningFence && !introducesClosingFence else {
            throw GrammarCorrectionResponseError.fenced
        }
        guard !hasNewCommentaryPrefix(lower, original: originalLower) else {
            throw GrammarCorrectionResponseError.commentary
        }
        guard !hasNewCommentarySuffix(lower, original: originalLower) else {
            throw GrammarCorrectionResponseError.commentary
        }
        let introducesStructuredPrefix = ["{", "["].contains {
            lower.hasPrefix($0) && !originalLower.hasPrefix($0)
        }
        guard !introducesStructuredPrefix else { throw GrammarCorrectionResponseError.commentary }
        let corrected = restoringOriginalBoundaryWhitespace(in: response, original: original)
        guard preservesNewlineStructure(original: original, corrected: corrected) else {
            throw GrammarCorrectionResponseError.truncated
        }
        if corrected == original { return corrected }
        if original.count >= 80, corrected.count < original.count * 3 / 5 {
            throw GrammarCorrectionResponseError.truncated
        }

        let edits = GrammarDiffService.edits(from: original, to: corrected)
        guard !edits.contains(where: { isSuspiciousOmission($0, original: original) }) else {
            throw GrammarCorrectionResponseError.truncated
        }
        guard !edits.contains(where: { isSuspiciousBoundaryCommentary($0, original: original) }) else {
            throw GrammarCorrectionResponseError.commentary
        }
        guard !hasSuspiciousBoundarySentenceSubstitution(original: original, corrected: corrected) else {
            throw GrammarCorrectionResponseError.commentary
        }
        let changedCharacters = edits.reduce(0) {
            $0 + max($1.originalText.count, $1.replacementText.count)
        }
        let sourceWords = original.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).count
        let changedWords = edits.reduce(0) {
            $0 + max(
                $1.originalText.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).count,
                $1.replacementText.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).count
            )
        }
        let originalWords = words(in: original)
        let responseWords = words(in: corrected)
        let approximatelyPreservedWords = originalWords.filter { sourceWord in
            responseWords.contains { candidate in
                wordEditDistance(sourceWord, candidate) <= max(2, max(sourceWord.count, candidate.count) / 3)
            }
        }.count
        guard changedCharacters <= max(48, original.count * 45 / 100),
              changedWords <= max(8, sourceWords * 60 / 100),
              approximatelyPreservedWords >= max(1, min(originalWords.count, responseWords.count) / 2) else {
            throw GrammarCorrectionResponseError.suspiciousRewrite
        }
        return corrected
    }

    private static func isSuspiciousOmission(_ edit: GrammarEdit, original: String) -> Bool {
        let removedWords = words(in: edit.originalText).count
        let replacementWords = words(in: edit.replacementText).count
        guard removedWords > 0, replacementWords == 0 else { return false }
        let originalCharacters = Array(original)
        let beforeEdit = String(originalCharacters.prefix(edit.range.start))
        let afterEdit = String(originalCharacters.dropFirst(edit.range.end))
        let removesDocumentBoundary = words(in: beforeEdit).isEmpty || words(in: afterEdit).isEmpty
        return removesDocumentBoundary || removedWords >= 3
    }

    private static func isSuspiciousBoundaryCommentary(_ edit: GrammarEdit, original: String) -> Bool {
        guard edit.originalText.isEmpty else { return false }
        let inserted = edit.replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        let insertedWords = words(in: inserted)
        guard !insertedWords.isEmpty else { return false }
        let originalCharacters = Array(original)
        let beforeEdit = String(originalCharacters.prefix(edit.range.start))
        let afterEdit = String(originalCharacters.dropFirst(edit.range.start))
        guard words(in: beforeEdit).isEmpty || words(in: afterEdit).isEmpty else { return false }
        return true
    }

    private struct WordOccurrence {
        let value: String
        let start: Int
        let end: Int
    }

    private struct GrammarLineStructure {
        let lines: [String]
        let separators: [Character]
    }

    private struct ProtectedGrammarStructure {
        let segments: [String]
        let tokens: [Character]
    }

    private static func preservesNewlineStructure(original: String, corrected: String) -> Bool {
        let sourceStructure = grammarLineStructure(in: original)
        let correctedStructure = grammarLineStructure(in: corrected)
        guard sourceStructure.separators == correctedStructure.separators,
              sourceStructure.lines.count == correctedStructure.lines.count else {
            return false
        }
        return zip(sourceStructure.lines, correctedStructure.lines).allSatisfy { sourceLine, correctedLine in
            leadingWhitespace(in: sourceLine) == leadingWhitespace(in: correctedLine) &&
            trailingWhitespace(in: sourceLine) == trailingWhitespace(in: correctedLine) &&
            preservesProtectedGrammarStructure(original: sourceLine, corrected: correctedLine) &&
            !hasUnanchoredGrammarContent(
                wordOccurrences(in: Array(sourceLine)).map(\.value),
                wordOccurrences(in: Array(correctedLine)).map(\.value)
            )
        }
    }

    private static func preservesProtectedGrammarStructure(original: String, corrected: String) -> Bool {
        let sourceStructure = protectedGrammarStructure(in: original)
        let correctedStructure = protectedGrammarStructure(in: corrected)
        guard sourceStructure.tokens == correctedStructure.tokens,
              sourceStructure.segments.count == correctedStructure.segments.count else {
            return false
        }
        return zip(sourceStructure.segments, correctedStructure.segments).allSatisfy { source, response in
            leadingWhitespace(in: source) == leadingWhitespace(in: response) &&
            trailingWhitespace(in: source) == trailingWhitespace(in: response) &&
            !hasUnanchoredGrammarContent(
                wordOccurrences(in: Array(source)).map(\.value),
                wordOccurrences(in: Array(response)).map(\.value)
            )
        }
    }

    private static func protectedGrammarStructure(in value: String) -> ProtectedGrammarStructure {
        var segments: [String] = []
        var tokens: [Character] = []
        var currentSegment = ""
        for character in value {
            if isProtectedGrammarCharacter(character) {
                segments.append(currentSegment)
                tokens.append(character)
                currentSegment = ""
            } else {
                currentSegment.append(character)
            }
        }
        segments.append(currentSegment)
        return ProtectedGrammarStructure(segments: segments, tokens: tokens)
    }

    private static func isProtectedGrammarCharacter(_ character: Character) -> Bool {
        let formattingMarkers: Set<Character> = [
            "*", "_", "~", "`", "#", ">", "<", "=", "|", "\\", "/", "@", "&", "%",
            "[", "]", "(", ")", "{", "}"
        ]
        if formattingMarkers.contains(character) { return true }
        if character.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { return true }
        return character.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
                return true
            default:
                return false
            }
        }
    }

    private static func grammarLineStructure(in value: String) -> GrammarLineStructure {
        var lines: [String] = []
        var separators: [Character] = []
        var currentLine = ""
        for character in value {
            if character.isNewline {
                lines.append(currentLine)
                separators.append(character)
                currentLine = ""
            } else {
                currentLine.append(character)
            }
        }
        lines.append(currentLine)
        return GrammarLineStructure(lines: lines, separators: separators)
    }

    private static func hasSuspiciousBoundarySentenceSubstitution(original: String, corrected: String) -> Bool {
        let sourceCharacters = Array(original)
        let correctedCharacters = Array(corrected)
        let sourceWords = wordOccurrences(in: sourceCharacters)
        let correctedWords = wordOccurrences(in: correctedCharacters)
        let comparableCount = min(sourceWords.count, correctedWords.count)
        guard !hasUnanchoredGrammarContent(
            sourceWords.map(\.value),
            correctedWords.map(\.value)
        ) else { return true }
        guard comparableCount >= 2 else { return false }

        var preservedPrefixCount = 0
        while preservedPrefixCount < comparableCount,
              approximatelyMatches(
                  sourceWords[preservedPrefixCount].value,
                  correctedWords[preservedPrefixCount].value
              ) {
            preservedPrefixCount += 1
        }
        if preservedPrefixCount > 0, preservedPrefixCount < comparableCount {
            let sourceSeparator = sourceCharacters[
                sourceWords[preservedPrefixCount - 1].end..<sourceWords[preservedPrefixCount].start
            ]
            let correctedSeparator = correctedCharacters[
                correctedWords[preservedPrefixCount - 1].end..<correctedWords[preservedPrefixCount].start
            ]
            if containsBoundaryDelimiter(correctedSeparator) || containsBoundaryDelimiter(sourceSeparator) {
                return true
            }
        }

        var preservedSuffixCount = 0
        while preservedSuffixCount < comparableCount,
              approximatelyMatches(
                  sourceWords[sourceWords.count - preservedSuffixCount - 1].value,
                  correctedWords[correctedWords.count - preservedSuffixCount - 1].value
              ) {
            preservedSuffixCount += 1
        }
        if preservedSuffixCount > 0, preservedSuffixCount < comparableCount {
            let sourceBoundaryIndex = sourceWords.count - preservedSuffixCount
            let correctedBoundaryIndex = correctedWords.count - preservedSuffixCount
            let sourceSeparator = sourceCharacters[
                sourceWords[sourceBoundaryIndex - 1].end..<sourceWords[sourceBoundaryIndex].start
            ]
            let correctedSeparator = correctedCharacters[
                correctedWords[correctedBoundaryIndex - 1].end..<correctedWords[correctedBoundaryIndex].start
            ]
            if containsBoundaryDelimiter(correctedSeparator) || containsBoundaryDelimiter(sourceSeparator) {
                return true
            }
        }
        return false
    }

    private static func hasUnanchoredGrammarContent(
        _ sourceWords: [String],
        _ correctedWords: [String]
    ) -> Bool {
        func expandingGrammarInsertions(from states: Set<GrammarAlignmentState>) -> Set<GrammarAlignmentState> {
            var expanded = states
            var pending = Array(states)
            while let state = pending.popLast() {
                guard state.correctedCount < correctedWords.count,
                      state.gap != .deletion,
                      grammarInsertableWords.contains(correctedWords[state.correctedCount]) else {
                    continue
                }
                let inserted = GrammarAlignmentState(
                    correctedCount: state.correctedCount + 1,
                    gap: .insertion
                )
                if expanded.insert(inserted).inserted {
                    pending.append(inserted)
                }
            }
            return expanded
        }

        var reachableStates = expandingGrammarInsertions(from: [
            GrammarAlignmentState(correctedCount: 0, gap: .none)
        ])
        for sourceIndex in sourceWords.indices {
            var nextStates: Set<GrammarAlignmentState> = []
            let sourceWord = sourceWords[sourceIndex]
            let canDeleteSource = grammarDeletableWords.contains(sourceWord) ||
                isRepeatedSourceWord(at: sourceIndex, in: sourceWords)
            for state in reachableStates {
                if canDeleteSource, state.gap != .insertion {
                    nextStates.insert(GrammarAlignmentState(correctedCount: state.correctedCount, gap: .deletion))
                }
                if state.correctedCount < correctedWords.count,
                   isPlausibleGrammarWordReplacement(sourceWord, correctedWords[state.correctedCount]) {
                    nextStates.insert(GrammarAlignmentState(
                        correctedCount: state.correctedCount + 1,
                        gap: .none
                    ))
                }
            }
            reachableStates = expandingGrammarInsertions(from: nextStates)
            if reachableStates.isEmpty { return true }
        }
        return !reachableStates.contains(where: { $0.correctedCount == correctedWords.count })
    }

    private enum GrammarAlignmentGap: Hashable {
        case none
        case insertion
        case deletion
    }

    private struct GrammarAlignmentState: Hashable {
        let correctedCount: Int
        let gap: GrammarAlignmentGap
    }

    private static func isPlausibleGrammarWordReplacement(_ source: String, _ corrected: String) -> Bool {
        guard source != corrected else { return true }
        if grammarWordFamilies.contains(where: { $0.contains(source) && $0.contains(corrected) }) {
            return true
        }
        if knownSpellingWordFamilies.contains(where: { $0.contains(source) && $0.contains(corrected) }) {
            return true
        }
        return isAdjacentTransposition(source, corrected) ||
            isPlausibleInflection(source, corrected) ||
            isConservativeMissingCharacterCorrection(source, corrected)
    }

    private static func isConservativeMissingCharacterCorrection(_ source: String, _ corrected: String) -> Bool {
        guard source.count >= 5,
              corrected.count == source.count + 1,
              source.first == corrected.first,
              source.last == corrected.last else {
            return false
        }
        return wordEditDistance(source, corrected) == 1
    }

    private static func isPlausibleInflection(_ source: String, _ corrected: String) -> Bool {
        !grammarInflectionStems(for: source).isDisjoint(with: grammarInflectionStems(for: corrected))
    }

    private static func grammarInflectionStems(for word: String) -> Set<String> {
        var stems: Set<String> = [word]
        for suffix in ["ing", "ed", "es", "s"] where word.hasSuffix(suffix) && word.count > suffix.count + 1 {
            let stem = String(word.dropLast(suffix.count))
            stems.insert(stem)
            if suffix == "ing" {
                stems.insert(stem + "e")
                if stem.count > 2, stem.last == stem.dropLast().last {
                    stems.insert(String(stem.dropLast()))
                }
            }
        }
        if word.hasSuffix("ies"), word.count > 4 {
            stems.insert(String(word.dropLast(3)) + "y")
        }
        return stems
    }

    private static func isRepeatedSourceWord(at index: Int, in words: [String]) -> Bool {
        (index > words.startIndex && words[index - 1] == words[index]) ||
            (index + 1 < words.endIndex && words[index + 1] == words[index])
    }

    private static func isAdjacentTransposition(_ source: String, _ corrected: String) -> Bool {
        let sourceCharacters = Array(source)
        let correctedCharacters = Array(corrected)
        guard sourceCharacters.count == correctedCharacters.count else { return false }
        let differences = sourceCharacters.indices.filter { sourceCharacters[$0] != correctedCharacters[$0] }
        guard differences.count == 2,
              differences[1] == differences[0] + 1 else { return false }
        return sourceCharacters[differences[0]] == correctedCharacters[differences[1]] &&
            sourceCharacters[differences[1]] == correctedCharacters[differences[0]]
    }

    private static let grammarInsertableWords: Set<String> = [
        "a", "an", "the",
        "am", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did",
        "at", "by", "from", "in", "into", "of", "on", "to", "with"
    ]

    private static let grammarDeletableWords = grammarInsertableWords

    private static let grammarWordFamilies: [Set<String>] = [
        ["am", "is", "are", "was", "were", "be", "been", "being"],
        ["have", "has", "had"], ["do", "does", "did", "done"],
        ["dont", "doesnt", "didnt"],
        ["can", "could"], ["will", "would"], ["shall", "should"], ["may", "might"],
        ["a", "an", "the"], ["this", "these"], ["that", "those"],
        ["good", "well", "better", "best"], ["bad", "badly", "worse", "worst"],
        ["go", "goes", "went", "gone", "going", "goed"], ["hear", "here"]
    ]

    private static let knownSpellingWordFamilies: [Set<String>] = [
        ["definately", "definitely"], ["shure", "sure"],
        ["yestarday", "yesterday"], ["wrng", "wrong"],
        ["seperate", "separate"], ["reveiw", "review"],
        ["paymant", "payment"], ["cliant", "client"],
        ["tommorow", "tomorrow"]
    ]

    private static func wordOccurrences(in characters: [Character]) -> [WordOccurrence] {
        var occurrences: [WordOccurrence] = []
        var index = 0
        while index < characters.count {
            guard characters[index].isLetter || characters[index].isNumber else {
                index += 1
                continue
            }
            let start = index
            while index < characters.count {
                if characters[index].isLetter || characters[index].isNumber {
                    index += 1
                    continue
                }
                let isInternalApostrophe = (characters[index] == "'" || characters[index] == "’") &&
                    index > start && index + 1 < characters.count &&
                    (characters[index + 1].isLetter || characters[index + 1].isNumber)
                if isInternalApostrophe {
                    index += 1
                    continue
                }
                break
            }
            occurrences.append(WordOccurrence(
                value: normalizedGrammarWord(String(characters[start..<index])),
                start: start,
                end: index
            ))
        }
        return occurrences
    }

    private static func normalizedGrammarWord(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
    }

    private static func approximatelyMatches(_ lhs: String, _ rhs: String) -> Bool {
        wordEditDistance(lhs, rhs) <= max(2, max(lhs.count, rhs.count) / 3)
    }

    private static func hasNewCommentarySuffix(_ corrected: String, original: String) -> Bool {
        let correctedWords = words(in: corrected)
        let originalWords = words(in: original)
        let commentarySuffixes = [
            "hope this helps", "happy to help", "let me know", "thank you", "thanks",
            "sure thing", "all set", "sure", "okay", "ok", "done", "enjoy"
        ]
        return commentarySuffixes.contains { suffix in
            let suffixWords = words(in: suffix)
            guard correctedWords.count >= suffixWords.count,
                  Array(correctedWords.suffix(suffixWords.count)) == suffixWords else {
                return false
            }
            let originalTail = Array(originalWords.suffix(suffixWords.count))
            return originalTail.count != suffixWords.count ||
                !zip(originalTail, suffixWords).allSatisfy { approximatelyMatches($0, $1) }
        }
    }

    private static func hasNewCommentaryPrefix(_ corrected: String, original: String) -> Bool {
        let correctedWords = words(in: corrected)
        let originalWords = words(in: original)
        let commentaryPrefixes = [
            "here is", "here's", "corrected text", "the corrected", "i corrected",
            "sure thing", "of course", "sure", "certainly", "okay", "ok", "done", "correction"
        ]
        return commentaryPrefixes.contains { prefix in
            let prefixWords = words(in: prefix)
            guard correctedWords.count >= prefixWords.count,
                  Array(correctedWords.prefix(prefixWords.count)) == prefixWords else {
                return false
            }
            let originalHead = Array(originalWords.prefix(prefixWords.count))
            return originalHead.count != prefixWords.count ||
                !zip(originalHead, prefixWords).allSatisfy { approximatelyMatches($0, $1) }
        }
    }

    private static func containsBoundaryDelimiter(_ characters: ArraySlice<Character>) -> Bool {
        characters.contains(where: { !$0.isWhitespace })
    }

    private static func words(in value: String) -> [String] {
        value.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map { $0.lowercased() }
    }

    private static func wordEditDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous.last ?? 0
    }

    private static func leadingWhitespace(in value: String) -> String {
        String(value.prefix(while: { $0.isWhitespace }))
    }

    private static func trailingWhitespace(in value: String) -> String {
        String(value.reversed().prefix(while: { $0.isWhitespace }).reversed())
    }

    private static func restoringOriginalBoundaryWhitespace(in response: String, original: String) -> String {
        guard original.contains(where: { !$0.isWhitespace }) else { return original }
        let withoutLeadingWhitespace = response.drop(while: { $0.isWhitespace })
        let responseBody = withoutLeadingWhitespace.reversed().drop(while: { $0.isWhitespace }).reversed()
        return leadingWhitespace(in: original) + String(responseBody) + trailingWhitespace(in: original)
    }
}

struct KeyboardPredictionSuggestion: Equatable, Identifiable {
    let id: String
    let label: String
    let text: String
    let kind: String?

    init(id: String = UUID().uuidString, label: String, text: String, kind: String? = nil) {
        self.id = id
        self.label = label
        self.text = text
        self.kind = kind
    }
}

struct KeyboardCorrectionCard: Equatable {
    let categoryTitle: String
    let original: String
    let replacement: String
    let explanation: String

    init(correction: KeyboardCorrectionSuggestion) {
        self.categoryTitle = Self.categoryTitle(label: correction.label, category: correction.category)
        self.original = correction.original
        self.replacement = correction.replacement
        self.explanation = Self.explanation(for: correction)
    }

    private static func categoryTitle(label: String, category: String?) -> String {
        let labelValue = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let categoryValue = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = "\(labelValue) \(categoryValue)".lowercased()

        if combined.contains("subject") || combined.contains("verb") {
            return "Subject-verb agreement"
        }
        if !labelValue.isEmpty, !combined.contains("grammar"), !combined.contains("correct") {
            return labelValue.replacingOccurrences(of: ":", with: "")
        }
        return "Correctness"
    }

    private static func explanation(for correction: KeyboardCorrectionSuggestion) -> String {
        let provided = correction.explanation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !provided.isEmpty { return provided }
        return "Replace \"\(correction.original)\" with \"\(correction.replacement)\"."
    }
}

struct KeyboardSuggestionState: Equatable {
    private(set) var corrections: [KeyboardCorrectionSuggestion]
    let predictions: [KeyboardPredictionSuggestion]
    let correctedText: String?
    private(set) var currentCorrectionIndex: Int
    private(set) var grammarSession: GrammarCorrectionSession?

    init(response: KeyboardSuggestionResponse, sourceContext: String? = nil, currentCorrectionIndex: Int = 0) {
        if let sourceContext, !sourceContext.isEmpty {
            let filteredCorrections = response.corrections.filter { $0.isAtomicCorrection(for: sourceContext) }
            self.corrections = filteredCorrections
            self.correctedText = Self.textByApplying(filteredCorrections, to: sourceContext)
        } else {
            self.corrections = response.corrections
            self.correctedText = response.correctedText
        }
        self.predictions = Self.filteredPredictions(response.predictions, sourceContext: sourceContext)
        self.grammarSession = nil
        if response.corrections.isEmpty {
            self.currentCorrectionIndex = 0
        } else {
            self.currentCorrectionIndex = min(max(currentCorrectionIndex, 0), response.corrections.count - 1)
        }
    }

    init(grammarOriginal: String, correctedText: String, documentRevision: Int) {
        let session = GrammarCorrectionSession(
            originalText: grammarOriginal,
            correctedText: correctedText,
            documentRevision: documentRevision
        )
        self.grammarSession = session
        self.corrections = session.edits.map(\.suggestion)
        self.predictions = []
        self.correctedText = correctedText
        self.currentCorrectionIndex = session.currentEditIndex
    }

    var currentCorrection: KeyboardCorrectionSuggestion? {
        if let edit = grammarSession?.currentEdit { return edit.suggestion }
        guard currentCorrectionIndex < corrections.count else { return nil }
        return corrections[currentCorrectionIndex]
    }

    var currentPrediction: KeyboardPredictionSuggestion? { predictions.first }

    var remainingCorrectionCount: Int {
        corrections.count
    }

    var correctionCount: Int {
        grammarSession?.edits.count ?? corrections.count
    }

    var currentCorrectionPosition: Int {
        guard currentCorrection != nil else { return 0 }
        return currentCorrectionIndex + 1
    }

    var showsCorrectionProgress: Bool {
        currentCorrection != nil && correctionCount > 1
    }

    var correctionProgressText: String? {
        guard showsCorrectionProgress else { return nil }
        return "\(currentCorrectionPosition) of \(correctionCount)"
    }

    var canMoveToPreviousCorrection: Bool {
        if let session = grammarSession {
            return session.edits[..<session.currentEditIndex].contains(where: { $0.decision == .pending })
        }
        return currentCorrectionIndex > 0
    }

    var canMoveToNextCorrection: Bool {
        if let session = grammarSession {
            guard session.currentEditIndex + 1 < session.edits.count else { return false }
            return session.edits[(session.currentEditIndex + 1)...].contains(where: { $0.decision == .pending })
        }
        return currentCorrectionIndex + 1 < corrections.count
    }

    var isComplete: Bool {
        grammarSession?.isComplete ?? (currentCorrection == nil && predictions.isEmpty)
    }

    var compactCorrectionReplacement: String? {
        currentCorrection?.replacement
    }

    var compactPredictionText: String? {
        currentPrediction?.text
    }

    var currentCorrectionCard: KeyboardCorrectionCard? {
        currentCorrection.map(KeyboardCorrectionCard.init(correction:))
    }

    mutating func moveToPreviousCorrection() {
        if grammarSession != nil {
            grammarSession?.movePrevious()
            currentCorrectionIndex = grammarSession?.currentEditIndex ?? currentCorrectionIndex
            return
        }
        guard canMoveToPreviousCorrection else { return }
        currentCorrectionIndex -= 1
    }

    mutating func moveToNextCorrection() {
        if grammarSession != nil {
            grammarSession?.moveNext()
            currentCorrectionIndex = grammarSession?.currentEditIndex ?? currentCorrectionIndex
            return
        }
        guard canMoveToNextCorrection else { return }
        currentCorrectionIndex += 1
    }

    mutating func applyCurrentCorrection() {
        if grammarSession != nil {
            grammarSession?.decideCurrent(.accepted)
            currentCorrectionIndex = grammarSession?.currentEditIndex ?? currentCorrectionIndex
            return
        }
        removeCurrentCorrection()
    }

    mutating func dismissCurrentCorrection() {
        if grammarSession != nil {
            grammarSession?.decideCurrent(.rejected)
            currentCorrectionIndex = grammarSession?.currentEditIndex ?? currentCorrectionIndex
            return
        }
        removeCurrentCorrection()
    }

    func textByApplyingCurrentCorrection(to text: String) -> String? {
        if var session = grammarSession {
            guard text == session.renderedText else { return nil }
            session.decideCurrent(.accepted)
            return session.renderedText
        }
        guard let correction = currentCorrection else { return nil }
        return correction.applying(to: text)
    }

    var renderedGrammarText: String? { grammarSession?.renderedText }

    var grammarDocumentRevision: Int? { grammarSession?.documentRevision }

    mutating func acceptAllGrammarCorrections() {
        grammarSession?.decideAll(.accepted)
    }

    mutating func rejectAllGrammarCorrections() {
        grammarSession?.decideAll(.rejected)
    }

    private mutating func removeCurrentCorrection() {
        guard currentCorrection != nil else { return }
        corrections.remove(at: currentCorrectionIndex)
        currentCorrectionIndex = min(currentCorrectionIndex, max(corrections.count - 1, 0))
    }

    private static func filteredPredictions(_ predictions: [KeyboardPredictionSuggestion], sourceContext: String?) -> [KeyboardPredictionSuggestion] {
        guard let sourceContext, !sourceContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return predictions
        }
        return predictions.filter { !isRedundantPrediction($0.text, sourceContext: sourceContext) }
    }

    private static func textByApplying(_ corrections: [KeyboardCorrectionSuggestion], to sourceText: String) -> String? {
        let corrected = corrections.reduce(sourceText) { text, correction in
            correction.applying(to: text) ?? text
        }
        return corrected == sourceText ? nil : corrected
    }

    static func isRedundantPrediction(_ prediction: String, sourceContext: String) -> Bool {
        let normalizedPrediction = normalizeText(prediction)
        guard !normalizedPrediction.isEmpty else { return true }
        let normalizedContext = normalizeText(sourceContext)
        guard !normalizedContext.isEmpty else { return false }

        return normalizedContext == normalizedPrediction
            || normalizedContext.hasSuffix(" " + normalizedPrediction)
            || normalizedContext.split(separator: " ").last.map(String.init) == normalizedPrediction
    }

    private static func normalizeText(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension KeyboardCorrectionSuggestion {
    func isAtomicCorrection(for sourceText: String) -> Bool {
        let cleanOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanOriginal.isEmpty,
              !cleanReplacement.isEmpty,
              cleanOriginal != cleanReplacement,
              cleanOriginal != sourceText.trimmingCharacters(in: .whitespacesAndNewlines),
              sourceText.correctionRange(of: cleanOriginal) != nil else {
            return false
        }
        let originalWords = cleanOriginal.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let replacementWords = cleanReplacement.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let originalWordCount = originalWords.count
        let replacementWordCount = replacementWords.count
        guard originalWordCount <= 3, replacementWordCount <= 3 else { return false }

        let metadata = [label, category ?? "", explanation ?? ""]
            .joined(separator: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
        let stylisticMarkers = [
            "word choice", "vocabulary", "synonym", "style", "tone", "clarity",
            "formal", "friendly", "concise", "professional", "rewrite", "rephrase"
        ]
        guard !stylisticMarkers.contains(where: metadata.contains) else { return false }

        let mechanicalMarkers = [
            "spell", "capital", "punct", "grammar", "agreement", "article",
            "missing", "extra word", "word form", "inflection", "contraction",
            "pronoun", "tense", "plural", "singular"
        ]
        let hasMechanicalMarker = mechanicalMarkers.contains(where: metadata.contains)
        if originalWordCount == replacementWordCount {
            let changedTokens = zip(originalWords, replacementWords).filter { pair in pair.0 != pair.1 }
            guard changedTokens.count == 1, let changedToken = changedTokens.first else { return false }
            return Self.isMechanicalTokenReplacement(
                original: changedToken.0,
                replacement: changedToken.1,
                hasMechanicalMarker: hasMechanicalMarker
            )
        }

        guard hasMechanicalMarker, abs(originalWordCount - replacementWordCount) == 1 else { return false }
        return Self.isSingleMechanicalInsertionOrRemoval(originalWords, replacementWords)
    }

    private static func isMechanicalTokenReplacement(
        original: String,
        replacement: String,
        hasMechanicalMarker: Bool
    ) -> Bool {
        let lowerOriginal = original.lowercased()
        let lowerReplacement = replacement.lowercased()
        if lowerOriginal == lowerReplacement { return true }

        let letterSet = CharacterSet.letters.union(.decimalDigits)
        let originalCore = lowerOriginal.trimmingCharacters(in: letterSet.inverted)
        let replacementCore = lowerReplacement.trimmingCharacters(in: letterSet.inverted)
        if !originalCore.isEmpty, originalCore == replacementCore { return true }
        if originalCore.isEmpty, replacementCore.isEmpty { return hasMechanicalMarker }
        if isLikelySpellingCorrection(originalCore, replacementCore) { return true }

        guard hasMechanicalMarker else { return false }
        if grammaticalWordFamilies.contains(where: { $0.contains(originalCore) && $0.contains(replacementCore) }) {
            return true
        }
        return !inflectionStems(for: originalCore).isDisjoint(with: inflectionStems(for: replacementCore))
    }

    private static func isSingleMechanicalInsertionOrRemoval(_ lhs: [String], _ rhs: [String]) -> Bool {
        let shorter = lhs.count < rhs.count ? lhs : rhs
        let longer = lhs.count < rhs.count ? rhs : lhs
        let allowedInsertedWords: Set<String> = [
            "a", "an", "the", "to", "of", "in", "on", "at", "for", "from",
            "with", "by", "and", "or", "but", "as", "than", "that", "if", "so"
        ]
        for skippedIndex in longer.indices {
            let candidate = longer.enumerated().compactMap { index, word in
                index == skippedIndex ? nil : word.lowercased()
            }
            if candidate == shorter.map({ $0.lowercased() }),
               allowedInsertedWords.contains(longer[skippedIndex].lowercased()) {
                return true
            }
        }
        return false
    }

    private static let grammaticalWordFamilies: [Set<String>] = [
        ["am", "is", "are", "was", "were", "be", "been", "being"],
        ["have", "has", "had", "having"],
        ["do", "does", "did", "done", "doing"]
    ]

    private static func inflectionStems(for word: String) -> Set<String> {
        guard !word.isEmpty else { return [] }
        var stems: Set<String> = [word]
        let suffixes = ["ing", "ed", "es", "s"]
        for suffix in suffixes where word.hasSuffix(suffix) && word.count > suffix.count + 1 {
            let stem = String(word.dropLast(suffix.count))
            stems.insert(stem)
            if suffix == "ing" {
                stems.insert(stem + "e")
                if stem.count > 2, stem.last == stem.dropLast().last {
                    stems.insert(String(stem.dropLast()))
                }
            }
        }
        if word.hasSuffix("ies"), word.count > 4 {
            stems.insert(String(word.dropLast(3)) + "y")
        }
        return stems
    }

    private static func isLikelySpellingCorrection(_ original: String, _ replacement: String) -> Bool {
        guard !original.isEmpty, !replacement.isEmpty else { return false }
        let editDistance = characterEditDistance(original, replacement)
        guard editDistance <= max(2, max(original.count, replacement.count) / 3) else { return false }

        let checker = UITextChecker()
        let preferredPrefixes = Set(Locale.preferredLanguages.map { String($0.prefix(2)).lowercased() })
        let preferredCheckerLanguages = UITextChecker.availableLanguages.filter {
            preferredPrefixes.contains(String($0.prefix(2)).lowercased())
        }
        let languages = Set(preferredCheckerLanguages + ["en_US", "en_GB"])
        let originalRange = NSRange(location: 0, length: original.utf16.count)
        for language in languages {
            let guesses = checker.guesses(
                forWordRange: originalRange,
                in: original,
                language: language
            ) ?? []
            if guesses.contains(where: { $0.caseInsensitiveCompare(replacement) == .orderedSame }) {
                return true
            }
        }
        return false
    }

    private static func characterEditDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous.last ?? 0
    }

    func applying(to text: String) -> String? {
        guard !original.isEmpty, !replacement.isEmpty else { return nil }
        let range = range.flatMap { text.correctionRange(of: original, near: $0.start) } ?? text.correctionRange(of: original)
        guard let range else { return nil }
        return text.replacingCharacters(in: range, with: replacement)
    }
}

private extension String {
    func correctionRange(of target: String) -> Range<String.Index>? {
        correctionRanges(of: target).first
    }

    func correctionRange(of target: String, near offset: Int) -> Range<String.Index>? {
        correctionRanges(of: target)
            .map { range in
                let candidateOffset = distance(from: startIndex, to: range.lowerBound)
                return (range: range, distance: abs(candidateOffset - offset))
            }
            .min { lhs, rhs in lhs.distance < rhs.distance }?
            .range
    }

    func correctionRanges(of target: String) -> [Range<String.Index>] {
        guard !target.isEmpty else { return [] }
        var matches: [Range<String.Index>] = []
        var searchStart = startIndex

        while searchStart < endIndex,
              let candidate = range(of: target, range: searchStart..<endIndex) {
            if isCorrectionTokenRange(candidate, target: target) {
                matches.append(candidate)
            }
            searchStart = candidate.upperBound
        }

        return matches
    }

    func isCorrectionTokenRange(_ range: Range<String.Index>, target: String) -> Bool {
        let firstTargetCharacter = target.first
        let lastTargetCharacter = target.last

        if firstTargetCharacter?.isCorrectionWordCharacter == true,
           range.lowerBound > startIndex,
           self[index(before: range.lowerBound)].isCorrectionWordCharacter {
            return false
        }

        if lastTargetCharacter?.isCorrectionWordCharacter == true,
           range.upperBound < endIndex,
           self[range.upperBound].isCorrectionWordCharacter {
            return false
        }

        return true
    }
}

private extension Character {
    var isCorrectionWordCharacter: Bool {
        unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }
}

enum KeyboardActionErrorKind: Equatable {
    case gatewayUnavailable
    case timeout
    case authentication
    case modelUnavailable
    case modelCapability

    var title: String {
        switch self {
        case .gatewayUnavailable: return "AI unavailable"
        case .timeout: return "Request timed out"
        case .authentication: return "Invalid API key"
        case .modelUnavailable: return "Model unavailable"
        case .modelCapability: return "Model not compatible"
        }
    }
}

enum KeyboardActionErrorScope: Equatable {
    case global
    case grammar
    case writingAction
}

struct KeyboardActionErrorState: Equatable {
    static let modelCapabilityMessage = "The selected model is not capable of this AI action. Choose another model or retry the model check."

    let kind: KeyboardActionErrorKind
    let scope: KeyboardActionErrorScope
    let message: String

    init(
        kind: KeyboardActionErrorKind = .gatewayUnavailable,
        scope: KeyboardActionErrorScope = .global,
        message: String
    ) {
        self.kind = kind
        self.scope = kind == .modelCapability ? scope : .global
        self.message = kind == .modelCapability ? Self.modelCapabilityMessage : Self.sanitized(message)
    }

    var title: String { kind.title }

    var blocksGrammarCorrection: Bool {
        kind != .modelCapability || scope != .writingAction
    }

    static func sanitized(_ rawMessage: String) -> String {
        var message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty { return "Something went wrong. Try again." }
        if message.contains("{") || message.contains("}") || message.contains("[") || message.contains("]") {
            message = "Gateway returned an invalid response."
        }
        let forbiddenMarkers = ["Bearer ", "api_key", "apiKey", "Authorization", "BEGIN ", "token", "password"]
        if forbiddenMarkers.contains(where: { message.localizedCaseInsensitiveContains($0) }) {
            message = "Gateway request failed. Check settings and try again."
        }
        return String(message.prefix(140))
    }
}

enum KeyboardActionOperationResultError: Error, Equatable {
    case invalidResponse
}

struct KeyboardRewriteOption: Equatable, Identifiable {
    let id: String
    let title: String
    let text: String
}

struct KeyboardActionOperationResult: Equatable {
    let operation: String
    let items: [Item]
    let summary: String?
    let correctedText: String?
    let isStructuredResponse: Bool
    let isNoChangeResult: Bool

    init(operation: String, items: [Item], summary: String? = nil, correctedText: String? = nil, isStructuredResponse: Bool = false, isNoChangeResult: Bool = false) {
        self.operation = operation
        self.items = items
        self.summary = summary
        self.correctedText = correctedText
        self.isStructuredResponse = isStructuredResponse
        self.isNoChangeResult = isNoChangeResult
    }

    func suggestionResponse(sourceText: String? = nil) -> KeyboardSuggestionResponse {
        let mappedCorrections = items.compactMap(\.correctionSuggestion)
        let corrections: [KeyboardCorrectionSuggestion]
        let safeCorrectedText: String?
        if let sourceText, !sourceText.isEmpty {
            corrections = mappedCorrections.filter { $0.isAtomicCorrection(for: sourceText) }
            safeCorrectedText = Self.textByApplying(corrections, to: sourceText)
        } else {
            corrections = mappedCorrections
            safeCorrectedText = correctedText
        }
        return KeyboardSuggestionResponse(
            corrections: corrections,
            predictions: [],
            correctedText: safeCorrectedText
        )
    }

    private static func textByApplying(_ corrections: [KeyboardCorrectionSuggestion], to sourceText: String) -> String? {
        let corrected = corrections.reduce(sourceText) { text, correction in
            correction.applying(to: text) ?? text
        }
        return corrected == sourceText ? nil : corrected
    }

    var displayText: String {
        if operation == "fix_grammar", let correctedText {
            return correctedText
        }
        if let correctedText, !correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let replacement = items.first(where: { ($0.replacement ?? "").isEmpty == false })?.replacement {
            return replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let text = items.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.text {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func rewriteOptions(sourceText: String, maxOptions: Int = 5) -> [KeyboardRewriteOption] {
        let normalizedSource = Self.normalizedCandidateKey(sourceText)
        var seen = Set<String>()
        var options: [KeyboardRewriteOption] = []

        func append(_ candidate: String?, title: String?) {
            guard options.count < maxOptions else { return }
            let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return }
            guard KeyboardReplacementTextSafety.isSafeReplacementText(text) else { return }
            let key = Self.normalizedCandidateKey(text)
            guard !key.isEmpty, key != normalizedSource, !seen.contains(key) else { return }
            seen.insert(key)

            let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let optionTitle = cleanTitle?.isEmpty == false ? cleanTitle ?? "" : "Option \(options.count + 1)"
            options.append(KeyboardRewriteOption(
                id: "rewrite-option-\(options.count + 1)",
                title: optionTitle,
                text: text
            ))
        }

        for item in items {
            append(item.replacement, title: item.title)
            append(item.text, title: item.title)
        }
        append(correctedText, title: "Suggested rewrite")
        append(displayText, title: "Suggested rewrite")

        return options
    }

    static func plainTextGrammarResponse(_ content: String, original: String) throws -> KeyboardActionOperationResult {
        let corrected = try GrammarCorrectionResponseValidator.validated(content, original: original)
        return KeyboardActionOperationResult(
            operation: "fix_grammar",
            items: [],
            correctedText: corrected,
            isNoChangeResult: corrected == original
        )
    }

    static func parse(_ content: String, operation: String, fallbackText: String) throws -> KeyboardActionOperationResult {
        guard operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "fix_grammar" else {
            throw KeyboardActionOperationResultError.invalidResponse
        }
        let stripped = stripMarkdownFence(content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { throw KeyboardActionOperationResultError.invalidResponse }
        if let structuredContent = try normalizedStructuredContent(from: stripped) {
            return try parseStructuredContent(structuredContent, operation: operation, fallbackText: fallbackText)
        }
        guard !isJSONLike(stripped) else { throw KeyboardActionOperationResultError.invalidResponse }
        let legacy = stripped
        guard !legacy.isEmpty, legacy != fallbackText.trimmingCharacters(in: .whitespacesAndNewlines) else { throw KeyboardActionOperationResultError.invalidResponse }
        return KeyboardActionOperationResult(
            operation: operation,
            items: [Item(id: "legacy-1", type: "correction", title: defaultTitle(for: "correction", operation: operation), text: legacy, original: fallbackText, replacement: legacy, category: "grammar")],
            summary: nil,
            correctedText: legacy
        )
    }

    private static func parseStructuredContent(_ content: String, operation: String, fallbackText: String) throws -> KeyboardActionOperationResult {
        guard let data = content.data(using: .utf8), let decoded = try? JSONDecoder().decode(Raw.self, from: data) else {
            throw KeyboardActionOperationResultError.invalidResponse
        }
        let items = decoded.decodedItems.enumerated().compactMap { index, raw -> Item? in
            let text = clean(raw.text ?? raw.replacement ?? raw.explanation ?? raw.title)
            guard let text, !text.isEmpty, !isNestedJSONLike(text) else { return nil }
            return Item(
                id: clean(raw.id) ?? "item-\(index + 1)",
                type: clean(raw.type) ?? "suggestion",
                title: clean(raw.title) ?? defaultTitle(for: raw.type, operation: decoded.operation ?? operation),
                text: text,
                original: clean(raw.original),
                replacement: clean(raw.replacement).flatMap { isNestedJSONLike($0) ? nil : $0 },
                range: raw.range,
                confidence: raw.confidence,
                explanation: clean(raw.explanation),
                category: clean(raw.category)
            )
        }
        let correctedText = clean(decoded.correctedText).flatMap { isNestedJSONLike($0) ? nil : $0 }
        let summary = clean(decoded.summary).flatMap { isNestedJSONLike($0) ? nil : $0 }
        let topLevelDisplayText = clean(decoded.topLevelDisplayText).flatMap { isNestedJSONLike($0) ? nil : $0 }
        if items.isEmpty, correctedText == nil, summary == nil, topLevelDisplayText == nil { throw KeyboardActionOperationResultError.invalidResponse }

        var canonicalItems = items
        if canonicalItems.isEmpty, let topLevelDisplayText {
            canonicalItems = [Item(
                id: "result-1",
                type: operation == "summarize" ? "summary" : "suggestion",
                title: defaultTitle(for: operation == "summarize" ? "summary" : "suggestion", operation: operation),
                text: topLevelDisplayText,
                replacement: topLevelDisplayText
            )]
        }

        let finalCorrectedText = correctedText ?? topLevelDisplayText
        return KeyboardActionOperationResult(operation: clean(decoded.operation) ?? operation, items: canonicalItems, summary: summary, correctedText: finalCorrectedText, isStructuredResponse: true)
    }

    private static func normalizedStructuredContent(from stripped: String, depth: Int = 0) throws -> String? {
        guard depth < 4 else { return nil }
        guard let data = stripped.data(using: .utf8) else { return nil }
        if let wrapped = try? JSONDecoder().decode(ChatCompletionWrapper.self, from: data),
           let content = wrapped.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            let nested = stripMarkdownFence(content).trimmingCharacters(in: .whitespacesAndNewlines)
            return try normalizedStructuredContent(from: nested, depth: depth + 1)
        }
        if isJSONObjectLike(stripped) { return stripped }
        if let jsonString = try? JSONDecoder().decode(String.self, from: data) {
            let nested = stripMarkdownFence(jsonString).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nested.isEmpty else { throw KeyboardActionOperationResultError.invalidResponse }
            if isJSONObjectLike(nested) { return nested }
            if isJSONLike(nested) { throw KeyboardActionOperationResultError.invalidResponse }
            return try normalizedStructuredContent(from: nested, depth: depth + 1)
        }
        return nil
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedCandidateKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private static func isNestedJSONLike(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isJSONLike(trimmed) else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
    }

    private static func isJSONObjectLike(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
    }

    private static func isJSONLike(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    private static func defaultTitle(for type: String?, operation: String) -> String {
        if operation == "fix_grammar" { return "Grammar correction" }
        if operation == "summarize" || type == "summary" { return "Summary" }
        if operation == "rewrite" { return "Rewrite" }
        if operation == "improve" { return "Improve" }
        return "Writing result"
    }

    private static func stripMarkdownFence(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return value }
        trimmed = trimmed.replacingOccurrences(of: "```json", with: "")
        trimmed = trimmed.replacingOccurrences(of: "```JSON", with: "")
        trimmed = trimmed.replacingOccurrences(of: "```", with: "")
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct Item: Equatable {
        let id: String
        let type: String
        let title: String
        let text: String
        let original: String?
        let replacement: String?
        let range: KeyboardTextRange?
        let confidence: Double?
        let explanation: String?
        let category: String?

        init(id: String, type: String, title: String, text: String, original: String? = nil, replacement: String? = nil, range: KeyboardTextRange? = nil, confidence: Double? = nil, explanation: String? = nil, category: String? = nil) {
            self.id = id
            self.type = type
            self.title = title
            self.text = text
            self.original = original
            self.replacement = replacement
            self.range = range
            self.confidence = confidence
            self.explanation = explanation
            self.category = category
        }

        var correctionSuggestion: KeyboardCorrectionSuggestion? {
            guard type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "correction" else { return nil }
            let cleanOriginal = original?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cleanReplacement = replacement?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cleanOriginal.isEmpty, !cleanReplacement.isEmpty else { return nil }
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanExplanation = explanation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return KeyboardCorrectionSuggestion(
                id: id,
                label: cleanTitle.isEmpty ? "Correct grammar" : cleanTitle,
                original: cleanOriginal,
                replacement: String(cleanReplacement.prefix(32)),
                explanation: cleanExplanation.isEmpty ? cleanText : cleanExplanation,
                category: cleanCategory?.isEmpty == false ? cleanCategory : type,
                range: range
            )
        }
    }

    private struct ChatCompletionWrapper: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String?
        }
    }

    private struct Raw: Decodable {
        let operation: String?
        let results: [RawItem]?
        let rawItems: [RawItem]?
        let rawResult: RawItem?
        let summary: String?
        let correctedText: String?
        let topLevelDisplayText: String?

        enum CodingKeys: String, CodingKey {
            case operation
            case results
            case rawItems = "items"
            case rawResult = "result"
            case summary
            case correctedText = "corrected_text"
            case correctedTextCamel = "correctedText"
            case rewrittenText = "rewritten_text"
            case rewrittenTextCamel = "rewrittenText"
            case improvedText = "improved_text"
            case improvedTextCamel = "improvedText"
            case replacement
            case text
            case output
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            operation = try? container.decode(String.self, forKey: .operation)
            results = try? container.decode([RawItem].self, forKey: .results)
            rawItems = try? container.decode([RawItem].self, forKey: .rawItems)
            rawResult = try? container.decode(RawItem.self, forKey: .rawResult)
            summary = try? container.decode(String.self, forKey: .summary)
            correctedText = Self.firstString(in: container, keys: [.correctedText, .correctedTextCamel])
            topLevelDisplayText = Self.firstString(in: container, keys: [.rawResult, .rewrittenText, .rewrittenTextCamel, .improvedText, .improvedTextCamel, .replacement, .text, .output])
        }

        var decodedItems: [RawItem] { results ?? rawItems ?? rawResult.map { [$0] } ?? [] }

        private static func firstString(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> String? {
            for key in keys {
                if let value = try? container.decodeIfPresent(String.self, forKey: key) { return value }
            }
            return nil
        }
    }

    private struct RawItem: Decodable {
        let id: String?
        let type: String?
        let title: String?
        let text: String?
        let original: String?
        let replacement: String?
        let range: KeyboardTextRange?
        let confidence: Double?
        let explanation: String?
        let category: String?

        enum CodingKeys: String, CodingKey {
            case id, type, title, text, original, replacement, range, confidence, explanation, category
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decode(String.self, forKey: .id)
            type = try? container.decode(String.self, forKey: .type)
            title = try? container.decode(String.self, forKey: .title)
            text = try? container.decode(String.self, forKey: .text)
            original = try? container.decode(String.self, forKey: .original)
            replacement = try? container.decode(String.self, forKey: .replacement)
            range = try? container.decode(KeyboardTextRange.self, forKey: .range)
            confidence = Self.decodeConfidence(from: container)
            explanation = try? container.decode(String.self, forKey: .explanation)
            category = try? container.decode(String.self, forKey: .category)
        }

        private static func decodeConfidence(from container: KeyedDecodingContainer<CodingKeys>) -> Double? {
            if let value = try? container.decode(Double.self, forKey: .confidence) { return value }
            guard let value = try? container.decode(String.self, forKey: .confidence) else { return nil }
            return Double(value)
        }
    }
}

enum KeyboardActionProductOutcome: Equatable {
    case showCorrections(KeyboardSuggestionResponse)
    case showRewriteOptions([KeyboardRewriteOption])
    case replaceText(String)
    case noChanges
    case noUsableResult
}

enum KeyboardActionResultHandler {
    static func outcome(operation: String, result: KeyboardActionOperationResult, sourceText: String = "") -> KeyboardActionProductOutcome {
        let normalizedOperation = operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedOperation == "fix_grammar" {
            guard let correctedText = result.correctedText else {
                return result.isNoChangeResult ? .noChanges : .noUsableResult
            }
            let edits = GrammarDiffService.edits(from: sourceText, to: correctedText)
            guard !edits.isEmpty else { return .noChanges }
            return .showCorrections(KeyboardSuggestionResponse(
                corrections: edits.map(\.suggestion),
                predictions: [],
                correctedText: correctedText
            ))
        }
        if normalizedOperation == "rewrite" {
            let options = result.rewriteOptions(sourceText: sourceText)
            guard !options.isEmpty else { return .noUsableResult }
            return .showRewriteOptions(options)
        }

        let displayText = result.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayText.isEmpty else { return .noUsableResult }
        guard KeyboardReplacementTextSafety.isSafeReplacementText(displayText) else { return .noUsableResult }
        return .replaceText(displayText)
    }
}

enum KeyboardReplacementTextSafety {
    static func isSafeReplacementText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        let unsafeErrorFragments = [
            "malformed json",
            "no safe keyboard text",
            "could be extracted",
            "gateway returned an invalid response",
            "invalid response",
            "gateway error",
            "network error",
            "server error",
            "unauthorized",
            "api key",
            "stack trace"
        ]
        return !unsafeErrorFragments.contains { normalized.contains($0) }
    }
}

enum KeyboardSuggestionParserError: Error, Equatable {
    case invalidJSON
}

enum KeyboardSuggestionParser {
    private static let compactLimit = 32
    private static let maxItems = 5

    static func parseAssistantContent(_ content: String) throws -> KeyboardSuggestionResponse {
        let stripped = stripMarkdownFence(content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = stripped.data(using: .utf8) else { throw KeyboardSuggestionParserError.invalidJSON }
        do {
            let decoded = try JSONDecoder().decode(RawResponse.self, from: data)
            let corrections = decoded.corrections.prefix(maxItems).compactMap(cleanCorrection)
            let remainingSlots = max(maxItems - corrections.count, 0)
            let canonicalCorrections = decoded.canonicalCorrectionItems.prefix(remainingSlots).compactMap(cleanOperationItemCorrection)
            return KeyboardSuggestionResponse(
                corrections: corrections + canonicalCorrections,
                predictions: decoded.usesStructuredOperationContract ? [] : decoded.predictions.prefix(maxItems).compactMap(cleanPrediction),
                correctedText: decoded.correctedText
            )
        } catch {
            throw KeyboardSuggestionParserError.invalidJSON
        }
    }

    static func prompt(for boundedContext: String) -> String {
        SemanticPromptContract.renderKeyboardSuggestions(input: boundedContext).messages.last?.content ?? ""
    }

    private static func stripMarkdownFence(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return value }
        trimmed = trimmed.replacingOccurrences(of: "```json", with: "")
        trimmed = trimmed.replacingOccurrences(of: "```JSON", with: "")
        trimmed = trimmed.replacingOccurrences(of: "```", with: "")
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanCorrection(_ raw: RawCorrection) -> KeyboardCorrectionSuggestion? {
        let label = clean(raw.label, fallback: "Correct grammar")
        let original = (raw.original ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = capped(raw.replacement ?? "")
        guard !original.isEmpty, !replacement.isEmpty else { return nil }
        let id = raw.id?.trimmingCharacters(in: .whitespacesAndNewlines)
        return KeyboardCorrectionSuggestion(id: id?.isEmpty == false ? id! : UUID().uuidString, label: label, original: original, replacement: replacement, explanation: raw.explanation?.trimmingCharacters(in: .whitespacesAndNewlines), category: raw.category?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func cleanPrediction(_ raw: RawPrediction) -> KeyboardPredictionSuggestion? {
        let text = capped(raw.text ?? "")
        guard !text.isEmpty else { return nil }
        return KeyboardPredictionSuggestion(label: clean(raw.label, fallback: "Suggestion"), text: text, kind: raw.kind?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func cleanOperationItemCorrection(_ raw: RawOperationItem) -> KeyboardCorrectionSuggestion? {
        let type = raw.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard type == "correction" else { return nil }
        let original = (raw.original ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = capped(raw.replacement ?? "")
        guard !original.isEmpty, !replacement.isEmpty else { return nil }
        let id = raw.id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = clean(raw.title ?? raw.text, fallback: "Correct grammar")
        return KeyboardCorrectionSuggestion(
            id: id?.isEmpty == false ? id! : UUID().uuidString,
            label: label,
            original: original,
            replacement: replacement,
            explanation: raw.explanation?.trimmingCharacters(in: .whitespacesAndNewlines),
            category: type
        )
    }

    private static func clean(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : capped(trimmed)
    }

    private static func capped(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(compactLimit))
    }

    private struct RawResponse: Decodable {
        let correctedText: String?
        let corrections: [RawCorrection]
        let predictions: [RawPrediction]
        let results: [RawOperationItem]
        let rawItems: [RawOperationItem]

        enum CodingKeys: String, CodingKey {
            case correctedText = "corrected_text"
            case corrections
            case predictions
            case results
            case rawItems = "items"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            correctedText = try? container.decode(String.self, forKey: .correctedText)
            corrections = (try? container.decode([RawCorrection].self, forKey: .corrections)) ?? []
            predictions = (try? container.decode([RawPrediction].self, forKey: .predictions)) ?? []
            results = (try? container.decode([RawOperationItem].self, forKey: .results)) ?? []
            rawItems = (try? container.decode([RawOperationItem].self, forKey: .rawItems)) ?? []
        }

        var canonicalCorrectionItems: [RawOperationItem] { results.isEmpty ? rawItems : results }
        var usesStructuredOperationContract: Bool { !results.isEmpty || !rawItems.isEmpty || correctedText != nil }
    }

    private struct RawCorrection: Decodable {
        let id: String?
        let label: String?
        let original: String?
        let replacement: String?
        let explanation: String?
        let category: String?
    }

    private struct RawPrediction: Decodable {
        let label: String?
        let text: String?
        let kind: String?
    }

    private struct RawOperationItem: Decodable {
        let id: String?
        let type: String?
        let title: String?
        let text: String?
        let original: String?
        let replacement: String?
        let explanation: String?
    }
}
