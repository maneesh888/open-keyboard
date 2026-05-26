import XCTest
@testable import OpenKeyboardCore

final class KeyboardInputReducerTests: XCTestCase {
    func testInsertCharacterAppendsLowercaseByDefault() {
        var state = KeyboardInputState()

        KeyboardInputReducer.apply(.character("a"), to: &state)

        XCTAssertEqual(state.text, "a")
        XCTAssertFalse(state.isShiftEnabled)
    }

    func testShiftUppercasesNextCharacterThenTurnsOff() {
        var state = KeyboardInputState()

        KeyboardInputReducer.apply(.toggleShift, to: &state)
        KeyboardInputReducer.apply(.character("a"), to: &state)

        XCTAssertEqual(state.text, "A")
        XCTAssertFalse(state.isShiftEnabled)
    }

    func testSpaceReturnAndDelete() {
        var state = KeyboardInputState(text: "Hi")

        KeyboardInputReducer.apply(.space, to: &state)
        KeyboardInputReducer.apply(.character("t"), to: &state)
        KeyboardInputReducer.apply(.deleteBackward, to: &state)
        KeyboardInputReducer.apply(.returnKey, to: &state)

        XCTAssertEqual(state.text, "Hi \n")
    }

    func testDeleteOnEmptyTextDoesNothing() {
        var state = KeyboardInputState()

        KeyboardInputReducer.apply(.deleteBackward, to: &state)

        XCTAssertEqual(state.text, "")
    }

    func testContextExtractionLimitsCharactersBeforeCursor() {
        let context = KeyboardContextExtractor.contextBeforeCursor("abcdefghijklmnopqrstuvwxyz", limit: 5)

        XCTAssertEqual(context, "vwxyz")
    }

    func testReplacementStrategyReplaceAll() {
        let result = AITextReplacementStrategy.replaceAll.apply(original: "bad text", replacement: "good text")

        XCTAssertEqual(result, "good text")
    }

    func testReplacementStrategyAppendToCursor() {
        let result = AITextReplacementStrategy.appendToCursor.apply(original: "Hello", replacement: " world")

        XCTAssertEqual(result, "Hello world")
    }

    func testShiftDoesNotResetOnSpaceReturnOrDelete() {
        var state = KeyboardInputState(text: "x", isShiftEnabled: true)

        KeyboardInputReducer.apply(.space, to: &state)
        KeyboardInputReducer.apply(.returnKey, to: &state)
        KeyboardInputReducer.apply(.deleteBackward, to: &state)

        XCTAssertEqual(state.text, "x ")
        XCTAssertTrue(state.isShiftEnabled)
    }

    func testDeleteHandlesEmojiAsSingleCharacter() {
        var state = KeyboardInputState(text: "Hi 👋")

        KeyboardInputReducer.apply(.deleteBackward, to: &state)

        XCTAssertEqual(state.text, "Hi ")
    }

    func testContextExtractionReturnsWholeTextWhenLimitExceedsTextLength() {
        let context = KeyboardContextExtractor.contextBeforeCursor("short", limit: 20)

        XCTAssertEqual(context, "short")
    }

    func testContextExtractionHandlesZeroAndNegativeLimits() {
        XCTAssertEqual(KeyboardContextExtractor.contextBeforeCursor("abc", limit: 0), "")
        XCTAssertEqual(KeyboardContextExtractor.contextBeforeCursor("abc", limit: -1), "")
    }

    func testContextExtractionPreservesEmojiBoundaries() {
        let context = KeyboardContextExtractor.contextBeforeCursor("ab👨‍👩‍👧‍👦", limit: 1)

        XCTAssertEqual(context, "👨‍👩‍👧‍👦")
    }

    func testAppendReplacementPreservesEmptyReplacement() {
        let result = AITextReplacementStrategy.appendToCursor.apply(original: "Hello", replacement: "")

        XCTAssertEqual(result, "Hello")
    }

}
