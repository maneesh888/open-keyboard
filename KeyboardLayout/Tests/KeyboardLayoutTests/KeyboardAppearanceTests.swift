import XCTest
import SwiftUI
@testable import KeyboardLayout

final class KeyboardAppearanceTests: XCTestCase {
    @MainActor
    func testComposedEmojiControlsRenderConsumerForegroundOnDarkSurface() throws {
        let view = KeyboardContentView(typing: .init(), showsSmileys: true, interactionID: UUID(),
            style: .init(key: .black, control: .black, foreground: .red), onTyping: { _ in })
            .frame(width: 320, height: 267).background(.black).environment(\.colorScheme, .light)
        XCTAssertGreaterThan(try redPixels(view), 50, "Search, empty-state and back controls must use the consumer foreground")
    }

    @MainActor
    func testTypingSymbolFontChangesRenderedControlGlyphs() throws {
        func keyboard(_ size: CGFloat) -> some View {
            TypingKeyboardView(state: .init(), showsSystemKeyboardSwitch: true,
                style: .init(key: .black, control: .black, foreground: .red, shadow: .clear,
                             symbolFont: .system(size: size)), onAction: { _ in })
                .frame(width: 381, height: 216).background(.black).environment(\.colorScheme, .light)
        }
        XCTAssertGreaterThan(try redPixels(keyboard(28)), try redPixels(keyboard(10)) + 100,
                             "Modifier and icon glyphs must respond to the public symbol font")
    }

    @MainActor
    private func redPixels<V: View>(_ view: V) throws -> Int {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            if red > 80 && red > green * 2 && red > blue * 2 { count += 1 }
        }
        return count
    }
}
