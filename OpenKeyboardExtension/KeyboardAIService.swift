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
            return "Correct the grammar of this text. Return only the corrected text, no explanation:\n\n\(text)"
        case .rewrite:
            return "Rewrite this text in a clear, friendly tone. Return only the rewritten text, no explanation:\n\n\(text)"
        case .summarize:
            return "Summarize this text concisely. Return only the summary, no explanation:\n\n\(text)"
        }
    }
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

final class KeyboardAIService {
    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        let output = try await performRawSuggestionRequest(prompt: KeyboardSuggestionParser.prompt(for: text), config: config)
        return try KeyboardSuggestionParser.parseAssistantContent(output)
    }

    private func performRawSuggestionRequest(prompt: String, config: AppConfig) async throws -> String {
        try await performRequest(systemPrompt: "You are an iOS keyboard writing assistant. Return strict JSON only.", userPrompt: prompt, maxTokens: 360, config: config)
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        return try await performRequest(systemPrompt: "You are an iOS keyboard text editing assistant. Return only the replacement text.", userPrompt: action.prompt(for: text), maxTokens: 180, config: config)
    }

    private func performRequest(systemPrompt: String, userPrompt: String, maxTokens: Int, config: AppConfig) async throws -> String {
        let trimmed = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var gatewayURL = config.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while gatewayURL.hasSuffix("/") {
            gatewayURL.removeLast()
        }
        guard config.isConfigured, !apiKey.isEmpty else { throw KeyboardAIError.notConfigured }
        guard !trimmed.isEmpty else { throw KeyboardAIError.missingInput }
        guard let url = URL(string: gatewayURL + "/v1/chat/completions") else {
            throw KeyboardAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatRequest(
            model: config.selectedModel,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: trimmed)
            ],
            maxTokens: maxTokens,
            temperature: 0.1,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KeyboardAIError.invalidResponse }
        if http.statusCode == 401 { throw KeyboardAIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw KeyboardAIError.server("Gateway HTTP \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let output = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else { throw KeyboardAIError.invalidResponse }
        return output
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int
    let temperature: Double
    let stream: Bool
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
