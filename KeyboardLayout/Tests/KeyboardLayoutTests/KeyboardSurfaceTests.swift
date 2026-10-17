import XCTest
@testable import KeyboardLayout

final class KeyboardSurfaceTests: XCTestCase {
    func testEveryModeStaysInsideCompactFloatingDockedAndLandscapeWidths() {
        for width: CGFloat in [0, 100, 240, 288, 320, 381, 390, 808, 1024, 1366] {
            let positions = KeyboardKeyPositions(availableWidth: width)
            for mode: KeyboardInputMode in [.letters, .numbers, .symbols] {
                let rows = [
                    positions.topRow(keyIDs: mode.topRowKeys, keyHeight: 54),
                    positions.middleRow(keyIDs: mode.middleRowKeys, usesInset: mode.usesMiddleRowInset, keyHeight: 54),
                    positions.bottomLetterRow(leadingKeyID: "shift", letterKeyIDs: mode.bottomRowKeys,
                        trailingKeyID: "delete", keyWidth: mode == .symbols ? positions.symbolBottomKeyWidth : nil, keyHeight: 54),
                    positions.controlRow(keyIDs: ["123", "emoji", "space", "return"], keyHeight: 54),
                    positions.controlRow(keyIDs: ["123", "emoji", "globe", "space", "return"], keyHeight: 54)
                ]
                for row in rows {
                    XCTAssertEqual(row.keys.first?.touchFrame.minX, 0)
                    XCTAssertEqual(row.keys.last?.touchFrame.maxX ?? -1, width, accuracy: 0.001)
                    for key in row.keys {
                        XCTAssertGreaterThanOrEqual(key.visualFrame.minX, -0.001)
                        XCTAssertLessThanOrEqual(key.visualFrame.maxX, width + 0.001)
                        XCTAssertGreaterThanOrEqual(key.visualFrame.width, 0)
                        XCTAssertGreaterThanOrEqual(key.touchFrame.width, 0)
                    }
                    for pair in zip(row.keys, row.keys.dropFirst()) {
                        XCTAssertEqual(pair.0.touchFrame.maxX, pair.1.touchFrame.minX, accuracy: 0.001)
                    }
                }
            }
        }
    }
    func testSlotsContributeOnlyWhenPresentAndReplacementKeepsTheSameExtent() {
        XCTAssertEqual(KeyboardSurfaceLayout().preferredHeight, 216)
        let toolbar = KeyboardSurfaceLayout(toolbarHeight: 38, spacing: 10, topPadding: 2, bottomPadding: 1)
        XCTAssertEqual(toolbar.preferredHeight, 267)
        let both = KeyboardSurfaceLayout(contentHeight: 234, accessoryHeight: 30, toolbarHeight: 44, spacing: 4)
        XCTAssertEqual(both.preferredHeight, 316)
        XCTAssertEqual(KeyboardSurfaceLayout(contentHeight: -1, toolbarHeight: .nan).preferredHeight, 0)
        XCTAssertEqual(KeyboardMetrics(rowHeight: 60, rowSpacing: 3).keyGridHeight, 249)
    }
    func testOneShotShiftAndModeChangesEmitOnlyRequestedEdits() {
        var state = KeyboardTypingState()
        XCTAssertNil(state.send(.shift))
        XCTAssertEqual(state.send(.character("a")), .insertText("A"))
        XCTAssertEqual(state.send(.character("b")), .insertText("b"))
        XCTAssertNil(state.send(.numbers))
        XCTAssertEqual(state.mode, .numbers)
        XCTAssertNil(state.send(.symbols))
        XCTAssertEqual(state.mode, .symbols)
        XCTAssertNil(state.send(.numbers))
        XCTAssertEqual(state.mode, .letters)
        XCTAssertEqual(state.send(.space), .space)
        XCTAssertEqual(state.send(.return), .return)
        XCTAssertEqual(state.send(.deleteBackward), .deleteBackward)
    }
    func testSearchTypingCanRemainIndependentOfPreservedDocumentMode() {
        var document = KeyboardTypingState(mode: .symbols, isShiftEnabled: true)
        let original = document
        XCTAssertEqual(document.send(.smileys), .showSmileys)
        var search = KeyboardTypingState()
        XCTAssertEqual(search.send(.character("c")), .insertText("c"))
        XCTAssertNil(search.send(.shift))
        XCTAssertEqual(search.send(.character("a")), .insertText("A"))
        XCTAssertEqual(document, original)
        XCTAssertEqual(document.send(.nextKeyboard), .nextKeyboard)
        XCTAssertEqual(document, original)
    }
}
