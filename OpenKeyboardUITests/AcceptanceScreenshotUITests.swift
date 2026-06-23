import XCTest

final class AcceptanceScreenshotUITests: XCTestCase {
    private static let placeholderGatewayURL = "https://gateway.example.invalid"
    private static let placeholderAPIKey = "test-placeholder-key"
    private static let placeholderModel = "test-placeholder-model"
    private static let appGroupIdentifier = "group.com.maneesh.openkeyboard"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeLaunchLightScreenshotHasNoPreviewOrDebugCopy() throws {
        let app = launchHomeApp(appearance: .light)

        XCTAssertTrue(app.staticTexts["Open Keyboard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Keyboard Preview Lab"].exists)
        XCTAssertFalse(app.staticTexts["Gateway"].exists)
        XCTAssertFalse(app.staticTexts["API Key"].exists)
        XCTAssertFalse(app.staticTexts["Model"].exists)
        attachScreenshot(from: app, named: "acceptance-ui-test-home-light")
    }

    func testHomeLaunchDarkScreenshotHasNoPreviewOrDebugCopy() throws {
        let app = launchHomeApp(appearance: .dark)

        XCTAssertTrue(app.staticTexts["Open Keyboard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Keyboard Preview Lab"].exists)
        XCTAssertFalse(app.staticTexts["Gateway"].exists)
        XCTAssertFalse(app.staticTexts["API Key"].exists)
        XCTAssertFalse(app.staticTexts["Model"].exists)
        attachScreenshot(from: app, named: "acceptance-ui-test-home-dark")
    }




    func testSettingsCleanSuccessHidesConnectionActionsAndDirtyEditingRestoresThem() throws {
        let app = launchConfiguredHomeApp()

        XCTAssertTrue(app.staticTexts["Open Keyboard"].waitForExistence(timeout: 5))
        let settingsButton = app.buttons["App Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Configured home should expose App Settings")
        settingsButton.tap()

        let gatewayURLField = app.textFields["Gateway URL"]
        XCTAssertTrue(gatewayURLField.waitForExistence(timeout: 5), "Settings sheet should expose Gateway URL field")
        XCTAssertFalse(app.buttons["Test Connection & Save"].exists, "Clean validated settings should hide Test Connection & Save")
        XCTAssertTrue(app.staticTexts["Model"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts[Self.placeholderModel].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Structured corrections"].waitForExistence(timeout: 2))
        attachScreenshot(from: app, named: "settings-clean-success-hides-actions")

        let gatewayURL = app.textFields["Gateway URL"]
        gatewayURL.tap()
        gatewayURL.typeText("/edited")

        XCTAssertTrue(app.buttons["Test Connection & Save"].waitForExistence(timeout: 3), "Dirty edited settings should show Test Connection & Save")
        XCTAssertFalse(app.staticTexts[Self.placeholderModel].exists, "Dirty settings should not show stale validated model as current truth")
        XCTAssertFalse(app.staticTexts["Structured corrections"].exists, "Dirty settings should hide stale structured capability details")
        attachScreenshot(from: app, named: "settings-dirty-editing-shows-actions")
    }


    func testSettingsGlobalGatewayErrorShowsRetryAndHidesModelDetailsScreenshot() throws {
        let app = launchConfiguredHomeApp(extraArguments: ["--seed-gateway-error=Keyboard detected gateway timeout"])

        XCTAssertTrue(app.staticTexts["Open Keyboard"].waitForExistence(timeout: 5))
        app.buttons["App Settings"].tap()

        XCTAssertTrue(app.textFields["Gateway URL"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Test Connection & Save"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Keyboard detected gateway timeout")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts[Self.placeholderModel].exists, "Settings error state must hide stale model details")
        XCTAssertFalse(app.staticTexts["Structured corrections"].exists, "Settings error state must hide stale structured capability details")
        attachScreenshot(from: app, named: "settings-global-gateway-error-retry-no-model-details")
    }

    func testResetOnboardingFromSettingsShowsRealOnboardingScreenshot() throws {
        let app = launchConfiguredHomeAppWithoutSkipOnboarding()

        XCTAssertTrue(app.staticTexts["Open Keyboard"].waitForExistence(timeout: 5))
        app.buttons["App Settings"].tap()
        let resetButton = app.buttons["settings_reset_onboarding"]
        if !resetButton.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        if !resetButton.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(resetButton.waitForExistence(timeout: 5))
        resetButton.tap()

        app.terminate()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [:]
        app.launch()

        let onboardingTitle = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Welcome to")).firstMatch
        XCTAssertTrue(onboardingTitle.waitForExistence(timeout: 5), "Reset Onboarding should clear persisted state so the real onboarding flow appears on next launch")
        attachScreenshot(from: app, named: "settings-reset-onboarding-real-onboarding-next-launch")
    }

    func testNormalSurfacesDoNotExposeGatewayAdminNavigation() throws {
        let app = launchConfiguredHomeApp()

        XCTAssertTrue(app.staticTexts["Open Keyboard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Gateway Admin"].exists)
        XCTAssertFalse(app.links["Gateway Admin"].exists)

        app.buttons["App Settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Gateway URL"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Gateway Admin"].exists)
        XCTAssertFalse(app.links["Gateway Admin"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "admin panel")).firstMatch.exists)
        attachScreenshot(from: app, named: "settings-no-gateway-admin-navigation")
    }

    func testOnboardingGatewayCopyDoesNotMentionPrivateAdminPanel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--show-onboarding", "--onboarding-page=1"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Connect your gateway"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Connect a compatible gateway using your gateway URL and API key."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "admin")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "LLM Gateway")).firstMatch.exists)
        attachScreenshot(from: app, named: "onboarding-gateway-copy-no-admin-panel")
    }

    func testConfiguredHomeOpensPlaygroundAndFocusesInput() throws {
        let app = launchConfiguredHomeApp()

        let entry = app.buttons["playground_entry_button"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Configured home should expose the product Playground entry")
        attachScreenshot(from: app, named: "acceptance-ui-test-home-playground-entry")

        entry.tap()
        XCTAssertTrue(app.staticTexts["playground_title"].waitForExistence(timeout: 5))
        let input = app.textViews["playground_text_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Playground should expose a real editable text input")
        XCTAssertTrue(app.staticTexts["i has a apple,ths is nt sound god"].waitForExistence(timeout: 2) || input.value.debugDescription.contains("i has a apple,ths is nt sound god"), "Playground should open with the canonical grammar sample prefilled")
        input.tap()
        input.typeText("Testing Playground")
        let typed = NSPredicate(format: "value CONTAINS[c] %@", "Testing Playground")
        expectation(for: typed, evaluatedWith: input)
        waitForExpectations(timeout: 5)
        attachScreenshot(from: app, named: "acceptance-ui-test-playground-input-focused")
    }





    func testPlaygroundGatewayProofShowsActionableBackendStatus() throws {
        let app = launchConfiguredHomeApp(extraArguments: ["--playground-gateway-proof"])

        let entry = app.buttons["playground_entry_button"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Configured home should expose Playground entry")
        entry.tap()

        XCTAssertTrue(app.staticTexts["playground_title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["playground_text_input"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["i has a apple,ths is nt sound god"].waitForExistence(timeout: 2) || app.textViews["playground_text_input"].value.debugDescription.contains("i has a apple,ths is nt sound god"))
        XCTAssertTrue(app.staticTexts["Live gateway check"].waitForExistence(timeout: 5))
        let gatewayStatus = app.staticTexts["playground_gateway_status"]
        XCTAssertTrue(gatewayStatus.waitForExistence(timeout: 10) || app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Gateway")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["playground_gateway_retry"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Keyboard Preview Lab"].exists)
        XCTAssertFalse(app.otherElements["keyboard_visual_preview"].exists)
        attachScreenshot(from: app, named: "acceptance-ui-test-playground-gateway-proof")
    }

    func testPlaygroundGrammarlyCorrectionProofDoesNotUsePreviewLab() throws {
        let app = launchConfiguredHomeApp(extraArguments: ["--playground-grammarly-proof"])

        let entry = app.buttons["playground_entry_button"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Configured home should expose Playground entry")
        entry.tap()

        XCTAssertTrue(app.staticTexts["playground_title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["playground_text_input"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["There has been no apples"].waitForExistence(timeout: 2) || app.textViews["playground_text_input"].value.debugDescription.contains("There has been no apples"))
        XCTAssertTrue(app.staticTexts["Subject-verb agreement"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["has"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["have"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Use “have” because the subject is plural."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Apply"].waitForExistence(timeout: 2), "Playground correction proof should show the visible Apply action")
        XCTAssertTrue(app.buttons["Dismiss"].waitForExistence(timeout: 2), "Playground correction proof should show the visible Dismiss action")
        attachScreenshot(from: app, named: "acceptance-ui-test-playground-grammarly-real-app-proof")
        XCTAssertFalse(app.staticTexts["Keyboard Preview Lab"].exists)
        XCTAssertFalse(app.otherElements["keyboard_visual_preview"].exists)
        XCTAssertFalse(app.otherElements["keyboard_preview_lab"].exists)
    }


    func testPlaygroundBrokenSampleDoesNotRenderAllGoodRegression() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--skip-onboarding", "--playground-all-good-regression-proof"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Playground"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["playground_text_input"].waitForExistence(timeout: 5) || app.otherElements["playground_text_input"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Writing suggestions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Subject-verb agreement"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Spelling"].exists || app.staticTexts["Article"].exists)
        XCTAssertFalse(app.staticTexts["All Good"].exists)
        XCTAssertFalse(app.staticTexts["No issues found."].exists)
        attachScreenshot(from: app, named: "playground-all-good-regression-fixed")
    }

    func testGrammarlyAcceptanceMustNotUsePreviewLabRoute() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--skip-onboarding", "--keyboard-preview-panel=correctionDetail"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Open Keyboard"].waitForExistence(timeout: 5), "Preview-panel launch argument must be ignored and fall through to the real app shell")
        XCTAssertFalse(app.staticTexts["Keyboard Preview Lab"].waitForExistence(timeout: 1), "Grammarly acceptance proof must not use Keyboard Preview Lab")
        XCTAssertFalse(app.otherElements["keyboard_visual_preview"].exists, "Grammarly acceptance proof must not use KeyboardVisualPreviewView")
        XCTAssertFalse(app.otherElements["keyboard_preview_lab"].exists, "Grammarly acceptance proof must not use direct preview-route UI")
        attachScreenshot(from: app, named: "acceptance-ui-test-no-preview-lab-route")
    }



    func testProductionKeyboardReadyPolishScreenshotRoute() throws {
        let app = launchProductionKeyboardStateApp("ready")

        XCTAssertTrue(app.otherElements["production_keyboard_state_host_ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Open Keyboard AI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["AI ready · ui-test-model"].waitForExistence(timeout: 5), "Ready polish route must render a true ready/idle toolbar state")
        XCTAssertFalse(app.staticTexts["Analyzing"].exists, "Ready polish route must not render the analyzing toolbar state")
        XCTAssertTrue(app.buttons["Next Keyboard"].waitForExistence(timeout: 5), "Globe/next keyboard control should be visible and exposed with native label")
        XCTAssertFalse(app.buttons["Dictation unavailable"].waitForExistence(timeout: 1), "Mic/dictation affordance must not be visible in the keyboard bottom row")
        XCTAssertTrue(app.buttons["space"].waitForExistence(timeout: 2), "Space key should remain visible in ready keyboard state")
        XCTAssertTrue(app.buttons["q"].waitForExistence(timeout: 2) || app.buttons["w"].waitForExistence(timeout: 2), "Ready keyboard should keep letter keys visible")
        attachScreenshot(from: app, named: "production-keyboard-ready-polish")
        XCTAssertFalse(app.staticTexts["Full Access required"].exists)
    }

    func testProductionKeyboardAnalyzingStateScreenshotRoute() throws {
        let app = launchProductionKeyboardStateApp("analyzing")

        XCTAssertTrue(app.otherElements["production_keyboard_state_host_analyzing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Open Keyboard AI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Analyzing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["space"].waitForExistence(timeout: 2), "Space key should remain visible while analyzing")
        XCTAssertTrue(app.buttons["q"].waitForExistence(timeout: 2) || app.buttons["w"].waitForExistence(timeout: 2), "Production analyzing state should keep letter keys visible")
        attachScreenshot(from: app, named: "production-keyboard-state-analyzing")
        XCTAssertFalse(app.staticTexts["Full Access required"].exists)
        XCTAssertFalse(app.staticTexts["Analysis failed"].exists)
        XCTAssertFalse(app.otherElements["keyboard_analyzing_panel"].exists, "Analyzing must not use a blocking fake panel")
    }

    func testProductionKeyboardAnalysisFailedStateScreenshotRoute() throws {
        let app = launchProductionKeyboardStateApp("analysisFailed")

        XCTAssertTrue(app.otherElements["production_keyboard_state_host_analysisFailed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Open Keyboard AI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Analysis failed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["analysis_back_to_typing"].waitForExistence(timeout: 2) || app.buttons["Back to Typing"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["analysis_retry"].waitForExistence(timeout: 2) || app.buttons["Retry"].waitForExistence(timeout: 2))
        attachScreenshot(from: app, named: "production-keyboard-state-analysis-failed")
        XCTAssertFalse(app.staticTexts["Full Access required"].exists)
    }

    func testRealKeyboardExtensionGrammarlyCorrectionDetailScreenshotOrExplicitBlocker() throws {
        let app = launchKeyboardHostApp(extraArguments: ["--keyboard-suggestion-state=correctionDetail"])
        let input = focusKeyboardHostInput(in: app)
        let keyboardApp = XCUIApplication()

        guard switchToOpenKeyboardIfPossible(
            keyboardApp: keyboardApp,
            hostInput: input,
            successCheck: { self.grammarlyCorrectionDetailIsVisible(in: keyboardApp) }
        ) else {
            attachScreenshot(from: app, named: "acceptance-ui-test-grammarly-detail-blocked-host")
            attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-grammarly-detail-blocked-keyboard")
            XCTFail("Real Open Keyboard extension detail could not be detected by XCUITest after bounded attempts. Inspect attached screenshots for simulator keyboard-switcher/accessibility blocker evidence; do not use Preview Lab/direct preview-route screenshots as acceptance proof.")
            return
        }

        attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-grammarly-detail-real-extension")
        XCTAssertTrue(grammarlyCorrectionDetailIsVisible(in: keyboardApp), "Expected real extension correction detail panel")
        XCTAssertTrue(keyboardApp.staticTexts["Subject-verb agreement"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.staticTexts["has"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.staticTexts["have"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.staticTexts["Use “have” because the subject is plural."].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.buttons["correction_apply"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.buttons["correction_dismiss"].waitForExistence(timeout: 2))
        attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-grammarly-detail-real-extension")
    }

    func testRealKeyboardExtensionReadyStateScreenshotOrExplicitBlocker() throws {
        let app = launchKeyboardHostApp(extraArguments: ["--keyboard-suggestion-state=ready"])
        let input = focusKeyboardHostInput(in: app)
        let keyboardApp = XCUIApplication()

        guard switchToOpenKeyboardIfPossible(
            keyboardApp: keyboardApp,
            hostInput: input,
            successCheck: { self.realKeyboardReadyPolishIsVisible(in: keyboardApp) }
        ) else {
            attachScreenshot(from: app, named: "acceptance-ui-test-keyboard-ready-blocked-host")
            attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-keyboard-ready-blocked-keyboard")
            XCTFail("Real Open Keyboard extension did not reach ready keyboard controls. This is an explicit acceptance blocker; do not use Preview Lab/direct preview-route screenshots as fallback proof.")
            return
        }

        XCTAssertTrue(realKeyboardReadyPolishIsVisible(in: keyboardApp), "Ready real extension must show QWERTY keys plus visible adaptive globe controls and no dictation/mic key")
        XCTAssertTrue(keyboardApp.buttons["keyboard_openkeyboard_icon"].waitForExistence(timeout: 2) || keyboardApp.images["keyboard_openkeyboard_icon"].waitForExistence(timeout: 2))
        attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-keyboard-ready-real-extension")
    }

    func testRealKeyboardExtensionSuggestionStateScreenshotOrExplicitBlocker() throws {
        let app = launchKeyboardHostApp(extraArguments: ["--keyboard-suggestion-state=correctionCard"])
        let input = focusKeyboardHostInput(in: app)
        let keyboardApp = XCUIApplication()

        guard switchToOpenKeyboardIfPossible(keyboardApp: keyboardApp, hostInput: input) else {
            attachScreenshot(from: app, named: "acceptance-ui-test-keyboard-suggestion-blocked-host")
            attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-keyboard-suggestion-blocked-keyboard")
            XCTFail("Real Open Keyboard extension did not appear for seeded suggestion screenshot. Smallest next diagnostic: run this named test on the host, capture the keyboard switcher state, and verify the Open Keyboard extension is installed/enabled for the simulator.")
            return
        }

        XCTAssertTrue(keyboardApp.otherElements["keyboard_compact_suggestion_strip"].waitForExistence(timeout: 5) || keyboardApp.staticTexts["Correct capitalization:"].waitForExistence(timeout: 5))
        attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-keyboard-suggestion-real-extension")
    }

    func testRealKeyboardExtensionLogoActionMenuScreenshotOrExplicitBlocker() throws {
        let app = launchKeyboardHostApp(extraArguments: ["--keyboard-initial-panel=actions"])
        let input = focusKeyboardHostInput(in: app)
        let keyboardApp = XCUIApplication()

        guard switchToOpenKeyboardIfPossible(keyboardApp: keyboardApp, hostInput: input) else {
            attachScreenshot(from: app, named: "acceptance-ui-test-logo-menu-blocked-host")
            attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-logo-menu-blocked-keyboard")
            XCTFail("Real Open Keyboard extension did not appear for logo/action menu screenshot. Preview Lab/direct preview-route fallback is intentionally forbidden for acceptance.")
            return
        }

        attachKeyboardExtensionConfigProbe(named: "keyboard-extension-config-probe-before-sparkle")
        attachKeyboardExtensionUISurfaceConfigProbe(from: keyboardApp, named: "keyboard-ui-surface-config-probe-before-sparkle")
        let sparkle = keyboardApp.buttons["ai_sparkle_action"]
        guard sparkle.waitForExistence(timeout: 5) else {
            attachKeyboardExtensionConfigProbe(named: "keyboard-extension-config-probe-sparkle-missing")
            attachKeyboardExtensionUISurfaceConfigProbe(from: keyboardApp, named: "keyboard-ui-surface-config-probe-sparkle-missing")
            attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-logo-menu-config-probe-blocked-keyboard")
            XCTFail("Expected real extension sparkle action to be available. See keyboard-extension-config-probe-sparkle-missing attachment for sanitized extension config state.")
            return
        }
        sparkle.tap()
        guard keyboardApp.otherElements["ai_action_panel"].waitForExistence(timeout: 5) || keyboardApp.buttons["ai_action_fixGrammar"].waitForExistence(timeout: 5) else {
            attachKeyboardExtensionConfigProbe(named: "keyboard-extension-config-probe-action-panel-missing")
            attachKeyboardExtensionUISurfaceConfigProbe(from: keyboardApp, named: "keyboard-ui-surface-config-probe-action-panel-missing")
            XCTFail("Expected real extension action panel after tapping sparkle. See sanitized config probe attachment.")
            return
        }
        attachKeyboardExtensionConfigProbe(named: "keyboard-extension-config-probe-action-menu-visible")
        attachKeyboardExtensionUISurfaceConfigProbe(from: keyboardApp, named: "keyboard-ui-surface-config-probe-action-menu-visible")
        attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-logo-action-menu-real-extension")
    }


    func testRealKeyboardLogoAnalyzingStateKeepsKeyboardUsableOrExplicitBlocker() throws {
        let app = launchKeyboardHostApp(extraArguments: ["--keyboard-suggestion-state=analyzing"])
        let input = focusKeyboardHostInput(in: app)
        let keyboardApp = XCUIApplication()

        guard switchToOpenKeyboardIfPossible(keyboardApp: keyboardApp, hostInput: input) else {
            attachScreenshot(from: app, named: "acceptance-ui-test-logo-analyzing-blocked-host")
            attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-logo-analyzing-blocked-keyboard")
            XCTFail("Real Open Keyboard extension did not appear for logo analyzing screenshot. Do not use Preview Lab/direct preview-route fallback as acceptance proof.")
            return
        }

        XCTAssertTrue(keyboardApp.staticTexts["Analyzing"].waitForExistence(timeout: 5) || keyboardApp.staticTexts["Analyzing your text..."].waitForExistence(timeout: 5))
        XCTAssertFalse(keyboardApp.otherElements["keyboard_analyzing_panel"].exists, "Analyzing must not replace the usable keyboard with a blocking panel")
        XCTAssertTrue(keyboardApp.otherElements["keyboard_row_qwerty"].waitForExistence(timeout: 5), "QWERTY row should remain visible/usable while analyzing")
        XCTAssertTrue(keyboardApp.buttons["keyboard_key_space"].waitForExistence(timeout: 2), "Space key should remain visible/usable while analyzing")
        XCTAssertFalse(keyboardApp.otherElements["ai_action_panel"].exists)
        attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-logo-analyzing-usable-real-extension")
    }


    func testRealKeyboardAnalysisFailedPanelFitsOrExplicitBlocker() throws {
        let app = launchKeyboardHostApp(extraArguments: ["--keyboard-suggestion-state=analysisFailed"])
        let input = focusKeyboardHostInput(in: app)
        let keyboardApp = XCUIApplication()

        guard switchToOpenKeyboardIfPossible(keyboardApp: keyboardApp, hostInput: input) else {
            attachScreenshot(from: app, named: "acceptance-ui-test-analysis-failed-blocked-host")
            attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-analysis-failed-blocked-keyboard")
            XCTFail("Real Open Keyboard extension did not appear for analysis-failed screenshot. Do not use Preview Lab/direct preview-route fallback as acceptance proof.")
            return
        }

        XCTAssertTrue(keyboardApp.otherElements["keyboard_analysis_failed_panel"].waitForExistence(timeout: 5))
        XCTAssertTrue(keyboardApp.staticTexts["Analysis failed"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.staticTexts["Analysis failed. The selected model did not respond."].waitForExistence(timeout: 2) || keyboardApp.staticTexts["The selected model did not respond"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.buttons["analysis_back_to_typing"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.buttons["analysis_retry"].waitForExistence(timeout: 2))
        XCTAssertFalse(keyboardApp.staticTexts["Keyboard Preview Lab"].exists)
        attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-analysis-failed-real-extension")
    }

    func testRealKeyboardLogoAllGoodPanelScreenshotOrExplicitBlocker() throws {
        let app = launchKeyboardHostApp(extraArguments: ["--keyboard-suggestion-state=allGood"])
        let input = focusKeyboardHostInput(in: app)
        let keyboardApp = XCUIApplication()

        guard switchToOpenKeyboardIfPossible(keyboardApp: keyboardApp, hostInput: input) else {
            attachScreenshot(from: app, named: "acceptance-ui-test-logo-all-good-blocked-host")
            attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-logo-all-good-blocked-keyboard")
            XCTFail("Real Open Keyboard extension did not appear for logo all-good screenshot. Do not use Preview Lab/direct preview-route fallback as acceptance proof.")
            return
        }

        XCTAssertTrue(keyboardApp.otherElements["keyboard_all_good_panel"].waitForExistence(timeout: 5))
        XCTAssertTrue(keyboardApp.staticTexts["All Good"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.buttons["back_to_typing"].waitForExistence(timeout: 2))
        XCTAssertFalse(keyboardApp.otherElements["ai_action_panel"].exists)
        attachScreenshot(from: keyboardApp, named: "acceptance-ui-test-logo-all-good-real-extension")
    }

    private enum Appearance {
        case light
        case dark
    }

    private func launchHomeApp(appearance: Appearance) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--skip-onboarding", "--clear-gateway-config"]
        switch appearance {
        case .light:
            app.launchArguments += ["-AppleInterfaceStyle", "Light"]
        case .dark:
            app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        }
        app.launch()
        return app
    }


    private func launchConfiguredHomeApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--seed-gateway-config", "--skip-onboarding"] + extraArguments
        app.launchEnvironment["OPEN_KEYBOARD_TEST_GATEWAY_URL"] = Self.placeholderGatewayURL
        app.launchEnvironment["OPEN_KEYBOARD_TEST_API_KEY"] = Self.placeholderAPIKey
        app.launchEnvironment["OPEN_KEYBOARD_TEST_MODEL"] = Self.placeholderModel
        app.launch()
        return app
    }

    private func launchConfiguredHomeAppWithoutSkipOnboarding(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--seed-gateway-config"] + extraArguments
        app.launchEnvironment["OPEN_KEYBOARD_TEST_GATEWAY_URL"] = Self.placeholderGatewayURL
        app.launchEnvironment["OPEN_KEYBOARD_TEST_API_KEY"] = Self.placeholderAPIKey
        app.launchEnvironment["OPEN_KEYBOARD_TEST_MODEL"] = Self.placeholderModel
        app.launch()
        return app
    }


    private func launchProductionKeyboardStateApp(_ state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--skip-onboarding",
            "--production-keyboard-state=\(state)",
            "--keyboard-suggestion-state=\(state)",
        ]
        app.launch()
        return app
    }

    private func launchKeyboardHostApp(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--seed-gateway-config",
            "--keyboard-host-test"
        ] + extraArguments
        app.launchEnvironment["OPEN_KEYBOARD_TEST_GATEWAY_URL"] = Self.placeholderGatewayURL
        app.launchEnvironment["OPEN_KEYBOARD_TEST_API_KEY"] = Self.placeholderAPIKey
        app.launchEnvironment["OPEN_KEYBOARD_TEST_MODEL"] = Self.placeholderModel
        app.launch()
        return app
    }

    private func focusKeyboardHostInput(in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))
        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was not available for keyboard screenshot verification")
        tapCenter(of: input)
        dismissKnownKeyboardDialogs(in: XCUIApplication(bundleIdentifier: "com.apple.springboard"))
        return input
    }

    private func switchToOpenKeyboardIfPossible(keyboardApp: XCUIApplication, hostInput: XCUIElement, successCheck: (() -> Bool)? = nil) -> Bool {
        if realOpenKeyboardIsVisible(in: keyboardApp, successCheck: successCheck) {
            return true
        }

        for _ in 0..<2 {
            dismissKnownKeyboardDialogs(in: XCUIApplication(bundleIdentifier: "com.apple.springboard"))

            if selectOpenKeyboardFromVisibleSwitcher(in: keyboardApp, successCheck: successCheck) {
                return true
            }

            if switchFromObservedEmojiKeyboardIfNeeded(in: keyboardApp, hostInput: hostInput, successCheck: successCheck) {
                return true
            }

            let switcherCandidates = [
                keyboardApp.buttons["Next keyboard"],
                keyboardApp.buttons["Emoji"],
                keyboardApp.buttons["🌐"],
                keyboardApp.keys["Next keyboard"],
                keyboardApp.keys["Emoji"],
                keyboardApp.keys["🌐"]
            ]

            for candidateQuery in switcherCandidates {
                let candidate = candidateQuery.firstMatch
                guard candidate.waitForExistence(timeout: 1) else { continue }

                tapCenter(of: candidate)
                if waitForRealOpenKeyboard(in: keyboardApp, hostInput: hostInput, successCheck: successCheck) {
                    return true
                }
                if selectOpenKeyboardFromVisibleSwitcher(in: keyboardApp, successCheck: successCheck) {
                    return true
                }

                candidate.press(forDuration: 1.0)
                if selectOpenKeyboardFromVisibleSwitcher(in: keyboardApp, successCheck: successCheck) {
                    return true
                }
            }

            tapCenter(of: hostInput)
            if waitForRealOpenKeyboard(in: keyboardApp, hostInput: hostInput, successCheck: successCheck) {
                return true
            }
        }

        return realOpenKeyboardIsVisible(in: keyboardApp, successCheck: successCheck)
    }

    private func switchFromObservedEmojiKeyboardIfNeeded(in keyboardApp: XCUIApplication, hostInput: XCUIElement, successCheck: (() -> Bool)?) -> Bool {
        let emojiSearch = keyboardApp.textFields["Search Emoji"]
        let emojiPreview = keyboardApp.otherElements["UIKeyboardLayoutStar Preview"]
        let nextKeyboard = keyboardApp.buttons["Next keyboard"].firstMatch

        guard (emojiSearch.exists || emojiPreview.exists), nextKeyboard.waitForExistence(timeout: 1) else {
            return false
        }

        let nextValue = nextKeyboard.value as? String
        guard nextValue?.localizedCaseInsensitiveContains("Open Keyboard") == true else {
            return false
        }

        // iOS 26 exposes the Emoji keyboard's bottom-left switcher as "Next keyboard"
        // with value "Open Keyboard". A normal element tap can be swallowed by the
        // Emoji keyboard; tapping the concrete lower-left key center and then
        // re-focusing the host input gives the custom extension time to attach.
        tapCenter(of: nextKeyboard)
        if waitForRealOpenKeyboard(in: keyboardApp, hostInput: hostInput, successCheck: successCheck) {
            return true
        }

        nextKeyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return waitForRealOpenKeyboard(in: keyboardApp, hostInput: hostInput, successCheck: successCheck)
    }

    private func selectOpenKeyboardFromVisibleSwitcher(in keyboardApp: XCUIApplication, successCheck: (() -> Bool)?) -> Bool {
        let openKeyboardPredicate = NSPredicate(format: "label BEGINSWITH[c] %@", "Open Keyboard")
        let switcherItems = [
            keyboardApp.buttons.matching(openKeyboardPredicate).firstMatch,
            keyboardApp.cells.matching(openKeyboardPredicate).firstMatch,
            keyboardApp.staticTexts.matching(openKeyboardPredicate).firstMatch
        ]

        for item in switcherItems where item.waitForExistence(timeout: 1) {
            tapCenter(of: item)
            if waitForRealOpenKeyboard(in: keyboardApp, hostInput: nil, successCheck: successCheck) {
                return true
            }
        }

        return false
    }

    private func waitForRealOpenKeyboard(in keyboardApp: XCUIApplication, hostInput: XCUIElement?, successCheck: (() -> Bool)?) -> Bool {
        for _ in 0..<5 {
            if realOpenKeyboardIsVisible(in: keyboardApp, successCheck: successCheck) {
                return true
            }
            if let hostInput {
                tapCenter(of: hostInput)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        return false
    }

    private func realOpenKeyboardIsVisible(in keyboardApp: XCUIApplication, successCheck: (() -> Bool)?) -> Bool {
        if successCheck?() == true {
            return true
        }

        let openKeyboardControlsVisible = keyboardApp.buttons["ai_action_fixGrammar"].waitForExistence(timeout: 0.2)
            || keyboardApp.buttons["ai_sparkle_action"].waitForExistence(timeout: 0.2)
            || keyboardApp.otherElements["ai_toolbar"].waitForExistence(timeout: 0.2)
            || keyboardApp.buttons["ai_toolbar"].waitForExistence(timeout: 0.2)
            || keyboardApp.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Open Keyboard AI actions")).firstMatch.waitForExistence(timeout: 0.2)
            || keyboardApp.buttons["keyboard_openkeyboard_icon"].waitForExistence(timeout: 0.2)
            || keyboardApp.images["keyboard_openkeyboard_icon"].waitForExistence(timeout: 0.2)
            || keyboardApp.otherElements["keyboard_row_qwerty"].waitForExistence(timeout: 0.2)
            || keyboardApp.buttons["keyboard_key_space"].waitForExistence(timeout: 0.2)

        guard openKeyboardControlsVisible else {
            return false
        }

        return successCheck == nil || successCheck?() == true
    }


    private func realKeyboardReadyPolishIsVisible(in keyboardApp: XCUIApplication) -> Bool {
        recoverRealKeyboardToTypingIfNeeded(in: keyboardApp)

        let hasSpace = keyboardApp.buttons["keyboard_key_space"].waitForExistence(timeout: 1)
            || keyboardApp.buttons["space"].waitForExistence(timeout: 1)
        let hasLetterRow = keyboardApp.otherElements["keyboard_row_qwerty"].waitForExistence(timeout: 1)
            || keyboardApp.buttons["q"].waitForExistence(timeout: 1)
            || keyboardApp.buttons["w"].waitForExistence(timeout: 1)
        let hasGlobe = keyboardApp.buttons["keyboard_key_next_keyboard"].waitForExistence(timeout: 1)
            || keyboardApp.buttons["Next Keyboard"].waitForExistence(timeout: 1)
        let hasMic = keyboardApp.buttons["keyboard_key_dictation_unavailable"].waitForExistence(timeout: 1)
            || keyboardApp.buttons["Dictation unavailable"].waitForExistence(timeout: 1)
        let hasBlockingPanel = keyboardApp.otherElements["keyboard_analysis_failed_panel"].exists
            || keyboardApp.otherElements["keyboard_all_good_panel"].exists
            || keyboardApp.otherElements["ai_action_panel"].exists

        return hasSpace && hasLetterRow && hasGlobe && !hasMic && !hasBlockingPanel
    }

    private func recoverRealKeyboardToTypingIfNeeded(in keyboardApp: XCUIApplication) {
        let recoveryButtons = [
            keyboardApp.buttons["analysis_back_to_typing"],
            keyboardApp.buttons["back_to_typing"],
            keyboardApp.buttons["Back to Typing"]
        ]

        for button in recoveryButtons {
            if button.waitForExistence(timeout: 1) {
                button.tap()
                break
            }
        }
    }

    private func grammarlyCorrectionDetailIsVisible(in keyboardApp: XCUIApplication) -> Bool {
        let hasTitle = keyboardApp.staticTexts["Subject-verb agreement"].waitForExistence(timeout: 1)
        let hasOriginal = keyboardApp.staticTexts["has"].waitForExistence(timeout: 1)
        let hasReplacement = keyboardApp.staticTexts["have"].waitForExistence(timeout: 1)
        let hasApply = keyboardApp.buttons["correction_apply"].waitForExistence(timeout: 1) || keyboardApp.buttons["Apply"].waitForExistence(timeout: 1)
        let hasDismiss = keyboardApp.buttons["correction_dismiss"].waitForExistence(timeout: 1) || keyboardApp.buttons["Dismiss"].waitForExistence(timeout: 1)
        return hasTitle && hasOriginal && hasReplacement && hasApply && hasDismiss
    }

    private func dismissKnownKeyboardDialogs(in springboard: XCUIApplication) {
        let labels = [
            "Continue",
            "Not Now",
            "Don't Allow",
            "Don’t Allow",
            "Cancel",
            "OK",
            "Done"
        ]

        for label in labels {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 1) {
                button.tap()
            }
        }
    }

    private func tapCenter(of element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }


    private func attachKeyboardExtensionUISurfaceConfigProbe(from app: XCUIApplication, named name: String) {
        let toolbarButtons = app.buttons.matching(identifier: "ai_toolbar")
        let toolbarStatusButtons = app.buttons.matching(identifier: "ai_toolbar_status_action")
        let toolbarOthers = app.otherElements.matching(identifier: "ai_toolbar")
        let toolbarStatusOthers = app.otherElements.matching(identifier: "ai_toolbar_status_action")

        var lines: [String] = []
        appendProbeElements(toolbarStatusButtons, title: "buttons.ai_toolbar_status_action", to: &lines)
        appendProbeElements(toolbarButtons, title: "buttons.ai_toolbar", to: &lines)
        appendProbeElements(toolbarStatusOthers, title: "otherElements.ai_toolbar_status_action", to: &lines)
        appendProbeElements(toolbarOthers, title: "otherElements.ai_toolbar", to: &lines)

        if lines.isEmpty {
            lines.append("exists=false")
        }

        let attachment = XCTAttachment(string: lines.joined(separator: "\n---\n"))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func appendProbeElements(_ query: XCUIElementQuery, title: String, to lines: inout [String]) {
        let count = query.count
        guard count > 0 else { return }
        for index in 0..<count {
            lines.append(probeDescription(for: query.element(boundBy: index), index: index, group: title))
        }
    }

    private func probeDescription(for element: XCUIElement, index: Int, group: String) -> String {
        let value = element.value as? String
        return "exists=true\ngroup=\(group)\nindex=\(index)\nidentifier=\(element.identifier)\nlabel=\(element.label)\nvalue=\(value ?? "<nil>")\ndebugDescription=\(element.debugDescription)"
    }

    private func attachKeyboardExtensionConfigProbe(named name: String) {
        let defaults = UserDefaults(suiteName: Self.appGroupIdentifier)
        let probe = defaults?.string(forKey: "keyboardExtension.configProbe") ?? "keyboardExtension.configProbe=<missing>"
        let attachment = XCTAttachment(string: probe)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachScreenshot(from app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
