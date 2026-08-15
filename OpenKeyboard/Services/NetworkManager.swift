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
    case cancelled

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
            return "Gateway connected, but the selected model did not respond within the model-check limit."
        case .cancelled:
            return "The gateway request was cancelled."
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

class NetworkManager {
    static let shared = NetworkManager()
    static let diagnosticSettingsCorrectionInput = "i recieved teh refnd."
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

    /// Run a correction smoke through the same plain-text chat completions contract
    /// used by the keyboard action path.
    func testCorrectionSmoke(gatewayURL: String, apiKey: String, model: String) async throws {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw NetworkError.modelUnavailable }
        let smokeInput = Self.diagnosticSettingsCorrectionInput
        let grammarRendering = KeyboardGatewayActionContract.rendering(operation: "fix_grammar", text: smokeInput)
        let validationAttempts = 2
        for attempt in 1...validationAttempts {
            let content = try await chatCompletionContent(
                gatewayURL: gatewayURL,
                apiKey: apiKey,
                model: trimmedModel,
                operation: "fix_grammar",
                inputText: smokeInput,
                systemPrompt: grammarRendering.messages[0].content,
                userPrompt: grammarRendering.messages[1].content,
                maxTokens: grammarRendering.maxTokens,
                temperature: grammarRendering.temperature,
                expectsStructuredResponse: false,
                timeoutInterval: GatewayRequestTimeouts.modelCheckAttempt
            )
            do {
                _ = try Self.validatePlainTextCorrectionContent(content, inputText: smokeInput, minimumCount: 1)
                return
            } catch {
                guard attempt < validationAttempts else { throw NetworkError.unusableCorrection }
            }
        }
    }

    func runGatewayDiagnostics(gatewayURL: String, apiKey: String, preferredModel: String) async -> GatewayDiagnosticReport {
        let trimmedPreferredModel = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        var models: [String] = []
        var checks: [GatewayDiagnosticCheck] = []

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
            checks.append(Self.skippedGrammarDiagnostic(reason: "Skipped because no model was available."))
            return GatewayDiagnosticReport(selectedModel: selectedModel, checks: checks)
        }

        checks.append(await diagnosticCheck(
            id: "settings-correction-smoke",
            title: "Plain-text grammar",
            endpoint: "POST /v1/chat/completions"
        ) {
            try await testCorrectionSmoke(
                gatewayURL: gatewayURL,
                apiKey: apiKey,
                model: selectedModel
            )
            return "Returned complete corrected text and derived local edits."
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
                return "Gateway connected, but the selected model did not respond within 20 seconds. Choose a faster model or retry."
            case .modelUnavailable:
                return "The selected model is not available for this key."
            case .unusableCorrection:
                return "Gateway connected, but the selected model did not return a usable correction."
            case .cancelled:
                return "The gateway request was cancelled."
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
        } catch is CancellationError {
            throw NetworkError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw NetworkError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw NetworkError.timeout
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
        temperature: Double? = 0.1,
        expectsStructuredResponse: Bool? = nil,
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
                    grammarCorrectionVerified: true,
                    grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
                ),
                temperature: temperature,
                expectsStructuredResponse: expectsStructuredResponse,
                timeoutInterval: timeoutInterval
            )
        } catch let error as NetworkError {
            throw error
        } catch is CancellationError {
            throw NetworkError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw NetworkError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw NetworkError.timeout
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

    private static func validatePlainTextCorrectionContent(
        _ content: String,
        inputText: String,
        minimumCount: Int
    ) throws -> Int {
        let corrected: String
        do {
            corrected = try GrammarCorrectionResponseValidator.validated(content, original: inputText)
        } catch {
            throw NetworkError.unusableCorrection
        }
        let correctionCount = GrammarDiffService.edits(from: inputText, to: corrected).filter {
            !$0.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        guard correctionCount >= minimumCount else { throw NetworkError.unusableCorrection }
        return correctionCount
    }

    private static func skippedGrammarDiagnostic(reason: String) -> GatewayDiagnosticCheck {
        GatewayDiagnosticCheck(
            id: "settings-correction-smoke",
            title: "Plain-text grammar",
            endpoint: "POST /v1/chat/completions",
            status: .skipped,
            durationMilliseconds: nil,
            message: reason
        )
    }

    private static func durationMilliseconds(since started: Date) -> Int {
        max(0, Int((Date().timeIntervalSince(started) * 1000).rounded()))
    }

    private static func diagnosticMessage(for error: Error) -> String {
        let raw: String
        if let networkError = error as? NetworkError {
            raw = networkError.localizedDescription
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
