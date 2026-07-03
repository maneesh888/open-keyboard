//
//  KeyboardAIService.swift
//  OpenKeyboardExtension
//

import Foundation

enum KeyboardAIAction: String, CaseIterable, Identifiable {
    case fixGrammar
    case rewrite
    case summarize

    var id: String { rawValue }

    var operationName: String {
        switch self {
        case .fixGrammar: return "fix_grammar"
        case .rewrite: return "rewrite"
        case .summarize: return "summarize"
        }
    }

    var title: String {
        switch self {
        case .fixGrammar: return "Fix Grammar"
        case .rewrite: return "Rewrite"
        case .summarize: return "Summarize"
        }
    }

    var iconName: String {
        switch self {
        case .fixGrammar: return "checkmark.seal.fill"
        case .rewrite: return "wand.and.stars"
        case .summarize: return "text.bubble.fill"
        }
    }

    var maxTokens: Int {
        KeyboardGatewayActionContract.maxTokens(operation: operationName)
    }

    func prompt(for text: String) -> String {
        KeyboardGatewayActionContract.prompt(operation: operationName, text: text)
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
        let output: String
        do {
            output = try await gatewayClient.chatCompletionContent(
                systemPrompt: KeyboardGatewayActionContract.structuredSystemPrompt,
                userPrompt: action.prompt(for: text),
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
