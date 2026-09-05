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
        let state = KeyboardToolbarState(kind: .error(kind: .gatewayUnavailable, message: "Gateway HTTP 500"))

        XCTAssertEqual(state.title, "AI unavailable")
        XCTAssertEqual(state.subtitle, "Gateway HTTP 500")
        XCTAssertFalse(state.isActionEnabled)
        XCTAssertNotEqual(state.subtitle, "Ready")
    }

    func testTypedKeyboardErrorsUseDistinctTitles() {
        XCTAssertEqual(
            KeyboardToolbarState(kind: .error(kind: .timeout, message: "The request exceeded its deadline.")).title,
            "Request timed out"
        )
        XCTAssertEqual(
            KeyboardToolbarState(kind: .error(kind: .authentication, message: "Invalid API key")).title,
            "Invalid API key"
        )
        XCTAssertEqual(
            KeyboardToolbarState(kind: .error(kind: .modelUnavailable, message: "Missing model")).title,
            "Model unavailable"
        )
        let capability = KeyboardToolbarState(kind: .error(
            kind: .modelCapability,
            message: KeyboardActionErrorState.modelCapabilityMessage
        ))
        XCTAssertEqual(capability.title, "Model not compatible")
        XCTAssertEqual(capability.subtitle, KeyboardActionErrorState.modelCapabilityMessage)
        XCTAssertNotEqual(capability.title, "AI unavailable")

        let grammarCapability = KeyboardToolbarState(kind: .error(
            kind: .grammarCapability,
            message: KeyboardActionErrorState.grammarCapabilityMessage
        ))
        XCTAssertEqual(grammarCapability.title, "Model couldn't correct this text")
        XCTAssertEqual(grammarCapability.subtitle, KeyboardActionErrorState.grammarCapabilityMessage)
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

    func testKeyboardLayoutMatchesNativeKeyHeightAndRowPitch() {
        XCTAssertEqual(KeyboardPanelLayout.letterKeyHeight, 54)
        XCTAssertEqual(KeyboardPanelLayout.controlKeyHeight, 54)
        XCTAssertEqual(KeyboardPanelLayout.keyCapHeight, 43)
        XCTAssertEqual(KeyboardPanelLayout.keyRowSpacing, 0)
        XCTAssertEqual(KeyboardPanelLayout.toolbarHeight, 38)
        XCTAssertEqual(KeyboardPanelLayout.toolbarSpacing, 10)
        XCTAssertEqual(KeyboardPanelLayout.outerTopPadding, 2)
        XCTAssertEqual(KeyboardPanelLayout.outerBottomPadding, 1)
        XCTAssertEqual(KeyboardPanelLayout.keyGridHeight, 216)
        XCTAssertEqual(KeyboardPanelLayout.preferredKeyboardHeight, 267)
        XCTAssertEqual(KeyboardPanelLayout.actionPanelHeight, 351)
    }

    func testSecondarySymbolsModeMatchesReferenceLayout() {
        let mode = KeyboardInputMode.symbols

        XCTAssertEqual(mode.topRowKeys, ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="])
        XCTAssertEqual(mode.middleRowKeys, ["_", "\\", "|", "~", "<", ">", "$", "£", "€", "•"])
        XCTAssertEqual(mode.bottomRowKeys, [".", ",", "?", "!", "'"])
        XCTAssertEqual(mode.leadingBottomKeyLabel, "123")
        XCTAssertEqual(mode.bottomControlKeyLabel, "ABC")
        XCTAssertFalse(mode.usesMiddleRowInset)
    }

    func testKeyboardInputModeTransitionsThroughNumbersAndSymbols() {
        XCTAssertEqual(KeyboardInputMode.letters.togglingNumbers, .numbers)
        XCTAssertEqual(KeyboardInputMode.numbers.togglingNumbers, .letters)
        XCTAssertEqual(KeyboardInputMode.numbers.togglingSymbols, .symbols)
        XCTAssertEqual(KeyboardInputMode.symbols.togglingSymbols, .numbers)
        XCTAssertEqual(KeyboardInputMode.symbols.togglingNumbers, .letters)
    }

    func testSecondarySymbolRowsFillTouchAreaWithoutChangingSymbolWidths() throws {
        let positions = KeyboardKeyPositions(availableWidth: 381)
        let mode = KeyboardInputMode.symbols
        let middleRow = positions.middleRow(
            keyIDs: mode.middleRowKeys,
            usesInset: mode.usesMiddleRowInset,
            keyHeight: KeyboardPanelLayout.letterKeyHeight
        )

        XCTAssertEqual(middleRow.keys.first?.visualFrame.minX, 0)
        XCTAssertEqual(middleRow.keys.first?.touchFrame.minX, 0)
        XCTAssertEqual(middleRow.keys.last?.touchFrame.maxX, 381)

        let bottomRow = positions.bottomLetterRow(
            leadingKeyID: "shift",
            letterKeyIDs: mode.bottomRowKeys,
            trailingKeyID: "delete",
            keyWidth: positions.symbolBottomKeyWidth,
            keyHeight: KeyboardPanelLayout.letterKeyHeight
        )
        let firstSymbol = try XCTUnwrap(bottomRow.keys.first(where: { $0.id == "." }))

        XCTAssertEqual(firstSymbol.visualFrame.width, positions.symbolBottomKeyWidth, accuracy: 0.001)
        XCTAssertEqual(bottomRow.keys.first?.touchFrame.minX, 0)
        XCTAssertEqual(bottomRow.keys.last?.touchFrame.maxX, 381)
    }

    func testActionPanelUsesMinimumTapTargetsWithoutGrowingViewport() {
        XCTAssertEqual(KeyboardPanelLayout.actionCarouselButtonHeight, 44)
        XCTAssertEqual(KeyboardPanelLayout.actionControlButtonHeight, 44)
        XCTAssertEqual(KeyboardPanelLayout.actionGroupedButtonWidth, 48)
        XCTAssertEqual(KeyboardPanelLayout.actionPanelScrollableResultHeight, 160)
        XCTAssertEqual(KeyboardPanelLayout.actionContextSelectorHeight, 44)
        XCTAssertEqual(KeyboardPanelLayout.actionContextSelectorSpacing, 8)
        XCTAssertEqual(KeyboardPanelLayout.actionPanelContextualResultHeight, 108)
        XCTAssertEqual(KeyboardPanelLayout.actionPanelHeight, 351)
    }

    func testLetterRowTouchTargetsFillEveryVisualGapWithoutChangingKeyFrames() throws {
        let positions = KeyboardKeyPositions(availableWidth: 381)
        let keyIDs = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
        let row = positions.topRow(keyIDs: keyIDs, keyHeight: KeyboardPanelLayout.letterKeyHeight)

        XCTAssertEqual(row.keys.count, keyIDs.count)
        XCTAssertEqual(row.keys[0].touchFrame.minX, 0)
        XCTAssertEqual(row.keys[row.keys.count - 1].touchFrame.maxX, 381)
        for index in row.keys.indices.dropLast() {
            XCTAssertEqual(
                row.keys[index].touchFrame.maxX,
                row.keys[index + 1].touchFrame.minX,
                accuracy: 0.001
            )
            XCTAssertEqual(row.keys[index].visualFrame.width, positions.letterWidth, accuracy: 0.001)
        }

        let q = try XCTUnwrap(row.keys.first(where: { $0.id == "q" }))
        let w = try XCTUnwrap(row.keys.first(where: { $0.id == "w" }))
        XCTAssertEqual(w.visualFrame.minX - q.visualFrame.maxX, KeyboardKeyPositions.horizontalSpacing, accuracy: 0.001)

        let gapMidpoint = (q.visualFrame.maxX + w.visualFrame.minX) / 2
        XCTAssertEqual(
            row.keyID(at: CGPoint(x: gapMidpoint - 0.01, y: 20)),
            "q"
        )
        XCTAssertEqual(
            row.keyID(at: CGPoint(x: gapMidpoint + 0.01, y: 20)),
            "w"
        )
    }

    func testStaggeredRowsRouteOuterAndModifierGuttersToNearestKey() throws {
        let positions = KeyboardKeyPositions(availableWidth: 381)
        let homeRow = positions.homeRow(
            keyIDs: ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
            keyHeight: KeyboardPanelLayout.letterKeyHeight
        )

        XCTAssertEqual(homeRow.keyID(at: CGPoint(x: 1, y: 20)), "a")
        XCTAssertEqual(homeRow.keyID(at: CGPoint(x: 380, y: 20)), "l")
        XCTAssertEqual(homeRow.keys[0].visualFrame.minX, positions.homeRowInset, accuracy: 0.001)

        let bottomRow = positions.bottomLetterRow(
            leadingKeyID: "shift",
            letterKeyIDs: ["z", "x", "c", "v", "b", "n", "m"],
            trailingKeyID: "delete",
            keyHeight: KeyboardPanelLayout.letterKeyHeight
        )
        let shift = try XCTUnwrap(bottomRow.keys.first(where: { $0.id == "shift" }))
        let z = try XCTUnwrap(bottomRow.keys.first(where: { $0.id == "z" }))
        let gutterMidpoint = (shift.visualFrame.maxX + z.visualFrame.minX) / 2

        XCTAssertEqual(bottomRow.keyID(at: CGPoint(x: gutterMidpoint - 0.01, y: 20)), "shift")
        XCTAssertEqual(bottomRow.keyID(at: CGPoint(x: gutterMidpoint + 0.01, y: 20)), "z")
        XCTAssertEqual(bottomRow.keys[0].touchFrame.minX, 0)
        XCTAssertEqual(bottomRow.keys[bottomRow.keys.count - 1].touchFrame.maxX, 381)
    }

    func testControlRowPreservesWidthsAndRejectsTouchesOutsideItsBounds() throws {
        let positions = KeyboardKeyPositions(availableWidth: 381)
        let row = positions.controlRow(
            keyIDs: ["numbers", "emoji", "space", "return"],
            keyHeight: KeyboardPanelLayout.controlKeyHeight
        )
        let space = try XCTUnwrap(row.keys.first(where: { $0.id == "space" }))

        XCTAssertEqual(space.visualFrame.width, positions.spaceWidth, accuracy: 0.001)
        XCTAssertEqual(row.keyID(at: CGPoint(x: space.visualFrame.midX, y: 20)), "space")
        XCTAssertNil(row.keyID(at: CGPoint(x: -0.1, y: 20)))
        XCTAssertNil(row.keyID(at: CGPoint(x: 381.1, y: 20)))
        XCTAssertNil(row.keyID(at: CGPoint(x: 20, y: KeyboardPanelLayout.controlKeyHeight + 0.1)))
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
