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


public struct WritingActionResult: Equatable, Sendable {
    public var operation: String
    public var items: [WritingActionResultItem]
    public var summary: String?
    public var correctedText: String?

    public init(operation: String, items: [WritingActionResultItem], summary: String? = nil, correctedText: String? = nil) {
        self.operation = operation
        self.items = items
        self.summary = summary
        self.correctedText = correctedText
    }

    public var displayText: String {
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
        let displayText = result.displayText
        guard !displayText.isEmpty else { throw GatewayClientError.invalidResponse }
        return displayText
    }

    public func performWritingActionResult(_ action: WritingAction, text: String, model: String) async throws -> WritingActionResult {
        let prompt = WritingPromptBuilder.prompt(for: action, text: text)
        let payload = ChatCompletionRequest(
            model: model,
            operation: action.operationName,
            inputText: String(text.prefix(500)),
            messages: [
                ChatMessage(role: "system", content: Self.structuredResultSystemPrompt),
                ChatMessage(role: "user", content: prompt)
            ],
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
              let content = completion.choices.first?.message.content else {
            throw GatewayClientError.invalidResponse
        }

        return try Self.parseWritingActionResult(content, operation: action.operationName, fallbackText: text)
    }

    private static let structuredResultSystemPrompt = """
    You are an iOS keyboard writing assistant. Return strict JSON only.
    Contract: {"operation":"fix_grammar|summarize|rewrite|...","results":[{"id":"...","type":"correction|suggestion|summary|warning|explanation","title":"...","text":"...","original":"...","replacement":"...","range":{"start":0,"end":0},"confidence":0.0,"explanation":"..."}],"summary":"...","corrected_text":"..."}
    Use the requested operation and current text only. Unknown fields are allowed. Do not include markdown.
    """

    private static func parseWritingActionResult(_ content: String, operation: String, fallbackText: String) throws -> WritingActionResult {
        let trimmed = stripMarkdownFence(content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GatewayClientError.invalidResponse }
        if let data = trimmed.data(using: .utf8), let decoded = try? JSONDecoder().decode(RawWritingActionResult.self, from: data) {
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
            if items.isEmpty, correctedText == nil, summary == nil { throw GatewayClientError.invalidResponse }
            return WritingActionResult(operation: clean(decoded.operation) ?? operation, items: items, summary: summary, correctedText: correctedText)
        }
        let legacy = trimmed
        guard !legacy.isEmpty, legacy != fallbackText.trimmingCharacters(in: .whitespacesAndNewlines) else { throw GatewayClientError.invalidResponse }
        return WritingActionResult(
            operation: operation,
            items: [WritingActionResultItem(id: "legacy-1", type: "correction", title: defaultTitle(for: "correction", operation: operation), text: legacy, original: fallbackText, replacement: legacy)],
            correctedText: legacy
        )
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isNestedJSONLike(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
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
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case operation
        case inputText = "input_text"
        case messages
        case stream
    }
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

private struct RawWritingActionResult: Decodable {
    let operation: String?
    let results: [RawWritingActionResultItem]?
    let rawItems: [RawWritingActionResultItem]?
    let summary: String?
    let correctedText: String?

    enum CodingKeys: String, CodingKey {
        case operation
        case results
        case rawItems = "items"
        case summary
        case correctedText = "corrected_text"
    }

    var decodedItems: [RawWritingActionResultItem] { results ?? rawItems ?? [] }
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
}

extension WritingActionTextRange: Decodable {}

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
