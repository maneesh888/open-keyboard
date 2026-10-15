import XCTest
@testable import KeyboardLayout

final class NumberPadTests: XCTestCase {
    func testEveryVariantPreservesAllDigitsAndDeleteAtStablePositions() {
        for variant in NumberPadVariant.allCases {
            let config = NumberPadConfiguration(variant: variant, decimalSeparator: ",")
            XCTAssertEqual(config.cells.count, 12)
            XCTAssertEqual(Array(config.cells.prefix(9)), (1...9).map { .insertText(String($0)) })
            XCTAssertEqual(config.cells[10], .insertText("0"))
            XCTAssertEqual(config.cells[11], .deleteBackward)
        }
    }

    func testAuxiliaryAndPhoneControlsAreExactAndDoNotReplaceDelete() {
        var config = NumberPadConfiguration(variant: .digits, decimalSeparator: "٫")
        XCTAssertNil(config.cells[9])
        config.variant = .decimal
        XCTAssertEqual(config.cells[9], .insertText("٫"))
        config.decimalSeparator = ""
        XCTAssertNil(config.cells[9])
        config.variant = .phone
        XCTAssertEqual(config.cells[9], .insertText("+"))
        XCTAssertEqual(config.phoneControls, ["*", "#"])
        config.variant = .digits
        XCTAssertTrue(config.phoneControls.isEmpty)
    }

    func testNumberTextIsNotParsedOrReformatted() {
        let config = NumberPadConfiguration(decimalSeparator: ",")
        let input = [10, 10, 0, 9, 1].compactMap { config.cells[$0] }
        let text = input.reduce("") { result, intent in
            if case .insertText(let token) = intent { return result + token }
            return result
        }
        XCTAssertEqual(text, "001,2")
    }

    func testCompactAndWideGeometryIsBoundedWithUsableUtilityTargets() {
        for width: CGFloat in [308, 363, 390, 480, 808, 1024] {
            let metrics = NumberPadGeometry(availableWidth: width)
            XCTAssertLessThanOrEqual(metrics.contentWidth, width)
            XCTAssertLessThanOrEqual(metrics.contentWidth, 480)
            XCTAssertEqual(metrics.cellWidth * 3 + metrics.gap * 2, metrics.contentWidth, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(metrics.rowHeight, 44)
            XCTAssertGreaterThanOrEqual((metrics.contentWidth - metrics.gap * 5) / 6, 44)
            XCTAssertEqual(metrics.height, 264)
        }
    }

    func testDeleteRepeatHasDelayCadenceAndNoCatchUpBurst() {
        var repeatState = DeleteRepeatState()
        repeatState.begin(at: 10)
        XCTAssertFalse(repeatState.shouldRepeat(at: 10.39))
        XCTAssertTrue(repeatState.shouldRepeat(at: 10.4))
        XCTAssertFalse(repeatState.shouldRepeat(at: 10.41))
        XCTAssertTrue(repeatState.shouldRepeat(at: 11))
        XCTAssertFalse(repeatState.shouldRepeat(at: 11))
    }

    func testCancelAndNewPressCannotInheritAnOldRepeatDeadline() {
        var repeatState = DeleteRepeatState()
        repeatState.begin(at: 0)
        repeatState.cancel()
        XCTAssertFalse(repeatState.shouldRepeat(at: 5))
        repeatState.begin(at: 5)
        XCTAssertFalse(repeatState.shouldRepeat(at: 5.1))
        XCTAssertTrue(repeatState.shouldRepeat(at: 5.4))
        repeatState.cancel()
        XCTAssertFalse(repeatState.shouldRepeat(at: 6))
    }
}
