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
    
    private var launchArguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    private var isUITesting: Bool {
        launchArguments.contains("--uitesting")
    }

    private var shouldShowOnboarding: Bool {
        guard isUITesting else {
            return !hasCompletedOnboarding
        }

        return launchArguments.contains("--show-onboarding") || (!hasCompletedOnboarding && !launchArguments.contains("--skip-onboarding"))
    }

    private var onboardingInitialPage: Int {
        guard isUITesting,
              let pageArgument = launchArguments.first(where: { $0.hasPrefix("--onboarding-page=") }),
              let value = Int(pageArgument.replacingOccurrences(of: "--onboarding-page=", with: "")) else {
            return 0
        }

        return min(max(value, 0), 3)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if shouldShowOnboarding {
                    OnboardingView(
                        hasCompletedOnboarding: $hasCompletedOnboarding,
                        initialPage: onboardingInitialPage
                    )
                    .environmentObject(settingsViewModel)
                } else {
                    ContentView()
                        .environmentObject(settingsViewModel)
                }
            }
            .onAppear {
                if isUITesting && launchArguments.contains("--show-onboarding") {
                    hasCompletedOnboarding = false
                }
                if isUITesting && launchArguments.contains("--skip-onboarding") {
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}
