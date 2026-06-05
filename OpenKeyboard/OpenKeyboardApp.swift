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
    
    init() {
        Self.seedUITestGatewayConfigAtLaunchIfNeeded()
    }

    private var launchArguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    private var isUITesting: Bool {
        launchArguments.contains("--uitesting")
    }

    private var shouldShowLiveAITestHarness: Bool {
        isUITesting && launchArguments.contains("--live-ai-test-harness")
    }

    private var shouldShowKeyboardHostTest: Bool {
        isUITesting && launchArguments.contains("--keyboard-host-test")
    }

    private var shouldShowOnboarding: Bool {
        guard isUITesting else {
            return !hasCompletedOnboarding
        }

        guard !shouldShowLiveAITestHarness else { return false }
        guard !launchArguments.contains("--seed-gateway-config"), !launchArguments.contains("--seed-functional-gateway-config") else { return false }

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

    private static func seedUITestGatewayConfigAtLaunchIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"), arguments.contains("--seed-gateway-config") || arguments.contains("--seed-functional-gateway-config") else { return }

        AppConfig.clearSharedConfig()
        let environment = ProcessInfo.processInfo.environment
        let requiresFunctionalCredentials = arguments.contains("--seed-functional-gateway-config")
        let apiKey = environment["OPEN_KEYBOARD_TEST_API_KEY"]
        let gatewayURL = environment["OPEN_KEYBOARD_TEST_GATEWAY_URL"]
        let selectedModel = environment["OPEN_KEYBOARD_TEST_MODEL"]

        guard let apiKey, !apiKey.isEmpty,
              let gatewayURL, !gatewayURL.isEmpty,
              let selectedModel, !selectedModel.isEmpty else {
            return
        }

        let config = AppConfig(
            apiKey: apiKey,
            gatewayURL: normalizeUITestGatewayURL(gatewayURL),
            selectedModel: selectedModel,
            isConfigured: true
        )
        config.save()

        if requiresFunctionalCredentials, let sharedDefaults = AppConfig.sharedDefaults() {
            sharedDefaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
            sharedDefaults.synchronize()
        }
    }

    private static func normalizeUITestGatewayURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http:/"), !trimmed.hasPrefix("http://") {
            return "http://" + trimmed.dropFirst("http:/".count)
        }
        if trimmed.hasPrefix("https:/"), !trimmed.hasPrefix("https://") {
            return "https://" + trimmed.dropFirst("https:/".count)
        }
        return trimmed
    }

    private func refreshUITestGatewayConfigIfNeeded() {
        guard isUITesting, launchArguments.contains("--seed-gateway-config") || launchArguments.contains("--seed-functional-gateway-config") else { return }

        settingsViewModel.config = AppConfig.load()
        hasCompletedOnboarding = true
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if shouldShowLiveAITestHarness {
                    LiveAITestHarnessView()
                } else if shouldShowKeyboardHostTest {
                    KeyboardExtensionHostTestView()
                } else if shouldShowOnboarding {
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
                refreshUITestGatewayConfigIfNeeded()
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
