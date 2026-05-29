import XCTest
@testable import OpenKeyboardCore

final class KeyboardContextTests: XCTestCase {
    func testDocumentContextPreservesBeforeSelectedAndAfterCursor() {
        let context = KeyboardDocumentContext(
            textBeforeCursor: "Hello ",
            selectedText: "world",
            textAfterCursor: "!"
        )

        XCTAssertEqual(context.fullText, "Hello world!")
        XCTAssertEqual(context.promptSourceText, "world")
        XCTAssertTrue(context.hasSelection)
    }

    func testContextAroundCursorIsGraphemeSafe() {
        let context = KeyboardContextExtractor.contextAroundCursor(
            textBeforeCursor: "ab👨‍👩‍👧‍👦",
            textAfterCursor: "🌍cd",
            beforeLimit: 1,
            afterLimit: 1
        )

        XCTAssertEqual(context.textBeforeCursor, "👨‍👩‍👧‍👦")
        XCTAssertEqual(context.textAfterCursor, "🌍")
    }

    func testContextAroundCursorClampsNegativeLimitsToEmptyStrings() {
        let context = KeyboardContextExtractor.contextAroundCursor(
            textBeforeCursor: "before",
            textAfterCursor: "after",
            beforeLimit: -1,
            afterLimit: 0
        )

        XCTAssertEqual(context.textBeforeCursor, "")
        XCTAssertEqual(context.textAfterCursor, "")
    }

    func testReplaceSelectedOnlyChangesSelectedText() {
        let context = KeyboardDocumentContext(
            textBeforeCursor: "Hello ",
            selectedText: "wrld",
            textAfterCursor: "!"
        )

        let result = AITextReplacementStrategy.replaceSelected.apply(to: context, replacement: "world")

        XCTAssertEqual(result, "Hello world!")
    }

    func testReplaceSelectedFallsBackToInsertAtCursorWhenThereIsNoSelection() {
        let context = KeyboardDocumentContext(textBeforeCursor: "Hello", textAfterCursor: " world")

        let result = AITextReplacementStrategy.replaceSelected.apply(to: context, replacement: ",")

        XCTAssertEqual(result, "Hello, world")
    }

    func testInsertAtCursorPreservesSurroundingText() {
        let context = KeyboardDocumentContext(textBeforeCursor: "Hello", textAfterCursor: " world")

        let result = AITextReplacementStrategy.insertAtCursor.apply(to: context, replacement: ",")

        XCTAssertEqual(result, "Hello, world")
    }

    func testReplaceLastSentenceKeepsEarlierSentencesAndAfterCursor() {
        let context = KeyboardDocumentContext(
            textBeforeCursor: "First sentence. second sentence",
            textAfterCursor: " and suffix"
        )

        let result = AITextReplacementStrategy.replaceLastSentence.apply(
            to: context,
            replacement: "Second sentence"
        )

        XCTAssertEqual(result, "First sentence. Second sentence and suffix")
    }


    func testReplaceLastSentenceReplacesCompletedFinalSentence() {
        let context = KeyboardDocumentContext(textBeforeCursor: "First sentence. second sentence.")

        let result = AITextReplacementStrategy.replaceLastSentence.apply(
            to: context,
            replacement: "Second sentence."
        )

        XCTAssertEqual(result, "First sentence. Second sentence.")
    }

    func testReplaceLastSentenceReplacesCompletedFinalSentenceWithTrailingWhitespace() {
        let context = KeyboardDocumentContext(textBeforeCursor: "First sentence. second sentence.  ")

        let result = AITextReplacementStrategy.replaceLastSentence.apply(
            to: context,
            replacement: "Second sentence."
        )

        XCTAssertEqual(result, "First sentence. Second sentence.")
    }

    func testReplaceLastSentenceReplacesSingleCompletedSentence() {
        let context = KeyboardDocumentContext(textBeforeCursor: "wrong sentence.")

        let result = AITextReplacementStrategy.replaceLastSentence.apply(
            to: context,
            replacement: "Right sentence."
        )

        XCTAssertEqual(result, "Right sentence.")
    }

    func testReplaceLastSentenceHandlesEmojiTextWithoutSplittingGraphemeClusters() {
        let context = KeyboardDocumentContext(textBeforeCursor: "Earlier. fix 👨‍👩‍👧‍👦 sentence")

        let result = AITextReplacementStrategy.replaceLastSentence.apply(
            to: context,
            replacement: "Fixed 👨‍👩‍👧‍👦 sentence."
        )

        XCTAssertEqual(result, "Earlier. Fixed 👨‍👩‍👧‍👦 sentence.")
    }

    func testReplaceLastParagraphKeepsPreviousParagraphs() {
        let context = KeyboardDocumentContext(
            textBeforeCursor: "Paragraph one.\n\nparagraph two",
            textAfterCursor: " trailing"
        )

        let result = AITextReplacementStrategy.replaceLastParagraph.apply(
            to: context,
            replacement: "Paragraph two."
        )

        XCTAssertEqual(result, "Paragraph one.\n\nParagraph two. trailing")
    }
}
