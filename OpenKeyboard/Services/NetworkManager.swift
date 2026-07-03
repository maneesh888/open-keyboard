//
//  NetworkManager.swift
//  OpenKeyboard
//
//  Network service for gateway communication
//

import Foundation

protocol NetworkManagerTransporting: GatewayChatTransporting {}

extension URLSession: NetworkManagerTransporting {}

enum NetworkError: Error {
    case invalidURL
    case noData
    case unauthorized
    case serverError(String)
    case networkError(Error)
    case modelUnavailable
    case unusableCorrection
    case timeout

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid gateway URL"
        case .noData:
            return "No response from server"
        case .unauthorized:
            return "Invalid API key"
        case .serverError(let message):
            return "Server error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .modelUnavailable:
            return "The selected model is not available for this key."
        case .unusableCorrection:
            return "Gateway connected, but the selected model did not return a usable correction."
        case .timeout:
            return "Gateway connected, but the selected model timed out during the test."
        }
    }
}

enum GatewayDiagnosticStatus: String, Equatable {
    case passed = "Passed"
    case failed = "Failed"
    case skipped = "Skipped"
}

struct GatewayDiagnosticCheck: Identifiable, Equatable {
    let id: String
    let title: String
    let endpoint: String
    let status: GatewayDiagnosticStatus
    let durationMilliseconds: Int?
    let message: String

    var durationDisplay: String {
        guard let durationMilliseconds else { return "-" }
        return "\(durationMilliseconds) ms"
    }
}

struct GatewayDiagnosticReport: Equatable {
    let selectedModel: String
    let checks: [GatewayDiagnosticCheck]

    var hasFailures: Bool {
        checks.contains { $0.status == .failed }
    }

    var passedCount: Int {
        checks.filter { $0.status == .passed }.count
    }

    var failedCount: Int {
        checks.filter { $0.status == .failed }.count
    }

    var skippedCount: Int {
        checks.filter { $0.status == .skipped }.count
    }

    var measuredDurations: [Int] {
        checks.compactMap(\.durationMilliseconds)
    }

    var averageDurationMilliseconds: Int? {
        let durations = measuredDurations
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / durations.count
    }

    var maxDurationMilliseconds: Int? {
        measuredDurations.max()
    }

    var summary: String {
        var parts = ["\(passedCount)/\(checks.count) passed"]
        if failedCount > 0 { parts.append("\(failedCount) failed") }
        if skippedCount > 0 { parts.append("\(skippedCount) skipped") }
        if let averageDurationMilliseconds, let maxDurationMilliseconds {
            parts.append("avg \(averageDurationMilliseconds) ms")
            parts.append("max \(maxDurationMilliseconds) ms")
        }
        return parts.joined(separator: " · ")
    }
}

private enum GatewayDiagnosticValidationError: LocalizedError {
    case invalidJSON(String)
    case invalidOperation(expected: String, actual: String)
    case noUsableOutput(String)
    case unchangedOutput(String)
    case notEnoughCorrectionDetail

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let label):
            return "\(label) did not return valid app JSON."
        case .invalidOperation(let expected, let actual):
            return "Expected \(expected), got \(actual)."
        case .noUsableOutput(let label):
            return "\(label) returned no usable output."
        case .unchangedOutput(let label):
            return "\(label) returned unchanged text."
        case .notEnoughCorrectionDetail:
            return "Complex grammar response did not include enough correction detail."
        }
    }
}

class NetworkManager {
    static let shared = NetworkManager()
    static let correctionSmokeTestPhrases: [String] = [
        "teh tiny robot has a sandwhich for brekfast",
        "my keyboard definately knows alot about tacos",
        "the sleepy astronaut recieve a pizza tomorow",
        "i accidently taught the app to juggle banannas",
        "this sentence is wierd but the gateway should fix it",
        "our pocket wizard mispelled three words before lunch",
        "the brave toaster is runing late becuase traffic",
        "please seperate the spicy notes from teh soup",
        "my freind says the cloud printer is realy fast",
        "we will adress the bug after coffe arrives",
        "the calendar forgot tommorow and wrote yestarday",
        "this tiny app is recieveing a suprise message",
        "i should of saved teh draft before testing",
        "the button dissapeared untill i tapped it twice",
        "my burrito report is missing its grammer"
    ]

    private let transport: NetworkManagerTransporting

    init(transport: NetworkManagerTransporting = URLSession.shared) {
        self.transport = transport
    }

    /// Test connection to gateway with given API key. Uses the authenticated
    /// models endpoint so gateways that do not expose unauthenticated /health
    /// can still validate correctly.
    func testConnection(gatewayURL: String, apiKey: String) async throws -> Bool {
        !((try await fetchModels(gatewayURL: gatewayURL, apiKey: apiKey)).isEmpty)
    }

    /// Run a correction smoke through the same structured chat completions contract
    /// used by the keyboard action path.
    func testCorrectionSmoke(gatewayURL: String, apiKey: String, model: String) async throws {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw NetworkError.modelUnavailable }
        let smokeInput = Self.randomCorrectionSmokeTestPhrase()
        let content = try await chatCompletionContent(
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            model: trimmedModel,
            operation: "fix_grammar",
            inputText: smokeInput,
            systemPrompt: KeyboardGatewayActionContract.structuredSystemPrompt,
            userPrompt: KeyboardGatewayActionContract.prompt(operation: "fix_grammar", text: smokeInput),
            maxTokens: 1600,
            timeoutInterval: 45
        )
        do {
            _ = try Self.validateStructuredActionContent(content, operation: "fix_grammar", fallbackText: smokeInput, requireChangedOutput: true)
        } catch {
            throw NetworkError.unusableCorrection
        }
    }

    func runGatewayDiagnostics(gatewayURL: String, apiKey: String, preferredModel: String) async -> GatewayDiagnosticReport {
        let trimmedPreferredModel = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        var models: [String] = []
        var checks: [GatewayDiagnosticCheck] = []

        checks.append(await diagnosticCheck(
            id: "health",
            title: "Health",
            endpoint: "GET /health"
        ) {
            try await checkHealth(gatewayURL: gatewayURL, apiKey: apiKey)
            return "Gateway health is ok."
        })

        checks.append(await diagnosticCheck(
            id: "models",
            title: "Models",
            endpoint: "GET /v1/models"
        ) {
            models = try await fetchModels(gatewayURL: gatewayURL, apiKey: apiKey)
            guard !models.isEmpty else { throw NetworkError.modelUnavailable }
            return "Loaded \(models.count) model\(models.count == 1 ? "" : "s")."
        })

        let modelsCheckPassed = checks.last?.status == .passed
        let candidates = AppConfig.gatewayModelCandidates(from: models, currentModel: trimmedPreferredModel)
        let selectedModel = candidates.first ?? trimmedPreferredModel
        guard !selectedModel.isEmpty, modelsCheckPassed else {
            checks.append(contentsOf: Self.skippedDiagnosticChecks(reason: "Skipped because no model was available."))
            return GatewayDiagnosticReport(selectedModel: selectedModel, checks: checks)
        }

        let settingsSmokeInput = Self.randomCorrectionSmokeTestPhrase()
        checks.append(await chatDiagnosticCheck(
            id: "settings-correction-smoke",
            title: "Settings correction",
            operation: "fix_grammar",
            inputText: settingsSmokeInput,
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: KeyboardGatewayActionContract.structuredSystemPrompt,
            userPrompt: KeyboardGatewayActionContract.prompt(operation: "fix_grammar", text: settingsSmokeInput),
            maxTokens: 1600
        ) { content in
            let result = try Self.validateStructuredActionContent(content, operation: "fix_grammar", fallbackText: settingsSmokeInput, requireChangedOutput: true)
            return "Correction smoke returned usable structured JSON for: \"\(settingsSmokeInput)\""
        })

        let suggestionInput = "i definately recieve teh adress tomorow"
        checks.append(await chatDiagnosticCheck(
            id: "keyboard-suggestion-json",
            title: "Suggestion JSON",
            operation: nil,
            inputText: nil,
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: "You are an iOS keyboard writing assistant. Return strict JSON only.",
            userPrompt: KeyboardSuggestionParser.prompt(for: suggestionInput),
            maxTokens: 1_200
        ) { content in
            let parsed = try KeyboardSuggestionParser.parseAssistantContent(content)
            let itemCount = parsed.corrections.count + parsed.predictions.count + (parsed.correctedText == nil ? 0 : 1)
            guard itemCount > 0 else { throw GatewayDiagnosticValidationError.noUsableOutput("Suggestion JSON") }
            return "Parsed \(itemCount) suggestion item\(itemCount == 1 ? "" : "s")."
        })

        let complexGrammarInput = "i definately recieve teh adress tomorow, and seperate files wont upload because its recieve limit is to low."
        checks.append(await chatDiagnosticCheck(
            id: "complex-grammar-json",
            title: "Complex grammar JSON",
            operation: "fix_grammar",
            inputText: complexGrammarInput,
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: KeyboardGatewayActionContract.structuredSystemPrompt,
            userPrompt: KeyboardGatewayActionContract.prompt(operation: "fix_grammar", text: complexGrammarInput),
            maxTokens: 5_000
        ) { content in
            let result = try Self.validateStructuredActionContent(content, operation: "fix_grammar", fallbackText: complexGrammarInput, requireChangedOutput: true)
            let correctionCount = result.items.filter { $0.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "correction" }.count
            let expectedTerms = ["definitely", "receive", "address", "tomorrow", "separate", "won't", "too"]
            let displayText = result.displayText.lowercased()
            let hitCount = expectedTerms.filter { displayText.contains($0) || content.lowercased().contains($0) }.count
            guard correctionCount >= 3 || hitCount >= 3 else { throw GatewayDiagnosticValidationError.notEnoughCorrectionDetail }
            return "Parsed \(correctionCount) correction item\(correctionCount == 1 ? "" : "s")."
        })

        let rewriteInput = "hey team the app has issues and we need fix soon please check it"
        checks.append(await chatDiagnosticCheck(
            id: "rewrite-json",
            title: "Rewrite JSON",
            operation: "rewrite",
            inputText: rewriteInput,
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: KeyboardGatewayActionContract.structuredSystemPrompt,
            userPrompt: KeyboardGatewayActionContract.prompt(operation: "rewrite", text: rewriteInput),
            maxTokens: 3_000
        ) { content in
            let result = try Self.validateStructuredActionContent(content, operation: "rewrite", fallbackText: rewriteInput, requireChangedOutput: true)
            return "Parsed rewrite output, \(result.displayText.count) characters."
        })

        let summaryInput = "The keyboard extension now reads the same App Group gateway configuration as the host app. When the user tests the gateway in settings, the app loads models, stores the selected model, and runs a structured correction smoke request so the keyboard can rely on the same endpoint."
        checks.append(await chatDiagnosticCheck(
            id: "summarize-json",
            title: "Summarize JSON",
            operation: "summarize",
            inputText: summaryInput,
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: KeyboardGatewayActionContract.structuredSystemPrompt,
            userPrompt: KeyboardGatewayActionContract.prompt(operation: "summarize", text: summaryInput),
            maxTokens: 2_000
        ) { content in
            let result = try Self.validateStructuredActionContent(content, operation: "summarize", fallbackText: summaryInput, requireChangedOutput: false)
            return "Parsed summary output, \(result.displayText.count) characters."
        })

        let improveInput = "this message is confusing and it should sound better for the customer"
        checks.append(await chatDiagnosticCheck(
            id: "improve-rewrite-json",
            title: "Improve via Rewrite JSON",
            operation: "rewrite",
            inputText: String(improveInput.prefix(500)),
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: KeyboardGatewayActionContract.structuredSystemPrompt,
            userPrompt: KeyboardGatewayActionContract.prompt(operation: "improve", text: improveInput),
            maxTokens: 3_000
        ) { content in
            let result = try Self.validateStructuredActionContent(content, operation: "rewrite", fallbackText: improveInput, requireChangedOutput: true)
            return "Parsed improve rewrite output, \(result.displayText.count) characters."
        })

        return GatewayDiagnosticReport(selectedModel: selectedModel, checks: checks)
    }

    static func isUsableCorrectionSmokeResponse(_ value: String) -> Bool {
        CanonicalGatewayClient.isUsableCorrectionSmokeResponse(value)
    }

    static func randomCorrectionSmokeTestPhrase() -> String {
        correctionSmokeTestPhrases.randomElement() ?? "i has a apple"
    }

    static func normalizedGatewayBaseURLString(_ value: String) throws -> String {
        do {
            return try CanonicalGatewayClient.normalizedGatewayBaseURLString(value)
        } catch {
            throw NetworkError.invalidURL
        }
    }

    static func endpointURL(gatewayURL: String, path: String) throws -> URL {
        do {
            return try CanonicalGatewayClient.endpointURL(gatewayURL: gatewayURL, path: path)
        } catch {
            throw NetworkError.invalidURL
        }
    }

    static func userFacingSmokeErrorMessage(for error: Error, model: String) -> String {
        let raw = (error as? NetworkError)?.localizedDescription ?? error.localizedDescription
        let lower = raw.lowercased()
        let lowerModel = model.lowercased()
        if let networkError = error as? NetworkError {
            switch networkError {
            case .unauthorized:
                return "API key was rejected by the gateway. Reconnect your gateway in the app."
            case .timeout:
                return "Gateway connected, but the selected model timed out during the test."
            case .modelUnavailable:
                return "The selected model is not available for this key."
            case .unusableCorrection:
                return "Gateway connected, but the selected model did not return a usable correction."
            default:
                break
            }
        }
        if lowerModel.contains("apple-foundationmodel") || lower.contains("foundationmodels") || lower.contains("generationerror") {
            return "Gateway connected, but Apple Foundation model did not respond. Try another key/model."
        }
        if lower.contains("http 500") || lower.contains("server error") {
            return "Gateway connected, but the selected model failed to generate a response."
        }
        if lower.contains("invalid url") || lower.contains("network") || lower.contains("could not connect") {
            return "Could not reach gateway. Check the URL and network."
        }
        return "Gateway connected, but the selected model failed to generate a response."
    }

    /// Fetch available models from gateway
    func fetchModels(gatewayURL: String, apiKey: String) async throws -> [String] {
        let url = try Self.endpointURL(gatewayURL: gatewayURL, path: "v1/models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await transport.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.noData
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw NetworkError.unauthorized
            }

            if httpResponse.statusCode != 200 {
                throw NetworkError.serverError("HTTP \(httpResponse.statusCode)")
            }

            guard let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
                throw NetworkError.noData
            }

            return decoded.data.map(\.id)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.networkError(error)
        }
    }

    private func checkHealth(gatewayURL: String, apiKey: String) async throws {
        let url = try Self.endpointURL(gatewayURL: gatewayURL, path: "health")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await transport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw NetworkError.noData }
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 { throw NetworkError.unauthorized }
            guard httpResponse.statusCode == 200 else { throw NetworkError.serverError("HTTP \(httpResponse.statusCode)") }
            guard !data.isEmpty else { return }
            guard let decoded = try? JSONDecoder().decode(HealthResponse.self, from: data),
                  decoded.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ok" else {
                throw NetworkError.noData
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.networkError(error)
        }
    }

    private func chatCompletionContent(
        gatewayURL: String,
        apiKey: String,
        model: String,
        operation: String?,
        inputText: String?,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        timeoutInterval: TimeInterval
    ) async throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw NetworkError.modelUnavailable }

        do {
            return try await CanonicalGatewayClient(transport: transport).chatCompletionContent(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                operation: operation,
                inputText: inputText,
                maxTokens: maxTokens,
                config: AppConfig(
                    apiKey: apiKey,
                    gatewayURL: gatewayURL,
                    selectedModel: trimmedModel,
                    isConfigured: true,
                    supportsStructuredCorrections: true,
                    structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
                ),
                timeoutInterval: timeoutInterval
            )
        } catch let error as NetworkError {
            throw error
        } catch let error as CanonicalGatewayClientError {
            throw Self.networkError(from: error)
        } catch {
            throw NetworkError.networkError(error)
        }
    }

    private func diagnosticCheck(
        id: String,
        title: String,
        endpoint: String,
        operation: () async throws -> String
    ) async -> GatewayDiagnosticCheck {
        let started = Date()
        do {
            let message = try await operation()
            return GatewayDiagnosticCheck(
                id: id,
                title: title,
                endpoint: endpoint,
                status: .passed,
                durationMilliseconds: Self.durationMilliseconds(since: started),
                message: message
            )
        } catch {
            return GatewayDiagnosticCheck(
                id: id,
                title: title,
                endpoint: endpoint,
                status: .failed,
                durationMilliseconds: Self.durationMilliseconds(since: started),
                message: Self.diagnosticMessage(for: error)
            )
        }
    }

    private func chatDiagnosticCheck(
        id: String,
        title: String,
        operation: String?,
        inputText: String?,
        model: String,
        gatewayURL: String,
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        validation: (String) throws -> String
    ) async -> GatewayDiagnosticCheck {
        await diagnosticCheck(id: id, title: title, endpoint: "POST /v1/chat/completions") {
            let content = try await chatCompletionContent(
                gatewayURL: gatewayURL,
                apiKey: apiKey,
                model: model,
                operation: operation,
                inputText: inputText,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: maxTokens,
                timeoutInterval: 90
            )
            return try validation(content)
        }
    }

    private static func validateStructuredActionContent(_ content: String, operation: String, fallbackText: String, requireChangedOutput: Bool) throws -> KeyboardActionOperationResult {
        let result: KeyboardActionOperationResult
        do {
            result = try KeyboardActionOperationResult.parse(content, operation: operation, fallbackText: fallbackText)
        } catch {
            throw GatewayDiagnosticValidationError.invalidJSON(operation)
        }
        if result.operation.trimmingCharacters(in: .whitespacesAndNewlines) != operation {
            throw GatewayDiagnosticValidationError.invalidOperation(expected: operation, actual: result.operation)
        }
        guard result.isStructuredResponse else { throw GatewayDiagnosticValidationError.invalidJSON(operation) }
        let output = result.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw GatewayDiagnosticValidationError.noUsableOutput(operation) }
        if requireChangedOutput && output.caseInsensitiveCompare(fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
            throw GatewayDiagnosticValidationError.unchangedOutput(operation)
        }
        return result
    }

    private static func skippedDiagnosticChecks(reason: String) -> [GatewayDiagnosticCheck] {
        [
            ("settings-correction-smoke", "Settings correction"),
            ("keyboard-suggestion-json", "Suggestion JSON"),
            ("complex-grammar-json", "Complex grammar JSON"),
            ("rewrite-json", "Rewrite JSON"),
            ("summarize-json", "Summarize JSON"),
            ("improve-rewrite-json", "Improve via Rewrite JSON")
        ].map { id, title in
            GatewayDiagnosticCheck(
                id: id,
                title: title,
                endpoint: "POST /v1/chat/completions",
                status: .skipped,
                durationMilliseconds: nil,
                message: reason
            )
        }
    }

    private static func durationMilliseconds(since started: Date) -> Int {
        max(0, Int((Date().timeIntervalSince(started) * 1000).rounded()))
    }

    private static func diagnosticMessage(for error: Error) -> String {
        let raw: String
        if let networkError = error as? NetworkError {
            raw = networkError.localizedDescription
        } else if error is KeyboardSuggestionParserError {
            raw = "Suggestion JSON did not return valid app JSON."
        } else if let localized = error as? LocalizedError, let description = localized.errorDescription {
            raw = description
        } else {
            raw = error.localizedDescription
        }
        return KeyboardActionErrorState.sanitized(raw)
    }

    private static func networkError(from error: CanonicalGatewayClientError) -> NetworkError {
        switch error {
        case .invalidURL:
            return .invalidURL
        case .notConfigured:
            return .unauthorized
        case .missingInput:
            return .unusableCorrection
        case .unauthorized:
            return .unauthorized
        case .modelUnavailable:
            return .modelUnavailable
        case .invalidResponse, .unusableCorrection:
            return .unusableCorrection
        case .timeout:
            return .timeout
        case .serverStatus(let status):
            return .serverError("HTTP \(status)")
        case .transport:
            return .networkError(URLError(.unknown))
        }
    }
}

private struct ModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}

private struct HealthResponse: Decodable {
    let status: String
}
