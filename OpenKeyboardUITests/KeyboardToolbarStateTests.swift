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

        XCTAssertEqual(state.title, "Grammar suggestion")
        XCTAssertEqual(state.subtitle, "i has a apple → I have an apple.")
        XCTAssertFalse(state.isActionEnabled)
    }
}
