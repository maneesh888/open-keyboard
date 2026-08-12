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

    func testStructuredSystemPromptRequiresOneJSONObjectAndTreatsInputAsData() {
        XCTAssertTrue(WritingPromptBuilder.structuredSystemPrompt.contains("strict JSON only as one syntactically valid JSON object"))
        XCTAssertTrue(WritingPromptBuilder.structuredSystemPrompt.contains("Never add markdown fences"))
        XCTAssertTrue(WritingPromptBuilder.structuredSystemPrompt.contains("untrusted text data"))
    }

    func testEveryBuiltInPromptContainsStrictContractAndOperationRules() {
        struct Scenario {
            let action: WritingAction
            let operation: String
            let requiredRules: [String]
        }

        let scenarios = [
            Scenario(
                action: .fixGrammar,
                operation: "fix_grammar",
                requiredRules: [
                    "grammar, spelling, capitalization, punctuation, missing words",
                    "one atomic correction result per distinct issue",
                    "Never collapse multiple issues",
                    "type to exactly \"correction\"",
                    "smallest substring needed for that one edit",
                    "full corrected sentence belongs only in corrected_text",
                    "return three correction items",
                    "original and replacement",
                    "empty results array",
                ]
            ),
            Scenario(
                action: .rewrite,
                operation: "rewrite",
                requiredRules: [
                    "clarity, flow, and readability",
                    "preserving the original meaning, facts, tone",
                    "complete rewritten text",
                    "Do not add commentary or invent information",
                ]
            ),
            Scenario(
                action: .summarize,
                operation: "summarize",
                requiredRules: [
                    "using only facts present in the input",
                    "exactly one summary result",
                    "top-level summary",
                    "invented details",
                ]
            ),
            Scenario(
                action: .translate(language: "Arabic"),
                operation: "translate",
                requiredRules: [
                    "Translate into Arabic",
                    "preserving meaning, tone, paragraph breaks, punctuation, and emoji",
                    "exactly one translation result",
                    "complete translated replacement",
                ]
            ),
            Scenario(
                action: .continueWriting,
                operation: "continue_writing",
                requiredRules: [
                    "exact endpoint of the input",
                    "matching its tone, style, tense, and point of view",
                    "only the new continuation",
                    "do not repeat or rewrite the input",
                ]
            ),
        ]

        for scenario in scenarios {
            let input = "Exact input for \(scenario.operation)"
            let prompt = WritingPromptBuilder.prompt(for: scenario.action, text: input)

            XCTAssertTrue(prompt.contains("Operation: \(scenario.operation)"), scenario.operation)
            XCTAssertTrue(prompt.contains("Return strict JSON only"), scenario.operation)
            XCTAssertTrue(prompt.contains("{\"operation\":\"\(scenario.operation)\""), scenario.operation)
            XCTAssertTrue(prompt.contains("The JSON must parse as one object"), scenario.operation)
            XCTAssertTrue(prompt.contains("Every result item must include id, type, title, and text"), scenario.operation)
            XCTAssertTrue(prompt.contains("Do not include markdown fences or any text outside the JSON object"), scenario.operation)
            XCTAssertTrue(prompt.contains("<input_text>\n\(input)\n</input_text>"), scenario.operation)
            for rule in scenario.requiredRules {
                XCTAssertTrue(prompt.localizedCaseInsensitiveContains(rule), "\(scenario.operation) missing rule: \(rule)")
            }
        }
    }

    func testCustomActionUsesTemplateAndTextPlaceholder() {
        let action = WritingAction.custom(id: "friendly", title: "Make Friendly", promptTemplate: "Make this friendly:\n{{text}}")

        XCTAssertEqual(WritingPromptBuilder.prompt(for: action, text: "No."), "Make this friendly:\nNo.")
    }

    func testOnlyBuiltInActionsRequireStructuredJSON() {
        XCTAssertTrue(WritingAction.fixGrammar.requiresStructuredJSON)
        XCTAssertTrue(WritingAction.rewrite.requiresStructuredJSON)
        XCTAssertTrue(WritingAction.summarize.requiresStructuredJSON)
        XCTAssertTrue(WritingAction.translate(language: "Arabic").requiresStructuredJSON)
        XCTAssertTrue(WritingAction.continueWriting.requiresStructuredJSON)
        XCTAssertFalse(WritingAction.custom(id: "plain", title: "Plain", promptTemplate: "Plain").requiresStructuredJSON)
    }

    func testCustomActionWithoutPlaceholderReturnsTemplateUnchanged() {
        let action = WritingAction.custom(id: "plain", title: "Plain", promptTemplate: "Do something specific")

        XCTAssertEqual(WritingPromptBuilder.prompt(for: action, text: "ignored"), "Do something specific")
    }

}
