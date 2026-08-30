import XCTest

final class GatewayStatusUITests: XCTestCase {
    override func tearDown() {
        let app = XCUIApplication()
        if app.state != .notRunning {
            app.terminate()
        }
        AppConfig.clearGatewayConnectionError()
        super.tearDown()
    }

    func testHomeGatewayLoaderIsRemovedWhenErrorIsShown() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--clear-gateway-config",
            "--seed-gateway-config",
            "--seed-gateway-error=Gateway timed out"
        ]
        app.launchEnvironment["OPEN_KEYBOARD_TEST_GATEWAY_URL"] = "https://mock.local.invalid"
        app.launchEnvironment["OPEN_KEYBOARD_TEST_API_KEY"] = "mock-ui-test-key"
        app.launchEnvironment["OPEN_KEYBOARD_TEST_MODEL"] = "mock-ui-test-model"
        app.launch()

        XCTAssertTrue(app.staticTexts["Gateway needs attention"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["gateway_status_icon"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)["gateway_status_progress"].exists)
    }

    func testHomeShowsConnectedGatewayWhenModelCapabilityIsUnverified() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--clear-gateway-config",
            "--seed-gateway-config",
            "--replace-existing-config",
            "--seed-unverified-model-capability"
        ]
        app.launchEnvironment["OPEN_KEYBOARD_TEST_GATEWAY_URL"] = "https://mock.local.invalid"
        app.launchEnvironment["OPEN_KEYBOARD_TEST_API_KEY"] = "mock-ui-test-key"
        app.launchEnvironment["OPEN_KEYBOARD_TEST_MODEL"] = "gemma2:2b"
        app.launch()

        XCTAssertTrue(app.staticTexts["Gateway Connected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Retry model check"].exists)
        XCTAssertFalse(app.staticTexts["Gateway needs attention"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "gateway-connected-model-unverified"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSettingsRequiresExplicitModelSelectionBeforeConnectionSave() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--settings-direct",
            "--seed-settings-model-selection",
            "--skip-onboarding"
        ]
        app.launch()

        let picker = app.descendants(matching: .any)["settings_gateway_model_picker"]
        let selectionRequired = app.descendants(matching: .any)["settings_gateway_model_selection_required"]
        let testConnection = app.buttons["Test Connection & Save"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(selectionRequired.waitForExistence(timeout: 2))
        XCTAssertTrue(testConnection.waitForExistence(timeout: 2))
        XCTAssertFalse(testConnection.isEnabled)

        picker.tap()
        let modelOption = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "model-b"))
            .firstMatch
        XCTAssertTrue(modelOption.waitForExistence(timeout: 2))
        modelOption.tap()

        XCTAssertFalse(selectionRequired.exists)
        XCTAssertTrue(testConnection.isEnabled)
    }

    func testSettingsRendersAllDiagnosticRowsAfterPartialFailures() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--settings-direct",
            "--seed-settings-partial-diagnostics",
            "--skip-onboarding"
        ]
        app.launch()

        let models = app.descendants(matching: .any)["settings_gateway_diagnostic_models"]
        let grammar = app.descendants(matching: .any)["settings_gateway_diagnostic_settings-correction-smoke"]
        let rewrite = app.descendants(matching: .any)["settings_gateway_diagnostic_settings-rewrite-improve"]
        let translation = app.descendants(matching: .any)["settings_gateway_diagnostic_settings-translation-dutch"]
        for _ in 0..<4 where !models.exists {
            app.swipeUp()
        }
        XCTAssertTrue(models.waitForExistence(timeout: 5))
        XCTAssertTrue(grammar.waitForExistence(timeout: 2))
        let modelsLabel = models.label
        let grammarLabel = grammar.label

        for _ in 0..<4 where !translation.exists {
            app.swipeUp()
        }

        XCTAssertTrue(rewrite.exists)
        XCTAssertTrue(translation.exists)
        XCTAssertTrue(modelsLabel.contains("12 ms"))
        XCTAssertTrue(grammarLabel.contains("34 ms"))
        XCTAssertTrue(grammarLabel.contains("did not return usable grammar text"))
        XCTAssertTrue(rewrite.label.contains("56 ms"))
        XCTAssertTrue(rewrite.label.contains("plain-text replacement"))
        XCTAssertTrue(translation.label.contains("78 ms"))
        XCTAssertTrue(translation.label.contains("usable Dutch translation"))
    }
}

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

    func testRealKeyboardExtensionMatchesNativeTouchGeometry() throws {
        let app = configuredContainingApp(extraArguments: [
            "--keyboard-host-test",
            "--keyboard-host-autofocus",
            "--keyboard-host-prefer-openkeyboard"
        ])
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        tapCenter(of: input)

        let keyboardApp = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear"
        )

        let qKey = keyboardApp.buttons["q"]
        let aKey = keyboardApp.buttons["a"]
        let zKey = keyboardApp.buttons["z"]
        let spaceKey = keyboardApp.buttons["space"]
        for key in [qKey, aKey, zKey, spaceKey] {
            XCTAssertTrue(key.waitForExistence(timeout: 2), "Expected real keyboard key to be visible")
            XCTAssertEqual(key.frame.height, KeyboardPanelLayout.letterKeyHeight, accuracy: 1)
        }
        XCTAssertEqual(aKey.frame.minY - qKey.frame.minY, KeyboardPanelLayout.letterKeyHeight, accuracy: 1)
        XCTAssertEqual(zKey.frame.minY - aKey.frame.minY, KeyboardPanelLayout.letterKeyHeight, accuracy: 1)
        XCTAssertEqual(spaceKey.frame.minY - zKey.frame.minY, KeyboardPanelLayout.controlKeyHeight, accuracy: 1)
        try captureRealKeyboardStep("real-extension-native-touch-geometry")
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
        XCTAssertTrue(keyboardApp.buttons["ai_action_translate"].waitForExistence(timeout: 2))
        XCTAssertFalse(keyboardApp.buttons["ai_action_summarize"].exists)

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

    func testRealKeyboardShowsGrammarCorrectionFailureStateScreenshot() throws {
        let sourceText = "Please keep this text unchanged."
        let encodedSource = sourceText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceText
        let app = configuredContainingApp(extraArguments: [
            "--keyboard-host-test",
            "--keyboard-host-autofocus",
            "--keyboard-host-prefer-openkeyboard",
            "--keyboard-suggestion-state=modelCapabilityError",
            "--keyboard-host-text=\(encodedSource)"
        ])
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        tapCenter(of: input)

        let keyboardApp = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear"
        )

        XCTAssertTrue(keyboardApp.staticTexts["Model couldn't correct this text"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            keyboardApp.staticTexts["ai_error_message"].label,
            KeyboardActionErrorState.grammarCapabilityMessage
        )
        XCTAssertEqual(input.value as? String, sourceText)
        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].isEnabled)
        try captureRealKeyboardStep("real-keyboard-grammar-correction-failure")
    }

    func testRealKeyboardAutomaticModelFailureKeepsKeysTappable() throws {
        let sourceText = "Please keep this text unchanged."
        let encodedSource = sourceText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceText
        let app = configuredContainingApp(extraArguments: [
            "--keyboard-host-test",
            "--keyboard-host-autofocus",
            "--keyboard-host-prefer-openkeyboard",
            "--keyboard-suggestion-state=automaticModelCapabilityWarning",
            "--keyboard-host-text=\(encodedSource)"
        ])
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        tapCenter(of: input)

        let keyboardApp = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear"
        )

        XCTAssertTrue(keyboardApp.staticTexts["Model couldn't correct this text"].waitForExistence(timeout: 5))
        XCTAssertFalse(keyboardApp.otherElements["ai_error_panel"].exists)
        XCTAssertEqual(input.value as? String, sourceText)
        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].isEnabled)

        let qKey = keyboardApp.buttons["q"]
        let spaceKey = keyboardApp.buttons["space"]
        let aKey = keyboardApp.buttons["a"]
        let shiftKey = keyboardApp.buttons["⇧"]
        for key in [qKey, spaceKey, aKey, shiftKey] {
            XCTAssertTrue(key.waitForExistence(timeout: 2), "Expected the real key grid to remain visible after automatic analysis failed")
            XCTAssertTrue(key.isHittable, "Expected keyboard keys to remain tappable after automatic analysis failed")
        }

        shiftKey.tap()
        shiftKey.tap()
        XCTAssertTrue(keyboardApp.staticTexts["Model couldn't correct this text"].exists)
        try captureRealKeyboardStep("real-keyboard-automatic-model-warning-keys")

        qKey.tap()
        spaceKey.tap()
        aKey.tap()

        let editedText = "\(sourceText)q a"
        expectation(for: NSPredicate(format: "value == %@", editedText), evaluatedWith: input)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(input.value as? String, editedText)
        XCTAssertFalse(keyboardApp.otherElements["ai_error_panel"].exists)

        try captureRealKeyboardStep("real-keyboard-automatic-model-warning-after-edit")
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

    func testRealKeyboardNormalKeyboardScreenshotWhenExplicitlyRequested() throws {
        let screenshotDirectory = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_REAL_SCREENSHOT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !screenshotDirectory.isEmpty else {
            throw XCTSkip("Set OPEN_KEYBOARD_REAL_SCREENSHOT_DIR to opt into real keyboard normal screenshots.")
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
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was not available for keyboard screenshot")
        tapCenter(of: input)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keyboardApp = XCUIApplication()
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear"
        )
        XCTAssertTrue(keyboardApp.buttons["ai_sparkle_action"].waitForExistence(timeout: 5))
        try captureRealKeyboardStep("01-real-keyboard-normal-keyboard")
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
            "--keyboard-host-text=\(encodedSource)",
            "--keyboard-suggestion-state=improvePanel",
            "--keyboard-initial-panel=actions"
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
        XCTAssertTrue(keyboardApp.otherElements["ai_action_panel"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            keyboardApp.otherElements["ai_action_panel"].frame.height,
            KeyboardPanelLayout.actionPanelHeight,
            accuracy: 1
        )
        let resultText = keyboardApp.staticTexts["ai_action_result_text"]
        XCTAssertTrue(resultText.waitForExistence(timeout: 5))
        XCTAssertTrue(resultText.label.contains("SCROLL TEST START"))
        XCTAssertTrue(resultText.label.contains("SCROLL TEST END"))

        for identifier in ["ai_action_improve", "ai_action_rewrite", "ai_action_translate"] {
            let button = keyboardApp.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(button.frame.height, KeyboardPanelLayout.actionCarouselButtonHeight)
        }
        XCTAssertFalse(keyboardApp.buttons["ai_action_summarize"].exists)
        for identifier in ["back_to_keyboard", "ai_action_apply"] {
            let button = keyboardApp.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(button.frame.height, KeyboardPanelLayout.actionControlButtonHeight)
        }
        let groupedButtonIdentifiers = ["ai_action_rerun", "ai_action_toggle_carousel", "ai_action_copy"]
        for identifier in groupedButtonIdentifiers {
            let button = keyboardApp.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertEqual(button.frame.width, KeyboardPanelLayout.actionGroupedButtonWidth, accuracy: 1)
            XCTAssertEqual(button.frame.height, KeyboardPanelLayout.actionControlButtonHeight, accuracy: 1)
        }
        let groupedControls = keyboardApp.otherElements["ai_action_grouped_controls"]
        XCTAssertTrue(groupedControls.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(groupedControls.frame.width, KeyboardPanelLayout.actionGroupedButtonWidth * 3)
        XCTAssertGreaterThanOrEqual(groupedControls.frame.height, KeyboardPanelLayout.actionControlButtonHeight)
        let resultScroll = keyboardApp.scrollViews["ai_action_result_scroll"]
        XCTAssertTrue(resultScroll.waitForExistence(timeout: 5))
        XCTAssertEqual(resultScroll.frame.height, KeyboardPanelLayout.actionPanelScrollableResultHeight, accuracy: 1)

        let fixedControlIdentifiers = [
            "ai_action_improve",
            "ai_action_rewrite",
            "ai_action_translate",
            "back_to_keyboard",
            "ai_action_grouped_controls",
            "ai_action_apply"
        ]
        let initialFixedControlFrames = Dictionary(
            uniqueKeysWithValues: fixedControlIdentifiers.map {
                ($0, keyboardApp.descendants(matching: .any)[$0].frame)
            }
        )
        try captureRealKeyboardStep("02-real-keyboard-long-improve-result-top")

        let initialResultMinY = resultText.frame.minY
        resultScroll.swipeUp()
        XCTAssertLessThan(resultText.frame.minY, initialResultMinY - 20)
        for identifier in fixedControlIdentifiers {
            let initialFrame = try XCTUnwrap(initialFixedControlFrames[identifier])
            let currentFrame = keyboardApp.descendants(matching: .any)[identifier].frame
            XCTAssertEqual(currentFrame.minX, initialFrame.minX, accuracy: 1, "\(identifier) moved horizontally while scrolling")
            XCTAssertEqual(currentFrame.minY, initialFrame.minY, accuracy: 1, "\(identifier) moved vertically while scrolling")
            XCTAssertEqual(currentFrame.width, initialFrame.width, accuracy: 1, "\(identifier) width changed while scrolling")
            XCTAssertEqual(currentFrame.height, initialFrame.height, accuracy: 1, "\(identifier) height changed while scrolling")
        }
        try captureRealKeyboardStep("03-real-keyboard-long-improve-result-scrolled")
    }

    func testRealKeyboardActionCarouselScreenshotWhenExplicitlyRequested() throws {
        let screenshotDirectory = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_REAL_SCREENSHOT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !screenshotDirectory.isEmpty else {
            throw XCTSkip("Set OPEN_KEYBOARD_REAL_SCREENSHOT_DIR to opt into real keyboard action carousel screenshots.")
        }

        let sourceText = "Please send the customer an update about the delivery."
        let encodedSource = sourceText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceText
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--keyboard-host-test",
            "--keyboard-host-autofocus",
            "--keyboard-host-prefer-openkeyboard",
            "--keyboard-host-text=\(encodedSource)",
            "--keyboard-suggestion-state=actionCarouselPanel",
            "--keyboard-initial-panel=actions"
        ]
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        tapCenter(of: input)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keyboardApp = XCUIApplication()
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear for action carousel screenshot proof"
        )

        let panel = keyboardApp.otherElements["ai_action_panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertEqual(panel.frame.height, KeyboardPanelLayout.actionPanelHeight, accuracy: 1)

        let actionCarousel = keyboardApp.scrollViews["ai_action_carousel"]
        XCTAssertTrue(actionCarousel.waitForExistence(timeout: 5))
        XCTAssertEqual(actionCarousel.frame.height, KeyboardPanelLayout.actionCarouselButtonHeight, accuracy: 1)
        XCTAssertFalse(keyboardApp.scrollViews["ai_rewrite_style_carousel"].exists)
        XCTAssertFalse(keyboardApp.scrollViews["ai_translation_target_carousel"].exists)

        let improve = actionCarousel.buttons["ai_action_improve"]
        XCTAssertTrue(improve.waitForExistence(timeout: 5))
        XCTAssertEqual(improve.value as? String, "Selected")
        XCTAssertGreaterThanOrEqual(improve.frame.height, KeyboardPanelLayout.actionCarouselButtonHeight)

        for style in KeyboardRewriteStyle.allCases {
            let button = actionCarousel.buttons["ai_action_rewrite_\(style.rawValue)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(style.displayName) action was missing from the primary carousel")
            XCTAssertGreaterThanOrEqual(button.frame.height, KeyboardPanelLayout.actionCarouselButtonHeight)
        }

        XCTAssertTrue(keyboardApp.staticTexts["ai_action_empty_text"].waitForExistence(timeout: 5))
        XCTAssertEqual(keyboardApp.staticTexts["ai_action_empty_text"].label, "No suggestion yet")
        XCTAssertFalse(keyboardApp.buttons["ai_action_summarize"].exists)

        let fixedControlIdentifiers = ["back_to_keyboard", "ai_action_rerun", "ai_action_toggle_carousel", "ai_action_copy", "ai_action_apply"]
        for identifier in fixedControlIdentifiers {
            let button = keyboardApp.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(button.frame.height, KeyboardPanelLayout.actionControlButtonHeight)
        }

        let initialControlFrames = Dictionary(
            uniqueKeysWithValues: fixedControlIdentifiers.map {
                ($0, keyboardApp.buttons[$0].frame)
            }
        )
        try captureRealKeyboardStep("06-real-keyboard-actions-start")

        let professional = actionCarousel.buttons["ai_action_rewrite_professional"]
        for _ in 0..<8 where !professional.isHittable {
            actionCarousel.swipeLeft()
        }
        XCTAssertTrue(professional.isHittable, "Professional action did not scroll into view in the primary carousel")
        XCTAssertEqual(actionCarousel.frame.height, KeyboardPanelLayout.actionCarouselButtonHeight, accuracy: 1)
        for identifier in fixedControlIdentifiers {
            let initialFrame = try XCTUnwrap(initialControlFrames[identifier])
            let currentFrame = keyboardApp.buttons[identifier].frame
            XCTAssertEqual(currentFrame.minX, initialFrame.minX, accuracy: 1, "\(identifier) moved horizontally while scrolling actions")
            XCTAssertEqual(currentFrame.minY, initialFrame.minY, accuracy: 1, "\(identifier) moved vertically while scrolling actions")
            XCTAssertEqual(currentFrame.width, initialFrame.width, accuracy: 1, "\(identifier) width changed while scrolling actions")
            XCTAssertEqual(currentFrame.height, initialFrame.height, accuracy: 1, "\(identifier) height changed while scrolling actions")
        }
        try captureRealKeyboardStep("07-real-keyboard-actions-styles")
    }

    func testRealKeyboardTranslateModeScreenshotWhenExplicitlyRequested() throws {
        let screenshotDirectory = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_REAL_SCREENSHOT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !screenshotDirectory.isEmpty else {
            throw XCTSkip("Set OPEN_KEYBOARD_REAL_SCREENSHOT_DIR to opt into real keyboard Translate screenshots.")
        }

        let sourceText = "Good morning, I hope you are well."
        let encodedSource = sourceText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceText
        let app = configuredContainingApp(extraArguments: [
            "--keyboard-host-test",
            "--keyboard-host-autofocus",
            "--keyboard-host-prefer-openkeyboard",
            "--keyboard-host-text=\(encodedSource)",
            "--keyboard-suggestion-state=translatePanel",
            "--keyboard-initial-panel=actions"
        ])
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        tapCenter(of: input)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keyboardApp = XCUIApplication()
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear for Translate screenshot proof"
        )

        let panel = keyboardApp.otherElements["ai_action_panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertEqual(panel.frame.height, KeyboardPanelLayout.actionPanelHeight, accuracy: 1)

        let translate = keyboardApp.buttons["ai_action_translate"]
        XCTAssertTrue(translate.waitForExistence(timeout: 5))
        XCTAssertEqual(translate.value as? String, "Selected")
        XCTAssertGreaterThanOrEqual(translate.frame.height, KeyboardPanelLayout.actionCarouselButtonHeight)

        let targetCarousel = keyboardApp.scrollViews["ai_translation_target_carousel"]
        XCTAssertTrue(targetCarousel.waitForExistence(timeout: 5))
        XCTAssertEqual(targetCarousel.frame.height, KeyboardPanelLayout.actionContextSelectorHeight, accuracy: 1)

        for identifier in [
            "ai_translation_target_ar",
            "ai_translation_target_ml",
            "ai_translation_target_hi",
            "ai_translation_target_ur",
            "ai_translation_target_en-US",
            "ai_translation_target_bn",
            "ai_translation_target_mr",
            "ai_translation_target_te",
            "ai_translation_target_ta",
            "ai_translation_target_zh-Hans",
            "ai_translation_target_es",
            "ai_translation_target_fr",
            "ai_translation_target_pt",
            "ai_translation_target_ru",
            "ai_translation_target_nl"
        ] {
            let button = keyboardApp.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(button.frame.height, KeyboardPanelLayout.actionContextSelectorHeight)
        }
        XCTAssertEqual(keyboardApp.buttons["ai_translation_target_ar"].value as? String, "Selected")

        let resultText = keyboardApp.staticTexts["ai_action_result_text"]
        XCTAssertTrue(resultText.waitForExistence(timeout: 5))
        XCTAssertEqual(resultText.label, "صباح الخير، أتمنى أن تكون بخير.")
        let resultScroll = keyboardApp.scrollViews["ai_action_result_scroll"]
        XCTAssertTrue(resultScroll.waitForExistence(timeout: 5))
        XCTAssertEqual(resultScroll.frame.height, KeyboardPanelLayout.actionPanelContextualResultHeight, accuracy: 1)

        for identifier in ["back_to_keyboard", "ai_action_rerun", "ai_action_toggle_carousel", "ai_action_copy", "ai_action_apply"] {
            let button = keyboardApp.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(button.frame.height, KeyboardPanelLayout.actionControlButtonHeight)
        }

        let actionCarousel = keyboardApp.scrollViews["ai_action_carousel"]
        XCTAssertTrue(actionCarousel.waitForExistence(timeout: 5))
        let improve = keyboardApp.buttons["ai_action_improve"]
        let rephrase = keyboardApp.buttons["ai_action_rewrite"]
        XCTAssertTrue(improve.waitForExistence(timeout: 5))
        XCTAssertTrue(rephrase.waitForExistence(timeout: 5))
        XCTAssertFalse(keyboardApp.buttons["ai_action_summarize"].exists)
        XCTAssertLessThanOrEqual(resultScroll.frame.maxY, targetCarousel.frame.minY)
        XCTAssertLessThan(targetCarousel.frame.maxY, actionCarousel.frame.minY)
        XCTAssertEqual(
            actionCarousel.frame.minY - targetCarousel.frame.maxY,
            KeyboardPanelLayout.actionContextSelectorSpacing,
            accuracy: 1
        )
        XCTAssertGreaterThanOrEqual(improve.frame.minX, panel.frame.minX - 1)
        XCTAssertLessThanOrEqual(translate.frame.maxX, panel.frame.maxX + 1)

        try captureRealKeyboardStep("04-real-keyboard-translate-arabic-malayalam")

        let telugu = keyboardApp.buttons["ai_translation_target_te"]
        var scrollAttempts = 0
        while !telugu.isHittable && scrollAttempts < 4 {
            targetCarousel.swipeLeft()
            scrollAttempts += 1
        }
        XCTAssertTrue(telugu.isHittable, "More Indian languages should be reachable in the language carousel")
        try captureRealKeyboardStep("05-real-keyboard-translate-indian-languages")
    }

    func testRealKeyboardTranslationCapabilityWarningScreenshotWhenExplicitlyRequested() throws {
        let screenshotDirectory = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_REAL_SCREENSHOT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !screenshotDirectory.isEmpty else {
            throw XCTSkip("Set OPEN_KEYBOARD_REAL_SCREENSHOT_DIR to opt into real keyboard translation-warning screenshots.")
        }

        let sourceText = "Good morning, I hope you are well."
        let encodedSource = sourceText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceText
        let app = configuredContainingApp(extraArguments: [
            "--keyboard-host-test",
            "--keyboard-host-autofocus",
            "--keyboard-host-prefer-openkeyboard",
            "--keyboard-host-text=\(encodedSource)",
            "--keyboard-suggestion-state=translationWarning",
            "--keyboard-initial-panel=actions"
        ])
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        tapCenter(of: input)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keyboardApp = XCUIApplication()
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear for translation-warning screenshot proof"
        )

        XCTAssertTrue(keyboardApp.staticTexts[
            "This model may not reliably translate to Arabic. Try again or choose another model."
        ].waitForExistence(timeout: 5))
        XCTAssertEqual(keyboardApp.buttons["ai_translation_target_ar"].value as? String, "Selected")
        XCTAssertTrue(keyboardApp.buttons["ai_action_rerun"].isEnabled)
        XCTAssertFalse(keyboardApp.buttons["ai_action_copy"].isEnabled)
        XCTAssertFalse(keyboardApp.buttons["ai_action_apply"].isEnabled)
        XCTAssertFalse(keyboardApp.otherElements["ai_error_panel"].exists)
        XCTAssertEqual(input.value as? String, sourceText)

        try captureRealKeyboardStep("real-keyboard-translation-capability-warning")
    }

    func testRealKeyboardTranslateReplacesTextWhenGatewayConfigured() throws {
        let sourceText = "Good morning, I hope you are well."
        let encodedSource = sourceText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceText
        let app = configuredContainingApp(
            extraArguments: [
                "--keyboard-host-test",
                "--keyboard-host-autofocus",
                "--keyboard-host-prefer-openkeyboard",
                "--keyboard-host-text=\(encodedSource)",
                "--keyboard-suggestion-state=translatePanel",
                "--keyboard-initial-panel=actions"
            ],
            requiresInjectedGatewayCredentials: true
        )
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        tapCenter(of: input)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keyboardApp = XCUIApplication()
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear for live Translate verification"
        )

        let resultText = keyboardApp.staticTexts["ai_action_result_text"]
        XCTAssertTrue(resultText.waitForExistence(timeout: 5))
        let seededResult = resultText.label
        let targetCarousel = keyboardApp.scrollViews["ai_translation_target_carousel"]
        XCTAssertTrue(targetCarousel.waitForExistence(timeout: 5))
        let malayalam = keyboardApp.buttons["ai_translation_target_ml"]
        XCTAssertTrue(malayalam.waitForExistence(timeout: 5))
        XCTAssertTrue(malayalam.isHittable, "Malayalam should be immediately visible beside Arabic")
        tapCenter(of: malayalam)
        XCTAssertTrue(
            waitForAccessibilityValue("Selected", on: malayalam, timeout: 5),
            "Malayalam did not become the selected translation target"
        )

        XCTAssertTrue(
            waitForChangedLabel(resultText, originalLabel: seededResult, timeout: 90),
            "Live Malayalam translation did not replace the deterministic seed result"
        )
        XCTAssertFalse(resultText.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(resultText.label.contains("{\"operation\""))
        XCTAssertTrue(
            resultText.label.unicodeScalars.contains { (0x0D00...0x0D7F).contains($0.value) },
            "Live translation did not contain Malayalam characters"
        )
        XCTAssertEqual(malayalam.value as? String, "Selected")

        let apply = keyboardApp.buttons["ai_action_apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        XCTAssertTrue(apply.isEnabled)
        apply.tap()

        let translated = NSPredicate(format: "value != %@", sourceText)
        expectation(for: translated, evaluatedWith: input)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(keyboardApp.staticTexts["Translation applied"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "live-gateway-real-keyboard-malayalam-translation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRealKeyboardPlainTextLoadingScreenshotWhenExplicitlyRequested() throws {
        let keyboardApp = try launchSeededRealKeyboardState(
            suggestionState: "actionLoadingPanel",
            initialPanel: "actions"
        )
        XCTAssertTrue(keyboardApp.buttons["ai_action_improve"].waitForExistence(timeout: 5))
        XCTAssertTrue(keyboardApp.staticTexts["ai_action_loading_text"].waitForExistence(timeout: 5))
        try captureRealKeyboardStep("01-real-keyboard-plain-text-loading")
    }

    func testRealKeyboardPlainTextComparisonScreenshotWhenExplicitlyRequested() throws {
        let keyboardApp = try launchSeededRealKeyboardState(
            suggestionState: "rephraseComparisonPanel",
            initialPanel: "actions"
        )
        let result = keyboardApp.staticTexts["ai_action_result_text"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "Send the customer an update tomorrow.")
        XCTAssertTrue(keyboardApp.buttons["ai_action_apply"].isEnabled)
        try captureRealKeyboardStep("02-real-keyboard-plain-text-comparison")
    }

    func testRealKeyboardPlainTextFailureScreenshotWhenExplicitlyRequested() throws {
        let keyboardApp = try launchSeededRealKeyboardState(
            suggestionState: "modelCapabilityError",
            initialPanel: "keyboard"
        )
        XCTAssertTrue(
            keyboardApp.staticTexts["ai_error_message"].waitForExistence(timeout: 5),
            "Stable model-capability failure was not visible in the real keyboard extension"
        )
        XCTAssertFalse(keyboardApp.staticTexts["ai_action_loading_text"].exists)
        try captureRealKeyboardStep("03-real-keyboard-stable-failure")
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

        let connectionError = AppConfig.gatewayConnectionError(from: defaults)
        guard defaults.bool(forKey: AppConfig.gatewayProfileConfiguredHintKey),
              !(defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey) ?? "").isEmpty,
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

    private func launchSeededRealKeyboardState(
        suggestionState: String,
        initialPanel: String
    ) throws -> XCUIApplication {
        let screenshotDirectory = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_REAL_SCREENSHOT_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !screenshotDirectory.isEmpty else {
            throw XCTSkip("Set OPEN_KEYBOARD_REAL_SCREENSHOT_DIR to opt into real keyboard plain-text screenshots.")
        }

        let sourceText = "send the customer a update tomorrow"
        let encodedSource = sourceText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceText
        let hostApp = configuredContainingApp(extraArguments: [
            "--keyboard-host-test",
            "--keyboard-host-autofocus",
            "--keyboard-host-prefer-openkeyboard",
            "--keyboard-host-text=\(encodedSource)",
            "--keyboard-suggestion-state=\(suggestionState)",
            "--keyboard-initial-panel=\(initialPanel)"
        ])
        hostApp.launch()
        XCTAssertTrue(hostApp.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = hostApp.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was unavailable for seeded keyboard proof")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keyboardApp = XCUIApplication()
        XCTAssertTrue(
            waitForOpenKeyboard(keyboardApp: keyboardApp, hostInput: input, springboard: springboard),
            "Open Keyboard extension did not appear for seeded \(suggestionState) proof"
        )
        return keyboardApp
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
                || keyboardApp.buttons["keyboard_issue_count_badge"].exists
                || keyboardApp.otherElements["ai_action_panel"].exists {
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

    private func waitForChangedLabel(_ element: XCUIElement, originalLabel: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.waitForExistence(timeout: 1), element.label != originalLabel, !element.label.isEmpty {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    private func waitForAccessibilityValue(_ value: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.waitForExistence(timeout: 1), element.value as? String == value {
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
