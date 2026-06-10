import XCTest

final class KeyboardPreviewLabStateTests: XCTestCase {
    func testPreviewLabStatesMapToScreenshotPanels() {
        XCTAssertEqual(KeyboardPreviewLabState.ready.previewPanel, .keyboard)
        XCTAssertEqual(KeyboardPreviewLabState.issue.previewPanel, .issue)
        XCTAssertEqual(KeyboardPreviewLabState.correctionCard.previewPanel, .correctionCard)
        XCTAssertEqual(KeyboardPreviewLabState.correctionDetail.previewPanel, .correctionDetail)
        XCTAssertEqual(KeyboardPreviewLabState.actions.previewPanel, .actions)
        XCTAssertEqual(KeyboardPreviewLabState.correctionComplete.previewPanel, .correctionComplete)
    }

    func testPreviewPanelsAreLaunchArgumentAddressable() {
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "keyboard"), .keyboard)
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "issue"), .issue)
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "correctionCard"), .correctionCard)
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "correctionDetail"), .correctionDetail)
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "actions"), .actions)
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "correctionComplete"), .correctionComplete)
    }
}
