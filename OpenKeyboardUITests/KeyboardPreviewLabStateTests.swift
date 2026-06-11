import XCTest

final class KeyboardPreviewLabStateTests: XCTestCase {
    func testPreviewLabStatesMapToScreenshotPanels() {
        XCTAssertEqual(KeyboardPreviewLabState.ready.previewPanel, .keyboard)
        XCTAssertEqual(KeyboardPreviewLabState.issue.previewPanel, .issue)
        XCTAssertEqual(KeyboardPreviewLabState.correctionCard.previewPanel, .correctionCard)
        XCTAssertEqual(KeyboardPreviewLabState.correctionCardNext.previewPanel, .correctionCardNext)
        XCTAssertEqual(KeyboardPreviewLabState.correctionDetail.previewPanel, .correctionDetail)
        XCTAssertEqual(KeyboardPreviewLabState.actions.previewPanel, .actions)
        XCTAssertEqual(KeyboardPreviewLabState.correctionComplete.previewPanel, .correctionComplete)
    }

    func testPreviewPanelsAreLaunchArgumentAddressable() {
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "keyboard"), .keyboard)
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "issue"), .issue)
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "correctionCard"), .correctionCard)
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "correctionCardNext"), .correctionCardNext)
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "correctionDetail"), .correctionDetail)
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "actions"), .actions)
        XCTAssertEqual(KeyboardVisualPreviewPanel(rawValue: "correctionComplete"), .correctionComplete)
    }

    func testFirstCompactSuggestionShowsOnlyCurrentReplacementToken() {
        let suggestion = KeyboardPreviewLabState.correctionCard.compactSuggestion

        XCTAssertEqual(suggestion?.label, "Correct capitalization:")
        XCTAssertEqual(suggestion?.original, "i")
        XCTAssertEqual(suggestion?.replacement, "I")
        XCTAssertEqual(suggestion?.remainingCount, 3)
        XCTAssertFalse(suggestion?.replacement.contains(" ") ?? true)
        XCTAssertNotEqual(suggestion?.replacement, "I have an apple.")
    }

    func testNextCompactSuggestionAdvancesToNextCurrentReplacementToken() {
        let next = KeyboardPreviewLabState.correctionCard.advancedAfterApplyingCompactSuggestion()
        let suggestion = next.compactSuggestion

        XCTAssertEqual(next, .correctionCardNext)
        XCTAssertEqual(suggestion?.label, "Correct verb:")
        XCTAssertEqual(suggestion?.original, "has")
        XCTAssertEqual(suggestion?.replacement, "have")
        XCTAssertEqual(suggestion?.remainingCount, 2)
        XCTAssertFalse(suggestion?.replacement.contains(" ") ?? true)
        XCTAssertNotEqual(suggestion?.replacement, "I have an apple.")
    }

    func testFinalCompactSuggestionAdvancesToCompletion() {
        let finalSuggestion = KeyboardPreviewSuggestion(
            label: "Correct article:",
            replacement: "an",
            original: "a",
            remainingCount: 1
        )

        XCTAssertEqual(finalSuggestion.nextState, .correctionComplete)
        XCTAssertEqual(KeyboardPreviewLabState.correctionComplete.compactSuggestion, nil)
        XCTAssertEqual(KeyboardPreviewLabState.correctionComplete.previewPanel, .correctionComplete)
    }

    func testNonCompactStatesDoNotExposeReplacementTokens() {
        XCTAssertNil(KeyboardPreviewLabState.ready.compactSuggestion)
        XCTAssertNil(KeyboardPreviewLabState.issue.compactSuggestion)
        XCTAssertNil(KeyboardPreviewLabState.correctionDetail.compactSuggestion)
        XCTAssertNil(KeyboardPreviewLabState.correctionComplete.compactSuggestion)
    }
}
