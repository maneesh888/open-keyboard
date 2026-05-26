import XCTest
@testable import OpenKeyboardCore

final class WritingActionTests: XCTestCase {
    func testBuiltInActionsHaveStableTitles() {
        XCTAssertEqual(WritingAction.continueWriting.title, "Continue Writing")
        XCTAssertEqual(WritingAction.rewrite.title, "Rewrite")
        XCTAssertEqual(WritingAction.fixGrammar.title, "Fix Grammar & Spelling")
        XCTAssertEqual(WritingAction.summarize.title, "Summarize")
    }

    func testPromptForFixGrammarPreservesMeaningInstruction() {
        let prompt = WritingPromptBuilder.prompt(for: .fixGrammar, text: "i has a apple")

        XCTAssertTrue(prompt.contains("Fix grammar and spelling"))
        XCTAssertTrue(prompt.contains("preserve the original meaning"))
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
