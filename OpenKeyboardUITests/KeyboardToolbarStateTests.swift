import XCTest

final class KeyboardToolbarStateTests: XCTestCase {
    func testFullAccessRequiredStateBlocksActions() {
        let state = KeyboardToolbarState.current(
            hasFullAccess: false,
            isConfigured: true,
            selectedModel: "model",
            isPerformingAIAction: false,
            aiStatus: "Ready"
        )

        XCTAssertEqual(state.kind, .fullAccessRequired)
        XCTAssertEqual(state.title, "Full Access required")
        XCTAssertEqual(state.subtitle, "Basic typing is local. Full Access lets AI send bounded text to your gateway.")
        XCTAssertFalse(state.isActionEnabled)
    }

    func testNotConfiguredStateBlocksActions() {
        let state = KeyboardToolbarState.current(
            hasFullAccess: true,
            isConfigured: false,
            selectedModel: "",
            isPerformingAIAction: false,
            aiStatus: "Pair gateway in app"
        )

        XCTAssertEqual(state.kind, .notConfigured)
        XCTAssertEqual(state.title, "Gateway not configured")
        XCTAssertEqual(state.subtitle, "Pair your gateway in the app before using AI actions.")
        XCTAssertFalse(state.isActionEnabled)
    }

    func testRuntimeGatewayErrorDoesNotShowReady() {
        let state = KeyboardToolbarState(kind: .error(message: "Gateway HTTP 500"))

        XCTAssertEqual(state.title, "AI unavailable")
        XCTAssertEqual(state.subtitle, "Gateway HTTP 500")
        XCTAssertFalse(state.isActionEnabled)
        XCTAssertNotEqual(state.subtitle, "Ready")
    }

    func testActionsStateUsesLoadedModel() {
        let state = KeyboardToolbarState.current(
            hasFullAccess: true,
            isConfigured: true,
            selectedModel: "gemma4:latest",
            isPerformingAIAction: false,
            aiStatus: "Ready"
        )

        XCTAssertEqual(state.kind, .actions(status: "Ready"))
        XCTAssertEqual(state.title, "Open Keyboard AI")
        XCTAssertEqual(state.subtitle, "Ready")
        XCTAssertTrue(state.isActionEnabled)
        XCTAssertTrue(state.showsBrandMark)
        XCTAssertFalse(state.showsIssueCount)
        XCTAssertEqual(state.issueCount, 0)
    }

    func testKeyboardLayoutUsesNativeLikeTypingGrid() {
        XCTAssertEqual(KeyboardPanelLayout.letterKeyHeight, 45)
        XCTAssertEqual(KeyboardPanelLayout.controlKeyHeight, 45)
        XCTAssertEqual(KeyboardPanelLayout.outerHorizontalPadding, 4)
        XCTAssertEqual(KeyboardPanelLayout.outerTopPadding, 6)
        XCTAssertEqual(KeyboardPanelLayout.keyHorizontalSpacing, 5.5)
        XCTAssertEqual(KeyboardPanelLayout.keyRowSpacing, 11)
        XCTAssertEqual(KeyboardPanelLayout.keyGridHeight, 215)
        XCTAssertEqual(KeyboardPanelLayout.preferredKeyboardHeight, 280)

        let metrics = KeyboardPanelLayout.keyGridMetrics(for: 385)
        XCTAssertEqual(metrics.homeRowInset, (metrics.letterWidth + KeyboardPanelLayout.keyHorizontalSpacing) / 2)
        XCTAssertEqual(metrics.modifierWidth, metrics.letterWidth * (149 / 111), accuracy: 0.001)
        XCTAssertEqual(metrics.bottomLetterSideGap, metrics.letterWidth * (43 / 111), accuracy: 0.001)
        XCTAssertEqual(metrics.bottomControlWidth, metrics.letterWidth * (142 / 111), accuracy: 0.001)
        XCTAssertEqual(metrics.returnWidth, metrics.letterWidth * (302 / 111), accuracy: 0.001)
    }

    func testConfiguredIdleStateDoesNotPretendToAnalyzeWhenEmpty() {
        let state = KeyboardToolbarState.current(
            hasFullAccess: true,
            isConfigured: true,
            selectedModel: "gemma4:latest",
            isPerformingAIAction: false,
            aiStatus: "AI ready · gemma4:latest"
        )

        XCTAssertEqual(state.kind, .actions(status: "Ready"))
        XCTAssertEqual(state.title, "Open Keyboard AI")
        XCTAssertEqual(state.subtitle, "Ready")
        XCTAssertNotEqual(state.subtitle, "Analyzing")
        XCTAssertTrue(state.isActionEnabled)
        XCTAssertTrue(state.showsBrandMark)
    }

    func testLoadingStateBlocksActions() {
        let state = KeyboardToolbarState.current(
            hasFullAccess: true,
            isConfigured: true,
            selectedModel: "gemma4:latest",
            isPerformingAIAction: true,
            aiStatus: "Fix Grammar…"
        )

        XCTAssertEqual(state.kind, .loading(title: "Fix Grammar…"))
        XCTAssertEqual(state.title, "Fix Grammar…")
        XCTAssertEqual(state.subtitle, "Checking…")
        XCTAssertFalse(state.isActionEnabled)
    }

    func testCorrectionPreviewSubtitleFallsBackToOriginalToReplacement() {
        let state = KeyboardToolbarState(kind: .correctionPreview(
            count: 1,
            explanation: "",
            replacement: "I have an apple.",
            original: "i has a apple"
        ))

        XCTAssertEqual(state.title, "1 writing suggestion")
        XCTAssertEqual(state.subtitle, "i has a apple → I have an apple.")
        XCTAssertFalse(state.isActionEnabled)
        XCTAssertFalse(state.showsBrandMark)
        XCTAssertTrue(state.showsIssueCount)
        XCTAssertEqual(state.issueCount, 1)
    }

    func testCorrectionPreviewPluralizesIssueCount() {
        let state = KeyboardToolbarState(kind: .correctionPreview(
            count: 3,
            explanation: "Spelling and grammar suggestions",
            replacement: "I have an apple.",
            original: "i has a apple"
        ))

        XCTAssertEqual(state.title, "3 writing suggestions")
        XCTAssertTrue(state.showsIssueCount)
        XCTAssertEqual(state.issueCount, 3)
    }
}
