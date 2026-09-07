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

    init(factory: @escaping RuntimeFactory = UniversalAIConnectorAdapter.makeRuntime) {
        store = RuntimeStore(factory: factory)
    }

    deinit {
        store.close()
    }

    func listModels(profile: OpenKeyboardGatewayProfile) async throws -> [String] {
        do {
            let runtime = try store.runtime(for: profile)
            let providerId = UniversalAiProviderId(rawValue: OpenKeyboardGatewayProfile.providerID)
            switch try await runtime.listModels(providerId: providerId) {
            case let .supported(returnedProviderId, models):
                guard returnedProviderId == providerId,
                      models.allSatisfy({ $0.target.providerId == providerId }) else {
                    throw OpenKeyboardAIConnectorError.invalidResponse
                }
                return models.map(\.target.modelId.rawValue)
            case let .unsupported(returnedProviderId):
                guard returnedProviderId == providerId else {
                    throw OpenKeyboardAIConnectorError.invalidResponse
                }
                throw OpenKeyboardAIConnectorError.unsupportedModelDiscovery
            }
        } catch {
            throw Self.mappedError(error)
        }
    }

    func respond(
        to request: OpenKeyboardAIRequest,
        profile: OpenKeyboardGatewayProfile
    ) async throws -> String {
        do {
            let runtime = try store.runtime(for: profile)
            let connectorRequest = Self.connectorRequest(from: request)
            let response = try await runtime.respond(to: connectorRequest)
            return try Self.plainText(
                from: response,
                expectedTarget: connectorRequest.target
            )
        } catch {
            throw Self.mappedError(error)
        }
    }

    func close() {
        store.close()
    }

    static func connectorRequest(from request: OpenKeyboardAIRequest) -> UniversalAiRequest {
        UniversalAiRequest(
            target: UniversalAiTarget(
                providerId: UniversalAiProviderId(
                    rawValue: OpenKeyboardGatewayProfile.providerID
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
                temperature: request.temperature,
                topP: request.topP,
                stopSequences: request.stopSequences
            )
        )
    }

    static func plainText(
        from response: UniversalAiResponse,
        expectedTarget: UniversalAiTarget
    ) throws -> String {
        guard response.target == expectedTarget else {
            throw OpenKeyboardAIConnectorError.invalidResponse
        }
        switch response.completionReason {
        case .stop:
            break
        case .maxOutputTokens:
            throw OpenKeyboardAIConnectorError.truncatedResponse
        default:
            throw OpenKeyboardAIConnectorError.invalidResponse
        }
        guard response.outputs.count == 1,
              let output = response.outputs.first,
              output.index == 0,
              output.kind == .text,
              output.structuredJson == nil,
              let text = output.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenKeyboardAIConnectorError.invalidResponse
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
            rawValue: OpenKeyboardGatewayProfile.providerID
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
            providerId: OpenKeyboardGatewayProfile.providerID,
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
