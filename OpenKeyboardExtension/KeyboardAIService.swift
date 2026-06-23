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

    func prompt(for text: String) -> String {
        switch self {
        case .fixGrammar:
            return """
            Operation: fix_grammar
            Analyze this text and return structured JSON with a results array of correction items. Preserve the original meaning and include corrected_text when you can safely produce the full corrected text.

            Text:
            \(text)
            """
        case .rewrite:
            return """
            Operation: rewrite
            Rewrite this text in a clear, friendly tone. Return structured JSON with a rewrite/suggestion item and corrected_text for the full replacement.

            Text:
            \(text)
            """
        case .summarize:
            return """
            Operation: summarize
            Summarize this text concisely. Return structured JSON with a summary item.

            Text:
            \(text)
            """
        }
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
    case missingModel
    case unauthorized
    case timeout
    case transport(String)
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
        case .missingModel:
            return "No model selected. Reconnect your gateway in the app."
        case .unauthorized:
            return "API key was rejected by the gateway. Reconnect your gateway in the app."
        case .timeout:
            return "Gateway connected, but the selected model timed out. Try again or choose a faster model."
        case .transport(let message):
            return message
        case .server(let message):
            return message
        case .invalidResponse:
            return "Gateway connected, but the selected model returned no usable text."
        }
    }
}

final class KeyboardAIService: KeyboardAIServiceProviding {
    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        do {
            return try await analyzeSuggestionsOnce(prompt: KeyboardSuggestionParser.prompt(for: text), text: text, config: config)
        } catch let error where Self.isParserRetryable(error) {
            return try await retryAnalyzeSuggestions(text: text, config: config)
        } catch {
            throw error
        }
    }

    private func retryAnalyzeSuggestions(text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        do {
            return try await analyzeSuggestionsOnce(prompt: KeyboardSuggestionParser.retryPrompt(for: text), text: text, config: config)
        } catch let error where Self.isParserRetryable(error) {
            throw KeyboardAIError.server("Gateway connected, but the selected model returned unusable suggestions. Try again or switch models.")
        } catch {
            throw error
        }
    }

    private static func isParserRetryable(_ error: Error) -> Bool {
        if error is KeyboardSuggestionParserError { return true }
        if error is DecodingError { return true }
        return false
    }

    private func analyzeSuggestionsOnce(prompt: String, text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        let output = try await performRawSuggestionRequest(prompt: prompt, config: config)
        let response = try KeyboardSuggestionParser.parseAssistantContent(output, sourceContext: text)
        return KeyboardSuggestionResponse(
            corrections: response.corrections,
            predictions: KeyboardSuggestionState(response: response, sourceContext: text).predictions
        )
    }

    private func performRawSuggestionRequest(prompt: String, config: AppConfig) async throws -> String {
        try await performRequest(systemPrompt: "You are an iOS keyboard writing assistant. Return strict JSON only. If you cannot produce a safe useful result, return NO_CLEAR_CORRECTION.", userPrompt: prompt, maxTokens: 420, config: config)
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        let result = try await performResult(action: action, on: text, config: config)
        let output = result.displayText
        guard KeyboardSuggestionParser.isMeaningfulOutput(output, for: text) || action == .summarize else { throw KeyboardAIError.invalidResponse }
        return output
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        let output = try await performRequest(
            systemPrompt: Self.structuredOperationSystemPrompt,
            userPrompt: action.prompt(for: text),
            operation: action.operationName,
            inputText: text,
            maxTokens: 320,
            config: config
        )
        do {
            return try KeyboardActionOperationResult.parse(output, operation: action.operationName, fallbackText: text)
        } catch {
            throw Self.recordedGatewayError(.invalidResponse)
        }
    }

    private static let structuredOperationSystemPrompt = """
    You are an iOS keyboard text editing assistant. Return strict JSON only.
    Contract: {"operation":"fix_grammar|summarize|rewrite","results":[{"id":"...","type":"correction|suggestion|summary|warning|explanation","title":"...","text":"...","original":"...","replacement":"...","range":{"start":0,"end":0},"confidence":0.0,"explanation":"..."}],"summary":"...","corrected_text":"..."}
    Use the requested operation and current text only. Unknown item types are allowed. Do not include markdown.
    """

    private func performRequest(systemPrompt: String, userPrompt: String, operation: String? = nil, inputText: String? = nil, maxTokens: Int, config: AppConfig) async throws -> String {
        let trimmed = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModel = config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let gatewayURL: String
        do {
            gatewayURL = try Self.normalizedGatewayBaseURLString(config.gatewayURL)
        } catch {
            throw Self.recordedGatewayError(.invalidURL)
        }
        guard config.isConfigured, !apiKey.isEmpty else { throw Self.recordedGatewayError(.notConfigured) }
        guard !selectedModel.isEmpty else { throw Self.recordedGatewayError(.missingModel) }
        guard !trimmed.isEmpty else { throw KeyboardAIError.missingInput }
        guard let url = URL(string: gatewayURL + "/v1/chat/completions") else {
            throw Self.recordedGatewayError(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatRequest(
            model: selectedModel,
            operation: operation,
            inputText: inputText.map { String($0.prefix(500)) },
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: trimmed)
            ],
            maxTokens: maxTokens,
            temperature: 0.1,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw Self.recordedGatewayError(.timeout)
        } catch {
            throw Self.recordedGatewayError(.transport("Could not reach gateway. Check the URL and network."))
        }

        guard let http = response as? HTTPURLResponse else { throw Self.recordedGatewayError(.invalidResponse) }
        if http.statusCode == 401 || http.statusCode == 403 { throw Self.recordedGatewayError(.unauthorized) }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw Self.recordedGatewayError(.server(Self.userFacingServerMessage(statusCode: http.statusCode, body: body, model: selectedModel)))
        }

        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            let output = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !output.isEmpty else { throw KeyboardAIError.invalidResponse }
            AppConfig.clearGatewayConnectionError()
            return output
        } catch let error as KeyboardAIError {
            throw Self.recordedGatewayError(error)
        } catch {
            throw Self.recordedGatewayError(.invalidResponse)
        }
    }

    private static func normalizedGatewayBaseURLString(_ value: String) throws -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeyboardAIError.invalidURL }
        while trimmed.localizedCaseInsensitiveContains("https://https://") {
            trimmed = trimmed.replacingOccurrences(of: "https://https://", with: "https://", options: .caseInsensitive)
        }
        while trimmed.localizedCaseInsensitiveContains("http://http://") {
            trimmed = trimmed.replacingOccurrences(of: "http://http://", with: "http://", options: .caseInsensitive)
        }
        if trimmed.hasPrefix("http:/"), !trimmed.hasPrefix("http://") {
            trimmed = "http://" + trimmed.dropFirst("http:/".count)
        }
        if trimmed.hasPrefix("https:/"), !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed.dropFirst("https:/".count)
        }
        if !trimmed.localizedCaseInsensitiveContains("://") {
            trimmed = "https://" + trimmed
        }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = components.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeyboardAIError.invalidURL
        }
        components.scheme = scheme
        components.path = components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        if components.path == "/v1" { components.path = "" }
        components.query = nil
        components.fragment = nil
        guard let normalized = components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), !normalized.isEmpty else {
            throw KeyboardAIError.invalidURL
        }
        return normalized
    }

    private static func recordedGatewayError(_ error: KeyboardAIError) -> KeyboardAIError {
        if let message = error.errorDescription, !message.isEmpty {
            AppConfig.saveGatewayConnectionError(message)
        }
        return error
    }

    private static func userFacingServerMessage(statusCode: Int, body: String, model: String) -> String {
        let lowerBody = body.lowercased()
        let lowerModel = model.lowercased()
        if statusCode == 404 || lowerBody.contains("model") && (lowerBody.contains("not found") || lowerBody.contains("not available") || lowerBody.contains("unknown")) {
            return "Selected model ‘\(model)’ is not available. Reconnect your gateway or choose another model."
        }
        if lowerModel.contains("apple-foundationmodel") || lowerBody.contains("foundationmodels") || lowerBody.contains("generationerror") {
            return "Apple Foundation model did not respond. Try again or switch to another gateway model."
        }
        if statusCode == 429 || lowerBody.contains("rate limit") {
            return "Gateway rate limit reached. Try again shortly or choose another model."
        }
        if statusCode >= 500 {
            return "Gateway error while running ‘\(model)’. Try again or choose another model."
        }
        return "Gateway HTTP \(statusCode) while running ‘\(model)’"
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let operation: String?
    let inputText: String?
    let messages: [ChatMessage]
    let maxTokens: Int
    let temperature: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case operation
        case inputText = "input_text"
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case stream
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}
