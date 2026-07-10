import XCTest

final class KeyboardExtensionConfiguredUITests: XCTestCase {
    private static let mockGatewayURL = "https://mock.local.invalid"
    private static let mockAPIKey = "mock-ui-test-key"
    private static let mockModel = "mock-ui-test-model"

    func testContainingAppSeedsSharedGatewayConfigForKeyboardExtension() {
        let app = configuredContainingApp()
        app.launch()

        let checkingGateway = app.staticTexts["Checking gateway…"].waitForExistence(timeout: 2)
        let gatewayNeedsAttention = app.staticTexts["Gateway needs attention"].waitForExistence(timeout: 12)
        XCTAssertTrue(checkingGateway || gatewayNeedsAttention)
        XCTAssertFalse(app.staticTexts["Gateway Ready"].exists)
        XCTAssertTrue(app.staticTexts[Self.mockModel].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["playground_entry_button"].exists, "Unvalidated gateway config must not expose Playground as usable.")
    }


    func testPlaygroundDirectRouteFocusesInput() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--playground-direct"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Playground"].waitForExistence(timeout: 5), "Playground navigation title should be visible after tapping entry")
        XCTAssertEqual(app.staticTexts.matching(identifier: "Playground").count, 1, "Playground should only render one visible title")
        let input = app.textViews["playground_text_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Playground text input should be available")
        let initialValue = try XCTUnwrap(input.value as? String)
        XCTAssertTrue(
            NetworkManager.correctionSmokeTestPhrases.contains { initialValue.contains($0) },
            "Playground input should start with a curated typo sample phrase"
        )
        input.tap()
        input.typeText(" hello")
        XCTAssertTrue((input.value as? String)?.contains("hello") == true, "Playground input should accept typed text")
    }

    func testRealKeyboardExtensionShowsConfiguredAIControlsWhenSharedConfigSeeded() throws {
        let sourceText = "All of these are no bulb in the universe."
        let encodedSource = sourceText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceText
        let app = configuredContainingApp(extraArguments: [
            "--keyboard-host-test",
            "--keyboard-host-autofocus",
            "--keyboard-host-prefer-openkeyboard",
            "--keyboard-host-text=\(encodedSource)"
        ])
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was not available for keyboard verification")
        input.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        dismissKnownKeyboardDialogs(in: springboard)

        let keyboardApp = XCUIApplication()
        var foundOpenKeyboard = keyboardApp.buttons["ai_sparkle_action"].waitForExistence(timeout: 2)

        if !foundOpenKeyboard {
            for _ in 0..<8 {
                dismissKnownKeyboardDialogs(in: springboard)
                switchToOpenKeyboardIfPossible(keyboardApp: keyboardApp, hostInput: input)

                if keyboardApp.buttons["ai_sparkle_action"].waitForExistence(timeout: 2) {
                    foundOpenKeyboard = true
                    break
                }
            }
        }

        if !foundOpenKeyboard {
            attachKeyboardConfigVisibilityDiagnostic(named: "real-keyboard-config-visibility-probe")
        }
        XCTAssertTrue(foundOpenKeyboard, "Open Keyboard extension did not appear or the AI menu trigger was missing; see redacted config visibility diagnostic attachment")
        XCTAssertFalse(keyboardApp.staticTexts["Gateway not configured"].exists)
        XCTAssertFalse(keyboardApp.staticTexts["Pair gateway in app"].exists)
        XCTAssertFalse(keyboardApp.staticTexts["Full Access required"].exists)
        XCTAssertTrue(
            waitForEnabledLeftStatusLane(keyboardApp: keyboardApp, timeout: 2),
            "Left correction/status lane should stay enabled while the sparkle action is available"
        )
        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].isEnabled)
        keyboardApp.buttons["ai_sparkle_action"].tap()
        XCTAssertTrue(keyboardApp.otherElements["ai_action_panel"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.staticTexts["ai_action_loading_text"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.buttons["ai_action_improve"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.buttons["ai_action_rewrite"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.buttons["ai_action_summarize"].waitForExistence(timeout: 2))

        let backToKeyboard = keyboardApp.buttons["back_to_keyboard"]
        XCTAssertTrue(backToKeyboard.waitForExistence(timeout: 2))
        backToKeyboard.tap()
        XCTAssertTrue(
            waitForEnabledLeftStatusLane(keyboardApp: keyboardApp, timeout: 5),
            "Left correction/status lane was not enabled after returning from the sparkle action panel"
        )
    }

    func testRealKeyboardEmptyInputShowsNoStaleCorrectionsScreenshotWhenExplicitlyRequested() throws {
        let app = configuredContainingApp(extraArguments: [
            "--keyboard-host-test",
            "--keyboard-host-autofocus",
            "--keyboard-host-prefer-openkeyboard"
        ])
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was not available for empty-input verification")
        XCTAssertTrue(((input.value as? String) ?? "").isEmpty, "Host input must start empty for stale correction proof")
        tapCenter(of: input)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keyboardApp = XCUIApplication()
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear"
        )

        XCTAssertTrue(keyboardApp.buttons["keyboard_openkeyboard_icon"].waitForExistence(timeout: 5))
        XCTAssertFalse(keyboardApp.buttons["keyboard_issue_count_badge"].exists)
        XCTAssertFalse(keyboardApp.otherElements["ai_correction_panel"].exists)
        XCTAssertFalse(keyboardApp.otherElements["correction_complete_panel"].exists)

        try captureRealKeyboardStep("empty-input-no-stale-corrections")
    }

    func testSeededRealKeyboardCorrectionCarouselCanNavigateCards() throws {
        let seededCorrectionText = "i has a apple and ths sentence"
        let app = configuredContainingApp(extraArguments: [
            "--keyboard-host-test",
            "--keyboard-host-autofocus",
            "--keyboard-host-prefer-openkeyboard",
            "--keyboard-suggestion-state=correctionCarousel",
            "--keyboard-initial-panel=correctionDetail",
            "--keyboard-host-text=\(seededCorrectionText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? seededCorrectionText)"
        ])
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was not available for seeded carousel verification")
        XCTAssertTrue((input.value as? String)?.contains(seededCorrectionText) == true)
        input.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        dismissKnownKeyboardDialogs(in: springboard)

        let keyboardApp = XCUIApplication()
        for _ in 0..<8 where !keyboardApp.buttons["keyboard_correction_next"].exists {
            dismissKnownKeyboardDialogs(in: springboard)
            switchToOpenKeyboardIfPossible(keyboardApp: keyboardApp, hostInput: input)
        }

        XCTAssertTrue(keyboardApp.buttons["keyboard_correction_next"].waitForExistence(timeout: 5), "Seeded correction carousel did not appear in the real keyboard extension")
        XCTAssertTrue(keyboardApp.staticTexts["keyboard_correction_progress"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.staticTexts["keyboard_correction_progress"].label.contains("1 of 3"))
        XCTAssertEqual(keyboardApp.staticTexts["ai_correction_replacement"].label, "have")

        keyboardApp.buttons["keyboard_correction_next"].tap()

        XCTAssertTrue(keyboardApp.staticTexts["keyboard_correction_progress"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.staticTexts["keyboard_correction_progress"].label.contains("2 of 3"))
        XCTAssertEqual(keyboardApp.staticTexts["ai_correction_replacement"].label, "an apple")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "seeded-real-keyboard-correction-carousel"
        attachment.lifetime = .keepAlways
        add(attachment)
        try captureRealKeyboardStep("04-real-keyboard-correction-detail")
    }

    func testRealKeyboardImproveReplacesTextWhenGatewayConfigured() throws {
        let app = configuredContainingApp(extraArguments: ["--keyboard-host-test", "--keyboard-host-autofocus", "--keyboard-host-prefer-openkeyboard"], requiresInjectedGatewayCredentials: true)
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was not available for keyboard action verification")
        tapCenter(of: input)

        let keyboardApp = XCUIApplication()
        for _ in 0..<8 where !keyboardApp.buttons["ai_sparkle_action"].exists {
            switchToOpenKeyboardIfPossible(keyboardApp: keyboardApp, hostInput: input)
        }

        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].waitForExistence(timeout: 5), "Open Keyboard AI trigger was not available")
        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].isEnabled)

        tapCenter(of: input)
        typeUsingOpenKeyboard("i has a apple", keyboardApp: keyboardApp)
        let typed = NSPredicate(format: "value CONTAINS[c] %@", "i has a apple")
        expectation(for: typed, evaluatedWith: input)
        waitForExpectations(timeout: 10)

        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].waitForExistence(timeout: 5), "Open Keyboard AI trigger disappeared after typing")
        keyboardApp.buttons["ai_sparkle_action"].tap()
        let liveImprove = keyboardApp.buttons["ai_action_improve"]
        XCTAssertTrue(liveImprove.waitForExistence(timeout: 5), "Improve disappeared after typing")
        XCTAssertTrue(keyboardApp.staticTexts["ai_action_result_text"].waitForExistence(timeout: 60), "Generated improvement text did not appear in the top-right sparkle panel")
        let applyAction = keyboardApp.buttons["ai_action_apply"]
        XCTAssertTrue(applyAction.waitForExistence(timeout: 5), "Accept was missing from the AI action panel")
        XCTAssertTrue(applyAction.isEnabled)
        applyAction.tap()

        let improved = NSPredicate(format: "NOT (value CONTAINS[c] %@)", "i has a apple")
        expectation(for: improved, evaluatedWith: input)
        waitForExpectations(timeout: 10)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "live-gateway-real-keyboard-improved-text"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRealKeyboardAutomaticAnalysisWorkflowScreenshotsWhenExplicitlyRequested() throws {
        let screenshotDirectory = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_REAL_SCREENSHOT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !screenshotDirectory.isEmpty else {
            throw XCTSkip("Set OPEN_KEYBOARD_REAL_SCREENSHOT_DIR to opt into real keyboard workflow screenshots.")
        }

        let defaultPhrase = "i has wrote ths sentance becaus this grammer checker should catches many mistake before i sends it"
        let phrase = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_REAL_SCREENSHOT_PHRASE"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? defaultPhrase

        let hostArguments = ["--keyboard-host-test", "--keyboard-host-autofocus", "--keyboard-host-prefer-openkeyboard"]
        let environment = ProcessInfo.processInfo.environment
        let hasInjectedGatewayCredentials = [
            environment["OPEN_KEYBOARD_TEST_GATEWAY_URL"],
            environment["OPEN_KEYBOARD_TEST_API_KEY"],
            environment["OPEN_KEYBOARD_TEST_MODEL"]
        ].allSatisfy { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }

        let app: XCUIApplication
        if hasInjectedGatewayCredentials {
            app = configuredContainingApp(
                extraArguments: hostArguments,
                requiresInjectedGatewayCredentials: true
            )
        } else {
            try skipUnlessExistingSimulatorGatewayConfigIsPresent()
            app = existingConfiguredContainingApp(extraArguments: hostArguments)
        }
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was not available for keyboard workflow verification")
        tapCenter(of: input)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keyboardApp = XCUIApplication()
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear"
        )
        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].isEnabled, "Open Keyboard AI trigger was not enabled")

        try captureRealKeyboardStep("01-real-keyboard-ready")

        typeUsingOpenKeyboard(phrase, keyboardApp: keyboardApp)
        let typed = NSPredicate(format: "value CONTAINS[c] %@", phrase)
        expectation(for: typed, evaluatedWith: input)
        waitForExpectations(timeout: 20)

        try captureRealKeyboardStep("02-real-keyboard-typed-text")

        let sawIssueCount = waitForIssueCountBadge(keyboardApp: keyboardApp, timeout: 90)
        try captureRealKeyboardStep("03-real-keyboard-issue-count")
        XCTAssertTrue(sawIssueCount, "Automatic grammar analysis did not expose a writing suggestion count")
        guard sawIssueCount else { return }

        keyboardApp.buttons["keyboard_issue_count_badge"].tap()
        XCTAssertTrue(
            keyboardApp.otherElements["ai_correction_panel"].waitForExistence(timeout: 10),
            "Tapping the issue count did not open the correction carousel"
        )
        try captureRealKeyboardStep("04-real-keyboard-carousel-first-card")

        let nextCorrection = keyboardApp.buttons["keyboard_correction_next"]
        if nextCorrection.exists, nextCorrection.isEnabled {
            nextCorrection.tap()
            XCTAssertTrue(keyboardApp.otherElements["ai_correction_panel"].waitForExistence(timeout: 5))
            try captureRealKeyboardStep("05-real-keyboard-carousel-next-card")
        }

        let accept = keyboardApp.buttons["ai_correction_apply"]
        if accept.exists, accept.isEnabled {
            accept.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            try captureRealKeyboardStep("06-real-keyboard-after-one-accept")
        }
    }

    func testRealKeyboardSparkleImproveModeScreenshotWhenExplicitlyRequested() throws {
        let screenshotDirectory = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_REAL_SCREENSHOT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !screenshotDirectory.isEmpty else {
            throw XCTSkip("Set OPEN_KEYBOARD_REAL_SCREENSHOT_DIR to opt into real keyboard sparkle Improve screenshots.")
        }

        let sourceText = "All of these are no bulb in the universe."
        let encodedSource = sourceText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceText
        let app = configuredContainingApp(extraArguments: [
            "--keyboard-host-test",
            "--keyboard-host-autofocus",
            "--keyboard-host-prefer-openkeyboard",
            "--keyboard-host-text=\(encodedSource)"
        ])
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was not available for keyboard sparkle screenshots")
        tapCenter(of: input)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keyboardApp = XCUIApplication()
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear"
        )
        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].waitForExistence(timeout: 5))
        try captureRealKeyboardStep("01-real-keyboard-normal-keyboard")

        keyboardApp.buttons["ai_sparkle_action"].tap()
        XCTAssertTrue(keyboardApp.otherElements["ai_action_panel"].waitForExistence(timeout: 5))
        XCTAssertTrue(keyboardApp.staticTexts["ai_action_loading_text"].waitForExistence(timeout: 5))
        XCTAssertTrue(keyboardApp.buttons["back_to_keyboard"].waitForExistence(timeout: 5))
        XCTAssertTrue(keyboardApp.buttons["ai_action_rerun"].waitForExistence(timeout: 5))
        XCTAssertTrue(keyboardApp.buttons["ai_action_toggle_carousel"].waitForExistence(timeout: 5))
        XCTAssertTrue(keyboardApp.buttons["ai_action_copy"].waitForExistence(timeout: 5))
        XCTAssertTrue(keyboardApp.buttons["ai_action_apply"].waitForExistence(timeout: 5))
        try captureRealKeyboardStep("02-real-keyboard-sparkle-improve-mode")
    }

    func testRealKeyboardRewriteOptionsWorkflowScreenshotsWhenExplicitlyRequested() throws {
        let screenshotDirectory = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_REAL_SCREENSHOT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !screenshotDirectory.isEmpty else {
            throw XCTSkip("Set OPEN_KEYBOARD_REAL_SCREENSHOT_DIR to opt into real keyboard rewrite screenshots.")
        }

        let sourceText = "All of these are no bulb in the universe."
        let encodedSource = sourceText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceText
        let hostArguments = [
            "--keyboard-host-test",
            "--keyboard-host-autofocus",
            "--keyboard-host-prefer-openkeyboard",
            "--keyboard-host-text=\(encodedSource)"
        ]

        let app = configuredContainingApp(extraArguments: hostArguments)
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was not available for keyboard rewrite screenshots")
        tapCenter(of: input)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keyboardApp = XCUIApplication()
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear"
        )

        try captureRealKeyboardStep("01-real-keyboard-normal-keyboard")

        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForEnabledAITrigger(keyboardApp: keyboardApp, timeout: 10))
        keyboardApp.buttons["ai_sparkle_action"].tap()
        XCTAssertTrue(keyboardApp.buttons["ai_action_rewrite"].waitForExistence(timeout: 5))
        XCTAssertTrue(keyboardApp.staticTexts["ai_action_loading_text"].waitForExistence(timeout: 5))
        try captureRealKeyboardStep("02-real-keyboard-ai-action-screen")

        seedKeyboardExtensionDebugState(suggestionState: "rewriteOptions", initialPanel: "rewriteOptions")
        reopenHostInput(input)
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear for seeded rewrite options"
        )
        XCTAssertTrue(keyboardApp.buttons["ai_rewrite_option_1"].waitForExistence(timeout: 5))
        try captureRealKeyboardStep("03-real-keyboard-rewrite-options-carousel")

        let secondOption = keyboardApp.buttons["ai_rewrite_option_1"]
        XCTAssertTrue(secondOption.waitForExistence(timeout: 5))
        secondOption.tap()

        let apply = keyboardApp.buttons["ai_rewrite_apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        apply.tap()

        let rewritten = NSPredicate(format: "value CONTAINS[c] %@", "There are no bulbs anywhere in the universe.")
        expectation(for: rewritten, evaluatedWith: input)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(keyboardApp.staticTexts["Rewrite applied"].waitForExistence(timeout: 5))
        try captureRealKeyboardStep("04-real-keyboard-rewrite-applied")
    }

    func testRealKeyboardImproveReplacesTextWithExistingSimulatorGatewayConfig() throws {
        try skipUnlessExistingSimulatorGatewayConfigIsPresent()

        let app = existingConfiguredContainingApp(extraArguments: ["--keyboard-host-test", "--keyboard-host-autofocus", "--keyboard-host-prefer-openkeyboard"])
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was not available for existing gateway verification")
        tapCenter(of: input)

        let keyboardApp = XCUIApplication()
        for _ in 0..<8 where !keyboardApp.buttons["ai_sparkle_action"].exists {
            switchToOpenKeyboardIfPossible(keyboardApp: keyboardApp, hostInput: input)
        }

        if keyboardApp.buttons["Back to Typing"].waitForExistence(timeout: 1) {
            keyboardApp.buttons["Back to Typing"].tap()
        }

        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].waitForExistence(timeout: 5), "Open Keyboard AI trigger was not available with the existing simulator config")
        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].isEnabled)

        tapCenter(of: input)
        typeUsingOpenKeyboard("i has a apple", keyboardApp: keyboardApp)
        let typed = NSPredicate(format: "value CONTAINS[c] %@", "i has a apple")
        expectation(for: typed, evaluatedWith: input)
        waitForExpectations(timeout: 10)

        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].waitForExistence(timeout: 5), "Open Keyboard AI trigger disappeared after typing")
        keyboardApp.buttons["ai_sparkle_action"].tap()
        let liveImprove = keyboardApp.buttons["ai_action_improve"]
        XCTAssertTrue(liveImprove.waitForExistence(timeout: 5), "Improve disappeared after typing")
        XCTAssertTrue(keyboardApp.staticTexts["ai_action_result_text"].waitForExistence(timeout: 60), "Generated improvement text did not appear in the top-right sparkle panel")
        let applyAction = keyboardApp.buttons["ai_action_apply"]
        XCTAssertTrue(applyAction.waitForExistence(timeout: 5), "Accept was missing from the AI action panel")
        XCTAssertTrue(applyAction.isEnabled)
        applyAction.tap()

        let improved = NSPredicate(format: "NOT (value CONTAINS[c] %@)", "i has a apple")
        expectation(for: improved, evaluatedWith: input)
        waitForExpectations(timeout: 10)
    }

    private func skipUnlessExistingSimulatorGatewayConfigIsPresent() throws {
        guard let defaults = AppConfig.sharedDefaults() else {
            throw XCTSkip("App Group defaults are unavailable for existing simulator gateway verification.")
        }

        let gatewayURL = defaults.string(forKey: AppConfig.gatewayURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedModel = defaults.string(forKey: AppConfig.selectedModelKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let connectionError = AppConfig.gatewayConnectionError(from: defaults)
        guard defaults.bool(forKey: AppConfig.isConfiguredKey),
              !gatewayURL.isEmpty,
              !selectedModel.isEmpty,
              connectionError == nil else {
            throw XCTSkip("Existing simulator gateway config is not present or has a saved gateway error.")
        }

        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        defaults.removeObject(forKey: "keyboardExtension.composingBuffer")
        defaults.removeObject(forKey: "keyboardExtension.lastDebugEvent")
        defaults.removeObject(forKey: "keyboardExtension.debugEvents")
        defaults.synchronize()
    }

    private func attachKeyboardConfigVisibilityDiagnostic(named name: String) {
        guard let defaults = AppConfig.sharedDefaults() else {
            let attachment = XCTAttachment(string: "keyboard config visibility probe unavailable: shared App Group defaults unavailable")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            return
        }

        let lastEvent = defaults.string(forKey: "keyboardExtension.lastDebugEvent") ?? "missing"
        let events = defaults.string(forKey: "keyboardExtension.debugEvents") ?? "missing"
        let appSideDiagnostic = AppConfig.redactedVisibilityDiagnostic(from: defaults).redactedDescription
        let attachment = XCTAttachment(string: [
            "appSide=\(appSideDiagnostic)",
            "extensionLastEvent=\(lastEvent)",
            "extensionRecentEvents=\(events)"
        ].joined(separator: "\n"))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func seedKeyboardExtensionDebugState(suggestionState: String, initialPanel: String) {
        guard let defaults = AppConfig.sharedDefaults() else {
            XCTFail("App Group defaults were unavailable for keyboard debug state seeding")
            return
        }

        let seedID = UUID().uuidString
        let seededAt = Date().timeIntervalSince1970
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        defaults.set(suggestionState, forKey: "keyboardExtension.suggestionState")
        defaults.set(seedID, forKey: "keyboardExtension.suggestionStateSeedID")
        defaults.set(seededAt, forKey: "keyboardExtension.suggestionStateSeededAt")
        defaults.set(initialPanel, forKey: "keyboardExtension.initialPanelMode")
        defaults.set(seedID, forKey: "keyboardExtension.initialPanelModeSeedID")
        defaults.set(seededAt, forKey: "keyboardExtension.initialPanelModeSeededAt")
        defaults.synchronize()
    }

    private func reopenHostInput(_ input: XCUIElement) {
        XCUIDevice.shared.press(.home)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCUIApplication().activate()
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Host input was not available after reactivating the containing app")
        tapCenter(of: input)
    }

    private func tapCenter(of element: XCUIElement) {
        let coordinate = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coordinate.tap()
    }

    private func captureRealKeyboardStep(_ name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_REAL_SCREENSHOT_DIR"],
              !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let url = directoryURL.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: url)
    }

    private func typeUsingOpenKeyboard(_ text: String, keyboardApp: XCUIApplication) {
        for character in text {
            let label = character == " " ? "space" : String(character)
            let key = keyboardApp.buttons[label]
            XCTAssertTrue(key.waitForExistence(timeout: 3), "Expected Open Keyboard key '\(label)' to exist")
            key.tap()
        }
    }

    private func applyVisibleCorrections(keyboardApp: XCUIApplication) {
        for _ in 0..<6 {
            let apply = keyboardApp.buttons["ai_correction_apply"]
            guard apply.waitForExistence(timeout: 3), apply.isEnabled else { return }
            apply.tap()
            if keyboardApp.otherElements["correction_complete_panel"].waitForExistence(timeout: 1) {
                return
            }
        }
    }

    private func switchToOpenKeyboardIfPossible(keyboardApp: XCUIApplication, hostInput: XCUIElement) {
        if keyboardApp.buttons["Open Keyboard"].waitForExistence(timeout: 1) {
            keyboardApp.buttons["Open Keyboard"].tap()
            return
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
            if keyboardApp.buttons["ai_sparkle_action"].waitForExistence(timeout: 1) { return }
            if keyboardApp.buttons["Open Keyboard"].waitForExistence(timeout: 1) {
                keyboardApp.buttons["Open Keyboard"].tap()
                return
            }

            candidate.press(forDuration: 1.0)
            if keyboardApp.buttons["Open Keyboard"].waitForExistence(timeout: 2) {
                keyboardApp.buttons["Open Keyboard"].tap()
                return
            }
            if keyboardApp.cells["Open Keyboard"].waitForExistence(timeout: 1) {
                keyboardApp.cells["Open Keyboard"].tap()
                return
            }
        }

        tapCenter(of: hostInput)
    }

    private func waitForOpenKeyboard(
        keyboardApp: XCUIApplication,
        hostInput: XCUIElement,
        springboard: XCUIApplication,
        timeout: TimeInterval = 30
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            dismissKnownKeyboardDialogs(in: springboard)
            if keyboardApp.buttons["ai_sparkle_action"].waitForExistence(timeout: 1)
                || keyboardApp.buttons["keyboard_openkeyboard_icon"].exists
                || keyboardApp.buttons["keyboard_issue_count_badge"].exists {
                return true
            }
            switchToOpenKeyboardIfPossible(keyboardApp: keyboardApp, hostInput: hostInput)
        }
        return false
    }

    private func waitForEnabledAITrigger(keyboardApp: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let trigger = keyboardApp.buttons["ai_sparkle_action"]
        while Date() < deadline {
            if trigger.waitForExistence(timeout: 1),
               trigger.isEnabled,
               !keyboardApp.staticTexts["Analyzing..."].exists,
               !keyboardApp.staticTexts["Checking..."].exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    private func waitForEnabledLeftStatusLane(keyboardApp: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let statusIcon = keyboardApp.buttons["keyboard_openkeyboard_icon"]
        let issueBadge = keyboardApp.buttons["keyboard_issue_count_badge"]
        while Date() < deadline {
            if statusIcon.waitForExistence(timeout: 1), statusIcon.isEnabled {
                return true
            }
            if issueBadge.waitForExistence(timeout: 1), issueBadge.isEnabled {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    private func waitForIssueCountBadge(keyboardApp: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if keyboardApp.buttons["keyboard_issue_count_badge"].exists {
                return true
            }
            if keyboardApp.otherElements["ai_error_panel"].exists
                || keyboardApp.otherElements["correction_complete_panel"].exists {
                return false
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return false
    }

    private func configuredContainingApp(
        extraArguments: [String] = [],
        requiresInjectedGatewayCredentials: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let seedArgument = requiresInjectedGatewayCredentials ? "--seed-functional-gateway-config" : "--seed-gateway-config"
        var launchArguments = ["--uitesting", seedArgument] + extraArguments
        if !requiresInjectedGatewayCredentials {
            launchArguments.insert("--clear-gateway-config", at: 1)
        }
        app.launchArguments = launchArguments

        let environment = ProcessInfo.processInfo.environment
        let injectedGatewayURL = environment["OPEN_KEYBOARD_TEST_GATEWAY_URL"]
        let injectedAPIKey = environment["OPEN_KEYBOARD_TEST_API_KEY"]
        let injectedModel = environment["OPEN_KEYBOARD_TEST_MODEL"]

        if requiresInjectedGatewayCredentials {
            XCTAssertNotNil(injectedGatewayURL, "OPEN_KEYBOARD_TEST_GATEWAY_URL must be injected for functional gateway tests", file: file, line: line)
            XCTAssertNotNil(injectedAPIKey, "OPEN_KEYBOARD_TEST_API_KEY must be injected for functional gateway tests", file: file, line: line)
            XCTAssertNotNil(injectedModel, "OPEN_KEYBOARD_TEST_MODEL must be injected for functional gateway tests", file: file, line: line)
        }

        if requiresInjectedGatewayCredentials {
            app.launchEnvironment["OPEN_KEYBOARD_TEST_GATEWAY_URL"] = injectedGatewayURL ?? ""
            app.launchEnvironment["OPEN_KEYBOARD_TEST_API_KEY"] = injectedAPIKey ?? ""
            app.launchEnvironment["OPEN_KEYBOARD_TEST_MODEL"] = injectedModel ?? ""
        } else {
            app.launchEnvironment["OPEN_KEYBOARD_TEST_GATEWAY_URL"] = injectedGatewayURL ?? Self.mockGatewayURL
            app.launchEnvironment["OPEN_KEYBOARD_TEST_API_KEY"] = injectedAPIKey ?? Self.mockAPIKey
            app.launchEnvironment["OPEN_KEYBOARD_TEST_MODEL"] = injectedModel ?? Self.mockModel
        }
        return app
    }

    private func existingConfiguredContainingApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--skip-onboarding"] + extraArguments
        return app
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
            springboard.buttons[label].tapIfExists()
        }
    }
}

private extension XCUIElement {
    func tapIfExists() {
        if waitForExistence(timeout: 1) {
            tap()
        }
    }
}
