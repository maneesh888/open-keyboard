//
//  AppConfig.swift
//  OpenKeyboard
//
//  Configuration model
//

import Foundation
import Security

enum SettingsDocumentationLink {
    static let url = URL(string: "https://myadidi.com/projects/open-keyboard-llm-gateway/")!
}

protocol AppConfigSecretStore {
    func loadAPIKey() -> String?
    @discardableResult func saveAPIKey(_ apiKey: String) -> Bool
    @discardableResult func clearAPIKey() -> Bool
}

final class KeychainAppConfigSecretStore: AppConfigSecretStore {
    static let sharedAccessGroupSuffix = "com.maneesh.openkeyboard.shared"

    private let service = "com.maneesh.openkeyboard.gateway"
    private let account = "gateway-api-key"
    private let accessGroup: String?

    init(accessGroup: String? = KeychainAppConfigSecretStore.defaultSharedAccessGroup()) {
        self.accessGroup = accessGroup
    }

    func loadAPIKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        return apiKey
    }

    @discardableResult
    func saveAPIKey(_ apiKey: String) -> Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return clearAPIKey()
        }

        var query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func clearAPIKey() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func baseQueryForTesting() -> [String: Any] {
        baseQuery()
    }

    private static func defaultSharedAccessGroup() -> String? {
        guard let appIdentifierPrefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !appIdentifierPrefix.isEmpty else {
            return nil
        }
        return appIdentifierPrefix + sharedAccessGroupSuffix
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

struct AppConfig: Codable {
    var apiKey: String
    var gatewayURL: String
    var selectedModel: String
    var isConfigured: Bool
    var supportsStructuredCorrections: Bool
    var structuredCorrectionSchemaVersion: String
    
    static let `default` = AppConfig(
        apiKey: "",
        gatewayURL: "",
        selectedModel: "",
        isConfigured: false,
        supportsStructuredCorrections: false,
        structuredCorrectionSchemaVersion: ""
    )
    
    // App Group identifier for sharing non-sensitive data with keyboard extension
    static let appGroupIdentifier = "group.com.maneesh.openkeyboard"
    
    // UserDefaults keys. apiKeyKey is legacy-only and is removed after Keychain migration.
    static let apiKeyKey = "apiKey"
    static let gatewayURLKey = "gatewayURL"
    static let selectedModelKey = "selectedModel"
    static let isConfiguredKey = "isConfigured"
    static let supportsStructuredCorrectionsKey = "supportsStructuredCorrections"
    static let structuredCorrectionSchemaVersionKey = "structuredCorrectionSchemaVersion"
    static let gatewayConnectionErrorMessageKey = "gatewayConnectionErrorMessage"
    static let gatewayConnectionErrorUpdatedAtKey = "gatewayConnectionErrorUpdatedAt"
    static let gatewayConnectionLastTestedAtKey = "gatewayConnectionLastTestedAt"
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let gatewayConnectionRetestInterval: TimeInterval = 60 * 60


    static var secretStore: AppConfigSecretStore = KeychainAppConfigSecretStore()
}

// Extension for saving/loading from App Group + shared Keychain
extension AppConfig {
    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    }

    static func load() -> AppConfig {
        guard let sharedDefaults = sharedDefaults() else {
            return .default
        }

        return load(from: sharedDefaults)
    }

    static func load(from defaults: UserDefaults) -> AppConfig {
        let legacyDefaultsAPIKey = defaults.string(forKey: AppConfig.apiKeyKey) ?? ""
        let keychainAPIKey = secretStore.loadAPIKey() ?? ""
        let apiKey = keychainAPIKey.isEmpty ? legacyDefaultsAPIKey : keychainAPIKey

        if keychainAPIKey.isEmpty, !legacyDefaultsAPIKey.isEmpty {
            if secretStore.saveAPIKey(legacyDefaultsAPIKey) {
                defaults.removeObject(forKey: AppConfig.apiKeyKey)
            }
        } else if !legacyDefaultsAPIKey.isEmpty {
            defaults.removeObject(forKey: AppConfig.apiKeyKey)
        }

        let loadedConfig = AppConfig(
            apiKey: apiKey,
            gatewayURL: defaults.string(forKey: AppConfig.gatewayURLKey) ?? "",
            selectedModel: defaults.string(forKey: AppConfig.selectedModelKey) ?? "",
            isConfigured: defaults.bool(forKey: AppConfig.isConfiguredKey),
            supportsStructuredCorrections: defaults.bool(forKey: AppConfig.supportsStructuredCorrectionsKey),
            structuredCorrectionSchemaVersion: defaults.string(forKey: AppConfig.structuredCorrectionSchemaVersionKey) ?? ""
        ).runtimeNormalized()

        if loadedConfig.isKnownTestPlaceholderConfig,
           !ProcessInfo.processInfo.arguments.contains("--uitesting"),
           !isUITestDebugStateEnabled(in: defaults) {
            clear(from: defaults)
            return .default
        }

        return loadedConfig
    }

    @discardableResult
    func save() -> Bool {
        guard let sharedDefaults = AppConfig.sharedDefaults() else {
            return false
        }

        return save(to: sharedDefaults)
    }

    @discardableResult
    func save(to defaults: UserDefaults) -> Bool {
        let runtimeConfig = runtimeNormalized()
        let trimmedAPIKey = runtimeConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard runtimeConfig.isConfigured else {
            _ = AppConfig.secretStore.clearAPIKey()
            var unconfigured = runtimeConfig
            unconfigured.apiKey = ""
            defaults.removeObject(forKey: AppConfig.apiKeyKey)
            unconfigured.saveNonSecretValues(to: defaults)
            return true
        }

        guard AppConfig.secretStore.saveAPIKey(trimmedAPIKey) else {
            var unconfigured = runtimeConfig
            unconfigured.apiKey = ""
            unconfigured.isConfigured = false
            unconfigured.supportsStructuredCorrections = false
            unconfigured.structuredCorrectionSchemaVersion = ""
            defaults.removeObject(forKey: AppConfig.apiKeyKey)
            unconfigured.saveNonSecretValues(to: defaults)
            return false
        }

        defaults.removeObject(forKey: AppConfig.apiKeyKey)
        runtimeConfig.saveNonSecretValues(to: defaults)
        return true
    }

    @discardableResult
    func saveTestSeed(
        to defaults: UserDefaults,
        overwriteExistingRealConfig: Bool = false,
        mirrorAPIKeyToDefaultsForUITest: Bool = false
    ) -> Bool {
        guard overwriteExistingRealConfig || !AppConfig.hasExistingRealConfig(in: defaults) else {
            return false
        }

        let didSaveSecret = AppConfig.secretStore.saveAPIKey(apiKey)
        if didSaveSecret {
            defaults.removeObject(forKey: AppConfig.apiKeyKey)
        }
        if mirrorAPIKeyToDefaultsForUITest {
            defaults.set(apiKey, forKey: AppConfig.apiKeyKey)
        }

        guard didSaveSecret || mirrorAPIKeyToDefaultsForUITest else {
            var unconfigured = self
            unconfigured.apiKey = ""
            unconfigured.isConfigured = false
            unconfigured.supportsStructuredCorrections = false
            unconfigured.structuredCorrectionSchemaVersion = ""
            defaults.removeObject(forKey: AppConfig.apiKeyKey)
            unconfigured.saveNonSecretValues(to: defaults)
            return false
        }

        runtimeNormalized().saveNonSecretValues(to: defaults)
        return true
    }

    private func saveNonSecretValues(to defaults: UserDefaults) {
        defaults.set(gatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(selectedModel, forKey: AppConfig.selectedModelKey)
        defaults.set(isConfigured, forKey: AppConfig.isConfiguredKey)
        defaults.set(supportsStructuredCorrections, forKey: AppConfig.supportsStructuredCorrectionsKey)
        defaults.set(structuredCorrectionSchemaVersion, forKey: AppConfig.structuredCorrectionSchemaVersionKey)
        defaults.synchronize()
    }

    static func hasExistingRealConfig(in defaults: UserDefaults) -> Bool {
        let keychainAPIKey = secretStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let legacyDefaultsAPIKey = defaults.string(forKey: AppConfig.apiKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let gatewayURL = defaults.string(forKey: AppConfig.gatewayURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedModel = defaults.string(forKey: AppConfig.selectedModelKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidate = AppConfig(
            apiKey: keychainAPIKey.isEmpty ? legacyDefaultsAPIKey : keychainAPIKey,
            gatewayURL: gatewayURL,
            selectedModel: selectedModel,
            isConfigured: defaults.bool(forKey: AppConfig.isConfiguredKey),
            supportsStructuredCorrections: defaults.bool(forKey: AppConfig.supportsStructuredCorrectionsKey),
            structuredCorrectionSchemaVersion: defaults.string(forKey: AppConfig.structuredCorrectionSchemaVersionKey) ?? ""
        )

        return candidate.isConfigured
            && !candidate.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !candidate.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !candidate.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !candidate.isKnownTestPlaceholderConfig
    }

    static func clearSharedConfig() {
        guard let sharedDefaults = sharedDefaults() else { return }
        clear(from: sharedDefaults)
    }

    static func resolvedGatewayModel(from availableModels: [String], currentModel: String = "") -> String? {
        gatewayModelCandidates(from: availableModels, currentModel: currentModel).first
    }

    static func gatewayModelCandidates(from availableModels: [String], currentModel: String = "") -> [String] {
        let models = availableModels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !models.isEmpty else { return [] }

        var candidates: [String] = []
        let current = currentModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let currentMatch = models.first(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            candidates.append(currentMatch)
        }

        if let appleFoundationModel = models.first(where: { $0.caseInsensitiveCompare("apple-foundationmodel") == .orderedSame }),
           !candidates.contains(where: { $0.caseInsensitiveCompare(appleFoundationModel) == .orderedSame }) {
            candidates.append(appleFoundationModel)
        }

        for model in models where !candidates.contains(where: { $0.caseInsensitiveCompare(model) == .orderedSame }) {
            candidates.append(model)
        }
        return candidates
    }

    static func gatewayConnectionError(from defaults: UserDefaults) -> String? {
        let value = defaults.string(forKey: gatewayConnectionErrorMessageKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    static func sharedGatewayConnectionError() -> String? {
        guard let defaults = sharedDefaults() else { return nil }
        return gatewayConnectionError(from: defaults)
    }

    static func gatewayConnectionLastTestedAt(from defaults: UserDefaults) -> Date? {
        guard defaults.object(forKey: gatewayConnectionLastTestedAtKey) != nil else { return nil }
        let timestamp = defaults.double(forKey: gatewayConnectionLastTestedAtKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    static func saveGatewayConnectionLastTestedAt(_ date: Date = Date(), to defaults: UserDefaults? = sharedDefaults()) {
        guard let defaults else { return }
        defaults.set(date.timeIntervalSince1970, forKey: gatewayConnectionLastTestedAtKey)
        defaults.synchronize()
    }

    static func clearGatewayConnectionLastTestedAt(from defaults: UserDefaults? = sharedDefaults()) {
        guard let defaults else { return }
        defaults.removeObject(forKey: gatewayConnectionLastTestedAtKey)
        defaults.synchronize()
    }

    static func saveGatewayConnectionError(_ message: String, to defaults: UserDefaults? = sharedDefaults()) {
        guard let defaults else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearGatewayConnectionError(from: defaults)
            return
        }
        defaults.set(trimmed, forKey: gatewayConnectionErrorMessageKey)
        defaults.set(Date().timeIntervalSince1970, forKey: gatewayConnectionErrorUpdatedAtKey)
        defaults.synchronize()
    }

    static func clearGatewayConnectionError(from defaults: UserDefaults? = sharedDefaults()) {
        guard let defaults else { return }
        defaults.removeObject(forKey: gatewayConnectionErrorMessageKey)
        defaults.removeObject(forKey: gatewayConnectionErrorUpdatedAtKey)
        defaults.synchronize()
    }

    static func resetOnboardingState(in defaults: UserDefaults? = sharedDefaults()) {
        defaults?.set(false, forKey: hasCompletedOnboardingKey)
        defaults?.synchronize()
        UserDefaults.standard.set(false, forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: .openKeyboardOnboardingReset, object: nil)
    }

    var isKnownTestPlaceholderConfig: Bool {
        let normalizedGatewayURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        return AppConfig.rejectedGatewayURLs.contains { $0.caseInsensitiveCompare(normalizedGatewayURL) == .orderedSame }
            || AppConfig.rejectedSelectedModels.contains(normalizedSelectedModel)
            || AppConfig.rejectedAPIKeys.contains(normalizedAPIKey)
    }

    var hasCompleteGatewayRuntimeConfig: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runtimeNormalized() -> AppConfig {
        guard isConfigured else {
            var copy = self
            copy.supportsStructuredCorrections = false
            copy.structuredCorrectionSchemaVersion = ""
            return copy
        }
        guard !hasCompleteGatewayRuntimeConfig else { return self }

        var copy = self
        copy.isConfigured = false
        copy.supportsStructuredCorrections = false
        copy.structuredCorrectionSchemaVersion = ""
        return copy
    }

    private static var rejectedGatewayURLs: [String] {
        [["https://gateway", "example", "invalid"].joined(separator: ".")]
    }

    private static var rejectedSelectedModels: [String] {
        [["test", "placeholder", "model"].joined(separator: "-")]
    }

    private static var rejectedAPIKeys: [String] {
        [["test", "placeholder", "key"].joined(separator: "-")]
    }

    struct RedactedVisibilityDiagnostic: Equatable {
        let uiTestDebugStateEnabled: Bool
        let gatewayURLPresent: Bool
        let gatewayHost: String
        let selectedModelPresent: Bool
        let selectedModel: String
        let defaultsIsConfigured: Bool
        let legacyDefaultsAPIKeyPresent: Bool
        let keychainAPIKeyPresent: Bool
        let loadedConfigIsConfigured: Bool

        var redactedDescription: String {
            [
                "keyboardExtension.uiTestDebugStateEnabled=\(uiTestDebugStateEnabled)",
                "gatewayURLPresent=\(gatewayURLPresent)",
                "gatewayHost=\(gatewayHost)",
                "selectedModelPresent=\(selectedModelPresent)",
                "selectedModel=\(selectedModel)",
                "AppConfig.isConfigured(defaults)=\(defaultsIsConfigured)",
                "legacyAppGroupAPIKeyPresent=\(legacyDefaultsAPIKeyPresent)",
                "keychainAPIKeyPresent=\(keychainAPIKeyPresent)",
                "loadedExtensionAppConfig.isConfigured=\(loadedConfigIsConfigured)"
            ].joined(separator: "; ")
        }
    }

    static func redactedVisibilityDiagnostic(from defaults: UserDefaults? = sharedDefaults()) -> RedactedVisibilityDiagnostic {
        guard let defaults else {
            return RedactedVisibilityDiagnostic(
                uiTestDebugStateEnabled: false,
                gatewayURLPresent: false,
                gatewayHost: "shared-defaults-unavailable",
                selectedModelPresent: false,
                selectedModel: "missing",
                defaultsIsConfigured: false,
                legacyDefaultsAPIKeyPresent: false,
                keychainAPIKeyPresent: false,
                loadedConfigIsConfigured: false
            )
        }

        let rawGatewayURL = defaults.string(forKey: gatewayURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawSelectedModel = defaults.string(forKey: selectedModelKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let legacyDefaultsAPIKey = defaults.string(forKey: apiKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keychainAPIKey = secretStore.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let loadedConfig = load(from: defaults)

        return RedactedVisibilityDiagnostic(
            uiTestDebugStateEnabled: isUITestDebugStateEnabled(in: defaults),
            gatewayURLPresent: !rawGatewayURL.isEmpty,
            gatewayHost: redactedGatewayHost(from: rawGatewayURL),
            selectedModelPresent: !rawSelectedModel.isEmpty,
            selectedModel: rawSelectedModel.isEmpty ? "missing" : rawSelectedModel,
            defaultsIsConfigured: defaults.bool(forKey: isConfiguredKey),
            legacyDefaultsAPIKeyPresent: !legacyDefaultsAPIKey.isEmpty,
            keychainAPIKeyPresent: !keychainAPIKey.isEmpty,
            loadedConfigIsConfigured: loadedConfig.isConfigured
        )
    }

    private static func redactedGatewayHost(from gatewayURL: String) -> String {
        guard !gatewayURL.isEmpty else { return "missing" }
        if let host = URL(string: gatewayURL)?.host, !host.isEmpty {
            return host
        }
        return "present-unparseable"
    }

    static func isUITestDebugStateEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled")
    }

    static func clear(from defaults: UserDefaults) {
        secretStore.clearAPIKey()
        [apiKeyKey, gatewayURLKey, selectedModelKey, isConfiguredKey, supportsStructuredCorrectionsKey, structuredCorrectionSchemaVersionKey, gatewayConnectionErrorMessageKey, gatewayConnectionErrorUpdatedAtKey, gatewayConnectionLastTestedAtKey, "keyboardExtension.composingBuffer", "keyboardExtension.lastDebugEvent", "keyboardExtension.debugEvents", "keyboardExtension.uiTestDebugStateEnabled", "keyboardExtension.initialPanelMode", "keyboardExtension.initialPanelModeSeedID", "keyboardExtension.initialPanelModeSeededAt", "keyboardExtension.suggestionState", "keyboardExtension.suggestionStateSeedID", "keyboardExtension.suggestionStateSeededAt"].forEach {
            defaults.removeObject(forKey: $0)
        }
        defaults.synchronize()
    }
}

extension Notification.Name {
    static let openKeyboardOnboardingReset = Notification.Name("openKeyboardOnboardingReset")
}
