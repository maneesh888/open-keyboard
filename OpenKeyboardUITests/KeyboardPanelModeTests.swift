import XCTest

final class KeyboardPanelModeTests: XCTestCase {
    func testDebugStatePersistenceIsOnlyAvailableInDebugBuilds() {
#if DEBUG
        XCTAssertTrue(KeyboardViewModel.isDebugStatePersistenceAvailable)
#else
        XCTAssertFalse(KeyboardViewModel.isDebugStatePersistenceAvailable)
#endif
    }

    func testPanelModesCoverKeyboardActionsAndCompletion() {
        XCTAssertEqual(KeyboardPanelMode.keyboard, .keyboard)
        XCTAssertEqual(KeyboardPanelMode.actions, .actions)
        XCTAssertEqual(KeyboardPanelMode.correctionComplete, .correctionComplete)
    }
}
