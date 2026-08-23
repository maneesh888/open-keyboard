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
    func testConnection(gatewayURL: String, apiKey: String) async throws -> Bool
    func fetchModels(gatewayURL: String, apiKey: String) async throws -> [String]
    func testCorrectionSmoke(gatewayURL: String, apiKey: String, model: String) async throws
    func runGatewayDiagnostics(gatewayURL: String, apiKey: String, preferredModel: String) async -> GatewayDiagnosticReport
}

extension NetworkManager: GatewayConnectionTesting {}

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var config: AppConfig
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
    @Published private(set) var showsValidatedGatewayDetails: Bool
    
    enum ConnectionStatus: Equatable {
        case unknown
        case checking
        case success
        case limited
        case failure
    }
    
    private let gatewayTester: GatewayConnectionTesting
    private let defaults: UserDefaults?
    private var hasValidatedSavedGatewayThisLaunch = false
    private var modelDiscoveryIdentity: GatewayDraftIdentity?

    private struct GatewayDraftIdentity: Equatable {
        let gatewayURL: String
        let apiKey: String
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
        self.gatewayURLInput = displayConfig.gatewayURL.isEmpty ? "https://" : displayConfig.gatewayURL
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
        let displayConfig = Self.settingsDisplayConfig(from: newConfig, defaults: defaults)
        config = displayConfig
        gatewayURLInput = displayConfig.gatewayURL.isEmpty ? "https://" : displayConfig.gatewayURL
        apiKeyInput = displayConfig.apiKey
        selectedModelInput = displayConfig.selectedModel
        availableModels = []
        modelSelectionMessage = nil
        modelDiscoveryIdentity = nil
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
        (normalizedGatewayURLInputOrNil ?? gatewayURLInput.trimmingCharacters(in: .whitespacesAndNewlines)) != config.gatewayURL
            || apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines) != config.apiKey
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
        return hasCompleteGatewayDraft && !modelSelectionRequired
    }

    var shouldShowModelSelection: Bool {
        guard let draftIdentity = currentDraftIdentity,
              draftIdentity != savedGatewayIdentity,
              modelDiscoveryIdentity == draftIdentity else { return false }
        return availableModels.count > 1
    }

    var modelSelectionRequired: Bool {
        shouldShowModelSelection && selectedModelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        "Gateway and model are available, but plain-text grammar correction could not be verified. Other AI actions remain available; use Diagnostics to test grammar."
    }
    
    func updateGatewayURLInput(_ value: String) {
        gatewayURLInput = value
        resetValidatedDisplayIfDraftChanged()
    }

    func updateAPIKeyInput(_ value: String) {
        apiKeyInput = value
        resetValidatedDisplayIfDraftChanged()
    }

    func updateSelectedModelInput(_ value: String) {
        guard let exactModel = availableModels.first(where: {
            $0.caseInsensitiveCompare(value.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }) else {
            selectedModelInput = ""
            return
        }
        selectedModelInput = exactModel
        modelSelectionMessage = nil
    }

    func normalizeGatewayURLInputForEditing() {
        guard let normalized = normalizedGatewayURLInputOrNil else { return }
        gatewayURLInput = normalized
        resetValidatedDisplayIfDraftChanged()
    }

    private var normalizedGatewayURLInputOrNil: String? {
        try? NetworkManager.normalizedGatewayBaseURLString(gatewayURLInput)
    }

    private var currentDraftIdentity: GatewayDraftIdentity? {
        guard let gatewayURL = normalizedGatewayURLInputOrNil else { return nil }
        let apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return nil }
        return GatewayDraftIdentity(gatewayURL: gatewayURL, apiKey: apiKey)
    }

    private var savedGatewayIdentity: GatewayDraftIdentity? {
        let gatewayURL = config.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard config.isConfigured, !gatewayURL.isEmpty, !apiKey.isEmpty else { return nil }
        return GatewayDraftIdentity(gatewayURL: gatewayURL, apiKey: apiKey)
    }

    private func resetValidatedDisplayIfDraftChanged() {
        let draftGatewayURL = normalizedGatewayURLInputOrNil ?? gatewayURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftAPIKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftIdentity = normalizedGatewayURLInputOrNil.map {
            GatewayDraftIdentity(gatewayURL: $0, apiKey: draftAPIKey)
        }
        if modelDiscoveryIdentity != draftIdentity {
            modelDiscoveryIdentity = nil
            availableModels = []
            selectedModelInput = draftIdentity == savedGatewayIdentity ? config.selectedModel : ""
            modelSelectionMessage = nil
        }
        guard draftGatewayURL != config.gatewayURL || draftAPIKey != config.apiKey else { return }
        showsValidatedGatewayDetails = false
        diagnosticReport = nil
        if connectionStatus == .success || connectionStatus == .limited || connectionStatus == .checking { connectionStatus = .unknown }
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
        AppConfig.clearGatewayConnectionError(from: defaults)
        AppConfig.clearGatewayConnectionLastTestedAt(from: defaults)
        await validateSavedGatewayOnceOnLaunch()
    }

    func testConnection() async {
        guard !isTestingConnection else { return }
        showsValidatedGatewayDetails = false
        diagnosticReport = nil
        isTestingConnection = true
        defer { isTestingConnection = false }
        connectionStatus = .checking
        errorMessage = nil
        await Task.yield()

        do {
            let draftGatewayURL = try NetworkManager.normalizedGatewayBaseURLString(gatewayURLInput)
            let draftAPIKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            gatewayURLInput = draftGatewayURL
            guard !draftAPIKey.isEmpty else { throw NetworkError.unauthorized }
            let draftIdentity = GatewayDraftIdentity(gatewayURL: draftGatewayURL, apiKey: draftAPIKey)
            let isSavedGatewayIdentity = draftIdentity == savedGatewayIdentity
            let previousDiscoveryIdentity = modelDiscoveryIdentity
            let previousDraftModel = selectedModelInput.trimmingCharacters(in: .whitespacesAndNewlines)

            let success = try await gatewayTester.testConnection(
                gatewayURL: draftGatewayURL,
                apiKey: draftAPIKey
            )

            if success {
                let models = try await gatewayTester.fetchModels(
                    gatewayURL: draftGatewayURL,
                    apiKey: draftAPIKey
                )
                availableModels = Self.normalizedModelChoices(models)
                modelDiscoveryIdentity = draftIdentity
                let gatewayModel: String
                if isSavedGatewayIdentity {
                    let configuredModel = config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let exactModel = Self.exactModel(configuredModel, in: availableModels) else {
                        failConnection(with: NetworkError.modelUnavailable.localizedDescription)
                        return
                    }
                    gatewayModel = exactModel
                    selectedModelInput = exactModel
                } else if availableModels.isEmpty {
                    selectedModelInput = ""
                    modelSelectionMessage = nil
                    failConnection(with: "No models returned by gateway")
                    return
                } else if availableModels.count == 1 {
                    gatewayModel = availableModels[0]
                    selectedModelInput = gatewayModel
                    modelSelectionMessage = nil
                } else if previousDiscoveryIdentity == draftIdentity,
                          let exactModel = Self.exactModel(previousDraftModel, in: availableModels) {
                    gatewayModel = exactModel
                    selectedModelInput = exactModel
                    modelSelectionMessage = nil
                } else {
                    selectedModelInput = ""
                    modelSelectionMessage = "Choose a model for these gateway credentials, then test again."
                    connectionStatus = .unknown
                    errorMessage = nil
                    showsValidatedGatewayDetails = false
                    return
                }
                guard !gatewayModel.isEmpty else {
                    if availableModels.isEmpty {
                        failConnection(with: "No models returned by gateway")
                    }
                    return
                }

                do {
                    try await gatewayTester.testCorrectionSmoke(
                        gatewayURL: draftGatewayURL,
                        apiKey: draftAPIKey,
                        model: gatewayModel
                    )
                    let validatedConfig = AppConfig(
                        apiKey: draftAPIKey,
                        gatewayURL: draftGatewayURL,
                        selectedModel: gatewayModel,
                        isConfigured: true,
                        grammarCorrectionVerified: true,
                        grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
                    )
                    guard saveConfig(validatedConfig) else {
                        failConnection(with: "Could not save gateway configuration. Check Keychain access and try again.")
                        return
                    }

                    config = validatedConfig
                    connectionStatus = .success
                    errorMessage = nil
                    modelSelectionMessage = nil
                    AppConfig.clearGatewayConnectionError(from: defaults)
                    AppConfig.saveGatewayConnectionLastTestedAt(to: defaults)
                    showsValidatedGatewayDetails = true
                    return
                } catch {
                    if Self.isCancellation(error) {
                        throw NetworkError.cancelled
                    }
                    failConnection(with: NetworkManager.userFacingSmokeErrorMessage(for: error, model: gatewayModel))
                }
            } else {
                failConnection(with: "Connection failed")
            }
        } catch {
            if Self.isCancellation(error) {
                connectionStatus = .unknown
                errorMessage = nil
                showsValidatedGatewayDetails = false
                return
            }
            if let networkError = error as? NetworkError {
                failConnection(with: networkError.localizedDescription)
            } else {
                failConnection(with: error.localizedDescription)
            }
        }

    }

    func runDiagnostics() async {
        guard canRunDiagnostics else { return }
        isRunningDiagnostics = true
        diagnosticReport = nil
        await Task.yield()

        do {
            let draftGatewayURL = try NetworkManager.normalizedGatewayBaseURLString(gatewayURLInput)
            let draftAPIKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            gatewayURLInput = draftGatewayURL
            guard !draftAPIKey.isEmpty else { throw NetworkError.unauthorized }
            let draftIdentity = GatewayDraftIdentity(gatewayURL: draftGatewayURL, apiKey: draftAPIKey)
            let preferredModel = diagnosticModel(for: draftIdentity)
            diagnosticReport = await gatewayTester.runGatewayDiagnostics(
                gatewayURL: draftGatewayURL,
                apiKey: draftAPIKey,
                preferredModel: preferredModel
            )
        } catch {
            diagnosticReport = GatewayDiagnosticReport(
                selectedModel: config.selectedModel,
                checks: [
                    GatewayDiagnosticCheck(
                        id: "diagnostic-input",
                        title: "Configuration",
                        endpoint: "-",
                        status: .failed,
                        durationMilliseconds: nil,
                        message: (error as? NetworkError)?.localizedDescription ?? error.localizedDescription
                    )
                ]
            )
        }

        isRunningDiagnostics = false
    }

    var canRunDiagnostics: Bool {
        guard hasCompleteGatewayDraft, !isRunningDiagnostics, let draftIdentity = currentDraftIdentity else { return false }
        return !diagnosticModel(for: draftIdentity).isEmpty
    }

    private func diagnosticModel(for draftIdentity: GatewayDraftIdentity) -> String {
        if draftIdentity == savedGatewayIdentity {
            return config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard modelDiscoveryIdentity == draftIdentity else { return "" }
        return Self.exactModel(selectedModelInput, in: availableModels) ?? ""
    }

    private func saveConfig(_ candidate: AppConfig) -> Bool {
        if let defaults {
            return candidate.save(to: defaults)
        }
        return candidate.save()
    }

    private static func normalizedModelChoices(_ models: [String]) -> [String] {
        var choices: [String] = []
        for model in models {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !choices.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { continue }
            choices.append(trimmed)
        }
        return choices
    }

    private static func exactModel(_ model: String, in choices: [String]) -> String? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return choices.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private func failConnection(with message: String) {
        connectionStatus = .failure
        errorMessage = message
        showsValidatedGatewayDetails = false
        // A failed replacement draft must not poison the still-persisted working profile.
        // Publish runtime failure metadata only when validating that saved identity, or when
        // no complete profile exists yet.
        if savedGatewayIdentity == nil || currentDraftIdentity == savedGatewayIdentity {
            AppConfig.saveGatewayConnectionError(message, to: defaults)
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

    private static func hasRecentSavedGatewayValidation(for config: AppConfig, defaults: UserDefaults?, now: Date = Date()) -> Bool {
        guard config.isConfigured, config.hasCompleteGatewayRuntimeConfig else { return false }
        guard config.hasCurrentGrammarCorrectionCapabilityRecord else { return false }
        guard let defaults, let lastTestedAt = AppConfig.gatewayConnectionLastTestedAt(from: defaults) else { return false }
        let elapsed = now.timeIntervalSince(lastTestedAt)
        return elapsed >= 0 && elapsed < AppConfig.gatewayConnectionRetestInterval
    }

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
