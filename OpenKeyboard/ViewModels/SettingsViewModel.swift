//
//  SettingsViewModel.swift
//  OpenKeyboard
//
//  ViewModel for settings screen
//

import Foundation
import SwiftUI
import UIKit

protocol GatewayConnectionTesting {
    func fetchModels(profile: OpenKeyboardGatewayProfile) async throws -> [String]
    func testCorrectionSmoke(profile: OpenKeyboardGatewayProfile, model: String) async throws
    func runGatewayDiagnostics(profile: OpenKeyboardGatewayProfile, preferredModel: String) async -> GatewayDiagnosticReport
    func closeConnector()
}

extension GatewayConnectionTesting {
    func closeConnector() {}
}

extension NetworkManager: GatewayConnectionTesting {}

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var config: AppConfig
    @Published var selectedProvider: OpenKeyboardAIProvider
    @Published var gatewayURLInput: String
    @Published var apiKeyInput: String
    @Published var selectedModelInput: String
    @Published var isTestingConnection = false
    @Published var availableModels: [String] = []
    @Published var modelSelectionMessage: String?
    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var errorMessage: String?
    @Published var onboardingResetMessage: String?
    @Published var isRunningDiagnostics = false
    @Published var diagnosticReport: GatewayDiagnosticReport?
    @Published private(set) var modelDiscoveryState: ModelDiscoveryState = .idle
    @Published private(set) var showsValidatedGatewayDetails: Bool
    
    enum ConnectionStatus: Equatable {
        case unknown
        case checking
        case success
        case limited
        case failure
    }

    enum ModelDiscoveryState: Equatable {
        case idle
        case loading
        case loaded
        case unsupported
        case failed(String)
        case cancelled
    }
    
    private let gatewayTester: GatewayConnectionTesting
    private let defaults: UserDefaults?
    private var hasValidatedSavedGatewayThisLaunch = false
    private var modelDiscoveryIdentity: GatewayDraftIdentity?
    private var gatewayOperationGeneration: UInt = 0

    private struct GatewayDraftIdentity: Equatable {
        let provider: OpenKeyboardAIProvider
        let baseURL: String
        let apiKey: String
    }

    private struct GatewayDraftContext {
        let profile: OpenKeyboardGatewayProfile
        let identity: GatewayDraftIdentity
    }

    init(
        config: AppConfig = AppConfig.load(),
        gatewayTester: GatewayConnectionTesting = NetworkManager.shared,
        defaults: UserDefaults? = AppConfig.sharedDefaults()
    ) {
        self.gatewayTester = gatewayTester
        self.defaults = defaults
        let displayConfig = Self.settingsDisplayConfig(from: config, defaults: defaults)
        self.config = displayConfig
        self.selectedProvider = displayConfig.provider
        self.gatewayURLInput = displayConfig.baseURL.isEmpty
            ? displayConfig.provider.defaultBaseURLString
            : displayConfig.baseURL
        self.apiKeyInput = displayConfig.apiKey
        self.selectedModelInput = displayConfig.selectedModel
        self.modelSelectionMessage = nil
        let sharedError = defaults.flatMap(AppConfig.gatewayConnectionError(from:))
        let hasRecentValidation = Self.hasRecentSavedGatewayValidation(for: displayConfig, defaults: defaults)
        self.errorMessage = sharedError
        self.connectionStatus = sharedError == nil ? (hasRecentValidation ? Self.validatedConnectionStatus(for: displayConfig) : .unknown) : .failure
        self.showsValidatedGatewayDetails = sharedError == nil && hasRecentValidation
        self.hasValidatedSavedGatewayThisLaunch = sharedError == nil && hasRecentValidation
    }
    
    @discardableResult
    func saveSettings() -> Bool {
        if let defaults {
            return config.save(to: defaults)
        } else {
            return config.save()
        }
    }

    func applyConfig(_ newConfig: AppConfig) {
        cancelInFlightGatewayOperations()
        let displayConfig = Self.settingsDisplayConfig(from: newConfig, defaults: defaults)
        config = displayConfig
        selectedProvider = displayConfig.provider
        gatewayURLInput = displayConfig.baseURL.isEmpty
            ? displayConfig.provider.defaultBaseURLString
            : displayConfig.baseURL
        apiKeyInput = displayConfig.apiKey
        selectedModelInput = displayConfig.selectedModel
        availableModels = []
        modelSelectionMessage = nil
        modelDiscoveryIdentity = nil
        modelDiscoveryState = .idle
        let sharedError = defaults.flatMap(AppConfig.gatewayConnectionError(from:))
        let hasRecentValidation = Self.hasRecentSavedGatewayValidation(for: displayConfig, defaults: defaults)
        errorMessage = sharedError
        showsValidatedGatewayDetails = sharedError == nil && hasRecentValidation
        diagnosticReport = nil
        connectionStatus = sharedError == nil ? (hasRecentValidation ? Self.validatedConnectionStatus(for: displayConfig) : .unknown) : .failure
        hasValidatedSavedGatewayThisLaunch = sharedError == nil && hasRecentValidation
    }

    private static func settingsDisplayConfig(from config: AppConfig, defaults: UserDefaults?) -> AppConfig {
        guard config.isKnownTestPlaceholderConfig else { return config }
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            return config
        }
        if let defaults {
            AppConfig.clear(from: defaults)
        } else {
            AppConfig.clearSharedConfig()
        }
        return .default
    }

    var isEditingGatewayDraft: Bool {
        selectedProvider != config.provider
            || (normalizedGatewayURLInputOrNil ?? gatewayURLInput.trimmingCharacters(in: .whitespacesAndNewlines)) != config.baseURL
            || apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines) != config.apiKey
            || selectedModelInput.trimmingCharacters(in: .whitespacesAndNewlines) != config.selectedModel
    }

    var hasConnectionError: Bool {
        connectionStatus == .failure || errorMessage != nil
    }

    var hasSavedGatewayConfig: Bool {
        config.isConfigured && config.hasCompleteGatewayRuntimeConfig
    }

    var shouldShowGatewayValidationPending: Bool {
        hasSavedGatewayConfig && !showsValidatedGatewayDetails && !hasConnectionError
    }

    var isGatewayValidationInProgress: Bool {
        guard !hasConnectionError else { return false }
        return isTestingConnection || connectionStatus == .checking || shouldShowGatewayValidationPending
    }

    var shouldShowConnectionActions: Bool {
        isTestingConnection || hasConnectionError || connectionStatus == .limited || !showsValidatedGatewayDetails || isEditingGatewayDraft
    }

    var canTestConnection: Bool {
        guard !isTestingConnection else { return false }
        guard !isRunningDiagnostics else { return false }
        guard !isLoadingModels else { return false }
        return hasCompleteGatewayDraft && !modelSelectionRequired
    }

    var shouldShowModelSelection: Bool {
        modelDiscoveryIdentity == currentDraftIdentity
            && modelDiscoveryState == .loaded
            && !availableModels.isEmpty
    }

    var modelSelectionRequired: Bool {
        if shouldShowModelSelection {
            return Self.exactModel(selectedModelInput, in: availableModels) == nil
        }
        if shouldShowManualModelEntry {
            return selectedModelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    var isLoadingModels: Bool {
        modelDiscoveryState == .loading
    }

    var canLoadModels: Bool {
        hasCompleteGatewayDraft && !isTestingConnection && !isRunningDiagnostics && !isLoadingModels
    }

    var canCancelModelDiscovery: Bool {
        isLoadingModels
    }

    var canRetryModelDiscovery: Bool {
        if case .failed = modelDiscoveryState { return canLoadModels }
        return modelDiscoveryState == .cancelled && canLoadModels
    }

    var modelDiscoveryActionTitle: String {
        if isLoadingModels { return "Loading Models..." }
        if canRetryModelDiscovery { return "Retry Models" }
        if hasSavedGatewayConfig, currentDraftIdentity == savedGatewayIdentity {
            return "Change Model"
        }
        return "Load Models"
    }

    var shouldShowManualModelEntry: Bool {
        modelDiscoveryIdentity == currentDraftIdentity && modelDiscoveryState == .unsupported
    }

    private var hasCompleteGatewayDraft: Bool {
        guard normalizedGatewayURLInputOrNil != nil else { return false }
        return !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var trustedModelDisplay: String {
        guard !hasConnectionError, showsValidatedGatewayDetails, config.isConfigured, !config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Test connection to load model"
        }
        return config.selectedModel
    }

    var trustedModelLoaded: Bool {
        !hasConnectionError && showsValidatedGatewayDetails && config.isConfigured && !config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var grammarCapabilityDisplay: String {
        guard !hasConnectionError, showsValidatedGatewayDetails, config.isConfigured else {
            return "Loaded after Test Connection"
        }
        guard config.grammarCorrectionVerified else { return "Not verified for selected model" }
        return "Plain text verified"
    }

    var modelCapabilityMessage: String {
        "Provider and model are available, but plain-text grammar correction could not be verified. Other AI actions remain available; use Diagnostics to test grammar."
    }

    func updateProvider(_ provider: OpenKeyboardAIProvider) {
        guard selectedProvider != provider else { return }
        invalidateGatewayOperationsForDraftChange()
        selectedProvider = provider
        gatewayURLInput = provider.defaultBaseURLString
        apiKeyInput = ""
        selectedModelInput = ""
        resetModelDiscovery()
        resetValidatedDisplayIfDraftChanged()
    }
    
    func updateGatewayURLInput(_ value: String) {
        guard gatewayURLInput != value else { return }
        invalidateGatewayOperationsForDraftChange()
        gatewayURLInput = value
        resetValidatedDisplayIfDraftChanged()
    }

    func updateAPIKeyInput(_ value: String) {
        guard apiKeyInput != value else { return }
        invalidateGatewayOperationsForDraftChange()
        apiKeyInput = value
        resetValidatedDisplayIfDraftChanged()
    }

    func updateSelectedModelInput(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let exactModel = Self.exactModel(trimmed, in: availableModels)
        let replacement = shouldShowManualModelEntry ? trimmed : (exactModel ?? "")
        guard selectedModelInput != replacement else { return }
        let wasCheckingConnection = isTestingConnection || connectionStatus == .checking
        invalidateGatewayOperationsForModelChange()
        selectedModelInput = replacement
        if wasCheckingConnection {
            connectionStatus = .unknown
            errorMessage = nil
        }
        guard exactModel != nil || shouldShowManualModelEntry else { return }
        modelSelectionMessage = nil
        resetValidatedDisplayIfModelChanged()
    }

    func normalizeGatewayURLInputForEditing() {
        guard let normalized = normalizedGatewayURLInputOrNil else { return }
        guard gatewayURLInput != normalized else { return }
        invalidateGatewayOperationsForDraftChange()
        gatewayURLInput = normalized
        resetValidatedDisplayIfDraftChanged()
    }

    func cancelInFlightGatewayOperations(closeConnector: Bool = true) {
        gatewayOperationGeneration &+= 1
        isTestingConnection = false
        isRunningDiagnostics = false
        if isLoadingModels {
            modelDiscoveryState = .cancelled
        }
        if closeConnector {
            gatewayTester.closeConnector()
        }
    }

    private func invalidateGatewayOperationsForDraftChange() {
        cancelInFlightGatewayOperations()
        diagnosticReport = nil
    }

    private func invalidateGatewayOperationsForModelChange() {
        cancelInFlightGatewayOperations(closeConnector: false)
        diagnosticReport = nil
    }

    private func beginGatewayOperation() -> UInt {
        gatewayOperationGeneration &+= 1
        return gatewayOperationGeneration
    }

    private func isCurrentGatewayOperation(_ generation: UInt, draftIdentity: GatewayDraftIdentity) -> Bool {
        generation == gatewayOperationGeneration
            && !Task.isCancelled
            && currentDraftIdentity == draftIdentity
    }

    private var normalizedGatewayURLInputOrNil: String? {
        try? NetworkManager.normalizedProviderBaseURLString(
            gatewayURLInput,
            provider: selectedProvider
        )
    }

    private var currentDraftIdentity: GatewayDraftIdentity? {
        guard let baseURL = normalizedGatewayURLInputOrNil else { return nil }
        let apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return nil }
        return GatewayDraftIdentity(
            provider: selectedProvider,
            baseURL: baseURL,
            apiKey: apiKey
        )
    }

    private var savedGatewayIdentity: GatewayDraftIdentity? {
        let baseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.isConfigured, !baseURL.isEmpty, !apiKey.isEmpty else { return nil }
        return GatewayDraftIdentity(
            provider: config.provider,
            baseURL: baseURL,
            apiKey: apiKey
        )
    }

    private func resetValidatedDisplayIfDraftChanged() {
        let draftGatewayURL = normalizedGatewayURLInputOrNil ?? gatewayURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftAPIKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftIdentity = normalizedGatewayURLInputOrNil.map {
            GatewayDraftIdentity(
                provider: selectedProvider,
                baseURL: $0,
                apiKey: draftAPIKey
            )
        }
        if modelDiscoveryIdentity != draftIdentity {
            modelDiscoveryIdentity = nil
            availableModels = []
            selectedModelInput = draftIdentity == savedGatewayIdentity ? config.selectedModel : ""
            modelSelectionMessage = nil
            modelDiscoveryState = .idle
        }
        guard selectedProvider != config.provider
                || draftGatewayURL != config.baseURL
                || draftAPIKey != config.apiKey else { return }
        showsValidatedGatewayDetails = false
        diagnosticReport = nil
        if connectionStatus == .success || connectionStatus == .limited || connectionStatus == .checking { connectionStatus = .unknown }
    }

    private func resetValidatedDisplayIfModelChanged() {
        let draftModel = selectedModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedModel = config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentDraftIdentity != savedGatewayIdentity || draftModel != savedModel else {
            return
        }
        showsValidatedGatewayDetails = false
        diagnosticReport = nil
        if connectionStatus == .success || connectionStatus == .limited || connectionStatus == .checking {
            connectionStatus = .unknown
        }
    }

    private func resetModelDiscovery() {
        modelDiscoveryIdentity = nil
        modelDiscoveryState = .idle
        availableModels = []
        modelSelectionMessage = nil
    }

    private func normalizedDraftContext() throws -> GatewayDraftContext {
        let baseURL = try NetworkManager.normalizedProviderBaseURLString(
            gatewayURLInput,
            provider: selectedProvider
        )
        let apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw NetworkError.unauthorized }
        let profile: OpenKeyboardGatewayProfile
        do {
            profile = try OpenKeyboardGatewayProfile(
                provider: selectedProvider,
                baseURL: baseURL,
                apiKey: apiKey
            )
        } catch OpenKeyboardAIConnectorError.invalidURL {
            throw NetworkError.invalidURL
        } catch OpenKeyboardAIConnectorError.unauthorized {
            throw NetworkError.unauthorized
        } catch {
            throw NetworkError.networkError(error)
        }
        gatewayURLInput = baseURL
        return GatewayDraftContext(
            profile: profile,
            identity: GatewayDraftIdentity(
                provider: selectedProvider,
                baseURL: profile.baseURL,
                apiKey: profile.apiKey
            )
        )
    }

    private func applyDiscoveredModels(
        _ models: [String],
        identity: GatewayDraftIdentity
    ) {
        let previousModel = selectedModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        availableModels = Self.normalizedModelChoices(models)
        modelDiscoveryIdentity = identity
        guard !availableModels.isEmpty else {
            selectedModelInput = identity == savedGatewayIdentity ? config.selectedModel : ""
            let message = "No models were returned by this provider."
            modelDiscoveryState = .failed(message)
            modelSelectionMessage = message
            return
        }

        modelDiscoveryState = .loaded
        if let exactModel = Self.exactModel(previousModel, in: availableModels) {
            selectedModelInput = exactModel
            modelSelectionMessage = nil
        } else if identity == savedGatewayIdentity,
                  let exactModel = Self.exactModel(config.selectedModel, in: availableModels) {
            selectedModelInput = exactModel
            modelSelectionMessage = nil
        } else if identity == savedGatewayIdentity {
            selectedModelInput = ""
            modelSelectionMessage = "The saved model is no longer available. Choose an exact model for this provider profile."
            resetValidatedDisplayIfModelChanged()
        } else if availableModels.count == 1 {
            selectedModelInput = availableModels[0]
            modelSelectionMessage = nil
        } else {
            selectedModelInput = ""
            modelSelectionMessage = "Choose an exact model for this provider profile."
        }
    }

    private func handleModelDiscoveryFailure(
        _ error: Error,
        identity: GatewayDraftIdentity?
    ) {
        if Self.isCancellation(error) {
            modelDiscoveryState = .cancelled
            modelSelectionMessage = "Model loading was cancelled."
            return
        }
        if Self.isUnsupportedModelDiscovery(error) {
            availableModels = []
            modelDiscoveryIdentity = identity
            modelDiscoveryState = .unsupported
            if identity != savedGatewayIdentity {
                selectedModelInput = ""
            }
            modelSelectionMessage = "Model discovery is unsupported. Enter the provider's exact model identifier."
            return
        }

        availableModels = []
        modelDiscoveryIdentity = nil
        selectedModelInput = identity == savedGatewayIdentity ? config.selectedModel : ""
        let message = NetworkManager.diagnosticMessage(for: error)
        modelDiscoveryState = .failed(message)
        modelSelectionMessage = message
    }

    func validateSavedGatewayOnceOnLaunch() async {
        guard hasSavedGatewayConfig else { return }
        guard !hasConnectionError else { return }
        guard !hasValidatedSavedGatewayThisLaunch else { return }
        hasValidatedSavedGatewayThisLaunch = true
        if Self.hasRecentSavedGatewayValidation(for: config, defaults: defaults) {
            connectionStatus = Self.validatedConnectionStatus(for: config)
            errorMessage = nil
            showsValidatedGatewayDetails = true
            return
        }
        await testConnection()
    }

    func retrySavedGatewayValidation() async {
        hasValidatedSavedGatewayThisLaunch = false
        errorMessage = nil
        connectionStatus = .unknown
        AppConfig.clearGatewayConnectionLastTestedAt(from: defaults)
        await validateSavedGatewayOnceOnLaunch()
    }

    func loadModels() async {
        guard canLoadModels else { return }
        let operationGeneration = beginGatewayOperation()
        var operationIdentity: GatewayDraftIdentity?
        modelDiscoveryState = .loading
        modelSelectionMessage = nil
        errorMessage = nil
        await Task.yield()

        do {
            let context = try normalizedDraftContext()
            operationIdentity = context.identity
            guard isCurrentGatewayOperation(
                operationGeneration,
                draftIdentity: context.identity
            ) else { return }
            let models = try await gatewayTester.fetchModels(profile: context.profile)
            guard isCurrentGatewayOperation(
                operationGeneration,
                draftIdentity: context.identity
            ) else { return }
            applyDiscoveredModels(models, identity: context.identity)
        } catch {
            guard operationGeneration == gatewayOperationGeneration,
                  !Task.isCancelled,
                  operationIdentity.map({ currentDraftIdentity == $0 }) ?? true else {
                return
            }
            handleModelDiscoveryFailure(error, identity: operationIdentity)
        }
    }

    func retryModelDiscovery() async {
        guard canRetryModelDiscovery else { return }
        await loadModels()
    }

    func cancelModelDiscovery() {
        guard isLoadingModels else { return }
        cancelInFlightGatewayOperations()
        modelSelectionMessage = "Model loading was cancelled."
    }

    func testConnection() async {
        guard !isTestingConnection, !isRunningDiagnostics else { return }
        let operationGeneration = beginGatewayOperation()
        var operationIdentity: GatewayDraftIdentity?
        let initialAttemptedModel = selectedModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        showsValidatedGatewayDetails = false
        diagnosticReport = nil
        isTestingConnection = true
        defer {
            if operationGeneration == gatewayOperationGeneration {
                isTestingConnection = false
            }
        }
        connectionStatus = .checking
        errorMessage = nil
        await Task.yield()

        do {
            let context = try normalizedDraftContext()
            let profile = context.profile
            let draftIdentity = context.identity
            let draftAPIKey = profile.apiKey
            operationIdentity = draftIdentity
            guard isCurrentGatewayOperation(operationGeneration, draftIdentity: draftIdentity) else { return }
            let isSavedGatewayIdentity = draftIdentity == savedGatewayIdentity
            let previousDiscoveryIdentity = modelDiscoveryIdentity
            let previousDiscoveryState = modelDiscoveryState
            let previousDraftModel = selectedModelInput.trimmingCharacters(in: .whitespacesAndNewlines)

            let gatewayModel: String
            do {
                let models = try await gatewayTester.fetchModels(profile: profile)
                guard isCurrentGatewayOperation(operationGeneration, draftIdentity: draftIdentity) else { return }
                availableModels = Self.normalizedModelChoices(models)
                modelDiscoveryIdentity = draftIdentity
                modelDiscoveryState = .loaded
                if isSavedGatewayIdentity {
                    // The credential identity deliberately excludes the model so selecting a new
                    // exact model does not rebuild the connector. Validate the current draft
                    // selection, which is the saved model until the user explicitly changes it.
                    guard let exactModel = Self.exactModel(previousDraftModel, in: availableModels) else {
                        failConnection(
                            with: NetworkError.modelUnavailable.localizedDescription,
                            attemptedIdentity: draftIdentity,
                            attemptedModel: previousDraftModel
                        )
                        return
                    }
                    gatewayModel = exactModel
                    selectedModelInput = exactModel
                } else if availableModels.isEmpty {
                    selectedModelInput = ""
                    modelSelectionMessage = nil
                    modelDiscoveryState = .failed("No models were returned by this provider.")
                    failConnection(
                        with: "No models were returned by this provider.",
                        attemptedIdentity: draftIdentity,
                        attemptedModel: previousDraftModel
                    )
                    return
                } else if previousDiscoveryIdentity == draftIdentity,
                          !previousDraftModel.isEmpty {
                    guard let exactModel = Self.exactModel(previousDraftModel, in: availableModels) else {
                        selectedModelInput = ""
                        modelSelectionMessage = "The previously selected model is no longer available. Choose an exact model for this provider profile."
                        failConnection(
                            with: NetworkError.modelUnavailable.localizedDescription,
                            attemptedIdentity: draftIdentity,
                            attemptedModel: previousDraftModel
                        )
                        return
                    }
                    gatewayModel = exactModel
                    selectedModelInput = exactModel
                    modelSelectionMessage = nil
                } else if availableModels.count == 1 {
                    gatewayModel = availableModels[0]
                    selectedModelInput = gatewayModel
                    modelSelectionMessage = nil
                } else {
                    selectedModelInput = ""
                    modelSelectionMessage = "Choose an exact model for this provider profile, then test again."
                    connectionStatus = .unknown
                    errorMessage = nil
                    showsValidatedGatewayDetails = false
                    return
                }
            } catch {
                guard Self.isUnsupportedModelDiscovery(error) else { throw error }
                guard isCurrentGatewayOperation(operationGeneration, draftIdentity: draftIdentity) else { return }
                availableModels = []
                modelDiscoveryIdentity = draftIdentity
                modelDiscoveryState = .unsupported
                // For a saved credential identity this begins as the persisted model, but it may
                // also be a new exact identifier the user entered after unsupported discovery.
                let candidate = previousDraftModel
                guard isSavedGatewayIdentity
                        || (previousDiscoveryIdentity == draftIdentity
                            && previousDiscoveryState == .unsupported),
                      !candidate.isEmpty else {
                    selectedModelInput = ""
                    modelSelectionMessage = "Model discovery is unsupported. Enter the provider's exact model identifier, then test again."
                    connectionStatus = .unknown
                    errorMessage = nil
                    showsValidatedGatewayDetails = false
                    return
                }
                gatewayModel = candidate
                selectedModelInput = candidate
                modelSelectionMessage = nil
            }
            guard !gatewayModel.isEmpty else { return }

            do {
                try await gatewayTester.testCorrectionSmoke(
                    profile: profile,
                    model: gatewayModel
                )
                guard isCurrentGatewayOperation(operationGeneration, draftIdentity: draftIdentity) else { return }
                let validatedConfig = AppConfig(
                    apiKey: draftAPIKey,
                    gatewayURL: profile.baseURL,
                    selectedModel: gatewayModel,
                    isConfigured: true,
                    grammarCorrectionVerified: true,
                    grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion,
                    provider: selectedProvider
                )
                let validatedAt = Date()
                guard saveConfig(
                    validatedConfig,
                    validatedAt: validatedAt,
                    notifyActiveProfileChange: false
                ) else {
                    failConnection(
                        with: "Could not save gateway configuration. Check Keychain access and try again.",
                        attemptedIdentity: draftIdentity,
                        attemptedModel: gatewayModel
                    )
                    return
                }
                AppConfig.clearGatewayConnectionError(
                    from: defaults,
                    notifyActiveProfileChange: false
                )
                // The profile, validation timestamp, and runtime-error state are one observable
                // cross-process transaction. Publish only after every component is committed.
                AppConfig.postActiveProfileDidChangeDarwinNotification()

                config = validatedConfig
                selectedModelInput = validatedConfig.selectedModel
                resetModelDiscovery()
                connectionStatus = .success
                errorMessage = nil
                showsValidatedGatewayDetails = true
                return
            } catch {
                if Self.isCancellation(error) {
                    throw NetworkError.cancelled
                }
                guard isCurrentGatewayOperation(operationGeneration, draftIdentity: draftIdentity) else {
                    return
                }
                failConnection(
                    with: NetworkManager.userFacingSmokeErrorMessage(for: error, model: gatewayModel),
                    attemptedIdentity: draftIdentity,
                    attemptedModel: gatewayModel
                )
            }
        } catch {
            guard operationGeneration == gatewayOperationGeneration,
                  !Task.isCancelled,
                  operationIdentity.map({ currentDraftIdentity == $0 }) ?? true else {
                return
            }
            if Self.isCancellation(error) {
                connectionStatus = .unknown
                errorMessage = nil
                showsValidatedGatewayDetails = false
                return
            }
            if let networkError = error as? NetworkError {
                failConnection(
                    with: networkError.localizedDescription,
                    attemptedIdentity: operationIdentity,
                    attemptedModel: initialAttemptedModel
                )
            } else {
                failConnection(
                    with: NetworkManager.diagnosticMessage(for: error),
                    attemptedIdentity: operationIdentity,
                    attemptedModel: initialAttemptedModel
                )
            }
        }

    }

    func runDiagnostics() async {
        guard canRunDiagnostics else { return }
        let operationGeneration = beginGatewayOperation()
        isRunningDiagnostics = true
        defer {
            if operationGeneration == gatewayOperationGeneration {
                isRunningDiagnostics = false
            }
        }
        diagnosticReport = nil
        await Task.yield()

        do {
            let context = try normalizedDraftContext()
            let draftIdentity = context.identity
            let preferredModel = diagnosticModel(for: draftIdentity)
            guard isCurrentGatewayOperation(operationGeneration, draftIdentity: draftIdentity) else { return }
            let report = await gatewayTester.runGatewayDiagnostics(
                profile: context.profile,
                preferredModel: preferredModel
            )
            guard isCurrentGatewayOperation(operationGeneration, draftIdentity: draftIdentity),
                  diagnosticModel(for: draftIdentity) == preferredModel else { return }
            diagnosticReport = report
        } catch {
            guard operationGeneration == gatewayOperationGeneration, !Task.isCancelled else { return }
            diagnosticReport = GatewayDiagnosticReport(
                selectedModel: config.selectedModel,
                checks: [
                    GatewayDiagnosticCheck(
                        id: "diagnostic-input",
                        title: "Configuration",
                        endpoint: "-",
                        status: .failed,
                        durationMilliseconds: nil,
                        message: NetworkManager.diagnosticMessage(for: error)
                    )
                ]
            )
        }
    }

    var canRunDiagnostics: Bool {
        guard hasCompleteGatewayDraft,
              !isTestingConnection,
              !isLoadingModels,
              !isRunningDiagnostics,
              let draftIdentity = currentDraftIdentity else { return false }
        return !diagnosticModel(for: draftIdentity).isEmpty
    }

    private func diagnosticModel(for draftIdentity: GatewayDraftIdentity) -> String {
        if modelDiscoveryIdentity == draftIdentity {
            if modelDiscoveryState == .unsupported {
                return selectedModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return Self.exactModel(selectedModelInput, in: availableModels) ?? ""
        }
        if draftIdentity == savedGatewayIdentity {
            return config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func saveConfig(
        _ candidate: AppConfig,
        validatedAt: Date,
        notifyActiveProfileChange: Bool = true
    ) -> Bool {
        if let defaults {
            return candidate.save(
                to: defaults,
                validatedAt: validatedAt,
                notifyActiveProfileChange: notifyActiveProfileChange
            )
        }
        return candidate.save(
            validatedAt: validatedAt,
            notifyActiveProfileChange: notifyActiveProfileChange
        )
    }

    private static func normalizedModelChoices(_ models: [String]) -> [String] {
        var choices: [String] = []
        for model in models {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty,
                  model == trimmed,
                  !choices.contains(model) else { continue }
            choices.append(model)
        }
        return choices
    }

    private static func exactModel(_ model: String, in choices: [String]) -> String? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return choices.first { $0 == trimmed }
    }

    private func failConnection(
        with message: String,
        attemptedIdentity: GatewayDraftIdentity?,
        attemptedModel: String
    ) {
        let sanitizedMessage = KeyboardActionErrorState.sanitized(message)
        connectionStatus = .failure
        errorMessage = sanitizedMessage
        showsValidatedGatewayDetails = false
        // A failed replacement draft must not poison the still-persisted working profile.
        // Publish runtime failure metadata only when validating that saved identity, or when
        // no complete profile exists yet.
        let normalizedAttemptedModel = attemptedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedModel = config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTestingPersistedProfile = attemptedIdentity == savedGatewayIdentity
            && normalizedAttemptedModel == savedModel
        if savedGatewayIdentity == nil || isTestingPersistedProfile {
            AppConfig.saveGatewayConnectionError(sanitizedMessage, to: defaults)
            AppConfig.clearGatewayConnectionLastTestedAt(from: defaults)
        }
    }

    private static func validatedConnectionStatus(for config: AppConfig) -> ConnectionStatus {
        config.grammarCorrectionVerified ? .success : .limited
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        guard let networkError = error as? NetworkError else { return false }
        if case .cancelled = networkError { return true }
        return false
    }

    private static func isUnsupportedModelDiscovery(_ error: Error) -> Bool {
        if let networkError = error as? NetworkError,
           case .unsupportedModelDiscovery = networkError {
            return true
        }
        if let connectorError = error as? OpenKeyboardAIConnectorError,
           case .unsupportedModelDiscovery = connectorError {
            return true
        }
        return false
    }

    private static func hasRecentSavedGatewayValidation(for config: AppConfig, defaults: UserDefaults?, now: Date = Date()) -> Bool {
        guard config.isConfigured, config.hasCompleteGatewayRuntimeConfig else { return false }
        guard config.hasCurrentGrammarCorrectionCapabilityRecord else { return false }
        guard let defaults, let lastTestedAt = AppConfig.gatewayConnectionLastTestedAt(from: defaults) else { return false }
        let elapsed = now.timeIntervalSince(lastTestedAt)
        return elapsed >= 0 && elapsed < AppConfig.gatewayConnectionRetestInterval
    }

    #if DEBUG && targetEnvironment(simulator)
    @discardableResult
    func applyUITestModelDiscoveryActionIfNeeded() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"),
              arguments.contains("--seed-settings-saved-model") else {
            return false
        }

        availableModels = ["model-a", "model-b"]
        selectedModelInput = config.selectedModel
        modelDiscoveryIdentity = currentDraftIdentity
        modelDiscoveryState = .loaded
        modelSelectionMessage = nil
        return true
    }

    func applyUITestSettingsStateIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting") else { return }

        if arguments.contains("--seed-settings-saved-model") {
            let savedConfig = AppConfig(
                apiKey: "ui-saved-key",
                gatewayURL: "https://saved-selection.local",
                selectedModel: "model-a",
                isConfigured: true,
                grammarCorrectionVerified: true,
                grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
            )
            config = savedConfig
            selectedProvider = savedConfig.provider
            gatewayURLInput = savedConfig.baseURL
            apiKeyInput = savedConfig.apiKey
            selectedModelInput = savedConfig.selectedModel
            availableModels = []
            modelDiscoveryIdentity = nil
            modelDiscoveryState = .idle
            modelSelectionMessage = nil
            connectionStatus = .success
            errorMessage = nil
            showsValidatedGatewayDetails = true
        }

        if arguments.contains("--seed-settings-model-selection") {
            gatewayURLInput = "https://selection.local"
            apiKeyInput = "ui-selection-key"
            selectedModelInput = ""
            availableModels = ["model-a", "model-b"]
            modelDiscoveryIdentity = currentDraftIdentity
            modelDiscoveryState = .loaded
            modelSelectionMessage = "Choose a model for these gateway credentials, then test again."
            connectionStatus = .unknown
            showsValidatedGatewayDetails = false
        }

        if arguments.contains("--seed-settings-partial-diagnostics") {
            diagnosticReport = GatewayDiagnosticReport(
                selectedModel: "diagnostic-model",
                checks: [
                    GatewayDiagnosticCheck(
                        id: "models",
                        title: "Models",
                        endpoint: "GET /v1/models",
                        status: .passed,
                        durationMilliseconds: 12,
                        message: "Loaded 2 models."
                    ),
                    GatewayDiagnosticCheck(
                        id: "settings-correction-smoke",
                        title: "Fast plain-text grammar",
                        endpoint: "POST /v1/chat/completions",
                        status: .failed,
                        durationMilliseconds: 34,
                        message: "The selected model did not return usable grammar text."
                    ),
                    GatewayDiagnosticCheck(
                        id: "settings-rewrite-improve",
                        title: "Rewrite and Improve",
                        endpoint: "POST /v1/chat/completions",
                        status: .passed,
                        durationMilliseconds: 56,
                        message: "Returned one complete validated plain-text replacement used by Rewrite and Improve."
                    ),
                    GatewayDiagnosticCheck(
                        id: "settings-translation-dutch",
                        title: "Translation to Dutch",
                        endpoint: "POST /v1/chat/completions",
                        status: .failed,
                        durationMilliseconds: 78,
                        message: "The selected model did not return a usable Dutch translation."
                    )
                ]
            )
        }
    }
    #endif

    var keyboardSettingsInstructions: String {
        "If Settings opens one level above, go to General → Keyboard → Keyboards → Add New Keyboard → Open Keyboard, then enable Allow Full Access."
    }

    var keyboardSettingsURLCandidates: [URL] {
        [
            "App-Prefs:root=General&path=Keyboard/KEYBOARDS",
            "App-Prefs:root=General&path=Keyboard",
            "prefs:root=General&path=Keyboard/KEYBOARDS",
            "prefs:root=General&path=Keyboard",
            UIApplication.openSettingsURLString
        ].compactMap(URL.init(string:))
    }

    var keyboardSettingsPrimaryURLDescription: String {
        keyboardSettingsURLCandidates.first?.absoluteString ?? UIApplication.openSettingsURLString
    }

    func resetOnboarding() {
        AppConfig.resetOnboardingState(in: defaults)
        onboardingResetMessage = "Onboarding will show again after you close Settings."
    }

    func openKeyboardSettings() {
        openKeyboardSettingsCandidate(at: 0)
    }

    private func openKeyboardSettingsCandidate(at index: Int) {
        guard index < keyboardSettingsURLCandidates.count else { return }
        let url = keyboardSettingsURLCandidates[index]
        UIApplication.shared.open(url) { [weak self] opened in
            guard !opened else { return }
            Task { @MainActor in
                self?.openKeyboardSettingsCandidate(at: index + 1)
            }
        }
    }
}
