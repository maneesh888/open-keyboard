import XCTest
import SwiftUI

final class OpenKeyboardThemeTests: XCTestCase {
    func testBrandPaletteHasDistinctBlueAndGreen() {
        XCTAssertNotEqual(OpenKeyboardTheme.Brand.blue.description, OpenKeyboardTheme.Brand.green.description)
        XCTAssertNotEqual(OpenKeyboardTheme.Brand.cyan.description, OpenKeyboardTheme.Brand.green.description)
    }

    func testSemanticStatusColorsUseThemeTokens() {
        XCTAssertEqual(OpenKeyboardTheme.Semantic.aiReady.description, OpenKeyboardTheme.Brand.teal.description)
        XCTAssertEqual(OpenKeyboardTheme.Semantic.success.description, OpenKeyboardTheme.Brand.teal.description)
        XCTAssertEqual(OpenKeyboardTheme.Semantic.primaryAction.description, OpenKeyboardTheme.Brand.cyan.description)
        XCTAssertNotEqual(OpenKeyboardTheme.Semantic.warning.description, OpenKeyboardTheme.Semantic.error.description)
    }

    func testKeyboardSurfacesAreCentralized() {
        XCTAssertFalse(OpenKeyboardTheme.Surface.keyboardBackground.description.isEmpty)
        XCTAssertFalse(OpenKeyboardTheme.Surface.toolbarBackground.description.isEmpty)
        XCTAssertFalse(OpenKeyboardTheme.Surface.keyBackground.description.isEmpty)
        XCTAssertFalse(OpenKeyboardTheme.Surface.modifierKeyBackground.description.isEmpty)
    }
}
