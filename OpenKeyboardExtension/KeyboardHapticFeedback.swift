import UIKit

@MainActor
protocol KeyboardHapticFeedbackProviding {
    func keyTapped()
}

/// Keeps the generator alive between keystrokes and ready for the next tap.
@MainActor
final class KeyboardHapticFeedback: KeyboardHapticFeedbackProviding {
    private let generator = UIImpactFeedbackGenerator(style: .light)

    init() {
        generator.prepare()
    }

    func keyTapped() {
        generator.impactOccurred()
        generator.prepare()
    }
}
