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
        #if DEBUG
        Self.clearUITestConfigAtLaunchIfNeeded()
        Self.seedUITestGatewayConfigAtLaunchIfNeeded()
        Self.seedUITestGatewayErrorAtLaunchIfNeeded()
        Self.seedUITestKeyboardPanelModeAtLaunchIfNeeded()
        Self.seedUITestKeyboardSuggestionStateAtLaunchIfNeeded()
        #endif
    }

    private var launchArguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    private var isUITesting: Bool {
        #if DEBUG
        return launchArguments.contains("--uitesting")
        #else
        return false
        #endif
    }

    private var shouldShowLiveAITestHarness: Bool {
        #if DEBUG
        return isUITesting && launchArguments.contains("--live-ai-test-harness")
        #else
        return false
        #endif
    }

    private var shouldShowKeyboardHostTest: Bool {
        #if DEBUG
        return isUITesting && launchArguments.contains("--keyboard-host-test")
        #else
        return false
        #endif
    }

    private var shouldShowPlaygroundDirectly: Bool {
        #if DEBUG
        return isUITesting && (launchArguments.contains("--playground-all-good-regression-proof") || launchArguments.contains("--playground-direct"))
        #else
        return false
        #endif
    }

    private var productionKeyboardState: String? {
        #if DEBUG
        guard isUITesting,
              let argument = launchArguments.first(where: { $0.hasPrefix("--production-keyboard-state=") }) else {
            return nil
        }
        return argument.replacingOccurrences(of: "--production-keyboard-state=", with: "")
        #else
        return nil
        #endif
    }

    #if DEBUG
    private var editorHostPreviewState: KeyboardPreviewLabState? {
        guard isUITesting,
              let argument = launchArguments.first(where: { $0.hasPrefix("--editor-host-preview=") }) else {
            return nil
        }
        let value = argument.replacingOccurrences(of: "--editor-host-preview=", with: "")
        return KeyboardPreviewLabState(rawValue: value)
    }

    private var keyboardPreviewPanel: KeyboardVisualPreviewPanel? {
        nil
    }
    #endif

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

    #if DEBUG
    private static func clearUITestConfigAtLaunchIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"), arguments.contains("--clear-gateway-config") else { return }
        guard let sharedDefaults = AppConfig.sharedDefaults() else { return }

        let replacementRequested = isUITestConfigReplacementRequested(
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment
        )
        guard replacementRequested || !AppConfig.hasExistingRealConfig(in: sharedDefaults) else { return }

        AppConfig.clear(from: sharedDefaults)
    }

    private static func isUITestConfigReplacementRequested(
        arguments: [String],
        environment: [String: String]
    ) -> Bool {
        arguments.contains("--replace-existing-config")
            || environment["OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG"] == "1"
    }

    private static func seedUITestGatewayConfigAtLaunchIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"), arguments.contains("--seed-gateway-config") || arguments.contains("--seed-functional-gateway-config") else { return }

        let environment = ProcessInfo.processInfo.environment
        let apiKey = environment["OPEN_KEYBOARD_TEST_API_KEY"]
        let gatewayURL = environment["OPEN_KEYBOARD_TEST_GATEWAY_URL"]
        let selectedModel = environment["OPEN_KEYBOARD_TEST_MODEL"]
        let replacementRequested = isUITestConfigReplacementRequested(
            arguments: arguments,
            environment: environment
        )
        let shouldMirrorAPIKeyToDefaults = arguments.contains("--seed-gateway-config")
            && !arguments.contains("--seed-functional-gateway-config")

        guard let apiKey, !apiKey.isEmpty,
              let gatewayURL, !gatewayURL.isEmpty,
              let selectedModel, !selectedModel.isEmpty else {
            return
        }

        let config = AppConfig(
            apiKey: apiKey,
            gatewayURL: normalizeUITestGatewayURL(gatewayURL),
            selectedModel: selectedModel,
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
        if let sharedDefaults = AppConfig.sharedDefaults() {
            let didSeed = config.saveTestSeed(
                to: sharedDefaults,
                overwriteExistingRealConfig: replacementRequested,
                mirrorAPIKeyToDefaultsForUITest: shouldMirrorAPIKeyToDefaults
            )
            if didSeed {
                // Keep UI-test seeded config visible to the keyboard extension even when
                // the simulator proof configuration does not define DEBUG for the app target.
                sharedDefaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
                sharedDefaults.synchronize()
            }
        }
    }

    private static func seedUITestGatewayErrorAtLaunchIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"),
              let errorArgument = arguments.first(where: { $0.hasPrefix("--seed-gateway-error=") }) else {
            return
        }

        let message = errorArgument.replacingOccurrences(of: "--seed-gateway-error=", with: "")
        AppConfig.saveGatewayConnectionError(message)
    }

    private static func seedUITestKeyboardPanelModeAtLaunchIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"),
              let panelArgument = arguments.first(where: { $0.hasPrefix("--keyboard-initial-panel=") }),
              let sharedDefaults = AppConfig.sharedDefaults() else {
            return
        }

        let panelMode = panelArgument.replacingOccurrences(of: "--keyboard-initial-panel=", with: "")
        switch panelMode {
        case "actions", "rewriteOptions", "correctionDetail", "correctionCarousel", "correctionComplete":
            sharedDefaults.set(panelMode, forKey: "keyboardExtension.initialPanelMode")
            sharedDefaults.set(UUID().uuidString, forKey: "keyboardExtension.initialPanelModeSeedID")
            sharedDefaults.set(Date().timeIntervalSince1970, forKey: "keyboardExtension.initialPanelModeSeededAt")
        default:
            sharedDefaults.removeObject(forKey: "keyboardExtension.initialPanelMode")
            sharedDefaults.removeObject(forKey: "keyboardExtension.initialPanelModeSeedID")
            sharedDefaults.removeObject(forKey: "keyboardExtension.initialPanelModeSeededAt")
        }
        sharedDefaults.synchronize()
    }

    private static func seedUITestKeyboardSuggestionStateAtLaunchIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"),
              let stateArgument = arguments.first(where: { $0.hasPrefix("--keyboard-suggestion-state=") }),
              let sharedDefaults = AppConfig.sharedDefaults() else {
            return
        }

        let state = stateArgument.replacingOccurrences(of: "--keyboard-suggestion-state=", with: "")
        let allowedStates = ["correctionCard", "correctionOnly", "correctionComplete", "correctionDetail", "correctionCarousel", "rewriteOptions", "allGood", "analysisFailed", "analyzing"]
        if allowedStates.contains(state) {
            sharedDefaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
            sharedDefaults.set(state, forKey: "keyboardExtension.suggestionState")
            sharedDefaults.set(UUID().uuidString, forKey: "keyboardExtension.suggestionStateSeedID")
            sharedDefaults.set(Date().timeIntervalSince1970, forKey: "keyboardExtension.suggestionStateSeededAt")
        } else {
            sharedDefaults.removeObject(forKey: "keyboardExtension.suggestionState")
            sharedDefaults.removeObject(forKey: "keyboardExtension.suggestionStateSeedID")
            sharedDefaults.removeObject(forKey: "keyboardExtension.suggestionStateSeededAt")
        }
        sharedDefaults.synchronize()
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

    #endif

    private func refreshUITestGatewayConfigIfNeeded() {
        #if DEBUG
        guard isUITesting, launchArguments.contains("--seed-gateway-config") || launchArguments.contains("--seed-functional-gateway-config") else { return }

        settingsViewModel.applyConfig(AppConfig.load())
        hasCompletedOnboarding = true
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let editorHostPreviewState {
                    KeyboardEditorHostPreviewView(state: editorHostPreviewState)
                } else if let keyboardPreviewPanel {
                    KeyboardVisualPreviewView(panel: keyboardPreviewPanel)
                } else if shouldShowLiveAITestHarness {
                    LiveAITestHarnessView()
                } else if let productionKeyboardState {
                    ProductionKeyboardStateHostView(state: productionKeyboardState)
                } else if shouldShowKeyboardHostTest {
                    KeyboardExtensionHostTestView()
                } else if shouldShowPlaygroundDirectly {
                    NavigationView {
                        PlaygroundView()
                    }
                    .environmentObject(settingsViewModel)
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
                #else
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
                #endif
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
            .onReceive(NotificationCenter.default.publisher(for: .openKeyboardOnboardingReset)) { _ in
                hasCompletedOnboarding = false
            }
        }
    }
}
