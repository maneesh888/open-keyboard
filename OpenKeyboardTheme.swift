//
//  OpenKeyboardTheme.swift
//  OpenKeyboard
//

import SwiftUI

enum OpenKeyboardTheme {
    enum Brand {
        static let blue = Color(red: 0.00, green: 0.38, blue: 0.92)
        static let cyan = Color(red: 0.00, green: 0.66, blue: 0.82)
        static let teal = Color(red: 0.00, green: 0.70, blue: 0.58)
        static let green = Color(red: 0.00, green: 0.72, blue: 0.38)
        static let violet = Color(red: 0.42, green: 0.28, blue: 0.96)
        static let electricCyan = Color(red: 0.00, green: 0.82, blue: 0.95)
        static let blueGreenGradient = LinearGradient(
            colors: [blue, electricCyan, teal, green],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Semantic {
        static let aiReady = Brand.teal
        static let aiAccent = Brand.cyan
        static let primaryAction = Brand.cyan
        static let success = Brand.teal
        static let warning = Color(red: 0.96, green: 0.56, blue: 0.12)
        static let error = Color(red: 0.88, green: 0.16, blue: 0.22)
    }

    enum Surface {
        static let appBackgroundAccent = Brand.cyan.opacity(0.16)
        static let iconBackground = Brand.electricCyan.opacity(0.18)
        static let brandCardBackground = Brand.blue.opacity(0.12)
        static let brandPanelBackground = Brand.electricCyan.opacity(0.18)
        static let brandGlow = Brand.electricCyan.opacity(0.28)
        static let successBackground = Brand.teal.opacity(0.15)
        static let warningBackground = Semantic.warning.opacity(0.14)
        static let errorBackground = Semantic.error.opacity(0.12)
        static let keyboardBackground = Color.clear
        static let toolbarBackground = Brand.blue.opacity(0.14)
        static let panelBackground = Color(.systemBackground)
        static let overlayBackground = Color(.secondarySystemBackground).opacity(0.96)
        static let keyBackground = Color(.systemBackground)
        static let modifierKeyBackground = Color(.systemGray3)
    }

    enum Text {
        static let primary = Color.primary
        static let secondary = Color.secondary
        static let secondaryStrong = Color.primary.opacity(0.68)
        static let inverse = Color.white
    }

    enum Stroke {
        static let subtle = Color.primary.opacity(0.06)
        static let panel = Color.white.opacity(0.45)
        static let control = Color.secondary.opacity(0.24)
    }

    enum Shadow {
        static let card = Color.black.opacity(0.05)
        static let key = Color.black.opacity(0.18)
        static let overlay = Color.black.opacity(0.22)
    }
}


struct OpenKeyboardBrandMark: View {
    var size: CGFloat = 78
    var symbolSize: CGFloat = 32

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)

        Image("OpenKeyboardBrandIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(shape)
            .contentShape(shape)
            .shadow(color: OpenKeyboardTheme.Surface.brandGlow, radius: size * 0.10, x: 0, y: size * 0.05)
            .accessibilityLabel("Open Keyboard app icon")
    }
}
