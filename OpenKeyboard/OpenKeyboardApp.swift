//
//  OpenKeyboardApp.swift
//  OpenKeyboard
//
//  Main app entry point
//

import SwiftUI

@main
struct OpenKeyboardApp: App {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @AppStorage("hasCompletedOnboarding", store: UserDefaults(suiteName: "group.com.maneesh.openkeyboard"))
    private var hasCompletedOnboarding = false
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(settingsViewModel)
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(settingsViewModel)
            }
        }
    }
}
