import XCTest

final class KeyboardReplacementPlannerTests: XCTestCase {
    func testPlansSimpleLine() throws {
        let plan = try XCTUnwrap(KeyboardReplacementPlanner.plan(for: "i has a apple"))
        XCTAssertEqual(plan.textToDelete, "i has a apple")
        XCTAssertEqual(plan.textForAI, "i has a apple")
        XCTAssertEqual(plan.replacementText(from: "I have an apple."), "I have an apple.")
    }

    func testPreservesTrailingSpaceWhileDeletingExactSuffix() throws {
        let plan = try XCTUnwrap(KeyboardReplacementPlanner.plan(for: "i has a apple "))
        XCTAssertEqual(plan.textToDelete, "i has a apple ")
        XCTAssertEqual(plan.textForAI, "i has a apple")
        XCTAssertEqual(plan.trailingWhitespace, " ")
        XCTAssertEqual(plan.replacementText(from: "I have an apple."), "I have an apple. ")
    }

    func testUsesLastLineAndPreservesIndentationAndTrailingSpace() throws {
        let plan = try XCTUnwrap(KeyboardReplacementPlanner.plan(for: "hello\n  i has a apple "))
        XCTAssertEqual(plan.textToDelete, "  i has a apple ")
        XCTAssertEqual(plan.textForAI, "i has a apple")
        XCTAssertEqual(plan.leadingWhitespace, "  ")
        XCTAssertEqual(plan.trailingWhitespace, " ")
        XCTAssertEqual(plan.replacementText(from: "I have an apple."), "  I have an apple. ")
    }

    func testSupportsEmojiGraphemeClusters() throws {
        let plan = try XCTUnwrap(KeyboardReplacementPlanner.plan(for: "i like 👨‍👩‍👧‍👦 "))
        XCTAssertEqual(plan.textToDelete, "i like 👨‍👩‍👧‍👦 ")
        XCTAssertEqual(plan.textForAI, "i like 👨‍👩‍👧‍👦")
        XCTAssertEqual(plan.replacementText(from: "I like 👨‍👩‍👧‍👦."), "I like 👨‍👩‍👧‍👦. ")
    }

    func testPlansCurrentLineAcrossCursor() throws {
        let plan = try XCTUnwrap(KeyboardReplacementPlanner.plan(
            contextBeforeInput: "hello\n  it’s never going to be a penalty, gk can’t have handball",
            contextAfterInput: " in the box\nnext"
        ))
        XCTAssertEqual(plan.textToDelete, "  it’s never going to be a penalty, gk can’t have handball")
        XCTAssertEqual(plan.textAfterCursorToDelete, " in the box")
        XCTAssertEqual(plan.textToReplace, "  it’s never going to be a penalty, gk can’t have handball in the box")
        XCTAssertEqual(plan.textForAI, "it’s never going to be a penalty, gk can’t have handball in the box")
        XCTAssertEqual(plan.leadingWhitespace, "  ")
        XCTAssertEqual(plan.replacementText(from: "It will never be a penalty."), "  It will never be a penalty.")
    }

    func testReturnsNilForWhitespaceOnlyContext() {
        XCTAssertNil(KeyboardReplacementPlanner.plan(for: "   "))
        XCTAssertNil(KeyboardReplacementPlanner.plan(for: "hello\n   "))
        XCTAssertNil(KeyboardReplacementPlanner.plan(for: nil))
        XCTAssertNil(KeyboardReplacementPlanner.plan(contextBeforeInput: "", contextAfterInput: "   "))
    }
}
