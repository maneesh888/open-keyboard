//
//  AppConfig.swift
//  OpenKeyboard
//
//  Configuration model
//

import Foundation
import Security

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
    
    static let `default` = AppConfig(
        apiKey: "",
        gatewayURL: "",
        selectedModel: "",
        isConfigured: false
    )
    
    // App Group identifier for sharing non-sensitive data with keyboard extension
    static let appGroupIdentifier = "group.com.maneesh.openkeyboard"
    
    // UserDefaults keys. apiKeyKey is legacy-only and is removed after Keychain migration.
    static let apiKeyKey = "apiKey"
    static let gatewayURLKey = "gatewayURL"
    static let selectedModelKey = "selectedModel"
    static let isConfiguredKey = "isConfigured"

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

        return AppConfig(
            apiKey: apiKey,
            gatewayURL: defaults.string(forKey: AppConfig.gatewayURLKey) ?? "",
            selectedModel: defaults.string(forKey: AppConfig.selectedModelKey) ?? "",
            isConfigured: defaults.bool(forKey: AppConfig.isConfiguredKey)
        )
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
        defaults.synchronize()
    }

    static func clearSharedConfig() {
        guard let sharedDefaults = sharedDefaults() else { return }
        clear(from: sharedDefaults)
    }

    static func clear(from defaults: UserDefaults) {
        secretStore.clearAPIKey()
        [apiKeyKey, gatewayURLKey, selectedModelKey, isConfiguredKey, "keyboardExtension.composingBuffer", "keyboardExtension.lastDebugEvent", "keyboardExtension.debugEvents", "keyboardExtension.uiTestDebugStateEnabled", "keyboardExtension.initialPanelMode"].forEach {
            defaults.removeObject(forKey: $0)
        }
        defaults.synchronize()
    }
}
