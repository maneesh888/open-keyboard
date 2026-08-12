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
    case notEnoughCorrectionDetail(required: Int, actual: Int)

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
        case .notEnoughCorrectionDetail(let required, let actual):
            return "Correction response returned \(actual) valid atomic item\(actual == 1 ? "" : "s"); \(required) required."
        }
    }
}

class NetworkManager {
    static let shared = NetworkManager()
    static let diagnosticSettingsCorrectionInput = "i recieved teh refnd."
    static let diagnosticKeyboardCorrectionInput = "i recieved teh refnd"
    static let diagnosticAtomicCorrectionInput = "teh cliant recieve a refnd"
    static let correctionSmokeTestPhrases: [String] = [
        "I sent teh cliant an update this morning, but the timline still sound confussing to everyone.",
        "Our suport team definately need clearer notes befor they reply to the customer about the delayed refnd.",
        "The designer recieve the feedbak yestarday, but she forget to explan why the button moved.",
        "Please seperate the billing qustions from the logn issues so the right team is answr faster.",
        "I accidently marked the shipment as delievered even though the driver were still waitng outside.",
        "The meetng notes is missing several actoin items, and teh prototype deadline look wrng.",
        "My freind want to rephrase this mesage before sending it to the coatch after practce.",
        "We should of warnd the users that the repot are slower when the server is busy.",
        "The calendar say tommorow is free, but I promissed to reveiw the launch checlist.",
        "This onboarding email are too blunt and realy need a warmer explanaton for new customers.",
        "The app are recieveing the wrong text after editting, so the improved sentance feel unrelatted.",
        "Can you adress the confussing paragraf where I explains why the paymant failed twice?",
        "The project update has good detials, but the opening sentance are wierd and too casul.",
        "I wrote a quick apoligy to the cliant, but the grammer and tone both needs work.",
        "The button dissapeared untill I retryed the action, so the tester were unable to finish the demo."
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
        let smokeInput = Self.diagnosticSettingsCorrectionInput
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
            _ = try Self.validateAtomicCorrectionContent(content, inputText: smokeInput, minimumCount: 1)
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

        let settingsSmokeInput = Self.diagnosticSettingsCorrectionInput
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
            maxTokens: 1600,
            validationAttempts: 2
        ) { content in
            _ = try Self.validateAtomicCorrectionContent(content, inputText: settingsSmokeInput, minimumCount: 1)
            return "Correction smoke returned usable structured JSON for: \"\(settingsSmokeInput)\""
        })

        let suggestionInput = Self.diagnosticKeyboardCorrectionInput
        checks.append(await chatDiagnosticCheck(
            id: "keyboard-correction-card-json",
            title: "Keyboard correction cards",
            operation: nil,
            inputText: nil,
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: SemanticPromptContract.keyboardSuggestionsSystemInstruction,
            userPrompt: KeyboardSuggestionParser.prompt(for: suggestionInput),
            maxTokens: 1_200,
            validationAttempts: 2
        ) { content in
            let parsed = try KeyboardSuggestionParser.parseAssistantContent(content)
            let corrections = parsed.corrections.filter { $0.isAtomicCorrection(for: suggestionInput) }
            guard !corrections.isEmpty else { throw GatewayDiagnosticValidationError.notEnoughCorrectionDetail(required: 1, actual: 0) }
            return "Parsed \(corrections.count) valid keyboard correction card\(corrections.count == 1 ? "" : "s")."
        })

        let complexGrammarInput = Self.diagnosticAtomicCorrectionInput
        checks.append(await chatDiagnosticCheck(
            id: "atomic-correction-json",
            title: "Atomic correction cards",
            operation: "fix_grammar",
            inputText: complexGrammarInput,
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: KeyboardGatewayActionContract.structuredSystemPrompt,
            userPrompt: KeyboardGatewayActionContract.prompt(operation: "fix_grammar", text: complexGrammarInput),
            maxTokens: 5_000,
            validationAttempts: 2
        ) { content in
            let result = try Self.validateAtomicCorrectionContent(content, inputText: complexGrammarInput, minimumCount: 2)
            let correctionCount = result.suggestionResponse(sourceText: complexGrammarInput).corrections.count
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
            maxTokens: 3_000,
            optionalForSelectedModel: true
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
            maxTokens: 2_000,
            optionalForSelectedModel: true
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
            maxTokens: 3_000,
            optionalForSelectedModel: true
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
        optionalForSelectedModel: Bool = false,
        validationAttempts: Int = 1,
        validation: (String) throws -> String
    ) async -> GatewayDiagnosticCheck {
        let started = Date()
        do {
            let attempts = max(1, validationAttempts)
            var lastValidationError: Error?
            for attempt in 1...attempts {
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
                do {
                    let message = try validation(content)
                    return GatewayDiagnosticCheck(
                        id: id,
                        title: title,
                        endpoint: "POST /v1/chat/completions",
                        status: .passed,
                        durationMilliseconds: Self.durationMilliseconds(since: started),
                        message: attempt == 1 ? message : "\(message) Passed after \(attempt) attempts."
                    )
                } catch {
                    lastValidationError = error
                    guard attempt < attempts, Self.isModelCapabilityValidationError(error) else { throw error }
                }
            }
            throw lastValidationError ?? GatewayDiagnosticValidationError.noUsableOutput(operation ?? title)
        } catch {
            let isOptionalCapabilityGap = optionalForSelectedModel && Self.isModelCapabilityValidationError(error)
            let message = Self.diagnosticMessage(for: error)
            return GatewayDiagnosticCheck(
                id: id,
                title: title,
                endpoint: "POST /v1/chat/completions",
                status: isOptionalCapabilityGap ? .skipped : .failed,
                durationMilliseconds: Self.durationMilliseconds(since: started),
                message: isOptionalCapabilityGap ? "Optional for \(model): \(message)" : message
            )
        }
    }

    private static func validateAtomicCorrectionContent(
        _ content: String,
        inputText: String,
        minimumCount: Int
    ) throws -> KeyboardActionOperationResult {
        let result = try validateStructuredActionContent(
            content,
            operation: "fix_grammar",
            fallbackText: inputText,
            requireChangedOutput: true
        )
        let correctionCount = result.suggestionResponse(sourceText: inputText).corrections.count
        guard correctionCount >= minimumCount else {
            throw GatewayDiagnosticValidationError.notEnoughCorrectionDetail(
                required: minimumCount,
                actual: correctionCount
            )
        }
        return result
    }

    private static func isModelCapabilityValidationError(_ error: Error) -> Bool {
        error is GatewayDiagnosticValidationError || error is KeyboardSuggestionParserError
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
            ("keyboard-correction-card-json", "Keyboard correction cards"),
            ("atomic-correction-json", "Atomic correction cards"),
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
