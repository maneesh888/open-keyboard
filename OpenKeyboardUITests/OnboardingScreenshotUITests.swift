import XCTest

final class OnboardingScreenshotUITests: BaseOpenKeyboardUITestCase {
    override func launchArguments() -> [String] {
        OpenKeyboardUITestDataHelper.showOnboarding(page: 0)
    }

    func testWelcomePageContentIsVisibleAndNonOverlapping() throws {
        let title = assertVisible("onboarding_title")
        let subtitle = assertVisible("onboarding_subtitle")
        let llmTitle = assertVisible("onboarding_feature_llm_title")
        let llmDescription = assertVisible("onboarding_feature_llm_description")
        let privacyTitle = assertVisible("onboarding_feature_privacy_title")
        let privacyDescription = assertVisible("onboarding_feature_privacy_description")
        let aiTitle = assertVisible("onboarding_feature_ai_title")
        let aiDescription = assertVisible("onboarding_feature_ai_description")
        let pageIndicator = assertVisible("onboarding_page_indicator")

        XCTAssertEqual(title.label, "Welcome to\nOpen Keyboard")
        XCTAssertEqual(subtitle.label, "AI-powered typing with privacy in mind")
        XCTAssertEqual(llmTitle.label, "Your Own LLM")
        XCTAssertEqual(llmDescription.label, "Connect to your self-hosted LLM gateway")
        XCTAssertEqual(privacyTitle.label, "Privacy First")
        XCTAssertEqual(privacyDescription.label, "Your data never leaves your control")
        XCTAssertEqual(aiTitle.label, "AI Powered")
        XCTAssertEqual(aiDescription.label, "Smart suggestions and text improvements")

        XCTAssertLessThan(aiDescription.frame.maxY, pageIndicator.frame.minY, "Page indicator should not overlap the final feature row")
        attachScreenshot(named: "onboarding-welcome-iPhone")
    }
}

final class OnboardingNavigationUITests: BaseOpenKeyboardUITestCase {
    override func launchArguments() -> [String] {
        ["--uitesting", "--reset-onboarding", "--clear-keyboard-full-access"]
    }

    func testOnboardingSwipesToHomeAndKeepsSettingsShortcutBeforeFullAccess() throws {
        XCTAssertTrue(app.staticTexts["Welcome to\nOpen Keyboard"].waitForExistence(timeout: 5))

        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Connect your gateway"].waitForExistence(timeout: 5))

        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Enable the keyboard"].waitForExistence(timeout: 5))

        app.swipeLeft()
        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.tap()

        XCTAssertTrue(app.staticTexts["Open Keyboard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["open_keyboard_settings_button"].waitForExistence(timeout: 5))
        let fullAccessNote = app.staticTexts["keyboard_full_access_note"]
        XCTAssertTrue(fullAccessNote.waitForExistence(timeout: 5))
        XCTAssertEqual(fullAccessNote.label, "Allow Full Access is needed for AI actions. Open the keyboard once afterward to confirm access.")
    }
}

final class HomeScreenKeyboardAccessUITests: XCTestCase {
    func testHomeHidesKeyboardSettingsAfterKeyboardReportsFullAccess() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--skip-onboarding",
            "--seed-keyboard-full-access"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Open Keyboard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["open_keyboard_settings_button"].exists)
        XCTAssertFalse(app.buttons["check_keyboard_access_button"].exists)
        XCTAssertFalse(app.staticTexts["keyboard_full_access_note"].exists)
    }

    func testHomeShowsKeyboardSettingsBeforeKeyboardReportsFullAccess() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--skip-onboarding",
            "--clear-keyboard-full-access"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["open_keyboard_settings_button"].waitForExistence(timeout: 5))
        let fullAccessNote = app.staticTexts["keyboard_full_access_note"]
        XCTAssertTrue(fullAccessNote.waitForExistence(timeout: 5))
        XCTAssertEqual(fullAccessNote.label, "Allow Full Access is needed for AI actions. Open the keyboard once afterward to confirm access.")
    }

    func testHomeChecksAccessAfterReturningFromSettingsWithoutAnExtensionReport() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--skip-onboarding",
            "--seed-keyboard-settings-visited"
        ]
        app.launch()

        XCTAssertFalse(app.buttons["open_keyboard_settings_button"].exists)
        let checkButton = app.buttons["check_keyboard_access_button"]
        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["keyboard_access_check_note"].label,
                       "Select Open Keyboard in a text field to confirm Allow Full Access.")

        checkButton.tap()
        XCTAssertTrue(app.textViews["keyboard_access_check_input"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["keyboard_access_check_settings_button"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["open_keyboard_settings_button"].exists)
    }
}
