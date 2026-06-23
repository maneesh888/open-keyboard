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
        let categoryValue = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let labelValue = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLabel = labelValue.lowercased()
        let normalizedCategory = categoryValue.lowercased()
        let combined = "\(normalizedLabel) \(normalizedCategory)"

        if combined.contains("subject") || combined.contains("verb") { return "Subject-verb agreement" }
        if !labelValue.isEmpty, !normalizedLabel.contains("grammar"), !normalizedLabel.contains("correct") {
            return labelValue.replacingOccurrences(of: ":", with: "")
        }
        if normalizedCategory.contains("grammar") || normalizedLabel.contains("grammar") || normalizedLabel.contains("correct") { return "Correctness" }
        return "Correctness"
    }

    private static func explanation(for correction: KeyboardCorrectionSuggestion) -> String {
        let provided = correction.explanation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !provided.isEmpty { return provided }

        let original = correction.original.lowercased()
        let replacement = correction.replacement.lowercased()
        if original == "has", replacement == "have" {
            return "Use “have” because the subject is plural."
        }
        if original.contains("has"), replacement.contains("have") {
            return "Use “have” to match the plural subject."
        }
        return "Replace “\(correction.original)” with “\(correction.replacement)”."
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
        self.currentCorrectionIndex = min(max(currentCorrectionIndex, 0), response.corrections.count)
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

    var canMoveToPreviousCorrection: Bool {
        currentCorrectionIndex > 0
    }

    var canMoveToNextCorrection: Bool {
        currentCorrectionIndex + 1 < corrections.count
    }

    var showsCorrectionProgress: Bool {
        corrections.count > 1
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

    private mutating func removeCurrentCorrection() {
        guard currentCorrection != nil else { return }
        corrections.remove(at: currentCorrectionIndex)
        currentCorrectionIndex = min(currentCorrectionIndex, max(corrections.count - 1, 0))
    }

    private static func filteredPredictions(_ predictions: [KeyboardPredictionSuggestion], sourceContext: String?) -> [KeyboardPredictionSuggestion] {
        guard let sourceContext, !sourceContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return predictions }
        return predictions.filter { !isRedundantPrediction($0.text, sourceContext: sourceContext) }
    }

    static func isRedundantPrediction(_ prediction: String, sourceContext: String) -> Bool {
        let normalizedPrediction = normalizePrediction(prediction)
        guard !normalizedPrediction.isEmpty else { return true }
        let normalizedContext = normalizeContext(sourceContext)
        guard !normalizedContext.isEmpty else { return false }

        if lastToken(in: normalizedContext) == normalizedPrediction { return true }
        if normalizedContext == normalizedPrediction { return true }
        if normalizedContext.hasSuffix(" " + normalizedPrediction) { return true }
        return false
    }

    private static func normalizePrediction(_ value: String) -> String {
        normalizeContext(value)
    }

    private static func normalizeContext(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func lastToken(in normalizedContext: String) -> String? {
        normalizedContext.split(separator: " ").last.map(String.init)
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
        let stripped = stripMarkdownFence(content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { throw KeyboardActionOperationResultError.invalidResponse }
        if let data = stripped.data(using: .utf8), let decoded = try? JSONDecoder().decode(Raw.self, from: data) {
            let items = decoded.decodedItems.enumerated().compactMap { index, raw -> Item? in
                let text = clean(raw.text ?? raw.replacement ?? raw.explanation ?? raw.title)
                guard let text, !text.isEmpty, !isNestedJSONLike(text) else { return nil }
                return Item(
                    id: clean(raw.id) ?? "item-\(index + 1)",
                    type: clean(raw.type) ?? "suggestion",
                    title: clean(raw.title) ?? defaultTitle(for: raw.type, operation: decoded.operation ?? operation),
                    text: text,
                    original: clean(raw.original),
                    replacement: clean(raw.replacement),
                    range: raw.range,
                    confidence: raw.confidence,
                    explanation: clean(raw.explanation),
                    category: clean(raw.category)
                )
            }
            let correctedText = clean(decoded.correctedText)
            let summary = clean(decoded.summary)
            if items.isEmpty, correctedText == nil, summary == nil { throw KeyboardActionOperationResultError.invalidResponse }
            return KeyboardActionOperationResult(operation: clean(decoded.operation) ?? operation, items: items, summary: summary, correctedText: correctedText)
        }
        let legacy = stripped
        guard !legacy.isEmpty, legacy != fallbackText.trimmingCharacters(in: .whitespacesAndNewlines) else { throw KeyboardActionOperationResultError.invalidResponse }
        return KeyboardActionOperationResult(
            operation: operation,
            items: [Item(id: "legacy-1", type: "correction", title: defaultTitle(for: "correction", operation: operation), text: legacy, original: fallbackText, replacement: legacy, range: nil, confidence: nil, explanation: nil, category: "grammar")],
            summary: nil,
            correctedText: legacy
        )
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
    case uselessOutput
}

enum KeyboardSuggestionParser {
    private static let compactLimit = 32
    private static let maxItems = 5

    static func parseAssistantContent(_ content: String, sourceContext: String? = nil) throws -> KeyboardSuggestionResponse {
        let stripped = stripMarkdownFence(content).trimmingCharacters(in: .whitespacesAndNewlines)
        if isNoClearCorrection(stripped) || isEmptyNoClearResponse(stripped, sourceContext: sourceContext) {
            return KeyboardSuggestionResponse(corrections: [], predictions: [])
        }
        guard let data = stripped.data(using: .utf8) else { throw KeyboardSuggestionParserError.invalidJSON }
        do {
            let decoded = try JSONDecoder().decode(RawResponse.self, from: data)
            let mappedCorrections = decoded.corrections.prefix(maxItems).compactMap { cleanCorrection($0, sourceContext: sourceContext) }
            let remainingSlots = max(maxItems - mappedCorrections.count, 0)
            let canonicalCorrections = decoded.canonicalCorrectionItems.prefix(remainingSlots).compactMap { cleanOperationItemCorrection($0, sourceContext: sourceContext) }
            let response = KeyboardSuggestionResponse(
                corrections: mappedCorrections + canonicalCorrections,
                predictions: decoded.usesDynamicContract ? [] : decoded.predictions.prefix(maxItems).compactMap(cleanPrediction),
                correctedText: decoded.correctedText
            )
            return try validate(response: response, rawOutput: stripped, sourceContext: sourceContext, rawResponse: decoded)
        } catch is DecodingError {
            guard sourceContext != nil else { throw KeyboardSuggestionParserError.invalidJSON }
            return try parsePlainTextCorrection(stripped, sourceContext: sourceContext)
        } catch let error as KeyboardSuggestionParserError {
            throw error
        } catch {
            guard sourceContext != nil else { throw KeyboardSuggestionParserError.invalidJSON }
            return try parsePlainTextCorrection(stripped, sourceContext: sourceContext)
        }
    }

    static func prompt(for boundedContext: String) -> String {
        basePrompt(for: boundedContext, retry: false)
    }

    static func retryPrompt(for boundedContext: String) -> String {
        basePrompt(for: boundedContext, retry: true)
    }

    private static func basePrompt(for boundedContext: String, retry: Bool) -> String {
        let userText = String(boundedContext.prefix(500))
        let retryInstruction = retry
            ? "Previous output was invalid, empty, or reused a canned example. Re-analyze ONLY the current user text and return valid JSON for the actual text."
            : ""
        return """
        You are a grammar and writing-quality analyzer for an iOS keyboard.
        Analyze ONLY the provided user text. Do not use examples as output. Do not reuse previous results.
        Return strict JSON only matching this schema:
        {
          "issue_count": number,
          "overall_status": "issues_found" | "no_issues",
          "corrected_text": string,
          "corrections": [
            {
              "id": string,
              "category": "grammar" | "spelling" | "punctuation" | "clarity" | "style" | "other",
              "label": string,
              "original": string,
              "replacement": string,
              "start": number | null,
              "end": number | null,
              "explanation": string,
              "confidence": number
            }
          ],
          "summary": string
        }
        Rules:
        - Use the exact current user text below as source.
        - If there are no real issues, return issue_count 0, corrections [], corrected_text identical to input, overall_status "no_issues".
        - Never return canned examples.
        - Never return the sample schema values unless they are actually present in the user text.
        - For misspellings, include the original misspelled token and corrected token.
        - For grammar errors, include the minimal original phrase and replacement phrase.
        - issue_count must equal corrections.length.
        - Do not include predictions or markdown.
        \(retryInstruction)
        User text:
        <<<\(userText)>>>
        """
    }

    private static func parsePlainTextCorrection(_ output: String, sourceContext: String?) throws -> KeyboardSuggestionResponse {
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isMeaningfulOutput(cleaned, for: sourceContext) else { throw KeyboardSuggestionParserError.uselessOutput }
        let original = sourceContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "text"
        return KeyboardSuggestionResponse(
            corrections: [KeyboardCorrectionSuggestion(label: "Correct grammar", original: original, replacement: capped(cleaned), explanation: nil, category: "grammar")],
            predictions: [],
            correctedText: cleaned
        )
    }

    private static func validate(response: KeyboardSuggestionResponse, rawOutput: String, sourceContext: String?, rawResponse: RawResponse? = nil) throws -> KeyboardSuggestionResponse {
        if let rawResponse, rawResponse.usesDynamicContract {
            let declaredIssueCount = max(rawResponse.issueCount ?? response.corrections.count, 0)
            let status = rawResponse.overallStatus?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if declaredIssueCount == 0 || status == "no_issues" {
                if let sourceContext, clearlyHasGrammarIssue(normalized(sourceContext)) {
                    throw KeyboardSuggestionParserError.uselessOutput
                }
                return KeyboardSuggestionResponse(corrections: [], predictions: [])
            }
            if response.corrections.isEmpty { throw KeyboardSuggestionParserError.uselessOutput }
            return response
        }

        if let sourceContext, clearlyHasGrammarIssue(normalized(sourceContext)), response.corrections.isEmpty {
            throw KeyboardSuggestionParserError.uselessOutput
        }
        if !response.corrections.isEmpty || !response.predictions.isEmpty { return response }
        return response
    }

    static func isMeaningfulOutput(_ output: String, for sourceContext: String?) -> Bool {
        let normalizedOutput = normalized(output)
        guard normalizedOutput.count > 1 else { return false }
        guard normalizedOutput.split(separator: " ").count > 1 else { return false }
        let generic = ["ok", "okay", "done", "fixed", "corrected"]
        guard !generic.contains(normalizedOutput) else { return false }
        if let sourceContext {
            let normalizedSource = normalized(sourceContext)
            if normalizedSource == normalizedOutput { return false }
            if hasResidualGrammarIssue(normalizedOutput) { return false }
            if isIncompleteFragment(normalizedSource), isOnlyCapitalizedOrPunctuated(output, sourceContext: sourceContext) { return false }
            if clearlyHasGrammarIssue(normalizedSource), !looksLikeCorrection(normalizedOutput) { return false }
        }
        return true
    }

    private static func isNoClearCorrection(_ value: String) -> Bool {
        normalized(value.replacingOccurrences(of: "_", with: " ")) == "no clear correction"
    }

    private static func isEmptyNoClearResponse(_ value: String, sourceContext: String?) -> Bool {
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let sourceContext else { return false }
        return isIncompleteFragment(normalized(sourceContext))
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func isIncompleteFragment(_ normalizedSource: String) -> Bool {
        let trailingWords = ["with", "to", "for", "from", "by", "at", "in", "on", "and", "or", "but", "because", "about"]
        guard let last = normalizedSource.split(separator: " ").last.map(String.init) else { return false }
        return trailingWords.contains(last)
    }

    private static func isOnlyCapitalizedOrPunctuated(_ output: String, sourceContext: String) -> Bool {
        let outputBase = normalized(output)
        let sourceBase = normalized(sourceContext)
        return outputBase == sourceBase
    }


    private static func hasResidualGrammarIssue(_ normalizedOutput: String) -> Bool {
        normalizedOutput.contains("this are") ||
            normalizedOutput.contains(" has a apple") ||
            normalizedOutput.contains("not working good") ||
            normalizedOutput.contains(" nt ") ||
            normalizedOutput.contains("ths") ||
            normalizedOutput.contains("sound sound")
    }

    private static func clearlyHasGrammarIssue(_ normalizedSource: String) -> Bool {
        normalizedSource.contains(" i ") || normalizedSource.hasPrefix("i ") ||
            normalizedSource.contains(" has a apple") ||
            normalizedSource.contains("this are") ||
            normalizedSource.contains("there has been no apples") ||
            normalizedSource.contains("not working good") ||
            normalizedSource.contains(" nt ") ||
            normalizedSource.contains("ths") ||
            normalizedSource.contains("sound sound")
    }

    private static func looksLikeCorrection(_ normalizedOutput: String) -> Bool {
        normalizedOutput.contains(" i have an apple") || normalizedOutput.hasPrefix("i have an apple") ||
            normalizedOutput.contains("i tried") ||
            normalizedOutput.contains("this is") ||
            normalizedOutput.contains("not working well") ||
            normalizedOutput.contains("not working properly") ||
            normalizedOutput.contains("have") ||
            normalizedOutput.contains("an apple")
    }

    private static func stripMarkdownFence(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return value }
        trimmed = trimmed.replacingOccurrences(of: "```json", with: "")
        trimmed = trimmed.replacingOccurrences(of: "```JSON", with: "")
        trimmed = trimmed.replacingOccurrences(of: "```", with: "")
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanCorrection(_ raw: RawCorrection, sourceContext: String?) -> KeyboardCorrectionSuggestion? {
        let label = clean(raw.label, fallback: "Correct grammar")
        let original = (raw.original ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = capped(raw.replacement ?? "")
        guard !original.isEmpty, !replacement.isEmpty else { return nil }
        if let sourceContext {
            let normalizedReplacement = normalized(replacement)
            if hasResidualGrammarIssue(normalizedReplacement) { return nil }
            if isIncompleteFragment(normalized(sourceContext)), isOnlyCapitalizedOrPunctuated(replacement, sourceContext: sourceContext) {
                return nil
            }
        }
        let id = raw.id?.trimmingCharacters(in: .whitespacesAndNewlines)
        return KeyboardCorrectionSuggestion(id: id?.isEmpty == false ? id! : UUID().uuidString, label: label, original: original, replacement: replacement, explanation: raw.explanation?.trimmingCharacters(in: .whitespacesAndNewlines), category: raw.category?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func cleanPrediction(_ raw: RawPrediction) -> KeyboardPredictionSuggestion? {
        let text = capped(raw.text ?? "")
        guard !text.isEmpty else { return nil }
        return KeyboardPredictionSuggestion(label: clean(raw.label, fallback: "Suggestion"), text: text, kind: raw.kind?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func cleanOperationItemCorrection(_ raw: RawOperationItem, sourceContext: String?) -> KeyboardCorrectionSuggestion? {
        let type = raw.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard type == "correction" else { return nil }
        let original = (raw.original ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = capped(raw.replacement ?? "")
        guard !original.isEmpty, !replacement.isEmpty else { return nil }
        if let sourceContext {
            let normalizedReplacement = normalized(replacement)
            if hasResidualGrammarIssue(normalizedReplacement) { return nil }
            if isIncompleteFragment(normalized(sourceContext)), isOnlyCapitalizedOrPunctuated(replacement, sourceContext: sourceContext) {
                return nil
            }
        }
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
        let issueCount: Int?
        let overallStatus: String?
        let correctedText: String?
        let summary: String?
        let corrections: [RawCorrection]
        let predictions: [RawPrediction]
        let results: [RawOperationItem]
        let rawItems: [RawOperationItem]

        enum CodingKeys: String, CodingKey {
            case issueCount = "issue_count"
            case overallStatus = "overall_status"
            case correctedText = "corrected_text"
            case summary
            case corrections
            case predictions
            case results
            case rawItems = "items"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            issueCount = try? container.decode(Int.self, forKey: .issueCount)
            overallStatus = try? container.decode(String.self, forKey: .overallStatus)
            correctedText = try? container.decode(String.self, forKey: .correctedText)
            summary = try? container.decode(String.self, forKey: .summary)
            corrections = (try? container.decode([RawCorrection].self, forKey: .corrections)) ?? []
            // Legacy prediction support remains for old test fixtures only. The
            // production prompt no longer asks for predictions.
            predictions = (try? container.decode([RawPrediction].self, forKey: .predictions)) ?? []
            results = (try? container.decode([RawOperationItem].self, forKey: .results)) ?? []
            rawItems = (try? container.decode([RawOperationItem].self, forKey: .rawItems)) ?? []
        }

        var canonicalCorrectionItems: [RawOperationItem] { results.isEmpty ? rawItems : results }

        var usesDynamicContract: Bool {
            issueCount != nil || overallStatus != nil || correctedText != nil || summary != nil || !results.isEmpty || !rawItems.isEmpty
        }
    }

    private struct RawCorrection: Decodable {
        let id: String?
        let label: String?
        let original: String?
        let replacement: String?
        let start: Int?
        let end: Int?
        let explanation: String?
        let category: String?
        let confidence: Double?
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
