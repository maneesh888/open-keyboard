//
//  ProductionKeyboardStateHostView.swift
//  OpenKeyboard
//
//  UI-test-only host for rendering the actual production KeyboardView states.
//  This is not Preview Lab and should only be reachable with --uitesting.
//

import SwiftUI
import UIKit

struct ProductionKeyboardStateHostView: View {
    let state: String
    @StateObject private var viewModel: KeyboardViewModel

    init(state: String) {
        self.state = state
        Self.seedProductionKeyboardState(state)
        _viewModel = StateObject(wrappedValue: KeyboardViewModel(
            textDocumentProxy: HostKeyboardTextDocumentProxy(initialText: "i has a apple"),
            advanceToNextInputMode: {},
            productionTestState: state,
            productionTestFullAccess: true
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
                .accessibilityHidden(true)

            KeyboardView(viewModel: viewModel)
                .frame(height: 350)
                .accessibilityIdentifier("production_keyboard_state_view")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(OpenKeyboardTheme.Surface.panelBackground)
        .ignoresSafeArea(.keyboard)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("production_keyboard_state_host_\(state)")
        .onAppear {
            viewModel.updateFullAccess(true)
        }
    }

    private static func seedProductionKeyboardState(_ state: String) {
        guard let sharedDefaults = AppConfig.sharedDefaults() else { return }
        let config = AppConfig(
            apiKey: AppConfig.testPlaceholderAPIKey,
            gatewayURL: AppConfig.testPlaceholderGatewayURL,
            selectedModel: AppConfig.testPlaceholderModel,
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
        _ = config.saveTestSeed(to: sharedDefaults)
        sharedDefaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        sharedDefaults.set(state, forKey: "keyboardExtension.suggestionState")
        sharedDefaults.synchronize()
    }
}

private final class HostKeyboardTextDocumentProxy: NSObject, UITextDocumentProxy {
    private var storage: String
    let documentIdentifier = UUID()

    init(initialText: String) {
        self.storage = initialText
        super.init()
    }

    var documentContextBeforeInput: String? { storage }
    var documentContextAfterInput: String? { nil }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var hasText: Bool { !storage.isEmpty }

    func insertText(_ text: String) {
        storage.append(text)
    }

    func deleteBackward() {
        guard !storage.isEmpty else { return }
        storage.removeLast()
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {}

    func setMarkedText(_ markedText: String, selectedRange: NSRange) {
        storage.append(markedText)
    }

    func unmarkText() {}
}
