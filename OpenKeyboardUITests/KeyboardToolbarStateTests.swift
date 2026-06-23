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

    func testConfiguredIdleStateDoesNotPretendToAnalyzeWhenEmpty() {
        let state = KeyboardToolbarState.current(
            hasFullAccess: true,
            isConfigured: true,
            selectedModel: "gemma4:latest",
            isPerformingAIAction: false,
            aiStatus: "AI ready · gemma4:latest"
        )

        XCTAssertEqual(state.kind, .actions(status: "AI ready · gemma4:latest"))
        XCTAssertEqual(state.title, "Open Keyboard AI")
        XCTAssertEqual(state.subtitle, "AI ready · gemma4:latest")
        XCTAssertTrue(state.isActionEnabled)
        XCTAssertTrue(state.showsBrandMark)
    }

    func testKnownZeroIssueStateKeepsLogoButUsesAllGoodStatus() {
        let state = KeyboardToolbarState.current(
            hasFullAccess: true,
            isConfigured: true,
            selectedModel: "gemma4:latest",
            isPerformingAIAction: false,
            aiStatus: "No issues found"
        )

        XCTAssertEqual(state.kind, .actions(status: "No issues found"))
        XCTAssertTrue(state.showsBrandMark)
        XCTAssertTrue(state.isZeroIssueLogoState)
        XCTAssertTrue(state.isActionEnabled)
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
        XCTAssertTrue(state.showsBrandMark)
        XCTAssertFalse(state.showsIssueCount)
        XCTAssertEqual(state.leadingSystemImage, "keyboard")
        XCTAssertFalse(state.isActionEnabled)
    }

    func testCorrectionPreviewSubtitleFallsBackToOriginalToReplacement() {
        let state = KeyboardToolbarState(kind: .correctionPreview(
            count: 1,
            explanation: "",
            replacement: "I have an apple.",
            original: "i has a apple",
            prediction: nil
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
            original: "i has a apple",
            prediction: "apple"
        ))

        XCTAssertEqual(state.title, "3 writing suggestions")
        XCTAssertTrue(state.showsIssueCount)
        XCTAssertEqual(state.issueCount, 3)
        XCTAssertEqual(state.compactCorrection?.label, "Spelling and grammar suggestions")
        XCTAssertEqual(state.compactCorrection?.value, "i has a apple → I have an apple.")
        XCTAssertEqual(state.compactPrediction, "apple")
    }
}
