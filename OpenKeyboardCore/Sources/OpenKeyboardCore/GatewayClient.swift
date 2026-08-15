import Foundation
import SemanticPromptContract

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var statusCode: Int
    public var data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}


public struct WritingActionResult: Equatable, Sendable {
    public var operation: String
    public var items: [WritingActionResultItem]
    public var summary: String?
    public var correctedText: String?
    public var isStructuredResponse: Bool
    public var isNoChangeResult: Bool

    public init(operation: String, items: [WritingActionResultItem], summary: String? = nil, correctedText: String? = nil, isStructuredResponse: Bool = false, isNoChangeResult: Bool = false) {
        self.operation = operation
        self.items = items
        self.summary = summary
        self.correctedText = correctedText
        self.isStructuredResponse = isStructuredResponse
        self.isNoChangeResult = isNoChangeResult
    }

    public var displayText: String {
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
}

public struct WritingActionResultItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var type: String
    public var title: String
    public var text: String
    public var original: String?
    public var replacement: String?
    public var range: WritingActionTextRange?
    public var confidence: Double?
    public var explanation: String?

    public init(id: String, type: String, title: String, text: String, original: String? = nil, replacement: String? = nil, range: WritingActionTextRange? = nil, confidence: Double? = nil, explanation: String? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.text = text
        self.original = original
        self.replacement = replacement
        self.range = range
        self.confidence = confidence
        self.explanation = explanation
    }
}

public struct WritingActionTextRange: Equatable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public final class GatewayClient: Sendable {
    private let config: GatewayConfig
    private let httpClient: HTTPClient

    public init(config: GatewayConfig, httpClient: HTTPClient) {
        self.config = config.normalized()
        self.httpClient = httpClient
    }

    public func checkHealth() async throws -> Bool {
        let response = try await send(request(path: "/health", method: "GET"))
        try mapStatus(response.statusCode)

        if response.data.isEmpty {
            return true
        }

        guard let health = try? JSONDecoder().decode(HealthResponse.self, from: response.data) else {
            throw GatewayClientError.invalidResponse
        }
        return health.status == "ok"
    }

    public func fetchModels() async throws -> [String] {
        let response = try await send(request(path: "/v1/models", method: "GET"))
        try mapStatus(response.statusCode)

        guard let models = try? JSONDecoder().decode(ModelsResponse.self, from: response.data) else {
            throw GatewayClientError.invalidResponse
        }

        return models.data.map(\.id)
    }

    public func performWritingAction(_ action: WritingAction, text: String, model: String) async throws -> String {
        let result = try await performWritingActionResult(action, text: text, model: model)
        if action == .fixGrammar, let correctedText = result.correctedText {
            return correctedText
        }
        let displayText = result.displayText
        guard !displayText.isEmpty else { throw GatewayClientError.invalidResponse }
        return displayText
    }

    public func performWritingActionResult(_ action: WritingAction, text: String, model: String) async throws -> WritingActionResult {
        let prompt = WritingPromptBuilder.prompt(for: action, text: text)
        let rendering = WritingPromptBuilder.rendering(for: action, text: text)
        let payload = ChatCompletionRequest(
            model: model,
            operation: action.operationName,
            inputText: text,
            messages: [
                ChatMessage(
                    role: "system",
                    content: rendering?.messages.first?.content
                        ?? SemanticPromptContract.unstructuredWritingSystemInstruction
                ),
                ChatMessage(role: "user", content: prompt)
            ],
            responseFormat: rendering?.responseFormatType == "json_object" ? .jsonObject : nil,
            maxTokens: rendering?.maxTokens,
            temperature: rendering?.temperature,
            stream: false
        )

        guard let body = try? JSONEncoder().encode(payload) else {
            throw GatewayClientError.invalidResponse
        }

        var chatRequest = request(path: "/v1/chat/completions", method: "POST", body: body)
        chatRequest.headers["Content-Type"] = "application/json"

        let response = try await send(chatRequest)
        try mapStatus(response.statusCode)

        guard let completion = try? JSONDecoder().decode(ChatCompletionResponse.self, from: response.data),
              let choice = completion.choices.first,
              choice.finishReason != "length" else {
            throw GatewayClientError.invalidResponse
        }

        return try Self.parseWritingActionResult(choice.message.content, operation: action.operationName, fallbackText: text)
    }

    private static func parseWritingActionResult(_ content: String, operation: String, fallbackText: String) throws -> WritingActionResult {
        if operation == "fix_grammar" {
            let corrected = try validatedPlainTextGrammarResponse(content, original: fallbackText)
            return WritingActionResult(
                operation: operation,
                items: [],
                correctedText: corrected,
                isNoChangeResult: corrected == fallbackText
            )
        }
        let trimmed = stripMarkdownFence(content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GatewayClientError.invalidResponse }
        if let structuredContent = try normalizedStructuredContent(from: trimmed) {
            return try parseStructuredWritingActionResult(structuredContent, operation: operation, fallbackText: fallbackText)
        }
        guard !isJSONLike(trimmed) else { throw GatewayClientError.invalidResponse }
        let legacy = trimmed
        guard !legacy.isEmpty, legacy != fallbackText.trimmingCharacters(in: .whitespacesAndNewlines) else { throw GatewayClientError.invalidResponse }
        return WritingActionResult(
            operation: operation,
            items: [WritingActionResultItem(id: "legacy-1", type: "correction", title: defaultTitle(for: "correction", operation: operation), text: legacy, original: fallbackText, replacement: legacy)],
            correctedText: legacy
        )
    }

    private static func parseStructuredWritingActionResult(_ content: String, operation: String, fallbackText: String) throws -> WritingActionResult {
        guard let data = content.data(using: .utf8), let decoded = try? JSONDecoder().decode(RawWritingActionResult.self, from: data) else {
            throw GatewayClientError.invalidResponse
        }
        let items = decoded.decodedItems.enumerated().compactMap { index, raw -> WritingActionResultItem? in
            let text = clean(raw.text ?? raw.replacement ?? raw.explanation ?? raw.title)
            let title = clean(raw.title) ?? Self.defaultTitle(for: raw.type, operation: decoded.operation ?? operation)
            guard let text, !text.isEmpty, !Self.isNestedJSONLike(text) else { return nil }
            return WritingActionResultItem(
                id: clean(raw.id) ?? "item-\(index + 1)",
                type: clean(raw.type) ?? "suggestion",
                title: title,
                text: text,
                original: clean(raw.original),
                replacement: clean(raw.replacement),
                range: raw.range,
                confidence: raw.confidence,
                explanation: clean(raw.explanation)
            )
        }
        let correctedText = clean(decoded.correctedText)
        let summary = clean(decoded.summary)
        let topLevelDisplayText = clean(decoded.topLevelDisplayText)
        if items.isEmpty, correctedText == nil, summary == nil, topLevelDisplayText == nil { throw GatewayClientError.invalidResponse }

        var canonicalItems = items
        if canonicalItems.isEmpty, let topLevelDisplayText {
            canonicalItems = [WritingActionResultItem(
                id: "result-1",
                type: operation == "summarize" ? "summary" : "suggestion",
                title: Self.defaultTitle(for: operation == "summarize" ? "summary" : "suggestion", operation: operation),
                text: topLevelDisplayText,
                replacement: topLevelDisplayText
            )]
        }

        let finalCorrectedText = correctedText ?? topLevelDisplayText
        return WritingActionResult(operation: clean(decoded.operation) ?? operation, items: canonicalItems, summary: summary, correctedText: finalCorrectedText, isStructuredResponse: true)
    }

    private static func normalizedStructuredContent(from trimmed: String) throws -> String? {
        if isJSONObjectLike(trimmed) { return trimmed }
        guard let data = trimmed.data(using: .utf8),
              let decodedString = try? JSONDecoder().decode(String.self, from: data) else {
            return nil
        }
        let nested = stripMarkdownFence(decodedString).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nested.isEmpty else { throw GatewayClientError.invalidResponse }
        if isJSONObjectLike(nested) { return nested }
        if isJSONLike(nested) { throw GatewayClientError.invalidResponse }
        return nil
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

    private static func validatedPlainTextGrammarResponse(_ response: String, original: String) throws -> String {
        guard !response.isEmpty,
              !response.unicodeScalars.contains(where: { $0.value == 0xFFFD }) else {
            throw GatewayClientError.invalidResponse
        }
        let inspection = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let originalInspection = original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let invalidPrefixes = ["```", "{", "["]
        let corrected = restoringOriginalBoundaryWhitespace(in: response, original: original)
        guard !invalidPrefixes.contains(where: inspection.hasPrefix),
              !hasNewGrammarCommentaryPrefix(inspection, original: originalInspection),
              !hasNewGrammarCommentarySuffix(inspection, original: originalInspection),
              preservesNewlineStructure(original: original, corrected: corrected) else {
            throw GatewayClientError.invalidResponse
        }
        if original.count >= 80, corrected.count < original.count * 3 / 5 {
            throw GatewayClientError.invalidResponse
        }
        if corrected == original { return corrected }
        let originalWords = grammarWords(in: original)
        let responseWords = grammarWords(in: corrected)
        guard !hasSuspiciousBoundaryWordChange(originalWords: originalWords, responseWords: responseWords) else {
            throw GatewayClientError.invalidResponse
        }
        guard !hasSuspiciousBoundarySentenceSubstitution(original: original, corrected: corrected) else {
            throw GatewayClientError.invalidResponse
        }
        let approximatelyPreservedWords = originalWords.filter { sourceWord in
            responseWords.contains { candidate in
                grammarWordEditDistance(sourceWord, candidate) <= max(2, max(sourceWord.count, candidate.count) / 3)
            }
        }.count
        guard approximatelyPreservedWords >= max(1, min(originalWords.count, responseWords.count) / 2) else {
            throw GatewayClientError.invalidResponse
        }
        return corrected
    }

    private static func hasSuspiciousBoundaryWordChange(
        originalWords: [String],
        responseWords: [String]
    ) -> Bool {
        if responseWords.count < originalWords.count {
            return grammarWordsApproximatelyMatch(responseWords, Array(originalWords.prefix(responseWords.count))) ||
                grammarWordsApproximatelyMatch(responseWords, Array(originalWords.suffix(responseWords.count)))
        }
        if responseWords.count > originalWords.count {
            return grammarWordsApproximatelyMatch(originalWords, Array(responseWords.prefix(originalWords.count))) ||
                grammarWordsApproximatelyMatch(originalWords, Array(responseWords.suffix(originalWords.count)))
        }
        return false
    }

    private static func grammarWordsApproximatelyMatch(_ lhs: [String], _ rhs: [String]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            grammarWordEditDistance(left, right) <= max(2, max(left.count, right.count) / 3)
        }
    }

    private static func hasNewGrammarCommentarySuffix(_ corrected: String, original: String) -> Bool {
        let correctedWords = grammarWords(in: corrected)
        let originalWords = grammarWords(in: original)
        let commentarySuffixes = [
            "hope this helps", "happy to help", "let me know", "thank you", "thanks",
            "sure thing", "all set", "sure", "okay", "ok", "done", "enjoy"
        ]
        return commentarySuffixes.contains { suffix in
            let suffixWords = grammarWords(in: suffix)
            guard correctedWords.count >= suffixWords.count,
                  Array(correctedWords.suffix(suffixWords.count)) == suffixWords else {
                return false
            }
            let originalTail = Array(originalWords.suffix(suffixWords.count))
            return originalTail.count != suffixWords.count ||
                !grammarWordsApproximatelyMatch(originalTail, suffixWords)
        }
    }

    private static func hasNewGrammarCommentaryPrefix(_ corrected: String, original: String) -> Bool {
        let correctedWords = grammarWords(in: corrected)
        let originalWords = grammarWords(in: original)
        let commentaryPrefixes = [
            "here is", "here's", "corrected text", "the corrected", "i corrected",
            "sure thing", "of course", "sure", "certainly", "okay", "ok", "done", "correction"
        ]
        return commentaryPrefixes.contains { prefix in
            let prefixWords = grammarWords(in: prefix)
            guard correctedWords.count >= prefixWords.count,
                  Array(correctedWords.prefix(prefixWords.count)) == prefixWords else {
                return false
            }
            let originalHead = Array(originalWords.prefix(prefixWords.count))
            return originalHead.count != prefixWords.count ||
                !grammarWordsApproximatelyMatch(originalHead, prefixWords)
        }
    }

    private struct GrammarWordOccurrence {
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
            grammarLeadingWhitespace(in: sourceLine) == grammarLeadingWhitespace(in: correctedLine) &&
            grammarTrailingWhitespace(in: sourceLine) == grammarTrailingWhitespace(in: correctedLine) &&
            preservesProtectedGrammarStructure(original: sourceLine, corrected: correctedLine) &&
            !hasUnanchoredGrammarContent(
                grammarWordOccurrences(in: Array(sourceLine)).map(\.value),
                grammarWordOccurrences(in: Array(correctedLine)).map(\.value)
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
            !hasUnanchoredGrammarContent(
                grammarWordOccurrences(in: Array(source)).map(\.value),
                grammarWordOccurrences(in: Array(response)).map(\.value)
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
            "*", "_", "~", "`", "#", ">", "<", "=", "|", "\\", "/", "@", "&", "%"
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

    private static func grammarLeadingWhitespace(in value: String) -> String {
        String(value.prefix(while: { $0.isWhitespace }))
    }

    private static func grammarTrailingWhitespace(in value: String) -> String {
        String(value.reversed().prefix(while: { $0.isWhitespace }).reversed())
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
        let sourceWords = grammarWordOccurrences(in: sourceCharacters)
        let correctedWords = grammarWordOccurrences(in: correctedCharacters)
        let comparableCount = min(sourceWords.count, correctedWords.count)
        guard !hasUnanchoredGrammarContent(
            sourceWords.map(\.value),
            correctedWords.map(\.value)
        ) else { return true }
        guard comparableCount >= 2 else { return false }

        var preservedPrefixCount = 0
        while preservedPrefixCount < comparableCount,
              grammarWordsApproximatelyMatch(
                  [sourceWords[preservedPrefixCount].value],
                  [correctedWords[preservedPrefixCount].value]
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
            if grammarContainsBoundaryDelimiter(correctedSeparator) ||
               grammarContainsBoundaryDelimiter(sourceSeparator) {
                return true
            }
        }

        var preservedSuffixCount = 0
        while preservedSuffixCount < comparableCount,
              grammarWordsApproximatelyMatch(
                  [sourceWords[sourceWords.count - preservedSuffixCount - 1].value],
                  [correctedWords[correctedWords.count - preservedSuffixCount - 1].value]
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
            if grammarContainsBoundaryDelimiter(correctedSeparator) ||
               grammarContainsBoundaryDelimiter(sourceSeparator) {
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
        let distance = grammarWordEditDistance(source, corrected)
        return distance <= 1 || isAdjacentTransposition(source, corrected) ||
            (max(source.count, corrected.count) >= 8 && distance <= 2)
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
        ["can", "could"], ["will", "would"], ["shall", "should"], ["may", "might"],
        ["a", "an", "the"], ["this", "these"], ["that", "those"],
        ["good", "well", "better", "best"], ["bad", "badly", "worse", "worst"],
        ["go", "goes", "went", "gone", "going", "goed"], ["hear", "here"]
    ]

    private static func grammarWordOccurrences(in characters: [Character]) -> [GrammarWordOccurrence] {
        var occurrences: [GrammarWordOccurrence] = []
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
            occurrences.append(GrammarWordOccurrence(
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

    private static func grammarContainsBoundaryDelimiter(_ characters: ArraySlice<Character>) -> Bool {
        characters.contains(where: { !$0.isWhitespace })
    }

    private static func restoringOriginalBoundaryWhitespace(in response: String, original: String) -> String {
        guard original.contains(where: { !$0.isWhitespace }) else { return original }
        let withoutLeadingWhitespace = response.drop(while: { $0.isWhitespace })
        let responseBody = withoutLeadingWhitespace.reversed().drop(while: { $0.isWhitespace }).reversed()
        let originalLeadingWhitespace = original.prefix(while: { $0.isWhitespace })
        let originalTrailingWhitespace = original.reversed().prefix(while: { $0.isWhitespace }).reversed()
        return String(originalLeadingWhitespace) + String(responseBody) + String(originalTrailingWhitespace)
    }

    private static func grammarWords(in value: String) -> [String] {
        value.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map { $0.lowercased() }
    }

    private static func grammarWordEditDistance(_ lhs: String, _ rhs: String) -> Int {
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

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        do {
            return try await httpClient.send(request)
        } catch let error as GatewayClientError {
            throw error
        } catch is CancellationError {
            throw GatewayClientError.cancelled
        } catch let error as URLError {
            throw mapNetworkError(error)
        } catch {
            throw GatewayClientError.transportError
        }
    }

    private func request(path: String, method: String, body: Data? = nil) -> HTTPRequest {
        let url = config.gatewayURL.appendingPathComponent(path.trimmingPrefix("/"))
        return HTTPRequest(
            method: method,
            url: url,
            headers: [
                "Authorization": "Bearer \(config.apiKey)",
                "Accept": "application/json"
            ],
            body: body
        )
    }

    private func mapNetworkError(_ error: URLError) -> GatewayClientError {
        switch error.code {
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .networkUnavailable
        default:
            return .transportError
        }
    }

    private func mapStatus(_ statusCode: Int) throws {
        switch statusCode {
        case 200..<300:
            return
        case 401:
            throw GatewayClientError.unauthorized
        case 403:
            throw GatewayClientError.forbidden
        case 429:
            throw GatewayClientError.rateLimited
        case 500..<600:
            throw GatewayClientError.serverError(statusCode: statusCode)
        default:
            throw GatewayClientError.unexpectedStatus(statusCode: statusCode)
        }
    }
}

public enum GatewayClientError: Error, Equatable, Sendable {
    case unauthorized
    case forbidden
    case rateLimited
    case serverError(statusCode: Int)
    case unexpectedStatus(statusCode: Int)
    case invalidResponse
    case timedOut
    case cancelled
    case networkUnavailable
    case transportError

    public var userMessage: String {
        switch self {
        case .unauthorized:
            return "API key is missing or invalid. Check your Open Keyboard gateway settings."
        case .forbidden:
            return "This API key is not allowed to use the requested gateway resource."
        case .rateLimited:
            return "The gateway is receiving too many requests. Wait a moment and try again."
        case .serverError:
            return "The gateway had a server error. Try again shortly."
        case .unexpectedStatus:
            return "The gateway returned an unexpected response."
        case .invalidResponse:
            return "The gateway response could not be understood."
        case .timedOut:
            return "The gateway request timed out. Check your connection and try again."
        case .cancelled:
            return "The gateway request was cancelled."
        case .networkUnavailable:
            return "The gateway is unreachable. Check your network or gateway URL."
        case .transportError:
            return "The gateway request failed before a response was received."
        }
    }
}

private struct HealthResponse: Decodable {
    let status: String
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let operation: String
    let inputText: String
    let messages: [ChatMessage]
    let responseFormat: ChatCompletionResponseFormat?
    let maxTokens: Int?
    let temperature: Double?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case operation
        case inputText = "input_text"
        case messages
        case responseFormat = "response_format"
        case maxTokens = "max_tokens"
        case temperature
        case stream
    }
}

private struct ChatCompletionResponseFormat: Encodable {
    let type: String

    static let jsonObject = ChatCompletionResponseFormat(type: "json_object")
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ResponseMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Decodable {
        let content: String
    }
}

private struct RawWritingActionResult: Decodable {
    let operation: String?
    let results: [RawWritingActionResultItem]?
    let rawItems: [RawWritingActionResultItem]?
    let rawResult: RawWritingActionResultItem?
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
        results = try? container.decode([RawWritingActionResultItem].self, forKey: .results)
        rawItems = try? container.decode([RawWritingActionResultItem].self, forKey: .rawItems)
        rawResult = try? container.decode(RawWritingActionResultItem.self, forKey: .rawResult)
        summary = try? container.decode(String.self, forKey: .summary)
        correctedText = Self.firstString(in: container, keys: [.correctedText, .correctedTextCamel])
        topLevelDisplayText = Self.firstString(in: container, keys: [.rawResult, .rewrittenText, .rewrittenTextCamel, .improvedText, .improvedTextCamel, .replacement, .text, .output])
    }

    var decodedItems: [RawWritingActionResultItem] { results ?? rawItems ?? rawResult.map { [$0] } ?? [] }

    private static func firstString(in container: KeyedDecodingContainer<CodingKeys>, keys: [CodingKeys]) -> String? {
        for key in keys {
            if let value = try? container.decodeIfPresent(String.self, forKey: key) { return value }
        }
        return nil
    }
}

private struct RawWritingActionResultItem: Decodable {
    let id: String?
    let type: String?
    let title: String?
    let text: String?
    let original: String?
    let replacement: String?
    let range: WritingActionTextRange?
    let confidence: Double?
    let explanation: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, text, original, replacement, range, confidence, explanation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decode(String.self, forKey: .id)
        type = try? container.decode(String.self, forKey: .type)
        title = try? container.decode(String.self, forKey: .title)
        text = try? container.decode(String.self, forKey: .text)
        original = try? container.decode(String.self, forKey: .original)
        replacement = try? container.decode(String.self, forKey: .replacement)
        range = try? container.decode(WritingActionTextRange.self, forKey: .range)
        confidence = Self.decodeConfidence(from: container)
        explanation = try? container.decode(String.self, forKey: .explanation)
    }

    private static func decodeConfidence(from container: KeyedDecodingContainer<CodingKeys>) -> Double? {
        if let value = try? container.decode(Double.self, forKey: .confidence) { return value }
        guard let value = try? container.decode(String.self, forKey: .confidence) else { return nil }
        return Double(value)
    }
}

extension WritingActionTextRange: Decodable {
    enum CodingKeys: String, CodingKey {
        case start, end
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let start = Self.decodeOffset(from: container, forKey: .start),
              let end = Self.decodeOffset(from: container, forKey: .end) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Text range offsets must be integers."))
        }
        self.init(start: start, end: end)
    }

    private static func decodeOffset(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        guard let value = try? container.decode(String.self, forKey: key) else { return nil }
        return Int(value)
    }
}

private struct ModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        var copy = self
        while copy.hasPrefix(prefix) {
            copy.removeFirst(prefix.count)
        }
        return copy
    }
}
