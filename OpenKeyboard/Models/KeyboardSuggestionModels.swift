//
//  KeyboardSuggestionModels.swift
//  OpenKeyboard
//
//  Structured corrections + predictions for keyboard suggestion UI.
//

import Foundation

enum KeyboardGatewayActionContract {
    static let structuredSystemPrompt = """
    You are an iOS keyboard text editing assistant. Return strict JSON only.
    Contract: {"operation":"fix_grammar|summarize|rewrite","results":[{"id":"...","type":"correction|suggestion|summary|warning|explanation","title":"...","text":"...","original":"...","replacement":"...","range":{"start":0,"end":0},"confidence":0.0,"explanation":"...","category":"..."}],"summary":"...","corrected_text":"..."}
    Use the requested operation and current text only. Unknown item types are allowed. Do not include markdown.
    """

    static func prompt(operation: String, text: String) -> String {
        switch operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "fix_grammar":
            return """
            Operation: fix_grammar
            Analyze this text and return structured JSON with a results array of correction items. Include category on each correction when possible. Preserve the original meaning and include corrected_text when you can safely produce the full corrected text.

            Text:
            \(text)
            """
        case "rewrite":
            return """
            Operation: rewrite
            Rewrite this text in a clear, friendly tone. Return structured JSON with a rewrite/suggestion item and corrected_text for the full replacement.

            Text:
            \(text)
            """
        case "summarize":
            return """
            Operation: summarize
            Summarize this text concisely. Return structured JSON with a summary item.

            Text:
            \(text)
            """
        case "improve":
            return """
            Operation: rewrite
            Improve this text for clarity, tone, and readability. Preserve the original meaning and return structured JSON with a rewrite/suggestion item and corrected_text for the full replacement.

            Text:
            \(text)
            """
        default:
            return """
            Operation: \(operation)
            Return structured JSON for this keyboard writing operation.

            Text:
            \(text)
            """
        }
    }

    static func maxTokens(operation: String) -> Int {
        switch operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "fix_grammar":
            return 5_000
        case "rewrite", "improve":
            return 3_000
        case "summarize":
            return 2_000
        default:
            return 2_000
        }
    }
}

struct KeyboardSuggestionResponse: Equatable {
    let corrections: [KeyboardCorrectionSuggestion]
    let predictions: [KeyboardPredictionSuggestion]
    let correctedText: String?

    init(corrections: [KeyboardCorrectionSuggestion], predictions: [KeyboardPredictionSuggestion], correctedText: String? = nil) {
        self.corrections = corrections
        self.predictions = predictions
        let trimmed = correctedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.correctedText = trimmed.isEmpty ? nil : trimmed
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

struct KeyboardTextRange: Equatable, Decodable {
    let start: Int
    let end: Int
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

    init(response: KeyboardSuggestionResponse, sourceContext: String? = nil, currentCorrectionIndex: Int = 0) {
        self.corrections = response.corrections
        self.predictions = Self.filteredPredictions(response.predictions, sourceContext: sourceContext)
        self.correctedText = response.correctedText
        if response.corrections.isEmpty {
            self.currentCorrectionIndex = 0
        } else {
            self.currentCorrectionIndex = min(max(currentCorrectionIndex, 0), response.corrections.count - 1)
        }
    }

    var currentCorrection: KeyboardCorrectionSuggestion? {
        guard currentCorrectionIndex < corrections.count else { return nil }
        return corrections[currentCorrectionIndex]
    }

    var currentPrediction: KeyboardPredictionSuggestion? { predictions.first }

    var remainingCorrectionCount: Int {
        corrections.count
    }

    var correctionCount: Int {
        corrections.count
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
        currentCorrectionIndex > 0
    }

    var canMoveToNextCorrection: Bool {
        currentCorrectionIndex + 1 < corrections.count
    }

    var isComplete: Bool {
        currentCorrection == nil && predictions.isEmpty
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
        guard canMoveToPreviousCorrection else { return }
        currentCorrectionIndex -= 1
    }

    mutating func moveToNextCorrection() {
        guard canMoveToNextCorrection else { return }
        currentCorrectionIndex += 1
    }

    mutating func applyCurrentCorrection() {
        removeCurrentCorrection()
    }

    mutating func dismissCurrentCorrection() {
        removeCurrentCorrection()
    }

    func textByApplyingCurrentCorrection(to text: String) -> String? {
        guard let correction = currentCorrection else { return nil }
        return correction.applying(to: text)
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

struct KeyboardActionErrorState: Equatable {
    let title: String
    let message: String

    init(title: String = "Gateway error", message: String) {
        self.title = title
        self.message = Self.sanitized(message)
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

    func suggestionResponse() -> KeyboardSuggestionResponse {
        KeyboardSuggestionResponse(
            corrections: items.compactMap(\.correctionSuggestion),
            predictions: [],
            correctedText: correctedText
        )
    }

    var displayText: String {
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

    var isStructuredGrammarNoChange: Bool {
        isStructuredResponse && (isNoChangeResult || (correctedText == nil && !items.contains { $0.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "correction" }))
    }

    static func parse(_ content: String, operation: String, fallbackText: String) throws -> KeyboardActionOperationResult {
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
        let hasCorrections = canonicalItems.contains { $0.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "correction" }
        let trimmedFinalText = finalCorrectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFallbackText = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNoChangeResult = operation == "fix_grammar" && !hasCorrections && (trimmedFinalText == nil || trimmedFinalText == trimmedFallbackText)

        return KeyboardActionOperationResult(operation: clean(decoded.operation) ?? operation, items: canonicalItems, summary: summary, correctedText: finalCorrectedText, isStructuredResponse: true, isNoChangeResult: isNoChangeResult)
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
            return KeyboardCorrectionSuggestion(
                id: id,
                label: cleanTitle.isEmpty ? "Correct grammar" : cleanTitle,
                original: cleanOriginal,
                replacement: String(cleanReplacement.prefix(32)),
                explanation: explanation?.trimmingCharacters(in: .whitespacesAndNewlines),
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
            operation = try container.decodeIfPresent(String.self, forKey: .operation)
            results = try container.decodeIfPresent([RawItem].self, forKey: .results)
            rawItems = try container.decodeIfPresent([RawItem].self, forKey: .rawItems)
            rawResult = try? container.decodeIfPresent(RawItem.self, forKey: .rawResult)
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
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
            let response = result.suggestionResponse()
            if !response.corrections.isEmpty {
                return .showCorrections(response)
            }
            if result.isStructuredGrammarNoChange {
                return .noChanges
            }
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
        """
        Analyze this bounded keyboard context and return strict JSON only. Do not include markdown or explanations outside JSON.
        Return corrections and predictions separately using this schema:
        {"corrections":[{"label":"Correct capitalization","original":"i","replacement":"I","explanation":"Capitalize the pronoun I.","category":"capitalization"}],"predictions":[{"label":"Suggestion","text":"apple","kind":"nextWord"}]}
        Corrections modify existing text. Predictions are optional next-word/phrase/synonym suggestions. Keep replacements and prediction text short for a compact keyboard bar.
        Context:
        \(String(boundedContext.prefix(500)))
        """
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
