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
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    static let testPlaceholderGatewayURL = "https://gateway.example.invalid"
    static let testPlaceholderModel = "test-placeholder-model"
    static let testPlaceholderAPIKey = "test-placeholder-key"

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
        )

        if loadedConfig.isKnownTestPlaceholderConfig,
           !ProcessInfo.processInfo.arguments.contains("--uitesting"),
           !isUITestDebugStateEnabled(in: defaults) {
            clear(from: defaults)
            return .default
        }

        return loadedConfig
    }

    func save() {
        guard let sharedDefaults = AppConfig.sharedDefaults() else {
            return
        }

        save(to: sharedDefaults)
    }

    func save(to defaults: UserDefaults) {
        if AppConfig.secretStore.saveAPIKey(apiKey) {
            defaults.removeObject(forKey: AppConfig.apiKeyKey)
        }
        defaults.set(gatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(selectedModel, forKey: AppConfig.selectedModelKey)
        defaults.set(isConfigured, forKey: AppConfig.isConfiguredKey)
        defaults.set(supportsStructuredCorrections, forKey: AppConfig.supportsStructuredCorrectionsKey)
        defaults.set(structuredCorrectionSchemaVersion, forKey: AppConfig.structuredCorrectionSchemaVersionKey)
        defaults.synchronize()
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
        gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(AppConfig.testPlaceholderGatewayURL) == .orderedSame
            || selectedModel.trimmingCharacters(in: .whitespacesAndNewlines) == AppConfig.testPlaceholderModel
            || apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == AppConfig.testPlaceholderAPIKey
    }

    static func isUITestDebugStateEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled")
    }

    static func clear(from defaults: UserDefaults) {
        secretStore.clearAPIKey()
        [apiKeyKey, gatewayURLKey, selectedModelKey, isConfiguredKey, supportsStructuredCorrectionsKey, structuredCorrectionSchemaVersionKey, gatewayConnectionErrorMessageKey, gatewayConnectionErrorUpdatedAtKey, "keyboardExtension.composingBuffer", "keyboardExtension.lastDebugEvent", "keyboardExtension.debugEvents", "keyboardExtension.uiTestDebugStateEnabled", "keyboardExtension.initialPanelMode", "keyboardExtension.suggestionState"].forEach {
            defaults.removeObject(forKey: $0)
        }
        defaults.synchronize()
    }
}

extension Notification.Name {
    static let openKeyboardOnboardingReset = Notification.Name("openKeyboardOnboardingReset")
}
