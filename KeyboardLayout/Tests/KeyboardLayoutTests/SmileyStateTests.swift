import XCTest
@testable import KeyboardLayout

final class SmileyStateTests: XCTestCase {
    private let snapshot = SmileySnapshot(sections: [
        .init(id: "faces", label: "Faces", items: [.init(id: "happy", text: "🙂", label: "Smile")]),
        .init(id: "custom", label: "Custom", items: [.init(id: "family", text: "👩🏽‍💻", label: "Technologist")])
    ])

    func testCategorySelectionDoesNotInsertAndActivationIsLiteral() {
        var state = SmileyState(snapshot: snapshot)
        XCTAssertNil(state.send(.selectCategory("custom")))
        XCTAssertEqual(state.send(.activateItem("family")), .insertText("👩🏽‍💻", sectionID: "custom", itemID: "family"))
        XCTAssertEqual(state.selectedCategoryID, "custom")
        XCTAssertNil(state.send(.activateItem("happy")))
        XCTAssertNil(state.send(.selectCategory("missing")))
        XCTAssertEqual(state.selectedCategoryID, "custom")
    }

    func testCategoryMetadataUsesTheCategoryActuallyBrowsed() {
        let item = SmileyItem(id: "happy", text: "🙂", label: "Smile")
        var state = SmileyState(snapshot: .init(sections: [
            .init(id: "recent", label: "Recently Used", items: [item]),
            .init(id: "faces", label: "Faces", items: [item])]))
        _ = state.send(.selectCategory("faces"))
        XCTAssertEqual(state.send(.activateItem("happy")), .insertText("🙂", sectionID: "faces", itemID: "happy"))
        _ = state.send(.beginSearch)
        _ = state.send(.setSearchQuery(" "))
        XCTAssertEqual(state.send(.activateItem("happy")), .insertText("🙂", sectionID: "faces", itemID: "happy"))
    }

    func testScrollSelectionDoesNotRequestAnotherJumpOrInsert() {
        var state = SmileyState(snapshot: snapshot)
        let revision = state.categoryScrollRevision
        XCTAssertNil(state.send(.browseCategory("custom")))
        XCTAssertEqual(state.selectedCategoryID, "custom")
        XCTAssertEqual(state.categoryScrollRevision, revision)
        XCTAssertNil(state.send(.browseCategory("faces")))
        XCTAssertEqual(state.selectedCategoryID, "faces")
        XCTAssertEqual(state.categoryScrollRevision, revision)
        XCTAssertNil(state.send(.selectCategory("faces")))
        XCTAssertEqual(state.categoryScrollRevision, revision + 1, "Tapping the active tab still requests its beginning")
        XCTAssertEqual(state.categoryScrollRequest?.categoryID, "faces")
        _ = state.send(.selectCategory("custom"))
        XCTAssertEqual(state.categoryScrollRequest?.categoryID, "custom")
        _ = state.send(.browseCategory("faces"))
        XCTAssertEqual(state.categoryScrollRequest?.categoryID, "custom", "Swipe observations never request a feedback jump")
        _ = state.send(.beginSearch)
        _ = state.send(.browseCategory("custom"))
        XCTAssertEqual(state.selectedCategoryID, "faces", "Search does not follow browser scroll callbacks")
        _ = state.send(.endSearch)
        _ = state.send(.browseCategory("unknown"))
        XCTAssertEqual(state.selectedCategoryID, "faces")
    }

    func testSnapshotUpdatesPreserveSelectionOrRecover() {
        var state = SmileyState(snapshot: snapshot)
        _ = state.send(.selectCategory("custom"))
        state.update(SmileySnapshot(sections: snapshot.sections.reversed()))
        XCTAssertEqual(state.selectedCategoryID, "custom")
        state.update(SmileySnapshot(sections: [snapshot.sections[0]]))
        XCTAssertEqual(state.selectedCategoryID, "faces")
        state.update(SmileySnapshot(sections: []))
        XCTAssertNil(state.selectedCategoryID)
        XCTAssertNil(state.send(.activateItem("happy")))
        XCTAssertEqual(state.send(.returnToTyping), .returnToTyping)
        XCTAssertEqual(state.send(.deleteBackward), .deleteBackward)
        XCTAssertEqual(state.send(.nextSystemKeyboard), .nextSystemKeyboard)
    }

    func testMalformedAndDuplicateHostContentCannotAmbiguouslyInsert() {
        let item = SmileyItem(id: "x", text: ":-)", label: "Smile")
        let data = SmileySnapshot(sections: [
            .init(id: "", label: "Invalid", items: [item]),
            .init(id: "a", label: "Faces", items: [item, item, .init(id: "empty", text: "", label: "Empty")]),
            .init(id: "a", label: "Duplicate", items: [item])
        ])
        XCTAssertEqual(data.sections.count, 1)
        XCTAssertEqual(data.sections[0].items, [item])
    }

    func testGridFitsCompactAndDockedWidthsWithoutStretchingCells() {
        for width in [280.0, 308, 320, 381, 808, 1180] {
            let metrics = SmileyGridMetrics(availableWidth: width)
            XCTAssertGreaterThanOrEqual(metrics.cellWidth, 44)
            XCTAssertLessThanOrEqual(metrics.cellWidth, 64)
            XCTAssertLessThanOrEqual(Double(metrics.columns) * metrics.cellWidth + Double(metrics.columns - 1) * metrics.spacing, width + 0.001)
        }
        for width in [0.0, -1, .infinity, .nan] {
            let metrics = SmileyGridMetrics(availableWidth: width)
            XCTAssertEqual(metrics.columns, 1)
            XCTAssertEqual(metrics.cellWidth, 0)
        }
    }
}
