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
    private(set) var currentCorrectionIndex: Int

    init(response: KeyboardSuggestionResponse, currentCorrectionIndex: Int = 0) {
        self.corrections = response.corrections
        self.predictions = response.predictions
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
            return KeyboardSuggestionResponse(
                corrections: decoded.corrections.prefix(maxItems).compactMap(cleanCorrection),
                predictions: decoded.predictions.prefix(maxItems).compactMap(cleanPrediction)
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
        return KeyboardCorrectionSuggestion(label: label, original: original, replacement: replacement, explanation: raw.explanation?.trimmingCharacters(in: .whitespacesAndNewlines), category: raw.category?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func cleanPrediction(_ raw: RawPrediction) -> KeyboardPredictionSuggestion? {
        let text = capped(raw.text ?? "")
        guard !text.isEmpty else { return nil }
        return KeyboardPredictionSuggestion(label: clean(raw.label, fallback: "Suggestion"), text: text, kind: raw.kind?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func clean(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : capped(trimmed)
    }

    private static func capped(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(compactLimit))
    }

    private struct RawResponse: Decodable {
        let corrections: [RawCorrection]
        let predictions: [RawPrediction]

        enum CodingKeys: String, CodingKey { case corrections, predictions }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            corrections = (try? container.decode([RawCorrection].self, forKey: .corrections)) ?? []
            predictions = (try? container.decode([RawPrediction].self, forKey: .predictions)) ?? []
        }
    }

    private struct RawCorrection: Decodable {
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
}
