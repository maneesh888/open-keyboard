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
    case unsupportedModelDiscovery
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
        case .unsupportedModelDiscovery:
            return "This provider does not support model discovery. Enter an exact model identifier."
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
    private let diagnostics: AIOperationDiagnostics

    init(connector: OpenKeyboardAIConnectorServing = UniversalAIConnectorAdapter.shared, diagnostics: AIOperationDiagnostics = .shared) {
        self.connector = connector
        self.diagnostics = diagnostics
    }

    /// Run a correction smoke through the same plain-text chat completions contract
    /// used by the keyboard action path.
    func testCorrectionSmoke(gatewayURL: String, apiKey: String, model: String) async throws {
        let profile = try Self.profile(
            provider: .openAICompatible,
            baseURL: gatewayURL,
            apiKey: apiKey
        )
        try await testCorrectionSmoke(profile: profile, model: model)
    }

    func testCorrectionSmoke(profile: OpenKeyboardGatewayProfile, model: String) async throws {
        try await performDiagnosed(
            operation: .gatewayConnectionCheck,
            origin: .hostAppGatewayCheck
        ) {
            let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedModel.isEmpty else { throw NetworkError.modelUnavailable }
            let preset = Self.requiredGatewayPreset(id: Self.grammarDiagnosticPresetID)
            let smokeInput = preset.input
            let grammarRendering = preset.rendering
            let content = try await connectorResponseContent(
                profile: profile,
                model: trimmedModel,
                rendering: grammarRendering,
                timeoutInterval: GatewayRequestTimeouts.modelCheckAttempt
            )
            do {
                _ = try await Self.validatePlainTextCorrectionContent(
                    content,
                    inputText: smokeInput,
                    minimumCount: 1
                )
                recordValidation()
            } catch {
                recordValidation(failure: .validationRejected)
                throw NetworkError.unusableCorrection
            }
        }
    }

    func runGatewayDiagnostics(gatewayURL: String, apiKey: String, preferredModel: String) async -> GatewayDiagnosticReport {
        do {
            return await runGatewayDiagnostics(
                profile: try Self.profile(
                    provider: .openAICompatible,
                    baseURL: gatewayURL,
                    apiKey: apiKey
                ),
                preferredModel: preferredModel
            )
        } catch {
            return Self.invalidConfigurationDiagnosticReport(
                preferredModel: preferredModel,
                error: error
            )
        }
    }

    func runGatewayDiagnostics(
        profile: OpenKeyboardGatewayProfile,
        preferredModel: String
    ) async -> GatewayDiagnosticReport {
        let traceID = diagnostics.begin(
            operation: .gatewayDiagnostics,
            origin: .hostAppDiagnostics
        )
        diagnostics.record(traceID: traceID, stage: .contextCapture)
        return await AIOperationDiagnosticContext.$traceID.withValue(traceID) {
            let (report, wasCancelled) = await runGatewayDiagnosticsTracked(
                profile: profile,
                preferredModel: preferredModel
            )
            diagnostics.complete(
                traceID: traceID,
                outcome: wasCancelled ? .cancelled : (report.hasFailures ? .failed : .succeeded),
                failure: wasCancelled ? .cancelled : (report.hasFailures ? .validationRejected : nil)
            )
            return report
        }
    }

    private func runGatewayDiagnosticsTracked(
        profile: OpenKeyboardGatewayProfile,
        preferredModel: String
    ) async -> (report: GatewayDiagnosticReport, wasCancelled: Bool) {
        let trimmedPreferredModel = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        var models: [String] = []
        var checks: [GatewayDiagnosticCheck] = []

        let modelsOutcome = await diagnosticCheck(
            id: "models",
            title: "Models",
            endpoint: Self.modelDiscoveryEndpoint(for: profile.provider),
            unsupportedModelDiscoveryIsSkipped: true
        ) {
            models = try await fetchModels(profile: profile)
            guard !models.isEmpty else { throw NetworkError.modelUnavailable }
            return "Loaded \(models.count) model\(models.count == 1 ? "" : "s")."
        }
        checks.append(modelsOutcome.check)
        guard !modelsOutcome.wasCancelled else {
            return (GatewayDiagnosticReport(selectedModel: trimmedPreferredModel, checks: checks), true)
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
                endpoint: Self.responseEndpoint(for: profile.provider)
            ) {
                // Capability probes are deliberately independent from model discovery. The exact
                // selected model may still accept completions when /models is unavailable or
                // incomplete, and a failed probe must not prevent the remaining probes from
                // reporting their own outcome.
                guard !selectedModel.isEmpty else { throw NetworkError.modelUnavailable }
                try await testDiagnosticCapability(
                    profile: profile,
                    model: selectedModel,
                    presetID: capability.presetID
                )
                return capability.success
            }
            checks.append(outcome.check)
            if outcome.wasCancelled {
                return (GatewayDiagnosticReport(selectedModel: selectedModel, checks: checks), true)
            }
        }

        return (GatewayDiagnosticReport(selectedModel: selectedModel, checks: checks), Task.isCancelled)
    }

    private func testDiagnosticCapability(
        profile: OpenKeyboardGatewayProfile,
        model: String,
        presetID: String
    ) async throws {
        let preset = Self.requiredGatewayPreset(id: presetID)
        let rendering = preset.rendering
        let content = try await connectorResponseContent(
            profile: profile,
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
            recordValidation()
        } catch let error as NetworkError {
            recordValidation(failure: .validationRejected)
            throw error
        } catch {
            recordValidation(failure: .validationRejected)
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
        try normalizedProviderBaseURLString(value, provider: .openAICompatible)
    }

    static func normalizedProviderBaseURLString(
        _ value: String,
        provider: OpenKeyboardAIProvider
    ) throws -> String {
        do {
            return try GatewayURLNormalizer.normalizedStoredBaseURLString(
                value,
                provider: provider
            )
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
        let profile = try Self.profile(
            provider: .openAICompatible,
            baseURL: gatewayURL,
            apiKey: apiKey
        )
        return try await fetchModels(profile: profile)
    }

    func fetchModels(profile: OpenKeyboardGatewayProfile) async throws -> [String] {
        try await performDiagnosed(
            operation: .modelDiscovery,
            origin: .hostAppModelDiscovery
        ) {
            do {
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
    }

    private func connectorResponseContent(
        profile: OpenKeyboardGatewayProfile,
        model: String,
        rendering: SemanticPromptRendering,
        timeoutInterval: TimeInterval
    ) async throws -> String {
        do {
            let request = try OpenKeyboardAIRequest.writing(
                rendering: rendering,
                modelID: model,
                timeoutInterval: timeoutInterval
            )
            recordPromptConstruction(for: request)
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

    private func performDiagnosed<Value>(
        operation: AIOperationDiagnosticOperation,
        origin: AIOperationDiagnosticOrigin,
        work: () async throws -> Value
    ) async throws -> Value {
        if AIOperationDiagnosticContext.traceID != nil {
            return try await work()
        }

        let traceID = diagnostics.begin(operation: operation, origin: origin)
        diagnostics.record(traceID: traceID, stage: .contextCapture)
        do {
            let value = try await AIOperationDiagnosticContext.$traceID.withValue(traceID) {
                try await work()
            }
            diagnostics.complete(traceID: traceID, outcome: .succeeded)
            return value
        } catch is CancellationError {
            diagnostics.record(
                traceID: traceID,
                stage: .cancellation,
                failure: .cancelled
            )
            diagnostics.complete(
                traceID: traceID,
                outcome: .cancelled,
                failure: .cancelled
            )
            throw NetworkError.cancelled
        } catch NetworkError.cancelled {
            diagnostics.record(
                traceID: traceID,
                stage: .cancellation,
                failure: .cancelled
            )
            diagnostics.complete(
                traceID: traceID,
                outcome: .cancelled,
                failure: .cancelled
            )
            throw NetworkError.cancelled
        } catch {
            diagnostics.complete(
                traceID: traceID,
                outcome: .failed,
                failure: Self.diagnosticFailure(for: error)
            )
            throw error
        }
    }

    private func recordPromptConstruction(for request: OpenKeyboardAIRequest) {
        guard let traceID = AIOperationDiagnosticContext.traceID else { return }
        let byteCount = request.messages.reduce(0) { partial, message in
            partial + message.content.lengthOfBytes(using: .utf8)
        }
        diagnostics.record(
            traceID: traceID,
            stage: .promptConstruction,
            requestBytes: byteCount
        )
    }

    private func recordValidation(
        failure: AIOperationDiagnosticFailure? = nil
    ) {
        guard let traceID = AIOperationDiagnosticContext.traceID else { return }
        diagnostics.record(
            traceID: traceID,
            stage: .validation,
            failure: failure
        )
    }

    private static func diagnosticFailure(for error: Error) -> AIOperationDiagnosticFailure {
        if error is CancellationError { return .cancelled }
        guard let error = error as? NetworkError else { return .transportFailure }
        switch error {
        case .timeout:
            return .transportTimeout
        case .noData, .networkError:
            return .gatewayNonresponse
        case .unusableCorrection, .unusableCapability:
            return .validationRejected
        case .cancelled:
            return .cancelled
        case .serverError, .unauthorized, .modelUnavailable, .unsupportedModelDiscovery, .invalidURL:
            return .gatewayRejected
        }
    }

    private func diagnosticCheck(
        id: String,
        title: String,
        endpoint: String,
        unsupportedModelDiscoveryIsSkipped: Bool = false,
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
            let isUnsupported = unsupportedModelDiscoveryIsSkipped
                && Self.isUnsupportedModelDiscovery(error)
            return (GatewayDiagnosticCheck(
                id: id,
                title: title,
                endpoint: endpoint,
                status: isUnsupported ? .skipped : .failed,
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

    private static func isUnsupportedModelDiscovery(_ error: Error) -> Bool {
        guard let networkError = error as? NetworkError else { return false }
        if case .unsupportedModelDiscovery = networkError { return true }
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
            corrected = try GrammarCorrectionResponseValidator.classified(
                content,
                original: inputText
            ).text
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

    func closeConnector() {
        connector.close()
    }

    private static func profile(
        provider: OpenKeyboardAIProvider,
        baseURL: String,
        apiKey: String
    ) throws -> OpenKeyboardGatewayProfile {
        do {
            return try OpenKeyboardGatewayProfile(
                provider: provider,
                baseURL: baseURL,
                apiKey: apiKey
            )
        } catch let error as OpenKeyboardAIConnectorError {
            throw networkError(from: error, responseOperation: false)
        } catch {
            throw NetworkError.networkError(error)
        }
    }

    private static func invalidConfigurationDiagnosticReport(
        preferredModel: String,
        error: Error
    ) -> GatewayDiagnosticReport {
        GatewayDiagnosticReport(
            selectedModel: preferredModel.trimmingCharacters(in: .whitespacesAndNewlines),
            checks: [
                GatewayDiagnosticCheck(
                    id: "diagnostic-input",
                    title: "Configuration",
                    endpoint: "-",
                    status: .failed,
                    durationMilliseconds: nil,
                    message: diagnosticMessage(for: error)
                )
            ]
        )
    }

    private static func modelDiscoveryEndpoint(for provider: OpenKeyboardAIProvider) -> String {
        switch provider {
        case .anthropic:
            return "Connector model discovery"
        case .openAI, .openAICompatible:
            return "GET /v1/models"
        case .openRouter:
            return "GET /api/v1/models"
        }
    }

    private static func responseEndpoint(for provider: OpenKeyboardAIProvider) -> String {
        switch provider {
        case .anthropic:
            return "POST /v1/messages"
        case .openAI:
            return "POST /v1/responses"
        case .openAICompatible:
            return "POST /v1/chat/completions"
        case .openRouter:
            return "POST /api/v1/chat/completions"
        }
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
            return .unsupportedModelDiscovery
        case .transport, .provider, .closed:
            return .networkError(URLError(.unknown))
        }
    }
}
