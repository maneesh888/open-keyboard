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
    /// Compatibility identifier used by legacy gateway-only tests and callers.
    static let providerID = "openai-compatible"

    let provider: OpenKeyboardAIProvider
    let baseURL: String
    let connectorBaseURL: String
    let apiKey: String

    var providerID: String { provider.rawValue }
    var gatewayURL: String { baseURL }

    init(provider: OpenKeyboardAIProvider, baseURL: String, apiKey: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenKeyboardAIConnectorError.unauthorized
        }
        self.provider = provider
        self.baseURL = try GatewayURLNormalizer.normalizedStoredBaseURLString(
            baseURL,
            provider: provider
        )
        self.connectorBaseURL = try GatewayURLNormalizer.connectorBaseURLString(
            baseURL,
            provider: provider
        )
        self.apiKey = trimmedKey
    }

    init(gatewayURL: String, apiKey: String) throws {
        try self.init(provider: .openAICompatible, baseURL: gatewayURL, apiKey: apiKey)
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
        try normalizedStoredBaseURLString(value, provider: .openAICompatible)
    }

    static func normalizedStoredBaseURLString(
        _ value: String,
        provider: OpenKeyboardAIProvider
    ) throws -> String {
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
        guard !containsUnsafeTransportCharacter(trimmed),
              !trimmed.contains("\\"),
              hasValidAuthorityShape(trimmed) else {
            throw OpenKeyboardAIConnectorError.invalidURL
        }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = components.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              components.user == nil,
              components.password == nil,
              components.percentEncodedQuery == nil,
              components.percentEncodedFragment == nil,
              !hasAmbiguousPath(components.percentEncodedPath),
              scheme == "https" || (
                provider == .openAICompatible && isExactLoopbackHost(host)
              ) else {
            throw OpenKeyboardAIConnectorError.invalidURL
        }
        components.scheme = scheme
        components.path = components.path.replacingOccurrences(
            of: "/+$",
            with: "",
            options: .regularExpression
        )
        if provider == .openAICompatible,
           components.path.caseInsensitiveCompare("/v1") == .orderedSame {
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
        try connectorBaseURLString(value, provider: .openAICompatible)
    }

    static func connectorBaseURLString(
        _ value: String,
        provider: OpenKeyboardAIProvider
    ) throws -> String {
        let storedBase = try normalizedStoredBaseURLString(value, provider: provider)
        guard provider == .openAICompatible else { return storedBase }
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

    private static func containsUnsafeTransportCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            let code = scalar.value
            return code <= 0x20
                || code == 0x7f
                || (0x80...0x9f).contains(code)
                || code == 0x2028
                || code == 0x2029
                || (0x202a...0x202e).contains(code)
                || (0x2066...0x2069).contains(code)
        }
    }

    private static func hasValidAuthorityShape(_ value: String) -> Bool {
        guard let schemeRange = value.range(of: "://") else { return false }
        let authorityStart = schemeRange.upperBound
        let authorityEnd = value[authorityStart...].firstIndex(where: { character in
            character == "/" || character == "?" || character == "#"
        }) ?? value.endIndex
        let authority = value[authorityStart..<authorityEnd]
        guard !authority.isEmpty, !authority.contains("@") else { return false }

        if authority.first == "[" {
            guard let closingBracket = authority.firstIndex(of: "]"),
                  closingBracket > authority.startIndex else { return false }
            let suffix = authority[authority.index(after: closingBracket)...]
            return suffix.isEmpty
                || (suffix.first == ":"
                    && suffix.count > 1
                    && suffix.dropFirst().allSatisfy(isASCIIDigit))
        }

        guard authority.filter({ $0 == ":" }).count <= 1 else { return false }
        guard let portSeparator = authority.lastIndex(of: ":") else { return true }
        let host = authority[..<portSeparator]
        let port = authority[authority.index(after: portSeparator)...]
        return !host.isEmpty && !port.isEmpty && port.allSatisfy(isASCIIDigit)
    }

    private static func isExactLoopbackHost(_ value: String) -> Bool {
        var host = value.lowercased()
        if host.first == "[", host.last == "]" {
            host.removeFirst()
            host.removeLast()
        }
        return host == "localhost"
            || isCanonicalIPv4Loopback(host)
            || isIPv6Loopback(host)
    }

    private static func isCanonicalIPv4Loopback(_ value: String) -> Bool {
        let octets = value.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        let numbers = octets.compactMap { octet -> Int? in
            guard !octet.isEmpty,
                  octet.count <= 3,
                  octet.allSatisfy(isASCIIDigit),
                  !(octet.count > 1 && octet.first == "0"),
                  let number = Int(octet),
                  (0...255).contains(number) else {
                return nil
            }
            return number
        }
        return numbers.count == 4 && numbers[0] == 127
    }

    private static func isIPv6Loopback(_ value: String) -> Bool {
        func parseGroups(_ part: Substring) -> [Int]? {
            guard !part.isEmpty else { return [] }
            let groups = part.split(separator: ":", omittingEmptySubsequences: false)
            guard groups.allSatisfy({ group in
                (1...4).contains(group.count) && group.allSatisfy(isASCIIHexDigit)
            }) else { return nil }
            return groups.compactMap { Int($0, radix: 16) }
        }

        guard value.allSatisfy({ $0 == ":" || isASCIIHexDigit($0) }) else { return false }
        let parts = value.components(separatedBy: "::")
        let groups: [Int]
        if parts.count == 1 {
            guard let parsed = parseGroups(value[...]) else { return false }
            groups = parsed
        } else if parts.count == 2 {
            guard let leading = parseGroups(parts[0][...]),
                  let trailing = parseGroups(parts[1][...]) else { return false }
            let omittedCount = 8 - leading.count - trailing.count
            guard omittedCount >= 1 else { return false }
            groups = leading + Array(repeating: 0, count: omittedCount) + trailing
        } else {
            return false
        }
        return groups.count == 8
            && groups.dropLast().allSatisfy { $0 == 0 }
            && groups.last == 1
    }

    private static func hasAmbiguousPath(_ encodedPath: String) -> Bool {
        guard !encodedPath.isEmpty else { return false }
        let segments = encodedPath.split(separator: "/", omittingEmptySubsequences: false)
        let firstContentIndex = encodedPath.hasPrefix("/") ? 1 : 0
        let lastContentIndex = segments.lastIndex(where: { !$0.isEmpty }) ?? -1
        if lastContentIndex >= firstContentIndex,
           segments[firstContentIndex...lastContentIndex].contains(where: \.isEmpty) {
            return true
        }
        return segments.contains { hasUnsafeDecodedPathSegment(String($0)) }
    }

    private static func hasUnsafeDecodedPathSegment(_ value: String) -> Bool {
        var decoded = value
        for _ in 0..<8 {
            if decoded == "." || decoded == ".." || decoded.contains("/") || decoded.contains("\\") {
                return true
            }
            guard let next = decoded.removingPercentEncoding else { return true }
            if next == decoded { return false }
            decoded = next
        }
        return true
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1
            && character.unicodeScalars.first.map { (0x30...0x39).contains($0.value) } == true
    }

    private static func isASCIIHexDigit(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1
            && character.unicodeScalars.first.map { scalar in
                (0x30...0x39).contains(scalar.value)
                    || (0x41...0x46).contains(scalar.value)
                    || (0x61...0x66).contains(scalar.value)
            } == true
    }
}
