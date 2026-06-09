import XCTest

final class KeyboardPanelModeTests: XCTestCase {
    func testPanelModesCoverKeyboardActionsAndCompletion() {
        XCTAssertEqual(KeyboardPanelMode.keyboard, .keyboard)
        XCTAssertEqual(KeyboardPanelMode.actions, .actions)
        XCTAssertEqual(KeyboardPanelMode.correctionComplete, .correctionComplete)
    }
}
