//
//  SettingsViewModel.swift
//  OpenKeyboard
//
//  ViewModel for settings screen
//

import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var config: AppConfig
    @Published var isTestingConnection = false
    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var errorMessage: String?
    
    enum ConnectionStatus {
        case unknown
        case success
        case failure
    }
    
    init() {
        self.config = AppConfig.load()
    }
    
    func saveSettings() {
        config.save()
    }
    
    func testConnection() async {
        isTestingConnection = true
        connectionStatus = .unknown
        errorMessage = nil
        
        do {
            let success = try await NetworkManager.shared.testConnection(
                gatewayURL: config.gatewayURL,
                apiKey: config.apiKey
            )
            
            if success {
                connectionStatus = .success
                config.isConfigured = true
                saveSettings()
            } else {
                connectionStatus = .failure
                errorMessage = "Connection failed"
            }
        } catch {
            connectionStatus = .failure
            if let networkError = error as? NetworkError {
                errorMessage = networkError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
        
        isTestingConnection = false
    }
    
    func openKeyboardSettings() {
        if let url = URL(string: "App-Prefs:root=General&path=Keyboard") {
            UIApplication.shared.open(url)
        }
    }
}
