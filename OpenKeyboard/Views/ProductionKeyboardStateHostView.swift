#if DEBUG
//
//  ProductionKeyboardStateHostView.swift
//  OpenKeyboard
//
//  UI-test-only host for deterministic production-state routing.
//  This app-target view must stay self-contained; the real keyboard extension
//  UI lives in the extension target and is covered by real-extension smoke tests.
//

import SwiftUI

struct ProductionKeyboardStateHostView: View {
    let state: String

    init(state: String) {
        self.state = state
        Self.seedProductionKeyboardState(state)
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Semantic.primaryAction)
                .accessibilityHidden(true)

            Text("Keyboard state route")
                .font(.headline.weight(.bold))

            Text(state)
                .font(.subheadline.monospaced().weight(.semibold))
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                .accessibilityIdentifier("production_keyboard_state_value")

            Text("This deterministic app-target route seeds debug state for tests. Real extension UI acceptance still requires the focused keyboard-extension smoke.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OpenKeyboardTheme.Surface.panelBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("production_keyboard_state_host_\(state)")
    }

    private static func seedProductionKeyboardState(_ state: String) {
        guard let sharedDefaults = AppConfig.sharedDefaults() else { return }
        AppConfig.clear(from: sharedDefaults)
        sharedDefaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        sharedDefaults.set(state, forKey: "keyboardExtension.suggestionState")
        sharedDefaults.synchronize()
    }
}
#endif
