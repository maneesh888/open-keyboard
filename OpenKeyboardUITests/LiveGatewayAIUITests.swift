import XCTest

final class LiveGatewayAIUITests: BaseOpenKeyboardUITestCase {
    override func launchArguments() -> [String] {
        ["--uitesting", "--live-ai-test-harness"]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try requireLiveGatewayConfiguration()
        app = XCUIApplication()
        app.launchArguments = launchArguments()
        app.launchEnvironment["OPEN_KEYBOARD_LIVE_GATEWAY_URL"] = liveGatewayURL
        app.launchEnvironment["OPEN_KEYBOARD_LIVE_API_KEY"] = liveAPIKey
        app.launchEnvironment["OPEN_KEYBOARD_LIVE_MODEL"] = liveModel
        app.launch()
    }

    func testFixGrammarWithRealGatewayReplacesTypedText() throws {
        let source = "Our support team definately need clearer notes before they reply to the customer about the delayed refnd."
        let editor = app.textViews["live_ai_text_editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(source)

        app.buttons["live_ai_fix_grammar_button"].tap()

        let status = app.staticTexts["live_ai_status"]
        XCTAssertTrue(status.waitForText("Success", timeout: 90))

        let value = (editor.value as? String) ?? ""
        XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(
            value == "Our support team definitely needs clearer notes before they reply to the customer about the delayed refund.",
            "Live grammar output did not match the expected fixture."
        )
        XCTAssertTrue(value.contains("reply"), "Grammar correction rewrote an unrelated word.")
        XCTAssertFalse(
            value.localizedCaseInsensitiveContains("as an ai"),
            "Live grammar output included model meta commentary."
        )
        print("OpenKeyboard live grammar request status=passed")
    }

    func testImproveWithRealGatewayUsesPlainTextReplacementContract() throws {
        let editor = app.textViews["live_ai_text_editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("this message sound rough and unclear")

        app.buttons["live_ai_improve_button"].tap()

        let status = app.staticTexts["live_ai_status"]
        XCTAssertTrue(status.waitForText("Success", timeout: 90))

        let value = (editor.value as? String) ?? ""
        XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(
            value != "this message sound rough and unclear",
            "Live improve output did not change the source fixture."
        )
        XCTAssertFalse(
            value.contains("{\"operation\""),
            "Live improve output used a structured envelope instead of plain text."
        )
        XCTAssertFalse(
            value.localizedCaseInsensitiveContains("as an ai"),
            "Live improve output included model meta commentary."
        )
    }

    func testInvalidAPIKeyShowsErrorAndPreservesTypedText() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = launchArguments() + ["--live-ai-invalid-key"]
        app.launchEnvironment["OPEN_KEYBOARD_LIVE_GATEWAY_URL"] = liveGatewayURL
        app.launchEnvironment["OPEN_KEYBOARD_LIVE_API_KEY"] = liveAPIKey
        app.launchEnvironment["OPEN_KEYBOARD_LIVE_MODEL"] = liveModel
        app.launch()

        let editor = app.textViews["live_ai_text_editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("i has a apple")

        app.buttons["live_ai_fix_grammar_button"].tap()

        let status = app.staticTexts["live_ai_status"]
        XCTAssertTrue(status.waitForTextContaining("Error", timeout: 30))
        XCTAssertTrue(status.label.localizedCaseInsensitiveContains("authorization") || status.label.localizedCaseInsensitiveContains("gateway"))
        XCTAssertEqual((editor.value as? String) ?? "", "i has a apple")
    }

    private var liveGatewayURL: String {
        ProcessInfo.processInfo.environment["OPEN_KEYBOARD_LIVE_GATEWAY_URL"] ?? ""
    }

    private var liveAPIKey: String {
        ProcessInfo.processInfo.environment["OPEN_KEYBOARD_LIVE_API_KEY"] ?? ""
    }

    private var liveModel: String {
        ProcessInfo.processInfo.environment["OPEN_KEYBOARD_LIVE_MODEL"] ?? ""
    }

    private func requireLiveGatewayConfiguration() throws {
        guard !liveGatewayURL.isEmpty, !liveAPIKey.isEmpty, !liveModel.isEmpty else {
            throw XCTSkip("Set OPEN_KEYBOARD_LIVE_GATEWAY_URL, OPEN_KEYBOARD_LIVE_API_KEY, and OPEN_KEYBOARD_LIVE_MODEL to run live gateway UI tests.")
        }
    }
}

private extension XCUIElement {
    func waitForText(_ expected: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForTextContaining(_ expected: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
