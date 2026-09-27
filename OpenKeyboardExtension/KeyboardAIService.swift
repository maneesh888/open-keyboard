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

struct KeyboardTranslationOutputValidator {
    func validationFailure(
        for output: String,
        target: KeyboardTranslationTarget
    ) -> KeyboardTranslationValidationFailure? {
        TranslationLanguageOutputValidator().validationFailure(
            for: output,
            expectedScript: target.expectedScript,
            expectedLanguageCodes: target.expectedLanguageCodes
        )
    }
}

private extension KeyboardTranslationTarget {
    var expectedScript: TranslationLanguageOutputValidator.Script {
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

    var diagnosticOperation: AIOperationDiagnosticOperation {
        switch self {
        case .improve: return .improve
        case .fixGrammar: return .fixGrammar
        case .rewrite, .rewriteStyle: return .rewrite
        case .summarize: return .summarize
        case .translate: return .translate
        }
    }

    var contractOperationID: String {
        switch self {
        case .improve:
            return "improve"
        case .rewrite:
            return "rewrite"
        case .rewriteStyle(let style):
            return "rewrite_\(style.rawValue)"
        default:
            return operationName
        }
    }

    var title: String {
        switch self {
        case .improve: return "Improve"
        case .fixGrammar: return "Fix Grammar"
        case .rewrite: return "Rephrase"
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
        KeyboardGatewayActionContract.maxTokens(operation: contractOperationID)
    }

    func rendering(for text: String) -> SemanticPromptRendering? {
        if case .translate(let target) = self {
            guard let target else { return nil }
            return KeyboardGatewayActionContract.rendering(
                operation: operationName,
                text: text,
                translationLanguage: target.promptLanguage
            )
        }
        return KeyboardGatewayActionContract.rendering(operation: contractOperationID, text: text)
    }

    func prompt(for text: String) -> String? {
        rendering(for: text)?.messages.last?.content
    }
}

protocol KeyboardAIServiceProviding: AnyObject {
    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse
    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String
    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult
    func closeConnector()
}

extension KeyboardAIServiceProviding {
    // Most test doubles have no process-local connector to release.
    func closeConnector() {}
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
            return "Couldn't generate a usable suggestion. Try again."
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
        case .invalidResponse:
            return .invalidResponse
        case .notConfigured, .missingInput, .invalidURL, .transport, .server, .missingTranslationTarget:
            return .gatewayUnavailable
        }
    }
}

final class KeyboardAIService: KeyboardAIServiceProviding {
    private let diagnostics: AIOperationDiagnostics
    private let connector: OpenKeyboardAIConnectorServing
    private let requestTimeoutInterval: TimeInterval
    private let translationValidator: KeyboardTranslationOutputValidator

    init(
        connector: OpenKeyboardAIConnectorServing = UniversalAIConnectorAdapter.shared,
        requestTimeoutInterval: TimeInterval = GatewayRequestTimeouts.keyboardAction,
        translationValidator: KeyboardTranslationOutputValidator = KeyboardTranslationOutputValidator(),
        diagnostics: AIOperationDiagnostics = .shared
    ) {
        self.diagnostics = diagnostics
        self.connector = connector
        self.requestTimeoutInterval = requestTimeoutInterval
        self.translationValidator = translationValidator
    }

    func closeConnector() {
        connector.close()
    }

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        let output = try await performRawSuggestionRequest(prompt: KeyboardSuggestionParser.prompt(for: text), config: config)
        do {
            let response = try KeyboardSuggestionParser.parseAssistantContent(output)
            recordValidation()
            return response
        } catch {
            recordValidation(failure: .validationRejected)
            throw KeyboardAIError.modelCapability
        }
    }

    private func performRawSuggestionRequest(prompt: String, config: AppConfig) async throws -> String {
        do {
            let profile = try Self.connectorProfile(from: config)
            let request = try OpenKeyboardAIRequest.keyboardSuggestions(
                prompt: prompt,
                modelID: config.selectedModel,
                timeoutInterval: requestTimeoutInterval
            )
            recordPromptConstruction(for: request)
            return try await OpenKeyboardRequestDeadline.value(
                timeoutInterval: requestTimeoutInterval
            ) {
                try await self.connector.respond(to: request, profile: profile)
            }
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
        guard let rendering = action.rendering(for: text),
              rendering.messages.count >= 2 else {
            recordValidation(failure: .validationRejected)
            throw KeyboardAIError.missingTranslationTarget
        }
        let maximumAttempts = action.isTranslation ? 2 : 1
        for attempt in 0..<maximumAttempts {
            let result: KeyboardActionOperationResult
            do {
                result = try await AIOperationDiagnosticContext.$attempt.withValue(attempt + 1) {
                    try await requestResult(
                        action: action,
                        text: text,
                        rendering: rendering,
                        config: config
                    )
                }
            } catch let error as KeyboardAIError {
                let scopedError: KeyboardAIError
                if error == .modelCapability, let target = action.translationTarget {
                    scopedError = .unreliableTranslation(target)
                } else {
                    scopedError = error
                }
                if case .unreliableTranslation = scopedError,
                   attempt < maximumAttempts - 1 {
                    recordRetry(nextAttempt: attempt + 2)
                    continue
                }
                if attempt > 0 {
                    recordValidation(failure: .retryFailed)
                }
                throw scopedError
            }
            guard let target = action.translationTarget else { return result }
            let isUnusableTranslation = translationValidator.validationFailure(
                for: result.displayText,
                target: target
            ) != nil
            guard isUnusableTranslation else {
                return result
            }
            recordValidation(failure: .validationRejected)
            if attempt == maximumAttempts - 1 {
                recordValidation(failure: .retryFailed)
                throw KeyboardAIError.unreliableTranslation(target)
            }
            recordRetry(nextAttempt: attempt + 2)
        }
        recordValidation(failure: .retryFailed)
        throw KeyboardAIError.modelCapability
    }

    private func requestResult(
        action: KeyboardAIAction,
        text: String,
        rendering: SemanticPromptRendering,
        config: AppConfig
    ) async throws -> KeyboardActionOperationResult {
        let output: String
        do {
            let profile = try Self.connectorProfile(from: config)
            let request = try OpenKeyboardAIRequest.writing(
                rendering: rendering,
                modelID: config.selectedModel,
                timeoutInterval: requestTimeoutInterval
            )
            recordPromptConstruction(for: request)
            output = try await OpenKeyboardRequestDeadline.value(
                timeoutInterval: requestTimeoutInterval
            ) {
                try await self.connector.respond(to: request, profile: profile)
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            throw Self.keyboardError(from: error)
        }
        do {
            let result = try KeyboardActionOperationResult.plainTextResponse(
                output,
                rendering: rendering,
                title: action.title,
                source: text
            )
            recordValidation()
            return result
        } catch {
            recordValidation(failure: .validationRejected)
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
            throw KeyboardAIError.invalidResponse
        }

        var validatedChunks = try await requestGrammarCorrections(for: chunks, config: config)
        if validatedChunks.map(\.text).joined() == text {
            recordRetry(nextAttempt: 2)
            do {
                validatedChunks = try await AIOperationDiagnosticContext.$attempt.withValue(2) {
                    try await requestGrammarCorrections(for: chunks, config: config)
                }
            } catch {
                recordValidation(failure: .retryFailed)
                throw error
            }
        }

        let corrected = validatedChunks.map(\.text).joined()
        do {
            let validatedWholeResponse = try await GrammarCorrectionResponseValidator.classified(
                corrected,
                original: text
            )
            let hasStructurallyDriftingChunk = validatedChunks.contains {
                $0.disposition == .wholeVersionProposal
            }
            return KeyboardActionOperationResult.plainTextGrammarResponse(
                validatedWholeResponse,
                original: text,
                forceWholeVersionProposal: hasStructurallyDriftingChunk
            )
        } catch is GrammarCorrectionResponseError {
            recordValidation(failure: .validationRejected)
            throw KeyboardAIError.invalidResponse
        } catch {
            recordValidation(failure: .validationRejected)
            throw Self.keyboardError(from: error)
        }
    }

    private func requestGrammarCorrections(
        for chunks: [GrammarTextChunk],
        config: AppConfig
    ) async throws -> [ValidatedGrammarCorrectionResponse] {
        var correctedChunks = Array<ValidatedGrammarCorrectionResponse?>(repeating: nil, count: chunks.count)
        let concurrencyLimit = 2

        do {
            try await withThrowingTaskGroup(of: (Int, ValidatedGrammarCorrectionResponse).self) { group in
                var nextIndex = 0
                func addNext() {
                    guard nextIndex < chunks.count else { return }
                    let chunkIndex = nextIndex
                    let chunk = chunks[chunkIndex]
                    nextIndex += 1
                    group.addTask {
                        try await AIOperationDiagnosticContext.$requestID.withValue(UUID().uuidString.lowercased()) {
                            let rendering = KeyboardGatewayActionContract.rendering(
                                operation: "fix_grammar",
                                text: chunk.text
                            )
                            let profile = try Self.connectorProfile(from: config)
                            let request = try OpenKeyboardAIRequest.writing(
                                rendering: rendering,
                                modelID: config.selectedModel,
                                timeoutInterval: self.requestTimeoutInterval
                            )
                            self.recordPromptConstruction(for: request)
                            let output = try await OpenKeyboardRequestDeadline.value(
                                timeoutInterval: self.requestTimeoutInterval
                            ) {
                                try await self.connector.respond(to: request, profile: profile)
                            }
                            let validated: ValidatedGrammarCorrectionResponse
                            do {
                                validated = try await GrammarCorrectionResponseValidator.classified(output, original: chunk.text)
                            } catch {
                                self.recordValidation(failure: .validationRejected)
                                throw error
                            }
                            self.recordValidation()
                            return (
                                chunkIndex,
                                validated
                            )
                        }
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
        } catch let error as OpenKeyboardAIConnectorError {
            throw Self.keyboardError(from: error)
        } catch is GrammarCorrectionResponseError {
            throw KeyboardAIError.invalidResponse
        } catch {
            throw Self.keyboardError(from: error)
        }

        guard correctedChunks.allSatisfy({ $0 != nil }) else {
            recordValidation(failure: .validationRejected)
            throw KeyboardAIError.invalidResponse
        }
        return correctedChunks.compactMap { $0 }
    }

    private func recordPromptConstruction(for request: OpenKeyboardAIRequest) {
        guard let traceID = AIOperationDiagnosticContext.traceID else { return }
        let byteCount = request.messages.reduce(0) { partial, message in
            partial + message.content.lengthOfBytes(using: .utf8)
        }
        diagnostics.record(
            traceID: traceID,
            stage: .promptConstruction,
            requestBytes: byteCount
        )
    }

    private func recordValidation(
        failure: AIOperationDiagnosticFailure? = nil
    ) {
        guard let traceID = AIOperationDiagnosticContext.traceID else { return }
        diagnostics.record(
            traceID: traceID,
            stage: .validation,
            failure: failure
        )
    }

    private func recordRetry(nextAttempt: Int) {
        guard let traceID = AIOperationDiagnosticContext.traceID else { return }
        diagnostics.record(
            traceID: traceID,
            stage: .retry,
            attempt: nextAttempt
        )
    }

    static func keyboardError(from error: Error) -> KeyboardAIError {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return .timeout
        }
        guard let connectorError = error as? OpenKeyboardAIConnectorError else {
            return .transport
        }

        switch connectorError {
        case .invalidURL:
            return .invalidURL
        case .notConfigured:
            return .notConfigured
        case .missingInput:
            return .missingInput
        case .unauthorized, .forbidden:
            return .unauthorized
        case .modelUnavailable:
            return .modelUnavailable
        case .timeout:
            return .timeout
        case .transport, .provider, .closed, .unsupportedModelDiscovery:
            return .transport
        case .invalidResponse:
            return .invalidResponse
        case .truncatedResponse:
            return .modelCapability
        case .rateLimited:
            return .server("Gateway HTTP 429")
        case .serverStatus(let statusCode):
            return .server("Gateway HTTP \(statusCode)")
        }
    }

    private static func connectorProfile(from config: AppConfig) throws -> OpenKeyboardGatewayProfile {
        guard config.isConfigured else { throw OpenKeyboardAIConnectorError.notConfigured }
        return try OpenKeyboardGatewayProfile(
            provider: config.provider,
            baseURL: config.baseURL,
            apiKey: config.apiKey
        )
    }
}

struct GrammarTextChunk: Equatable, Sendable {
    let range: KeyboardTextRange
    let text: String
}

struct GrammarTextChunker {
    static let maximumCharacters = 6_000
    static let absoluteMaximumCharacters = 24_000

    static func chunks(in text: String, maximumCharacters: Int = GrammarTextChunker.maximumCharacters) -> [GrammarTextChunk] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }
        return chunks(
            in: characters,
            sectionEnds: sentenceBoundaryEnds(in: text, characterCount: characters.count),
            maximumCharacters: maximumCharacters
        )
    }

    private static func sentenceBoundaryEnds(in text: String, characterCount: Int) -> [Int] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ends: [Int] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let end = text.distance(from: text.startIndex, to: range.upperBound)
            if text[range].contains(where: { $0.isLetter || $0.isNumber }) {
                ends.append(end)
            } else if !ends.isEmpty {
                ends[ends.count - 1] = end
            }
            return true
        }

        guard !ends.isEmpty else { return [characterCount] }
        ends[ends.count - 1] = characterCount
        return ends
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
                    candidate = hardEnd
                    while candidate > minimumEnd {
                        if characters[candidate - 1].isWhitespace {
                            end = candidate
                            foundBoundary = true
                            break
                        }
                        candidate -= 1
                    }
                }
                if !foundBoundary {
                    end = hardEnd
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

}
