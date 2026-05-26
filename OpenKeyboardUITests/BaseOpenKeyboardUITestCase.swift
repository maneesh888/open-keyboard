import XCTest

class BaseOpenKeyboardUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = launchArguments()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func launchArguments() -> [String] {
        OpenKeyboardUITestDataHelper.showOnboarding()
    }

    func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func assertVisible(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected \(identifier) to exist", file: file, line: line)
        XCTAssertTrue(element.isHittable || element.frame.width > 0 && element.frame.height > 0, "Expected \(identifier) to be visible", file: file, line: line)
        return element
    }
}
