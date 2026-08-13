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
    @Published var isTestingConnection = false
    @Published var availableModels: [String] = []
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
        return hasCompleteGatewayDraft
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

    var structuredCapabilityDisplay: String {
        guard !hasConnectionError, showsValidatedGatewayDetails, config.isConfigured else {
            return "Loaded after Test Connection"
        }
        guard config.supportsStructuredCorrections else { return "Not verified for selected model" }
        return config.structuredCorrectionSchemaVersion.isEmpty ? "Structured corrections enabled" : config.structuredCorrectionSchemaVersion
    }

    var modelCapabilityMessage: String {
        "Gateway connected and the model is available, but its structured correction response could not be verified. Basic AI actions remain available; use Diagnostics to inspect model capabilities."
    }
    
    func updateGatewayURLInput(_ value: String) {
        gatewayURLInput = value
        resetValidatedDisplayIfDraftChanged()
    }

    func updateAPIKeyInput(_ value: String) {
        apiKeyInput = value
        resetValidatedDisplayIfDraftChanged()
    }

    func normalizeGatewayURLInputForEditing() {
        guard let normalized = normalizedGatewayURLInputOrNil else { return }
        gatewayURLInput = normalized
        resetValidatedDisplayIfDraftChanged()
    }

    private var normalizedGatewayURLInputOrNil: String? {
        try? NetworkManager.normalizedGatewayBaseURLString(gatewayURLInput)
    }

    private func resetValidatedDisplayIfDraftChanged() {
        let draftGatewayURL = normalizedGatewayURLInputOrNil ?? gatewayURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftAPIKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
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

            let success = try await gatewayTester.testConnection(
                gatewayURL: draftGatewayURL,
                apiKey: draftAPIKey
            )

            if success {
                let models = try? await gatewayTester.fetchModels(
                    gatewayURL: draftGatewayURL,
                    apiKey: draftAPIKey
                )
                availableModels = models ?? []
                let candidates = AppConfig.gatewayModelCandidates(from: availableModels, currentModel: config.selectedModel)
                guard !candidates.isEmpty else {
                    failConnection(with: "No models returned by gateway")
                    return
                }

                var smokeErrors: [Error] = []
                for gatewayModel in candidates {
                    do {
                        try await gatewayTester.testCorrectionSmoke(
                            gatewayURL: draftGatewayURL,
                            apiKey: draftAPIKey,
                            model: gatewayModel
                        )
                        let previousConfig = config
                        config.gatewayURL = draftGatewayURL
                        config.apiKey = draftAPIKey
                        config.selectedModel = gatewayModel
                        config.isConfigured = true
                        config.supportsStructuredCorrections = true
                        config.structuredCorrectionSchemaVersion = "openkeyboard.structured-corrections.v1"
                        guard saveSettings() else {
                            config = previousConfig
                            failConnection(with: "Could not save gateway configuration. Check Keychain access and try again.")
                            return
                        }

                        connectionStatus = .success
                        errorMessage = nil
                        AppConfig.clearGatewayConnectionError(from: defaults)
                        AppConfig.saveGatewayConnectionLastTestedAt(to: defaults)
                        showsValidatedGatewayDetails = true
                        return
                    } catch {
                        smokeErrors.append(error)
                    }
                }

                let fallbackModel = candidates.first ?? config.selectedModel
                if smokeErrors.count == candidates.count,
                   smokeErrors.allSatisfy(Self.isStructuredCorrectionCapabilityMiss) {
                    let previousConfig = config
                    config.gatewayURL = draftGatewayURL
                    config.apiKey = draftAPIKey
                    config.selectedModel = fallbackModel
                    config.isConfigured = true
                    config.supportsStructuredCorrections = false
                    config.structuredCorrectionSchemaVersion = ""
                    guard saveSettings() else {
                        config = previousConfig
                        failConnection(with: "Could not save gateway configuration. Check Keychain access and try again.")
                        return
                    }

                    connectionStatus = .limited
                    errorMessage = nil
                    AppConfig.clearGatewayConnectionError(from: defaults)
                    AppConfig.saveGatewayConnectionLastTestedAt(to: defaults)
                    showsValidatedGatewayDetails = true
                    return
                }

                failConnection(with: NetworkManager.userFacingSmokeErrorMessage(for: smokeErrors.last ?? NetworkError.unusableCorrection, model: fallbackModel))
            } else {
                failConnection(with: "Connection failed")
            }
        } catch {
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
            let preferredModel = config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
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
        hasCompleteGatewayDraft && !isRunningDiagnostics
    }

    private func failConnection(with message: String) {
        connectionStatus = .failure
        errorMessage = message
        showsValidatedGatewayDetails = false
        AppConfig.saveGatewayConnectionError(message, to: defaults)
        AppConfig.clearGatewayConnectionLastTestedAt(from: defaults)
    }

    private static func validatedConnectionStatus(for config: AppConfig) -> ConnectionStatus {
        config.supportsStructuredCorrections ? .success : .limited
    }

    private static func isStructuredCorrectionCapabilityMiss(_ error: Error) -> Bool {
        guard let networkError = error as? NetworkError else { return false }
        if case .unusableCorrection = networkError { return true }
        return false
    }

    private static func hasRecentSavedGatewayValidation(for config: AppConfig, defaults: UserDefaults?, now: Date = Date()) -> Bool {
        guard config.isConfigured, config.hasCompleteGatewayRuntimeConfig else { return false }
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
