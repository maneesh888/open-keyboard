//
//  NetworkManager.swift
//  OpenKeyboard
//
//  Network service for gateway communication
//

import Foundation

enum NetworkError: Error {
    case invalidURL
    case noData
    case unauthorized
    case serverError(String)
    case networkError(Error)
    case modelUnavailable
    case unusableCorrection
    case unusableCapability(String)
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
        case .unusableCapability(let capability):
            return "The selected model did not return a usable \(capability) response."
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
    static let shared = NetworkManager(connector: UniversalAIConnectorAdapter.shared)
    static let grammarDiagnosticPresetID = "plain-grammar-fast"
    static let rewriteDiagnosticPresetID = "structured-operation-rewrite"
    static let translationDiagnosticPresetID = "structured-operation-translate-dutch"
    static var diagnosticSettingsCorrectionInput: String {
        requiredGatewayPreset(id: grammarDiagnosticPresetID).input
    }
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

    private let connector: OpenKeyboardAIConnectorServing

    init(connector: OpenKeyboardAIConnectorServing = UniversalAIConnectorAdapter.shared) {
        self.connector = connector
    }

    /// Run a correction smoke through the same plain-text chat completions contract
    /// used by the keyboard action path.
    func testCorrectionSmoke(gatewayURL: String, apiKey: String, model: String) async throws {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw NetworkError.modelUnavailable }
        let preset = Self.requiredGatewayPreset(id: Self.grammarDiagnosticPresetID)
        let smokeInput = preset.input
        let grammarRendering = preset.rendering
        let validationAttempts = 2
        for attempt in 1...validationAttempts {
            let content = try await connectorResponseContent(
                gatewayURL: gatewayURL,
                apiKey: apiKey,
                model: trimmedModel,
                rendering: grammarRendering,
                timeoutInterval: GatewayRequestTimeouts.modelCheckAttempt
            )
            do {
                _ = try await Self.validatePlainTextCorrectionContent(content, inputText: smokeInput, minimumCount: 1)
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

        let modelsOutcome = await diagnosticCheck(
            id: "models",
            title: "Models",
            endpoint: "GET /v1/models"
        ) {
            models = try await fetchModels(gatewayURL: gatewayURL, apiKey: apiKey)
            guard !models.isEmpty else { throw NetworkError.modelUnavailable }
            return "Loaded \(models.count) model\(models.count == 1 ? "" : "s")."
        }
        checks.append(modelsOutcome.check)
        guard !modelsOutcome.wasCancelled else {
            return GatewayDiagnosticReport(selectedModel: trimmedPreferredModel, checks: checks)
        }

        let selectedModel = trimmedPreferredModel

        let capabilities: [(id: String, title: String, presetID: String, success: String)] = [
            (
                "settings-correction-smoke",
                "Fast plain-text grammar",
                Self.grammarDiagnosticPresetID,
                "Returned complete corrected text with a usable local edit."
            ),
            (
                "settings-rewrite-improve",
                "Rewrite and Improve",
                Self.rewriteDiagnosticPresetID,
                "Returned one complete validated plain-text replacement used by Rewrite and Improve."
            ),
            (
                "settings-translation-dutch",
                "Translation to Dutch",
                Self.translationDiagnosticPresetID,
                "Returned one complete validated Dutch translation."
            )
        ]
        for capability in capabilities {
            guard !Task.isCancelled else { break }
            let outcome = await diagnosticCheck(
                id: capability.id,
                title: capability.title,
                endpoint: "POST /v1/chat/completions"
            ) {
                // Capability probes are deliberately independent from model discovery. The exact
                // selected model may still accept completions when /models is unavailable or
                // incomplete, and a failed probe must not prevent the remaining probes from
                // reporting their own outcome.
                guard !selectedModel.isEmpty else { throw NetworkError.modelUnavailable }
                try await testDiagnosticCapability(
                    gatewayURL: gatewayURL,
                    apiKey: apiKey,
                    model: selectedModel,
                    presetID: capability.presetID
                )
                return capability.success
            }
            checks.append(outcome.check)
            if outcome.wasCancelled { break }
        }

        return GatewayDiagnosticReport(selectedModel: selectedModel, checks: checks)
    }

    private func testDiagnosticCapability(
        gatewayURL: String,
        apiKey: String,
        model: String,
        presetID: String
    ) async throws {
        let preset = Self.requiredGatewayPreset(id: presetID)
        let rendering = preset.rendering
        let content = try await connectorResponseContent(
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            model: model,
            rendering: rendering,
            timeoutInterval: GatewayRequestTimeouts.modelCheckAttempt
        )
        do {
            let validatedOutput = try SemanticPromptContract.validateGatewayPromptResponse(content, presetID: presetID)
            if presetID == Self.grammarDiagnosticPresetID {
                _ = try await Self.validatePlainTextCorrectionContent(content, inputText: preset.input, minimumCount: 1)
            } else if presetID == Self.translationDiagnosticPresetID,
                      TranslationLanguageOutputValidator().validationFailure(
                          for: validatedOutput,
                          expectedScript: .latin,
                          expectedLanguageCodes: ["nl"]
                      ) != nil {
                throw NetworkError.unusableCapability("Dutch translation")
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            if presetID == Self.rewriteDiagnosticPresetID {
                throw NetworkError.unusableCapability("Rewrite and Improve")
            }
            if presetID == Self.translationDiagnosticPresetID {
                throw NetworkError.unusableCapability("Dutch translation")
            }
            let capability = preset.label
                .replacingOccurrences(of: "Plain-text operation · ", with: "")
                .replacingOccurrences(of: "Plain-text grammar · ", with: "")
            throw NetworkError.unusableCapability(capability.lowercased())
        }
    }

    private static func requiredGatewayPreset(id: String) -> SemanticGatewayPromptPreset {
        guard let preset = SemanticPromptContract.gatewayPromptPreset(id: id) else {
            preconditionFailure("semantic-prompt-contract \(SemanticPromptContract.version) is missing gateway preset \(id)")
        }
        return preset
    }

    static func isUsableCorrectionSmokeResponse(_ value: String) -> Bool {
        let normalized = value.lowercased().trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters)
        )
        guard !normalized.isEmpty else { return false }
        return normalized.contains("i have an apple")
            || normalized.contains("i have a apple")
            || normalized.contains("i had an apple")
            || (normalized.contains("have") && normalized.contains("apple"))
    }

    static func randomCorrectionSmokeTestPhrase() -> String {
        correctionSmokeTestPhrases.randomElement() ?? "i has a apple"
    }

    static func normalizedGatewayBaseURLString(_ value: String) throws -> String {
        do {
            return try GatewayURLNormalizer.normalizedStoredBaseURLString(value)
        } catch {
            throw NetworkError.invalidURL
        }
    }

    static func endpointURL(gatewayURL: String, path: String) throws -> URL {
        do {
            let base = try GatewayURLNormalizer.normalizedStoredBaseURLString(gatewayURL)
            let cleanedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: "\(base)/\(cleanedPath)") else {
                throw OpenKeyboardAIConnectorError.invalidURL
            }
            return url
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
        do {
            let profile = try OpenKeyboardGatewayProfile(
                gatewayURL: gatewayURL,
                apiKey: apiKey
            )
            return try await OpenKeyboardRequestDeadline.value(
                timeoutInterval: GatewayRequestTimeouts.modelCheckAttempt
            ) {
                try await self.connector.listModels(profile: profile)
            }
        } catch let error as NetworkError {
            throw error
        } catch is CancellationError {
            throw NetworkError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw NetworkError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw NetworkError.timeout
        } catch let error as OpenKeyboardAIConnectorError {
            throw Self.networkError(from: error, responseOperation: false)
        } catch {
            throw NetworkError.networkError(error)
        }
    }

    private func connectorResponseContent(
        gatewayURL: String,
        apiKey: String,
        model: String,
        rendering: SemanticPromptRendering,
        timeoutInterval: TimeInterval
    ) async throws -> String {
        do {
            let profile = try OpenKeyboardGatewayProfile(
                gatewayURL: gatewayURL,
                apiKey: apiKey
            )
            let request = try OpenKeyboardAIRequest.writing(
                rendering: rendering,
                modelID: model,
                timeoutInterval: timeoutInterval
            )
            return try await OpenKeyboardRequestDeadline.value(
                timeoutInterval: timeoutInterval
            ) {
                try await self.connector.respond(to: request, profile: profile)
            }
        } catch let error as NetworkError {
            throw error
        } catch is CancellationError {
            throw NetworkError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw NetworkError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw NetworkError.timeout
        } catch let error as OpenKeyboardAIConnectorError {
            throw Self.networkError(from: error, responseOperation: true)
        } catch {
            throw NetworkError.networkError(error)
        }
    }

    private func diagnosticCheck(
        id: String,
        title: String,
        endpoint: String,
        operation: () async throws -> String
    ) async -> (check: GatewayDiagnosticCheck, wasCancelled: Bool) {
        let started = Date()
        do {
            let message = try await operation()
            return (GatewayDiagnosticCheck(
                id: id,
                title: title,
                endpoint: endpoint,
                status: .passed,
                durationMilliseconds: Self.durationMilliseconds(since: started),
                message: message
            ), false)
        } catch {
            return (GatewayDiagnosticCheck(
                id: id,
                title: title,
                endpoint: endpoint,
                status: .failed,
                durationMilliseconds: Self.durationMilliseconds(since: started),
                message: Self.diagnosticMessage(for: error)
            ), Self.isDiagnosticCancellation(error))
        }
    }

    private static func isDiagnosticCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let networkError = error as? NetworkError, case .cancelled = networkError { return true }
        return false
    }

    @MainActor
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

    private static func durationMilliseconds(since started: Date) -> Int {
        max(0, Int((Date().timeIntervalSince(started) * 1000).rounded()))
    }

    static func diagnosticMessage(for error: Error) -> String {
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

    private static func networkError(
        from error: OpenKeyboardAIConnectorError,
        responseOperation: Bool
    ) -> NetworkError {
        switch error {
        case .invalidURL:
            return .invalidURL
        case .notConfigured:
            return .unauthorized
        case .missingInput:
            return .unusableCorrection
        case .unauthorized, .forbidden:
            return .unauthorized
        case .modelUnavailable:
            return .modelUnavailable
        case .invalidResponse, .truncatedResponse:
            return responseOperation ? .unusableCorrection : .noData
        case .timeout:
            return .timeout
        case .rateLimited:
            return .serverError("HTTP 429")
        case .serverStatus(let statusCode):
            return .serverError("HTTP \(statusCode)")
        case .unsupportedModelDiscovery:
            return .serverError("Model discovery is not supported by this gateway.")
        case .transport, .provider, .closed:
            return .networkError(URLError(.unknown))
        }
    }
}
