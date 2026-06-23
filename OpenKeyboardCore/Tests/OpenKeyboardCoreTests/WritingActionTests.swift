import XCTest
@testable import OpenKeyboardCore

final class WritingActionTests: XCTestCase {
    func testBuiltInActionsHaveStableTitles() {
        XCTAssertEqual(WritingAction.continueWriting.title, "Continue Writing")
        XCTAssertEqual(WritingAction.rewrite.title, "Rewrite")
        XCTAssertEqual(WritingAction.fixGrammar.title, "Fix Grammar & Spelling")
        XCTAssertEqual(WritingAction.summarize.title, "Summarize")
    }

    func testBuiltInActionsHaveStableOperationNames() {
        XCTAssertEqual(WritingAction.continueWriting.operationName, "continue_writing")
        XCTAssertEqual(WritingAction.rewrite.operationName, "rewrite")
        XCTAssertEqual(WritingAction.fixGrammar.operationName, "fix_grammar")
        XCTAssertEqual(WritingAction.summarize.operationName, "summarize")
        XCTAssertEqual(WritingAction.translate(language: "Arabic").operationName, "translate")
        XCTAssertEqual(WritingAction.custom(id: "friendly", title: "Make Friendly", promptTemplate: "{{text}}").operationName, "friendly")
    }

    func testPromptForFixGrammarRequestsStructuredResultsAndPreservesMeaningInstruction() {
        let prompt = WritingPromptBuilder.prompt(for: .fixGrammar, text: "i has a apple")

        XCTAssertTrue(prompt.contains("Operation: fix_grammar"))
        XCTAssertTrue(prompt.contains("structured JSON"))
        XCTAssertTrue(prompt.contains("results array"))
        XCTAssertTrue(prompt.contains("Preserve the original meaning"))
        XCTAssertTrue(prompt.contains("i has a apple"))
    }

    func testPromptForRewriteAsksForImprovedClarity() {
        let prompt = WritingPromptBuilder.prompt(for: .rewrite, text: "This is not good")

        XCTAssertTrue(prompt.contains("Rewrite"))
        XCTAssertTrue(prompt.contains("clarity"))
        XCTAssertTrue(prompt.contains("This is not good"))
    }

    func testCustomActionUsesTemplateAndTextPlaceholder() {
        let action = WritingAction.custom(id: "friendly", title: "Make Friendly", promptTemplate: "Make this friendly:\n{{text}}")

        XCTAssertEqual(WritingPromptBuilder.prompt(for: action, text: "No."), "Make this friendly:\nNo.")
    }

    func testPromptForTranslateIncludesLanguageAndText() {
        let prompt = WritingPromptBuilder.prompt(for: .translate(language: "Arabic"), text: "Good morning")

        XCTAssertTrue(prompt.contains("Translate"))
        XCTAssertTrue(prompt.contains("Arabic"))
        XCTAssertTrue(prompt.contains("Good morning"))
    }

    func testPromptForContinueWritingAsksForContinuationOnly() {
        let prompt = WritingPromptBuilder.prompt(for: .continueWriting, text: "Once upon a time")

        XCTAssertTrue(prompt.contains("Continue writing"))
        XCTAssertTrue(prompt.contains("Return only the continuation"))
        XCTAssertTrue(prompt.contains("Once upon a time"))
    }

    func testCustomActionWithoutPlaceholderReturnsTemplateUnchanged() {
        let action = WritingAction.custom(id: "plain", title: "Plain", promptTemplate: "Do something specific")

        XCTAssertEqual(WritingPromptBuilder.prompt(for: action, text: "ignored"), "Do something specific")
    }

}
