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

enum KeyboardAIAction: CaseIterable, Hashable, Identifiable, Sendable {
    case improve
    case fixGrammar
    case rewrite
    case summarize
    case translate(KeyboardTranslationTarget?)

    static let allCases: [KeyboardAIAction] = [
        .improve,
        .fixGrammar,
        .rewrite,
        .summarize,
        .translate(nil)
    ]

    var rawValue: String {
        switch self {
        case .improve: return "improve"
        case .fixGrammar: return "fixGrammar"
        case .rewrite: return "rewrite"
        case .summarize: return "summarize"
        case .translate: return "translate"
        }
    }

    var id: String { rawValue }

    var translationTarget: KeyboardTranslationTarget? {
        guard case .translate(let target) = self else { return nil }
        return target
    }

    var isTranslation: Bool {
        if case .translate = self { return true }
        return false
    }

    var isReadyForRequest: Bool {
        !isTranslation || translationTarget != nil
    }

    func representsSameMode(as other: KeyboardAIAction) -> Bool {
        if isTranslation, other.isTranslation { return true }
        return self == other
    }

    var operationName: String {
        switch self {
        case .improve: return "rewrite"
        case .fixGrammar: return "fix_grammar"
        case .rewrite: return "rewrite"
        case .summarize: return "summarize"
        case .translate: return "translate"
        }
    }

    var title: String {
        switch self {
        case .improve: return "Improve"
        case .fixGrammar: return "Fix Grammar"
        case .rewrite: return "Rewrite"
        case .summarize: return "Summarize"
        case .translate: return "Translate"
        }
    }

    var iconName: String {
        switch self {
        case .improve: return "sparkles"
        case .fixGrammar: return "checkmark.seal.fill"
        case .rewrite: return "wand.and.stars"
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
        return KeyboardGatewayActionContract.prompt(operation: operationName, text: text)
    }
}

protocol KeyboardAIServiceProviding: AnyObject {
    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse
    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String
    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult
}

enum KeyboardAIError: LocalizedError {
    case notConfigured
    case missingInput
    case invalidURL
    case unauthorized
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
        case .server(let message):
            return message
        case .invalidResponse:
            return "No AI response"
        case .missingTranslationTarget:
            return "Choose a language"
        }
    }
}

final class KeyboardAIService: KeyboardAIServiceProviding {
    private let gatewayClient: CanonicalGatewayClient

    init(gatewayClient: CanonicalGatewayClient = CanonicalGatewayClient()) {
        self.gatewayClient = gatewayClient
    }

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        let output = try await performRawSuggestionRequest(prompt: KeyboardSuggestionParser.prompt(for: text), config: config)
        return try KeyboardSuggestionParser.parseAssistantContent(output)
    }

    private func performRawSuggestionRequest(prompt: String, config: AppConfig) async throws -> String {
        do {
            return try await gatewayClient.chatCompletionContent(
                systemPrompt: "You are an iOS keyboard writing assistant. Return strict JSON only.",
                userPrompt: prompt,
                operation: nil,
                inputText: nil,
                maxTokens: 1_200,
                config: config,
                timeoutInterval: 90
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
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KeyboardAIError.invalidResponse }
        return output
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
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
                timeoutInterval: 90
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            throw Self.keyboardError(from: error)
        }
        do {
            return try KeyboardActionOperationResult.parse(output, operation: action.operationName, fallbackText: text)
        } catch {
            throw KeyboardAIError.invalidResponse
        }
    }

    private static func keyboardError(from error: Error) -> KeyboardAIError {
        guard let gatewayError = error as? CanonicalGatewayClientError else {
            return .server("Gateway request failed. Check settings and try again.")
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
        case .invalidResponse, .unusableCorrection:
            return .invalidResponse
        case .modelUnavailable, .timeout, .transport:
            return .server(gatewayError.userMessage)
        case .serverStatus(let status):
            return .server("Gateway HTTP \(status)")
        }
    }
}
