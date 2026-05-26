import Foundation

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
        let response = try await httpClient.send(request(path: "/health", method: "GET"))
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
        let response = try await httpClient.send(request(path: "/v1/models", method: "GET"))
        try mapStatus(response.statusCode)

        guard let models = try? JSONDecoder().decode(ModelsResponse.self, from: response.data) else {
            throw GatewayClientError.invalidResponse
        }

        return models.data.map(\.id)
    }

    public func performWritingAction(_ action: WritingAction, text: String, model: String) async throws -> String {
        let prompt = WritingPromptBuilder.prompt(for: action, text: text)
        let payload = ChatCompletionRequest(
            model: model,
            messages: [ChatMessage(role: "user", content: prompt)],
            stream: false
        )

        guard let body = try? JSONEncoder().encode(payload) else {
            throw GatewayClientError.invalidResponse
        }

        var chatRequest = request(path: "/v1/chat/completions", method: "POST", body: body)
        chatRequest.headers["Content-Type"] = "application/json"

        let response = try await httpClient.send(chatRequest)
        try mapStatus(response.statusCode)

        guard let completion = try? JSONDecoder().decode(ChatCompletionResponse.self, from: response.data),
              let content = completion.choices.first?.message.content else {
            throw GatewayClientError.invalidResponse
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GatewayClientError.invalidResponse
        }

        return trimmed
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
}

private struct HealthResponse: Decodable {
    let status: String
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ResponseMessage
    }

    struct ResponseMessage: Decodable {
        let content: String
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
