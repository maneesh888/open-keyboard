//
//  KeyboardSuggestionModels.swift
//  OpenKeyboard
//
//  Structured corrections + predictions for keyboard suggestion UI.
//

import Foundation

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

    init(id: String = UUID().uuidString, label: String, original: String, replacement: String, explanation: String? = nil, category: String? = nil) {
        self.id = id
        self.label = label
        self.original = original
        self.replacement = replacement
        self.explanation = explanation
        self.category = category
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

struct KeyboardSuggestionState: Equatable {
    private(set) var corrections: [KeyboardCorrectionSuggestion]
    let predictions: [KeyboardPredictionSuggestion]
    let correctedText: String?
    private(set) var currentCorrectionIndex: Int

    init(response: KeyboardSuggestionResponse, currentCorrectionIndex: Int = 0) {
        self.corrections = response.corrections
        self.predictions = response.predictions
        self.correctedText = response.correctedText
        self.currentCorrectionIndex = min(max(currentCorrectionIndex, 0), response.corrections.count)
    }

    var currentCorrection: KeyboardCorrectionSuggestion? {
        guard currentCorrectionIndex < corrections.count else { return nil }
        return corrections[currentCorrectionIndex]
    }

    var currentPrediction: KeyboardPredictionSuggestion? { predictions.first }

    var remainingCorrectionCount: Int {
        max(corrections.count - currentCorrectionIndex, 0)
    }

    var correctionCount: Int {
        corrections.count
    }

    var isComplete: Bool {
        remainingCorrectionCount == 0 && predictions.isEmpty
    }

    var compactCorrectionReplacement: String? {
        currentCorrection?.replacement
    }

    var compactPredictionText: String? {
        currentPrediction?.text
    }

    mutating func applyCurrentCorrection() {
        guard currentCorrection != nil else { return }
        currentCorrectionIndex = min(currentCorrectionIndex + 1, corrections.count)
    }

    mutating func dismissCurrentCorrection() {
        guard currentCorrection != nil else { return }
        currentCorrectionIndex = min(currentCorrectionIndex + 1, corrections.count)
    }

    func textByApplyingCurrentCorrection(to text: String) -> String? {
        guard let correction = currentCorrection else { return nil }
        return correction.applying(to: text)
    }
}

extension KeyboardCorrectionSuggestion {
    func applying(to text: String) -> String? {
        guard !original.isEmpty, !replacement.isEmpty else { return nil }
        guard let range = text.range(of: original) else { return nil }
        return text.replacingCharacters(in: range, with: replacement)
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

struct KeyboardActionOperationResult: Equatable {
    let operation: String
    let items: [Item]
    let summary: String?
    let correctedText: String?

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

    static func parse(_ content: String, operation: String, fallbackText: String) throws -> KeyboardActionOperationResult {
        let stripped = try normalizedStructuredContent(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { throw KeyboardActionOperationResultError.invalidResponse }
        if let data = stripped.data(using: .utf8), let decoded = try? JSONDecoder().decode(Raw.self, from: data) {
            let items = decoded.decodedItems.enumerated().compactMap { index, raw -> Item? in
                let text = clean(raw.text ?? raw.replacement ?? raw.explanation ?? raw.title)
                guard let text, !text.isEmpty, !isNestedJSONLike(text) else { return nil }
                let replacement = clean(raw.replacement)
                return Item(
                    id: clean(raw.id) ?? "item-\(index + 1)",
                    type: clean(raw.type) ?? "suggestion",
                    title: clean(raw.title) ?? defaultTitle(for: raw.type, operation: decoded.operation ?? operation),
                    text: text,
                    original: clean(raw.original),
                    replacement: replacement.flatMap { isNestedJSONLike($0) ? nil : $0 },
                    range: raw.range,
                    confidence: raw.confidence,
                    explanation: clean(raw.explanation),
                    category: clean(raw.category)
                )
            }
            let correctedText = clean(decoded.correctedText).flatMap { isNestedJSONLike($0) ? nil : $0 }
            let summary = clean(decoded.summary).flatMap { isNestedJSONLike($0) ? nil : $0 }
            if items.isEmpty, correctedText == nil, summary == nil { throw KeyboardActionOperationResultError.invalidResponse }
            return KeyboardActionOperationResult(operation: clean(decoded.operation) ?? operation, items: items, summary: summary, correctedText: correctedText)
        }
        guard !isNestedJSONLike(stripped) else { throw KeyboardActionOperationResultError.invalidResponse }
        let legacy = stripped
        guard !legacy.isEmpty, legacy != fallbackText.trimmingCharacters(in: .whitespacesAndNewlines) else { throw KeyboardActionOperationResultError.invalidResponse }
        return KeyboardActionOperationResult(
            operation: operation,
            items: [Item(id: "legacy-1", type: "correction", title: defaultTitle(for: "correction", operation: operation), text: legacy, original: fallbackText, replacement: legacy, category: "grammar")],
            summary: nil,
            correctedText: legacy
        )
    }

    private static func normalizedStructuredContent(from content: String, depth: Int = 0) throws -> String {
        let stripped = stripMarkdownFence(content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { throw KeyboardActionOperationResultError.invalidResponse }
        guard depth < 4 else { return stripped }
        guard let data = stripped.data(using: .utf8) else { return stripped }
        if let jsonString = try? JSONDecoder().decode(String.self, from: data) {
            return try normalizedStructuredContent(from: jsonString, depth: depth + 1)
        }
        if let wrapped = try? JSONDecoder().decode(ChatCompletionWrapper.self, from: data),
           let content = wrapped.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return try normalizedStructuredContent(from: content, depth: depth + 1)
        }
        return stripped
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isNestedJSONLike(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
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
        let range: TextRange?
        let confidence: Double?
        let explanation: String?
        let category: String?

        init(id: String, type: String, title: String, text: String, original: String? = nil, replacement: String? = nil, range: TextRange? = nil, confidence: Double? = nil, explanation: String? = nil, category: String? = nil) {
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
                category: cleanCategory?.isEmpty == false ? cleanCategory : type
            )
        }
    }

    struct TextRange: Equatable, Decodable {
        let start: Int
        let end: Int
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
        let summary: String?
        let correctedText: String?

        enum CodingKeys: String, CodingKey {
            case operation
            case results
            case rawItems = "items"
            case summary
            case correctedText = "corrected_text"
        }

        var decodedItems: [RawItem] { results ?? rawItems ?? [] }
    }

    private struct RawItem: Decodable {
        let id: String?
        let type: String?
        let title: String?
        let text: String?
        let original: String?
        let replacement: String?
        let range: TextRange?
        let confidence: Double?
        let explanation: String?
        let category: String?
    }
}

enum KeyboardActionProductOutcome: Equatable {
    case showCorrections(KeyboardSuggestionResponse)
    case replaceText(String)
    case noUsableResult
}

enum KeyboardActionResultHandler {
    static func outcome(operation: String, result: KeyboardActionOperationResult) -> KeyboardActionProductOutcome {
        let normalizedOperation = operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedOperation == "fix_grammar" {
            let response = result.suggestionResponse()
            if !response.corrections.isEmpty {
                return .showCorrections(response)
            }
        }

        let displayText = result.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayText.isEmpty else { return .noUsableResult }
        return .replaceText(displayText)
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
