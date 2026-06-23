import XCTest

final class KeyboardPanelModeTests: XCTestCase {
    func testDebugStatePersistenceIsOnlyAvailableInDebugBuilds() {
#if DEBUG
        XCTAssertTrue(KeyboardDebugStatePolicy.isPersistenceAvailable)
#else
        XCTAssertFalse(KeyboardDebugStatePolicy.isPersistenceAvailable)
#endif
    }

    func testPanelModesCoverKeyboardActionsAndCompletion() {
        XCTAssertEqual(KeyboardPanelMode.keyboard, .keyboard)
        XCTAssertEqual(KeyboardPanelMode.actions, .actions)
        XCTAssertEqual(KeyboardPanelMode.analyzing, .analyzing)
        XCTAssertEqual(KeyboardPanelMode.allGood, .allGood)
        XCTAssertEqual(KeyboardPanelMode.analysisFailed, .analysisFailed)
        XCTAssertEqual(KeyboardPanelMode.correctionDetail, .correctionDetail)
        XCTAssertEqual(KeyboardPanelMode.correctionComplete, .correctionComplete)
    }
}
