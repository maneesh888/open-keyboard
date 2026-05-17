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
    var isConfigured: Bool
    
    static let `default` = AppConfig(
        apiKey: "",
        gatewayURL: "http://localhost:8080",
        isConfigured: false
    )
    
    // App Group identifier for sharing data with keyboard extension
    static let appGroupIdentifier = "group.com.maneesh.openkeyboard"
    
    // UserDefaults keys
    static let apiKeyKey = "apiKey"
    static let gatewayURLKey = "gatewayURL"
    static let isConfiguredKey = "isConfigured"
}

// Extension for saving/loading from App Group
extension AppConfig {
    static func load() -> AppConfig {
        guard let sharedDefaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier) else {
            return .default
        }
        
        return AppConfig(
            apiKey: sharedDefaults.string(forKey: AppConfig.apiKeyKey) ?? "",
            gatewayURL: sharedDefaults.string(forKey: AppConfig.gatewayURLKey) ?? "http://localhost:8080",
            isConfigured: sharedDefaults.bool(forKey: AppConfig.isConfiguredKey)
        )
    }
    
    func save() {
        guard let sharedDefaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier) else {
            return
        }
        
        sharedDefaults.set(apiKey, forKey: AppConfig.apiKeyKey)
        sharedDefaults.set(gatewayURL, forKey: AppConfig.gatewayURLKey)
        sharedDefaults.set(isConfigured, forKey: AppConfig.isConfiguredKey)
    }
}
