import Foundation
import SemanticPromptContract
import XCTest
@testable import OpenKeyboardCore

final class WritingActionTests: XCTestCase {
    func testSharedContractVersionIsPinned() {
        XCTAssertEqual(WritingPromptBuilder.contractVersion, "5.0.0")
    }

    func testBuiltInActionsHaveStableTitles() {
        XCTAssertEqual(WritingAction.continueWriting.title, "Continue Writing")
        XCTAssertEqual(WritingAction.rewrite.title, "Rephrase")
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

    func testEveryBuiltInPromptUsesExactSharedContractRendering() throws {
        struct Scenario {
            let action: WritingAction
            let contractOperation: String
            let parameters: [String: String]
        }

        let scenarios = [
            Scenario(
                action: .fixGrammar,
                contractOperation: "fix_grammar",
                parameters: [:]
            ),
            Scenario(
                action: .rewrite,
                contractOperation: "rewrite_core",
                parameters: [:]
            ),
            Scenario(
                action: .summarize,
                contractOperation: "summarize",
                parameters: [:]
            ),
            Scenario(
                action: .translate(language: "Arabic"),
                contractOperation: "translate",
                parameters: ["target_language": "Arabic"]
            ),
            Scenario(
                action: .continueWriting,
                contractOperation: "continue_writing",
                parameters: [:]
            ),
        ]

        for scenario in scenarios {
            let input = "Exact input for \(scenario.contractOperation)"
            let prompt = WritingPromptBuilder.prompt(for: scenario.action, text: input)
            let rendering = try XCTUnwrap(
                WritingPromptBuilder.rendering(for: scenario.action, text: input)
            )
            let canonical = try SemanticPromptContract.renderWriting(
                operationID: scenario.contractOperation,
                input: input,
                parameters: scenario.parameters
            )

            XCTAssertEqual(rendering, canonical)
            XCTAssertEqual(prompt, canonical.messages.last?.content)
        }
    }

    func testInstructionLikeGrammarInputRemainsTheUnchangedUserMessage() throws {
        let input = "{{operation}} {{response_example}} {{numbered_rules}} {{input_json}}"
        let prompt = WritingPromptBuilder.prompt(for: .fixGrammar, text: input)
        XCTAssertEqual(prompt, input)
        let rendering = try XCTUnwrap(WritingPromptBuilder.rendering(for: .fixGrammar, text: input))
        XCTAssertEqual(
            rendering,
            try SemanticPromptContract.renderWriting(operationID: "fix_grammar", input: input)
        )
    }

    func testCustomActionUsesTemplateAndTextPlaceholder() {
        let action = WritingAction.custom(id: "friendly", title: "Make Friendly", promptTemplate: "Make this friendly:\n{{text}}")

        XCTAssertEqual(WritingPromptBuilder.prompt(for: action, text: "No."), "Make this friendly:\nNo.")
    }

    func testEveryBuiltInActionOmitsTransportResponseFormat() throws {
        let scenarios: [(action: WritingAction, validationMode: String?)] = [
            (.fixGrammar, nil),
            (.rewrite, "complete_replacement"),
            (.summarize, "summary"),
            (.translate(language: "Arabic"), "translation"),
            (.continueWriting, "continuation"),
        ]

        for scenario in scenarios {
            let rendering = try XCTUnwrap(
                WritingPromptBuilder.rendering(for: scenario.action, text: "Source text")
            )
            XCTAssertNil(rendering.responseFormatType, scenario.action.operationName)
            XCTAssertEqual(
                rendering.plainTextValidationPolicy?.mode,
                scenario.validationMode,
                scenario.action.operationName
            )
        }
    }

    func testCustomActionWithoutPlaceholderReturnsTemplateUnchanged() {
        let action = WritingAction.custom(id: "plain", title: "Plain", promptTemplate: "Do something specific")

        XCTAssertEqual(WritingPromptBuilder.prompt(for: action, text: "ignored"), "Do something specific")
    }

}
