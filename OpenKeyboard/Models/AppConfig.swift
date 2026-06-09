//
//  AppConfig.swift
//  OpenKeyboard
//
//  Configuration model
//

import Foundation

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
    
    // App Group identifier for sharing data with keyboard extension
    static let appGroupIdentifier = "group.com.maneesh.openkeyboard"
    
    // UserDefaults keys
    static let apiKeyKey = "apiKey"
    static let gatewayURLKey = "gatewayURL"
    static let selectedModelKey = "selectedModel"
    static let isConfiguredKey = "isConfigured"
}

// Extension for saving/loading from App Group
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
        AppConfig(
            apiKey: defaults.string(forKey: AppConfig.apiKeyKey) ?? "",
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
        defaults.set(apiKey, forKey: AppConfig.apiKeyKey)
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
        [apiKeyKey, gatewayURLKey, selectedModelKey, isConfiguredKey, "keyboardExtension.composingBuffer", "keyboardExtension.lastDebugEvent", "keyboardExtension.debugEvents", "keyboardExtension.uiTestDebugStateEnabled", "keyboardExtension.initialPanelMode"].forEach {
            defaults.removeObject(forKey: $0)
        }
        defaults.synchronize()
    }
}
