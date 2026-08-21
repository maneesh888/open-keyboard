//
//  KeyboardAIService.swift
//  OpenKeyboardExtension
//

import Foundation

enum KeyboardTranslationTarget: String, CaseIterable, Hashable, Identifiable, Sendable {
    case arabic = "ar"
    case malayalam = "ml"
    case hindi = "hi"
    case urdu = "ur"
    case englishAmerican = "en-US"
    case bengali = "bn"
    case marathi = "mr"
    case telugu = "te"
    case tamil = "ta"
    case chineseSimplified = "zh-Hans"
    case spanish = "es"
    case french = "fr"
    case portuguese = "pt"
    case russian = "ru"
    case dutch = "nl"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .arabic: return "Arabic"
        case .dutch: return "Dutch"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .englishAmerican: return "English (American)"
        case .hindi: return "Hindi"
        case .malayalam: return "Malayalam"
        case .urdu: return "Urdu"
        case .bengali: return "Bengali"
        case .marathi: return "Marathi"
        case .telugu: return "Telugu"
        case .tamil: return "Tamil"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        }
    }

    var promptLanguage: String {
        switch self {
        case .arabic: return "Modern Standard Arabic"
        case .dutch: return "Dutch"
        case .chineseSimplified: return "Simplified Chinese"
        case .englishAmerican: return "American English"
        case .hindi: return "Hindi"
        case .malayalam: return "Malayalam"
        case .urdu: return "Urdu"
        case .bengali: return "Bengali"
        case .marathi: return "Marathi"
        case .telugu: return "Telugu"
        case .tamil: return "Tamil"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        }
    }
}

enum KeyboardRewriteStyle: String, CaseIterable, Hashable, Identifiable, Sendable {
    case shorten
    case friendly
    case formal
    case compassionate
    case confident
    case engaging
    case fluent
    case diplomatic
    case empathetic
    case exciting
    case cooperative
    case assertive
    case detailed
    case casual
    case professional

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var emoji: String {
        switch self {
        case .shorten: return "✂️"
        case .friendly: return "😊"
        case .formal: return "👔"
        case .compassionate: return "🤗"
        case .confident: return "🤝"
        case .engaging: return "🎯"
        case .fluent: return "🌊"
        case .diplomatic: return "😎"
        case .empathetic: return "😇"
        case .exciting: return "🤩"
        case .cooperative: return "👋"
        case .assertive: return "☝️"
        case .detailed: return "📊"
        case .casual: return "👕"
        case .professional: return "💼"
        }
    }

}

enum KeyboardAIAction: CaseIterable, Hashable, Identifiable, Sendable {
    case improve
    case fixGrammar
    case rewrite
    case rewriteStyle(KeyboardRewriteStyle)
    case summarize
    case translate(KeyboardTranslationTarget?)

    static let allCases: [KeyboardAIAction] = [
        .improve,
        .fixGrammar,
        .rewrite,
        .summarize,
        .translate(nil)
    ] + KeyboardRewriteStyle.allCases.map(KeyboardAIAction.rewriteStyle)

    var rawValue: String {
        switch self {
        case .improve: return "improve"
        case .fixGrammar: return "fixGrammar"
        case .rewrite: return "rewrite"
        case .rewriteStyle(let style): return "rewrite_\(style.rawValue)"
        case .summarize: return "summarize"
        case .translate: return "translate"
        }
    }

    var id: String { rawValue }

    var translationTarget: KeyboardTranslationTarget? {
        guard case .translate(let target) = self else { return nil }
        return target
    }

    var rewriteStyle: KeyboardRewriteStyle? {
        guard case .rewriteStyle(let style) = self else { return nil }
        return style
    }

    var isTranslation: Bool {
        if case .translate = self { return true }
        return false
    }

    var isRewrite: Bool {
        switch self {
        case .rewrite, .rewriteStyle: return true
        default: return false
        }
    }

    var isReadyForRequest: Bool {
        !isTranslation || translationTarget != nil
    }

    var isReadyForActionPanelRequest: Bool {
        isReadyForRequest
    }

    func representsSameMode(as other: KeyboardAIAction) -> Bool {
        if isTranslation, other.isTranslation { return true }
        return self == other
    }

    var operationName: String {
        switch self {
        case .improve: return "rewrite"
        case .fixGrammar: return "fix_grammar"
        case .rewrite, .rewriteStyle: return "rewrite"
        case .summarize: return "summarize"
        case .translate: return "translate"
        }
    }

    var title: String {
        switch self {
        case .improve: return "Improve"
        case .fixGrammar: return "Fix Grammar"
        case .rewrite: return "Rewrite"
        case .rewriteStyle(let style): return style.displayName
        case .summarize: return "Summarize"
        case .translate: return "Translate"
        }
    }

    var iconName: String {
        switch self {
        case .improve: return "sparkles"
        case .fixGrammar: return "checkmark.seal.fill"
        case .rewrite, .rewriteStyle: return "wand.and.stars"
        case .summarize: return "text.bubble.fill"
        case .translate: return "character.bubble"
        }
    }

    var maxTokens: Int {
        KeyboardGatewayActionContract.maxTokens(operation: operationName)
    }

    func prompt(for text: String) -> String? {
        if self == .improve {
            return KeyboardGatewayActionContract.prompt(operation: "improve", text: text)
        }
        if case .translate(let target) = self {
            guard let target else { return nil }
            return KeyboardGatewayActionContract.prompt(
                operation: operationName,
                text: text,
                translationLanguage: target.promptLanguage
            )
        }
        if case .rewriteStyle(let style) = self {
            return KeyboardGatewayActionContract.prompt(
                operation: "rewrite_\(style.rawValue)",
                text: text
            )
        }
        return KeyboardGatewayActionContract.prompt(operation: operationName, text: text)
    }
}

protocol KeyboardAIServiceProviding: AnyObject {
    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse
    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String
    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult
}

enum KeyboardAIError: LocalizedError, Equatable {
    case notConfigured
    case missingInput
    case invalidURL
    case unauthorized
    case modelUnavailable
    case modelCapability
    case timeout
    case transport
    case server(String)
    case invalidResponse
    case missingTranslationTarget

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Pair gateway in app"
        case .missingInput:
            return "Type text first"
        case .invalidURL:
            return "Invalid gateway URL"
        case .unauthorized:
            return "Invalid API key"
        case .modelUnavailable:
            return "The selected model is not available for this key."
        case .modelCapability:
            return KeyboardActionErrorState.modelCapabilityMessage
        case .timeout:
            return "The AI request took longer than 15 seconds. Try again or choose a faster model."
        case .transport:
            return "Gateway request failed. Check settings and try again."
        case .server(let message):
            return message
        case .invalidResponse:
            return "No AI response"
        case .missingTranslationTarget:
            return "Choose a language"
        }
    }

    var actionErrorKind: KeyboardActionErrorKind {
        switch self {
        case .unauthorized:
            return .authentication
        case .modelUnavailable:
            return .modelUnavailable
        case .modelCapability:
            return .modelCapability
        case .timeout:
            return .timeout
        case .notConfigured, .missingInput, .invalidURL, .transport, .server, .invalidResponse, .missingTranslationTarget:
            return .gatewayUnavailable
        }
    }
}

final class KeyboardAIService: KeyboardAIServiceProviding {
    private let gatewayClient: CanonicalGatewayClient
    private let requestTimeoutInterval: TimeInterval

    init(
        gatewayClient: CanonicalGatewayClient = CanonicalGatewayClient(),
        requestTimeoutInterval: TimeInterval = GatewayRequestTimeouts.keyboardAction
    ) {
        self.gatewayClient = gatewayClient
        self.requestTimeoutInterval = requestTimeoutInterval
    }

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        let output = try await performRawSuggestionRequest(prompt: KeyboardSuggestionParser.prompt(for: text), config: config)
        do {
            return try KeyboardSuggestionParser.parseAssistantContent(output)
        } catch {
            throw KeyboardAIError.modelCapability
        }
    }

    private func performRawSuggestionRequest(prompt: String, config: AppConfig) async throws -> String {
        do {
            return try await gatewayClient.chatCompletionContent(
                systemPrompt: SemanticPromptContract.keyboardSuggestionsSystemInstruction,
                userPrompt: prompt,
                operation: nil,
                inputText: nil,
                maxTokens: 1_200,
                config: config,
                timeoutInterval: requestTimeoutInterval
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            throw Self.keyboardError(from: error)
        }
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        let result = try await performResult(action: action, on: text, config: config)
        let output = result.displayText
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KeyboardAIError.modelCapability }
        return output
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        if action == .fixGrammar {
            return try await performGrammarCorrection(on: text, config: config)
        }
        guard let prompt = action.prompt(for: text) else {
            throw KeyboardAIError.missingTranslationTarget
        }
        let output: String
        do {
            output = try await gatewayClient.chatCompletionContent(
                systemPrompt: KeyboardGatewayActionContract.structuredSystemPrompt,
                userPrompt: prompt,
                operation: action.operationName,
                inputText: text,
                maxTokens: action.maxTokens,
                config: config,
                timeoutInterval: requestTimeoutInterval
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            throw Self.keyboardError(from: error)
        }
        do {
            return try KeyboardActionOperationResult.parse(output, operation: action.operationName, fallbackText: text)
        } catch {
            throw KeyboardAIError.modelCapability
        }
    }

    private func performGrammarCorrection(on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        let chunks = GrammarTextChunker.chunks(in: text)
        guard !chunks.isEmpty,
              chunks.allSatisfy({ $0.text.count <= GrammarTextChunker.absoluteMaximumCharacters }) else {
            throw KeyboardAIError.modelCapability
        }
        var correctedChunks = Array<String?>(repeating: nil, count: chunks.count)
        let concurrencyLimit = 2

        do {
            try await withThrowingTaskGroup(of: (Int, String).self) { group in
                var nextIndex = 0
                func addNext() {
                    guard nextIndex < chunks.count else { return }
                    let chunkIndex = nextIndex
                    let chunk = chunks[chunkIndex]
                    nextIndex += 1
                    group.addTask {
                        let rendering = KeyboardGatewayActionContract.rendering(
                            operation: "fix_grammar",
                            text: chunk.text
                        )
                        let output = try await self.gatewayClient.chatCompletionContent(
                            systemPrompt: rendering.messages[0].content,
                            userPrompt: rendering.messages[1].content,
                            operation: rendering.wireOperationID,
                            inputText: chunk.text,
                            maxTokens: rendering.maxTokens,
                            config: config,
                            temperature: rendering.temperature,
                            expectsStructuredResponse: rendering.responseFormatType != nil,
                            timeoutInterval: self.requestTimeoutInterval
                        )
                        return (chunkIndex, try await GrammarCorrectionResponseValidator.validated(output, original: chunk.text))
                    }
                }

                for _ in 0..<min(concurrencyLimit, chunks.count) { addNext() }
                while let (index, corrected) = try await group.next() {
                    correctedChunks[index] = corrected
                    addNext()
                }
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as KeyboardAIError {
            throw error
        } catch let error as CanonicalGatewayClientError {
            throw Self.keyboardError(from: error)
        } catch is GrammarCorrectionResponseError {
            throw KeyboardAIError.modelCapability
        } catch {
            throw Self.keyboardError(from: error)
        }

        guard correctedChunks.allSatisfy({ $0 != nil }) else { throw KeyboardAIError.invalidResponse }
        let corrected = correctedChunks.compactMap { $0 }.joined()
        do {
            return try await KeyboardActionOperationResult.plainTextGrammarResponse(corrected, original: text)
        } catch {
            throw KeyboardAIError.modelCapability
        }
    }

    static func keyboardError(from error: Error) -> KeyboardAIError {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return .timeout
        }
        guard let gatewayError = error as? CanonicalGatewayClientError else {
            return .transport
        }

        switch gatewayError {
        case .invalidURL:
            return .invalidURL
        case .notConfigured:
            return .notConfigured
        case .missingInput:
            return .missingInput
        case .unauthorized:
            return .unauthorized
        case .modelUnavailable:
            return .modelUnavailable
        case .unusableCorrection:
            return .modelCapability
        case .timeout:
            return .timeout
        case .transport:
            return .transport
        case .invalidResponse:
            return .invalidResponse
        case .serverStatus(let status):
            return .server("Gateway HTTP \(status)")
        }
    }
}

struct GrammarTextChunk: Equatable, Sendable {
    let range: KeyboardTextRange
    let text: String
}

struct GrammarTextChunker {
    static let maximumCharacters = 6_000
    static let absoluteMaximumCharacters = 24_000
    private static let multiParagraphSafetyCharacters = 256
    private static let multiParagraphChunkCharacters = 120

    static func chunks(in text: String, maximumCharacters: Int = GrammarTextChunker.maximumCharacters) -> [GrammarTextChunk] {
        let characters = Array(text)
        let paragraphEnds = paragraphBoundaryEnds(in: characters)
        if maximumCharacters == GrammarTextChunker.maximumCharacters,
           characters.count >= multiParagraphSafetyCharacters,
           paragraphEnds.count >= 2 {
            return chunks(
                in: characters,
                sectionEnds: [characters.count],
                maximumCharacters: multiParagraphChunkCharacters
            )
        }
        guard characters.count > maximumCharacters else {
            return [GrammarTextChunk(range: KeyboardTextRange(start: 0, end: characters.count), text: text)]
        }

        return chunks(
            in: characters,
            sectionEnds: [characters.count],
            maximumCharacters: maximumCharacters
        )
    }

    private static func chunks(
        in characters: [Character],
        sectionEnds: [Int],
        maximumCharacters: Int
    ) -> [GrammarTextChunk] {
        var chunks: [GrammarTextChunk] = []
        var sectionStart = 0
        for sectionEnd in sectionEnds where sectionEnd > sectionStart {
            appendChunks(
                in: characters,
                from: sectionStart,
                to: sectionEnd,
                maximumCharacters: maximumCharacters,
                into: &chunks
            )
            sectionStart = sectionEnd
        }
        return chunks
    }

    private static func appendChunks(
        in characters: [Character],
        from sectionStart: Int,
        to sectionEnd: Int,
        maximumCharacters: Int,
        into chunks: inout [GrammarTextChunk]
    ) {
        var start = sectionStart
        while start < sectionEnd {
            let hardEnd = min(start + maximumCharacters, sectionEnd)
            var end = hardEnd
            if hardEnd < sectionEnd {
                let minimumEnd = start + maximumCharacters / 2
                var candidate = hardEnd
                var foundBoundary = false
                while candidate > minimumEnd {
                    let previous = characters[candidate - 1]
                    let next = characters[candidate]
                    let paragraphBoundary = previous == "\n" && (candidate < 2 || characters[candidate - 2] == "\n")
                    let sentenceBoundary = ".!?".contains(previous) && next.isWhitespace
                    if paragraphBoundary || sentenceBoundary {
                        end = candidate
                        foundBoundary = true
                        break
                    }
                    candidate -= 1
                }
                if !foundBoundary {
                    candidate = hardEnd + 1
                    while candidate < sectionEnd {
                        let previous = characters[candidate - 1]
                        let next = characters[candidate]
                        let paragraphBoundary = previous == "\n" && (candidate < 2 || characters[candidate - 2] == "\n")
                        let sentenceBoundary = ".!?".contains(previous) && next.isWhitespace
                        if paragraphBoundary || sentenceBoundary {
                            end = candidate
                            foundBoundary = true
                            break
                        }
                        candidate += 1
                    }
                }
                if !foundBoundary {
                    end = sectionEnd
                }
            }
            let chunkText = String(characters[start..<end])
            chunks.append(GrammarTextChunk(
                range: KeyboardTextRange(start: start, end: end),
                text: chunkText
            ))
            start = end
        }
    }

    private static func paragraphBoundaryEnds(in characters: [Character]) -> [Int] {
        guard characters.count >= 2 else { return [] }
        var boundaries: [Int] = []
        var index = 1
        while index < characters.count {
            guard characters[index - 1] == "\n", characters[index] == "\n" else {
                index += 1
                continue
            }
            var end = index + 1
            while end < characters.count, characters[end] == "\n" {
                end += 1
            }
            boundaries.append(end)
            index = end
        }
        return boundaries
    }
}
