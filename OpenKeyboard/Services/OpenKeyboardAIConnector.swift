import Foundation

enum GatewayRequestTimeouts {
    static let keyboardAction: TimeInterval = 15
    static let modelCheckAttempt: TimeInterval = 20
}

enum OpenKeyboardAIConnectorError: Error, Equatable {
    case invalidURL
    case notConfigured
    case missingInput
    case unauthorized
    case forbidden
    case modelUnavailable
    case rateLimited
    case serverStatus(Int)
    case unsupportedModelDiscovery
    case timeout
    case transport
    case provider
    case invalidResponse
    case truncatedResponse
    case closed
}

struct OpenKeyboardGatewayProfile: Sendable {
    static let providerID = "openai-compatible"

    let gatewayURL: String
    let connectorBaseURL: String
    let apiKey: String

    init(gatewayURL: String, apiKey: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenKeyboardAIConnectorError.unauthorized
        }
        self.gatewayURL = try GatewayURLNormalizer.normalizedStoredBaseURLString(gatewayURL)
        self.connectorBaseURL = try GatewayURLNormalizer.connectorBaseURLString(gatewayURL)
        self.apiKey = trimmedKey
    }
}

enum OpenKeyboardAIMessageRole: String, Equatable, Sendable {
    case system
    case developer
    case user
    case assistant
}

struct OpenKeyboardAIMessage: Equatable, Sendable {
    let role: OpenKeyboardAIMessageRole
    let content: String
}

struct OpenKeyboardAIRequest: Equatable, Sendable {
    let modelID: String
    let messages: [OpenKeyboardAIMessage]
    let maxOutputTokens: Int?
    let temperature: Double?
    let topP: Double?
    let stopSequences: [String]
    let timeoutInterval: TimeInterval

    init(
        modelID: String,
        messages: [OpenKeyboardAIMessage],
        maxOutputTokens: Int?,
        temperature: Double?,
        topP: Double? = nil,
        stopSequences: [String] = [],
        timeoutInterval: TimeInterval = GatewayRequestTimeouts.keyboardAction
    ) throws {
        let trimmedModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw OpenKeyboardAIConnectorError.modelUnavailable
        }
        guard !messages.isEmpty,
              messages.allSatisfy({ !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw OpenKeyboardAIConnectorError.missingInput
        }
        self.modelID = trimmedModel
        self.messages = messages
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.stopSequences = stopSequences
        self.timeoutInterval = timeoutInterval
    }

    static func writing(
        rendering: SemanticPromptRendering,
        modelID: String,
        timeoutInterval: TimeInterval = GatewayRequestTimeouts.keyboardAction
    ) throws -> Self {
        guard rendering.responseFormatType == nil else {
            throw OpenKeyboardAIConnectorError.invalidResponse
        }
        return try Self(
            modelID: modelID,
            messages: try rendering.messages.map { message in
                guard let role = OpenKeyboardAIMessageRole(rawValue: message.role) else {
                    throw OpenKeyboardAIConnectorError.invalidResponse
                }
                return OpenKeyboardAIMessage(role: role, content: message.content)
            },
            maxOutputTokens: rendering.maxTokens,
            temperature: rendering.temperature,
            timeoutInterval: timeoutInterval
        )
    }

    static func keyboardSuggestions(
        prompt: String,
        modelID: String,
        timeoutInterval: TimeInterval = GatewayRequestTimeouts.keyboardAction
    ) throws -> Self {
        try Self(
            modelID: modelID,
            messages: [
                OpenKeyboardAIMessage(
                    role: .system,
                    content: SemanticPromptContract.keyboardSuggestionsSystemInstruction
                ),
                OpenKeyboardAIMessage(role: .user, content: prompt)
            ],
            maxOutputTokens: 1_200,
            temperature: 0.1,
            timeoutInterval: timeoutInterval
        )
    }
}

protocol OpenKeyboardAIConnectorServing: AnyObject, Sendable {
    func listModels(profile: OpenKeyboardGatewayProfile) async throws -> [String]
    func respond(
        to request: OpenKeyboardAIRequest,
        profile: OpenKeyboardGatewayProfile
    ) async throws -> String
    func close()
}

enum OpenKeyboardRequestDeadline {
    static func value<Value: Sendable>(
        timeoutInterval: TimeInterval,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let race = OpenKeyboardAsyncRace<Value>()
        let nanoseconds = UInt64(max(0.001, timeoutInterval) * 1_000_000_000)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
                let operationTask = Task {
                    do {
                        race.resolve(.success(try await operation()))
                    } catch {
                        race.resolve(.failure(error))
                    }
                }
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                        race.resolve(.failure(OpenKeyboardAIConnectorError.timeout))
                    } catch {
                        // The operation or caller completed first.
                    }
                }
                race.installTasks(operationTask, timeoutTask)
            }
        } onCancel: {
            race.resolve(.failure(CancellationError()))
        }
    }
}

private final class OpenKeyboardAsyncRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var storedResult: Result<Value, Error>?
    private var isResolved = false
    private var tasks: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let storedResult {
            self.storedResult = nil
            lock.unlock()
            continuation.resume(with: storedResult)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func installTasks(_ tasks: Task<Void, Never>...) {
        lock.lock()
        if isResolved {
            lock.unlock()
            tasks.forEach { $0.cancel() }
            return
        }
        self.tasks = tasks
        lock.unlock()
    }

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return
        }
        isResolved = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil {
            storedResult = result
        }
        let tasks = self.tasks
        self.tasks = []
        lock.unlock()

        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}

enum GatewayURLNormalizer {
    static func normalizedStoredBaseURLString(_ value: String) throws -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OpenKeyboardAIConnectorError.invalidURL }
        while trimmed.localizedCaseInsensitiveContains("https://https://") {
            trimmed = trimmed.replacingOccurrences(
                of: "https://https://",
                with: "https://",
                options: .caseInsensitive
            )
        }
        while trimmed.localizedCaseInsensitiveContains("http://http://") {
            trimmed = trimmed.replacingOccurrences(
                of: "http://http://",
                with: "http://",
                options: .caseInsensitive
            )
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
            throw OpenKeyboardAIConnectorError.invalidURL
        }
        components.scheme = scheme
        components.path = components.path.replacingOccurrences(
            of: "/+$",
            with: "",
            options: .regularExpression
        )
        if components.path.caseInsensitiveCompare("/v1") == .orderedSame {
            components.path = ""
        }
        components.query = nil
        components.fragment = nil
        guard let normalized = components.url?.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              !normalized.isEmpty else {
            throw OpenKeyboardAIConnectorError.invalidURL
        }
        return normalized
    }

    static func connectorBaseURLString(_ value: String) throws -> String {
        let storedBase = try normalizedStoredBaseURLString(value)
        guard var components = URLComponents(string: storedBase) else {
            throw OpenKeyboardAIConnectorError.invalidURL
        }
        var pathComponents = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        while pathComponents.last?.caseInsensitiveCompare("v1") == .orderedSame {
            pathComponents.removeLast()
        }
        pathComponents.append("v1")
        components.path = "/" + pathComponents.joined(separator: "/")
        guard let normalized = components.url?.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              !normalized.isEmpty else {
            throw OpenKeyboardAIConnectorError.invalidURL
        }
        return normalized
    }
}
