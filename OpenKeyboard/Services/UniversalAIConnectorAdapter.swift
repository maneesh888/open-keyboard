import Foundation
import UniversalAiConnector

protocol UniversalAIConnectorRuntime: AnyObject, Sendable {
    func listModels(providerId: UniversalAiProviderId) async throws -> UniversalAiModelListResult
    func respond(to request: UniversalAiRequest) async throws -> UniversalAiResponse
    func close()
}

extension UniversalAiConnector: UniversalAIConnectorRuntime {}

/// Process-local ownership boundary for the reusable Universal AI Connector.
/// The app and extension each compile this type into their own process and therefore
/// keep independent lifecycles while sharing a connector across operations in-process.
final class UniversalAIConnectorAdapter: OpenKeyboardAIConnectorServing, @unchecked Sendable {
    typealias RuntimeFactory = (OpenKeyboardGatewayProfile) throws -> UniversalAIConnectorRuntime

    static let shared = UniversalAIConnectorAdapter()

    private let store: RuntimeStore
    private let diagnostics: AIOperationDiagnostics

    init(factory: @escaping RuntimeFactory = UniversalAIConnectorAdapter.makeRuntime, diagnostics: AIOperationDiagnostics = .shared) {
        store = RuntimeStore(factory: factory)
        self.diagnostics = diagnostics
    }

    deinit {
        store.close()
    }

    func listModels(profile: OpenKeyboardGatewayProfile) async throws -> [String] {
        let traceID = AIOperationDiagnosticContext.traceID
        let requestID = traceID.flatMap { diagnostics.beginRequest(traceID: $0, provider: profile.provider) }
        let transportStarted = Date()
        if let traceID {
            diagnostics.record(traceID: traceID, stage: .transport, requestID: requestID)
        }
        do {
            let runtime = try store.runtime(for: profile)
            let providerId = UniversalAiProviderId(rawValue: profile.providerID)
            switch try await runtime.listModels(providerId: providerId) {
            case let .supported(returnedProviderId, models):
                guard returnedProviderId == providerId,
                      models.allSatisfy({ $0.target.providerId == providerId }) else {
                    throw SafeResponseRejection.targetMismatch
                }
                if let traceID {
                    let durationMilliseconds = Self.durationMilliseconds(since: transportStarted)
                    diagnostics.record(
                        traceID: traceID,
                        stage: .transport,
                        durationMilliseconds: durationMilliseconds,
                        requestID: requestID,
                        connectorResponseAccepted: true
                    )
                    diagnostics.record(
                        traceID: traceID,
                        stage: .decoding,
                        durationMilliseconds: durationMilliseconds,
                        requestID: requestID
                    )
                }
                return models.map(\.target.modelId.rawValue)
            case let .unsupported(returnedProviderId):
                guard returnedProviderId == providerId else {
                    throw SafeResponseRejection.targetMismatch
                }
                throw OpenKeyboardAIConnectorError.unsupportedModelDiscovery
            }
        } catch {
            let mappedError = Self.mappedError(error)
            if let traceID {
                let diagnostic = Self.diagnosticFailure(
                    for: mappedError,
                    subreason: Self.diagnosticSubreason(for: error)
                )
                diagnostics.record(
                    traceID: traceID,
                    stage: diagnostic.stage,
                    durationMilliseconds: Self.durationMilliseconds(since: transportStarted),
                    httpStatusCategory: (error as? UniversalAiConnectorError).flatMap { Self.statusCode(from: $0) }.map(AIOperationDiagnosticHTTPStatusCategory.init(statusCode:)),
                    failure: diagnostic.failure,
                    subreason: diagnostic.subreason,
                    requestID: requestID,
                    httpStatusCode: (error as? UniversalAiConnectorError).flatMap { Self.statusCode(from: $0) }
                )
            }
            throw mappedError
        }
    }

    func respond(
        to request: OpenKeyboardAIRequest,
        profile: OpenKeyboardGatewayProfile
    ) async throws -> String {
        let traceID = AIOperationDiagnosticContext.traceID
        let requestID = traceID.flatMap {
            diagnostics.beginRequest(traceID: $0, provider: profile.provider, request: request)
        }
        let transportStarted = Date()
        if let traceID {
            diagnostics.record(
                traceID: traceID,
                stage: .transport,
                requestBytes: request.messages.reduce(0) { partial, message in
                    partial + message.content.lengthOfBytes(using: .utf8)
                },
                requestID: requestID
            )
        }
        do {
            let runtime = try store.runtime(for: profile)
            let connectorRequest = Self.connectorRequest(
                from: request,
                providerID: profile.providerID
            )
            let response = try await runtime.respond(to: connectorRequest)
            if let traceID, let requestID {
                diagnostics.recordResponse(
                    traceID: traceID, requestID: requestID,
                    text: response.outputs.first?.text,
                    completionReason: response.completionReason.rawValue,
                    outputCount: response.outputs.count
                )
            }
            let output = try Self.validatedPlainText(
                from: response,
                expectedTarget: connectorRequest.target
            )
            if let traceID {
                let durationMilliseconds = Self.durationMilliseconds(since: transportStarted)
                diagnostics.record(
                    traceID: traceID,
                    stage: .transport,
                    durationMilliseconds: durationMilliseconds,
                    responseBytes: output.lengthOfBytes(using: .utf8),
                    requestID: requestID,
                    connectorResponseAccepted: true
                )
                diagnostics.record(
                    traceID: traceID,
                    stage: .decoding,
                    durationMilliseconds: durationMilliseconds,
                    responseBytes: output.lengthOfBytes(using: .utf8),
                    requestID: requestID
                )
            }
            return output
        } catch {
            let mappedError = Self.mappedError(error)
            if let traceID {
                let diagnostic = Self.diagnosticFailure(
                    for: mappedError,
                    subreason: Self.diagnosticSubreason(for: error)
                )
                diagnostics.record(
                    traceID: traceID,
                    stage: diagnostic.stage,
                    durationMilliseconds: Self.durationMilliseconds(since: transportStarted),
                    httpStatusCategory: (error as? UniversalAiConnectorError).flatMap { Self.statusCode(from: $0) }.map(AIOperationDiagnosticHTTPStatusCategory.init(statusCode:)),
                    failure: diagnostic.failure,
                    subreason: diagnostic.subreason,
                    requestID: requestID,
                    httpStatusCode: (error as? UniversalAiConnectorError).flatMap { Self.statusCode(from: $0) }
                )
            }
            throw mappedError
        }
    }

    func close() {
        store.close()
    }

    static func connectorRequest(from request: OpenKeyboardAIRequest) -> UniversalAiRequest {
        connectorRequest(from: request, providerID: OpenKeyboardGatewayProfile.providerID)
    }

    static func connectorRequest(
        from request: OpenKeyboardAIRequest,
        providerID: String
    ) -> UniversalAiRequest {
        let sampling = samplingParameters(
            providerID: providerID,
            temperature: request.temperature,
            topP: request.topP
        )
        return UniversalAiRequest(
            target: UniversalAiTarget(
                providerId: UniversalAiProviderId(
                    rawValue: providerID
                ),
                modelId: UniversalAiModelId(rawValue: request.modelID)
            ),
            input: request.messages.map { message in
                UniversalAiTextInput(
                    role: UniversalAiInputRole(rawValue: message.role.rawValue),
                    content: message.content
                )
            },
            responseFormat: .plainText,
            generation: UniversalAiGenerationParameters(
                maxOutputTokens: request.maxOutputTokens,
                temperature: sampling.temperature,
                topP: sampling.topP,
                stopSequences: request.stopSequences
            )
        )
    }

    /// Sampling controls are semantic preferences, but they are not portable across every
    /// provider/model pair. Anthropic's connector adapter rejects explicit sampling controls,
    /// while some OpenAI Responses models reject non-default temperature or top-p values. Let
    /// those providers select their supported defaults while preserving the canonical prompt,
    /// token limit, and explicit sampling controls for OpenRouter and compatible gateways.
    private static func samplingParameters(
        providerID: String,
        temperature: Double?,
        topP: Double?
    ) -> (temperature: Double?, topP: Double?) {
        switch providerID {
        case OpenKeyboardAIProvider.openAI.rawValue,
             OpenKeyboardAIProvider.anthropic.rawValue:
            return (nil, nil)
        default:
            return (temperature, topP)
        }
    }

    static func plainText(
        from response: UniversalAiResponse,
        expectedTarget: UniversalAiTarget
    ) throws -> String {
        do {
            return try validatedPlainText(from: response, expectedTarget: expectedTarget)
        } catch let rejection as SafeResponseRejection {
            throw rejection.mappedError
        }
    }

    /// Validates the canonical plain-text response without discarding its closed local rejection
    /// category. `respond` uses this form so the diagnostic ledger can preserve that category;
    /// `plainText` remains the compatibility boundary for callers expecting app errors.
    static func validatedPlainText(
        from response: UniversalAiResponse,
        expectedTarget: UniversalAiTarget
    ) throws -> String {
        guard response.target == expectedTarget else {
            throw SafeResponseRejection.targetMismatch
        }
        switch response.completionReason {
        case .stop:
            break
        case .maxOutputTokens:
            throw OpenKeyboardAIConnectorError.truncatedResponse
        default:
            throw SafeResponseRejection.unexpectedCompletionReason
        }
        guard response.outputs.count == 1,
              let output = response.outputs.first else {
            throw SafeResponseRejection.invalidOutputCount
        }
        guard output.index == 0 else {
            throw SafeResponseRejection.unexpectedOutputIndex
        }
        guard output.kind == .text else {
            throw SafeResponseRejection.nonTextOutput
        }
        guard output.structuredJson == nil else {
            throw SafeResponseRejection.unexpectedStructuredOutput
        }
        guard let text = output.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SafeResponseRejection.missingOrEmptyText
        }
        return text
    }

    static func mappedError(_ error: Error) -> Error {
        if error is CancellationError {
            return CancellationError()
        }
        if let mapped = error as? OpenKeyboardAIConnectorError {
            return mapped
        }
        if let rejection = error as? SafeResponseRejection {
            return rejection.mappedError
        }
        guard let connectorError = error as? UniversalAiConnectorError else {
            if error is UniversalAiContractValidationError {
                return OpenKeyboardAIConnectorError.invalidResponse
            }
            return OpenKeyboardAIConnectorError.transport
        }

        let code = connectorError.code.rawValue
        if connectorError.category == .validation,
           code == UniversalAiErrorCode.invalidRequest.rawValue,
           connectorError.message == "The Universal AI Connector is closed." {
            return OpenKeyboardAIConnectorError.closed
        }
        switch code {
        case "connection_timeout", "request_timeout", "provider_request_timeout":
            return OpenKeyboardAIConnectorError.timeout
        case "provider_authentication_failed", "missing_credential":
            return OpenKeyboardAIConnectorError.unauthorized
        case "provider_permission_denied":
            return OpenKeyboardAIConnectorError.forbidden
        case "provider_resource_not_found":
            return OpenKeyboardAIConnectorError.modelUnavailable
        case "provider_rate_limited":
            return OpenKeyboardAIConnectorError.rateLimited
        case "provider_output_limit_reached", "provider_incomplete_response", "incomplete_stream":
            return OpenKeyboardAIConnectorError.truncatedResponse
        case "malformed_provider_response", "invalid_structured_provider_response", "malformed_provider_stream":
            return OpenKeyboardAIConnectorError.invalidResponse
        case "provider_unavailable":
            return OpenKeyboardAIConnectorError.serverStatus(
                statusCode(from: connectorError) ?? 503
            )
        case "provider_server_error", "provider_invalid_request":
            if let statusCode = statusCode(from: connectorError) {
                return OpenKeyboardAIConnectorError.serverStatus(statusCode)
            }
        default:
            break
        }

        switch connectorError.category {
        case .authentication:
            return OpenKeyboardAIConnectorError.unauthorized
        case .authorization:
            return OpenKeyboardAIConnectorError.forbidden
        case .notFound:
            return OpenKeyboardAIConnectorError.modelUnavailable
        case .rateLimit:
            return OpenKeyboardAIConnectorError.rateLimited
        case .transport:
            return OpenKeyboardAIConnectorError.transport
        case .protocol, .validation:
            return OpenKeyboardAIConnectorError.invalidResponse
        case .provider, .internal:
            return OpenKeyboardAIConnectorError.provider
        default:
            return OpenKeyboardAIConnectorError.provider
        }
    }

    private static func makeRuntime(
        profile: OpenKeyboardGatewayProfile
    ) throws -> UniversalAIConnectorRuntime {
        let providerId = UniversalAiProviderId(
            rawValue: profile.providerID
        )
        let credential = profile.apiKey
        let provider = UniversalAiProviderConfiguration(
            providerId: providerId,
            baseURL: profile.connectorBaseURL,
            credentialSupplier: { credential }
        )
        do {
            return try UniversalAiConnector(
                configuration: UniversalAiConnectorConfiguration(
                    providers: [provider],
                    connectTimeoutMillis:
                        UniversalAiConnectorConfiguration.defaultConnectTimeoutMillis,
                    requestTimeoutMillis:
                        UniversalAiConnectorConfiguration.defaultRequestTimeoutMillis
                )
            )
        } catch {
            throw OpenKeyboardAIConnectorError.invalidURL
        }
    }

    private static func statusCode(
        from error: UniversalAiConnectorError
    ) -> Int? {
        guard case let .number(number)? = error.metadata?["statusCode"] else {
            return nil
        }
        return Int(number.rawValue)
    }

    private static func durationMilliseconds(since started: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(started) * 1_000))
    }

    private static func diagnosticFailure(
        for error: Error,
        subreason: AIOperationDiagnosticSubreason?
    ) -> (
        stage: AIOperationDiagnosticStage,
        failure: AIOperationDiagnosticFailure,
        statusCategory: AIOperationDiagnosticHTTPStatusCategory?,
        subreason: AIOperationDiagnosticSubreason?
    ) {
        if error is CancellationError { return (.cancellation, .cancelled, nil, nil) }
        guard let error = error as? OpenKeyboardAIConnectorError else {
            return (.transport, .transportFailure, nil, nil)
        }
        switch error {
        case .timeout:
            return (.transport, .transportTimeout, nil, nil)
        case .invalidResponse, .truncatedResponse:
            return (.decoding, .malformedResponse, nil, subreason)
        case .transport:
            return (.transport, .gatewayNonresponse, nil, nil)
        case .serverStatus(let statusCode):
            return (
                .transport,
                .gatewayRejected,
                AIOperationDiagnosticHTTPStatusCategory(statusCode: statusCode),
                nil
            )
        case .rateLimited, .unauthorized, .forbidden, .modelUnavailable:
            return (.transport, .gatewayRejected, .clientError, nil)
        case .provider, .closed, .unsupportedModelDiscovery:
            return (.transport, .transportFailure, nil, nil)
        case .invalidURL, .notConfigured, .missingInput:
            return (.promptConstruction, .validationRejected, nil, nil)
        }
    }

    /// Retains only closed reasons before `mappedError` intentionally reduces connector failures
    /// to product-facing categories. Do not inspect or retain provider messages or metadata here.
    static func diagnosticSubreason(for error: Error) -> AIOperationDiagnosticSubreason? {
        if let rejection = error as? SafeResponseRejection {
            return rejection.subreason
        }
        if let appError = error as? OpenKeyboardAIConnectorError, appError == .truncatedResponse { return .outputLimitReached }
        if error is UniversalAiContractValidationError {
            return .connectorContractValidationFailure
        }
        guard let connectorError = error as? UniversalAiConnectorError else {
            return nil
        }

        switch connectorError.code.rawValue {
        case "provider_output_limit_reached": return .outputLimitReached
        case "provider_incomplete_response": return .providerIncompleteResponse
        case "incomplete_stream": return .incompleteStream
        case "malformed_provider_response":
            return .malformedProviderResponse
        case "malformed_provider_stream":
            return .malformedProviderStream
        case "invalid_structured_provider_response":
            return .invalidStructuredProviderResponse
        default:
            break
        }

        guard connectorError.category == .validation,
              !isClosedConnectorError(connectorError) else {
            return nil
        }
        return .connectorContractValidationFailure
    }

    private static func isClosedConnectorError(_ error: UniversalAiConnectorError) -> Bool {
        error.category == .validation
            && error.code.rawValue == UniversalAiErrorCode.invalidRequest.rawValue
            && error.message == "The Universal AI Connector is closed."
    }

    private enum SafeResponseRejection: Error {
        case targetMismatch
        case unexpectedCompletionReason
        case invalidOutputCount
        case unexpectedOutputIndex
        case nonTextOutput
        case unexpectedStructuredOutput
        case missingOrEmptyText

        var mappedError: OpenKeyboardAIConnectorError { .invalidResponse }

        var subreason: AIOperationDiagnosticSubreason {
            switch self {
            case .targetMismatch:
                return .targetMismatch
            case .unexpectedCompletionReason:
                return .unexpectedCompletionReason
            case .invalidOutputCount:
                return .invalidOutputCount
            case .unexpectedOutputIndex:
                return .unexpectedOutputIndex
            case .nonTextOutput:
                return .nonTextOutput
            case .unexpectedStructuredOutput:
                return .unexpectedStructuredOutput
            case .missingOrEmptyText:
                return .missingOrEmptyText
            }
        }
    }
}

private final class RuntimeStore: @unchecked Sendable {
    private struct Identity: Equatable {
        let providerId: String
        let baseURL: String
        let credential: String
    }

    private struct Slot {
        let identity: Identity
        let runtime: UniversalAIConnectorRuntime
    }

    private let lock = NSLock()
    private let factory: UniversalAIConnectorAdapter.RuntimeFactory
    private var slot: Slot?

    init(factory: @escaping UniversalAIConnectorAdapter.RuntimeFactory) {
        self.factory = factory
    }

    func runtime(for profile: OpenKeyboardGatewayProfile) throws -> UniversalAIConnectorRuntime {
        let identity = Identity(
            providerId: profile.providerID,
            baseURL: profile.connectorBaseURL,
            credential: profile.apiKey
        )

        lock.lock()
        if let slot, slot.identity == identity {
            lock.unlock()
            return slot.runtime
        }
        do {
            let replacement = try factory(profile)
            let previous = slot?.runtime
            slot = Slot(identity: identity, runtime: replacement)
            lock.unlock()
            previous?.close()
            return replacement
        } catch {
            lock.unlock()
            throw error
        }
    }

    func close() {
        lock.lock()
        let runtime = slot?.runtime
        slot = nil
        lock.unlock()
        runtime?.close()
    }
}
