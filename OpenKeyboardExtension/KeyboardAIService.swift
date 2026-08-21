//
//  KeyboardAIService.swift
//  OpenKeyboardExtension
//

import Foundation
import NaturalLanguage

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

    var translationCapabilityWarning: String {
        "This model may not reliably translate to \(displayName). Try again or choose another model."
    }
}

enum KeyboardTranslationValidationFailure: Equatable {
    case predominantlyWrongLanguage
    case suspiciousMixedScripts
}

struct KeyboardTranslationOutputValidator {
    fileprivate enum Script: Hashable {
        case latin
        case arabic
        case devanagari
        case bengali
        case telugu
        case tamil
        case malayalam
        case cyrillic
        case han
        case other
    }

    func validationFailure(
        for output: String,
        target: KeyboardTranslationTarget
    ) -> KeyboardTranslationValidationFailure? {
        let scriptCounts = output.unicodeScalars.reduce(into: [Script: Int]()) { counts, scalar in
            guard let script = Self.script(for: scalar) else { return }
            counts[script, default: 0] += 1
        }
        let totalScriptLetters = scriptCounts.values.reduce(0, +)
        guard totalScriptLetters > 0 else { return nil }

        let expectedScript = target.expectedScript
        let expectedScriptCount = scriptCounts[expectedScript, default: 0]
        let unexpectedScriptCount = totalScriptLetters - expectedScriptCount
        let expectedScriptRatio = Double(expectedScriptCount) / Double(totalScriptLetters)
        let unexpectedScriptRatio = Double(unexpectedScriptCount) / Double(totalScriptLetters)

        if expectedScriptRatio < 0.55 {
            return .predominantlyWrongLanguage
        }
        if unexpectedScriptCount >= 4, unexpectedScriptRatio >= 0.20 {
            return .suspiciousMixedScripts
        }

        guard totalScriptLetters >= 4 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(output)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 4)
        let expectedConfidence = hypotheses
            .filter { target.expectedLanguageCodes.contains($0.key.rawValue) }
            .map(\.value)
            .max() ?? 0
        let dominantConfidence = hypotheses.values.max() ?? 0
        let isShortOutput = totalScriptLetters < 18
        let minimumExpectedConfidence = isShortOutput ? 0.08 : 0.12
        let minimumDominantConfidence = isShortOutput ? 0.60 : 0.55
        if expectedConfidence < minimumExpectedConfidence,
           dominantConfidence >= minimumDominantConfidence {
            return .predominantlyWrongLanguage
        }
        return nil
    }

    private static func script(for scalar: Unicode.Scalar) -> Script? {
        let value = scalar.value
        switch value {
        case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F, 0x1E00...0x1EFF:
            return .latin
        case 0x0400...0x052F:
            return .cyrillic
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
            return .arabic
        case 0x0900...0x097F, 0xA8E0...0xA8FF:
            return .devanagari
        case 0x0980...0x09FF:
            return .bengali
        case 0x0B80...0x0BFF:
            return .tamil
        case 0x0C00...0x0C7F:
            return .telugu
        case 0x0D00...0x0D7F:
            return .malayalam
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2EBEF:
            return .han
        default:
            return CharacterSet.letters.contains(scalar) ? .other : nil
        }
    }
}

private extension KeyboardTranslationTarget {
    var expectedScript: KeyboardTranslationOutputValidator.Script {
        switch self {
        case .arabic, .urdu: return .arabic
        case .hindi, .marathi: return .devanagari
        case .bengali: return .bengali
        case .telugu: return .telugu
        case .tamil: return .tamil
        case .malayalam: return .malayalam
        case .russian: return .cyrillic
        case .chineseSimplified: return .han
        case .dutch, .englishAmerican, .spanish, .french, .portuguese: return .latin
        }
    }

    var expectedLanguageCodes: Set<String> {
        switch self {
        case .englishAmerican: return ["en", "en-US"]
        case .chineseSimplified: return ["zh", "zh-Hans"]
        default: return [rawValue]
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
    case unreliableTranslation(KeyboardTranslationTarget)

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
        case .unreliableTranslation(let target):
            return target.translationCapabilityWarning
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
        case .unreliableTranslation:
            return .translationCapability
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
    private let translationValidator: KeyboardTranslationOutputValidator

    init(
        gatewayClient: CanonicalGatewayClient = CanonicalGatewayClient(),
        requestTimeoutInterval: TimeInterval = GatewayRequestTimeouts.keyboardAction,
        translationValidator: KeyboardTranslationOutputValidator = KeyboardTranslationOutputValidator()
    ) {
        self.gatewayClient = gatewayClient
        self.requestTimeoutInterval = requestTimeoutInterval
        self.translationValidator = translationValidator
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
        let maximumAttempts = action.isTranslation ? 2 : 1
        for attempt in 0..<maximumAttempts {
            let result: KeyboardActionOperationResult
            do {
                result = try await requestResult(action: action, text: text, prompt: prompt, config: config)
            } catch let error as KeyboardAIError {
                let scopedError: KeyboardAIError
                if error == .modelCapability, let target = action.translationTarget {
                    scopedError = .unreliableTranslation(target)
                } else {
                    scopedError = error
                }
                if case .unreliableTranslation = scopedError,
                   attempt < maximumAttempts - 1 {
                    continue
                }
                throw scopedError
            }
            guard let target = action.translationTarget else { return result }
            let isUnusableTranslation = result.containsWarningItem
                || translationValidator.validationFailure(for: result.displayText, target: target) != nil
            guard isUnusableTranslation else {
                return result
            }
            if attempt == maximumAttempts - 1 {
                throw KeyboardAIError.unreliableTranslation(target)
            }
        }
        throw KeyboardAIError.modelCapability
    }

    private func requestResult(
        action: KeyboardAIAction,
        text: String,
        prompt: String,
        config: AppConfig
    ) async throws -> KeyboardActionOperationResult {
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
            if let target = action.translationTarget {
                throw KeyboardAIError.unreliableTranslation(target)
            }
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
