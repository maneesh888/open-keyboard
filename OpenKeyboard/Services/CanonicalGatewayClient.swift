import Foundation

protocol GatewayChatTransporting: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: GatewayChatTransporting {}

enum CanonicalGatewayClientError: LocalizedError, Equatable {
    case invalidURL
    case notConfigured
    case missingInput
    case unauthorized
    case modelUnavailable
    case invalidResponse
    case unusableCorrection
    case timeout
    case serverStatus(Int)
    case transport

    var errorDescription: String? { userMessage }

    var userMessage: String {
        switch self {
        case .invalidURL: return "Invalid gateway URL"
        case .notConfigured: return "Pair gateway in app"
        case .missingInput: return "Type text first"
        case .unauthorized: return "Invalid API key"
        case .modelUnavailable: return "The selected model is not available for this key."
        case .invalidResponse: return "Gateway returned an invalid response."
        case .unusableCorrection: return "Gateway connected, but the selected model did not return a usable correction."
        case .timeout: return "Gateway connected, but the selected model timed out during the test."
        case .serverStatus(let status): return "Gateway HTTP \(status)"
        case .transport: return "Gateway request failed. Check settings and try again."
        }
    }
}

struct CanonicalGatewayClient {
    private let transport: GatewayChatTransporting

    init(transport: GatewayChatTransporting = URLSession.shared) {
        self.transport = transport
    }

    func chatCompletionContent(
        systemPrompt: String,
        userPrompt: String,
        operation: String?,
        inputText: String?,
        maxTokens: Int,
        config: AppConfig,
        temperature: Double = 0.1
    ) async throws -> String {
        let request = try chatCompletionRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            operation: operation,
            inputText: inputText,
            maxTokens: maxTokens,
            config: config,
            temperature: temperature
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw CanonicalGatewayClientError.timeout
        } catch is CancellationError {
            throw CanonicalGatewayClientError.transport
        } catch {
            throw CanonicalGatewayClientError.transport
        }
        guard let http = response as? HTTPURLResponse else { throw CanonicalGatewayClientError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw CanonicalGatewayClientError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw CanonicalGatewayClientError.serverStatus(http.statusCode) }
        guard let completion = try? JSONDecoder().decode(CanonicalChatCompletionResponse.self, from: data),
              let content = completion.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw CanonicalGatewayClientError.invalidResponse
        }
        return content
    }

    func chatCompletionRequest(
        systemPrompt: String,
        userPrompt: String,
        operation: String?,
        inputText: String?,
        maxTokens: Int,
        config: AppConfig,
        temperature: Double = 0.1
    ) throws -> URLRequest {
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.isConfigured, !apiKey.isEmpty else { throw CanonicalGatewayClientError.notConfigured }
        guard !model.isEmpty else { throw CanonicalGatewayClientError.modelUnavailable }
        guard !prompt.isEmpty else { throw CanonicalGatewayClientError.missingInput }
        let url = try Self.endpointURL(gatewayURL: config.gatewayURL, path: "v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(CanonicalChatCompletionRequest(
            model: model,
            operation: operation,
            inputText: inputText.map { String($0.prefix(500)) },
            messages: [
                CanonicalChatMessage(role: "system", content: systemPrompt),
                CanonicalChatMessage(role: "user", content: prompt)
            ],
            maxTokens: maxTokens,
            temperature: temperature,
            stream: false
        ))
        return request
    }

    static func normalizedGatewayBaseURLString(_ value: String) throws -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CanonicalGatewayClientError.invalidURL }
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
            throw CanonicalGatewayClientError.invalidURL
        }
        components.scheme = scheme
        components.path = components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        if components.path == "/v1" { components.path = "" }
        components.query = nil
        components.fragment = nil
        guard let normalized = components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), !normalized.isEmpty else {
            throw CanonicalGatewayClientError.invalidURL
        }
        return normalized
    }

    static func endpointURL(gatewayURL: String, path: String) throws -> URL {
        let base = try normalizedGatewayBaseURLString(gatewayURL)
        let cleanedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/\(cleanedPath)") else { throw CanonicalGatewayClientError.invalidURL }
        return url
    }

    static func isUsableCorrectionSmokeResponse(_ value: String) -> Bool {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !normalized.isEmpty else { return false }
        return normalized.contains("i have an apple") ||
            normalized.contains("i have a apple") ||
            normalized.contains("i had an apple") ||
            (normalized.contains("have") && normalized.contains("apple"))
    }
}

private struct CanonicalChatCompletionRequest: Encodable {
    let model: String
    let operation: String?
    let inputText: String?
    let messages: [CanonicalChatMessage]
    let maxTokens: Int
    let temperature: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, operation, messages, temperature, stream
        case inputText = "input_text"
        case maxTokens = "max_tokens"
    }
}

private struct CanonicalChatMessage: Codable {
    let role: String
    let content: String
}

private struct CanonicalChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}
