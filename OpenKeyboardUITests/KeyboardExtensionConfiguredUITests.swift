import XCTest

final class KeyboardExtensionConfiguredUITests: XCTestCase {
    private static let mockGatewayURL = "https://mock.local.invalid"
    private static let mockAPIKey = "mock-ui-test-key"
    private static let mockModel = "mock-ui-test-model"

    func testContainingAppSeedsSharedGatewayConfigForKeyboardExtension() {
        let app = configuredContainingApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Keyboard Configured"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Setup Required"].exists)
        XCTAssertTrue(app.staticTexts[Self.mockModel].waitForExistence(timeout: 5))
    }


    func testConfiguredHomeOpensPlaygroundAndFocusesInput() throws {
        let app = configuredContainingApp(extraArguments: ["--skip-onboarding"])
        app.launch()

        let entry = app.buttons["playground_entry_button"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Configured home should expose the Playground entry")
        XCTAssertFalse(app.staticTexts["Keyboard Preview Lab"].exists, "Normal home must not expose Preview Lab")

        entry.tap()

        XCTAssertTrue(app.navigationBars["Playground"].waitForExistence(timeout: 5), "Playground navigation title should be visible after tapping entry")
        XCTAssertEqual(app.staticTexts.matching(identifier: "Playground").count, 1, "Playground should only render one visible title")
        let input = app.textViews["playground_text_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Playground text input should be available")
        XCTAssertTrue((input.value as? String)?.contains("Me and my team was trying to finish the report yesterday") == true, "Playground input should start with the intentionally flawed sample sentence")
        input.tap()
        input.typeText(" hello")
        XCTAssertTrue((input.value as? String)?.contains("hello") == true, "Playground input should accept typed text")
    }

    func testRealKeyboardExtensionShowsConfiguredAIControlsWhenSharedConfigSeeded() throws {
        let app = configuredContainingApp(extraArguments: ["--keyboard-host-test", "--keyboard-host-autofocus", "--keyboard-host-prefer-openkeyboard"])
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was not available for keyboard verification")
        input.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        dismissKnownKeyboardDialogs(in: springboard)

        let keyboardApp = XCUIApplication()
        var foundOpenKeyboard = keyboardApp.buttons["ai_action_fixGrammar"].waitForExistence(timeout: 2)

        if !foundOpenKeyboard {
            for _ in 0..<8 {
                dismissKnownKeyboardDialogs(in: springboard)
                switchToOpenKeyboardIfPossible(keyboardApp: keyboardApp, hostInput: input)

                if keyboardApp.buttons["ai_action_fixGrammar"].waitForExistence(timeout: 2) {
                    foundOpenKeyboard = true
                    break
                }
            }
        }

        XCTAssertTrue(foundOpenKeyboard, "Open Keyboard extension did not appear or Fix Grammar was missing")
        XCTAssertFalse(keyboardApp.staticTexts["Gateway not configured"].exists)
        XCTAssertFalse(keyboardApp.staticTexts["Pair gateway in app"].exists)
        XCTAssertFalse(keyboardApp.staticTexts["Full Access required"].exists)
        XCTAssertTrue(keyboardApp.buttons["ai_action_fixGrammar"].isEnabled)
        XCTAssertTrue(keyboardApp.buttons["ai_action_rewrite"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.buttons["ai_action_rewrite"].isEnabled)
        XCTAssertTrue(keyboardApp.buttons["ai_action_summarize"].waitForExistence(timeout: 2))
        XCTAssertTrue(keyboardApp.buttons["ai_action_summarize"].isEnabled)
    }

    func testRealKeyboardFixGrammarReplacesTextWhenGatewayConfigured() throws {
        let app = configuredContainingApp(extraArguments: ["--keyboard-host-test", "--keyboard-host-autofocus", "--keyboard-host-prefer-openkeyboard"], requiresInjectedGatewayCredentials: true)
        app.launch()
        XCTAssertTrue(app.staticTexts["Keyboard Extension Host"].waitForExistence(timeout: 5))

        let input = app.textViews["keyboard_host_text_editor"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Host app text editor was not available for keyboard action verification")
        tapCenter(of: input)

        let keyboardApp = XCUIApplication()
        for _ in 0..<8 where !keyboardApp.buttons["ai_action_fixGrammar"].exists {
            switchToOpenKeyboardIfPossible(keyboardApp: keyboardApp, hostInput: input)
        }

        XCTAssertTrue(keyboardApp.buttons["ai_action_fixGrammar"].waitForExistence(timeout: 5), "Fix Grammar was not available in Open Keyboard")
        XCTAssertTrue(keyboardApp.buttons["ai_action_fixGrammar"].isEnabled)

        tapCenter(of: input)
        typeUsingOpenKeyboard("i has a apple", keyboardApp: keyboardApp)
        let typed = NSPredicate(format: "value CONTAINS[c] %@", "i has a apple")
        expectation(for: typed, evaluatedWith: input)
        waitForExpectations(timeout: 10)

        let liveFixGrammar = keyboardApp.buttons["ai_action_fixGrammar"]
        XCTAssertTrue(liveFixGrammar.waitForExistence(timeout: 5), "Fix Grammar disappeared after typing")
        XCTAssertTrue(liveFixGrammar.isEnabled)
        liveFixGrammar.tap()

        let corrected = NSPredicate(format: "value CONTAINS[c] %@", "I have an apple")
        expectation(for: corrected, evaluatedWith: input)
        waitForExpectations(timeout: 60)
    }

    private func tapCenter(of element: XCUIElement) {
        let coordinate = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coordinate.tap()
    }

    private func typeUsingOpenKeyboard(_ text: String, keyboardApp: XCUIApplication) {
        for character in text {
            let label = character == " " ? "space" : String(character)
            let key = keyboardApp.buttons[label]
            XCTAssertTrue(key.waitForExistence(timeout: 3), "Expected Open Keyboard key '\(label)' to exist")
            key.tap()
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
            if keyboardApp.buttons["ai_action_fixGrammar"].waitForExistence(timeout: 1) { return }
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

    private func configuredContainingApp(
        extraArguments: [String] = [],
        requiresInjectedGatewayCredentials: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        let app = XCUIApplication()
        let seedArgument = requiresInjectedGatewayCredentials ? "--seed-functional-gateway-config" : "--seed-gateway-config"
        app.launchArguments = ["--uitesting", seedArgument] + extraArguments

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
