//
//  KeyboardEditorHostPreviewView.swift
//  OpenKeyboard
//
//  Hidden deterministic editor + keyboard preview host for debug-reference-only screenshots. Not valid as acceptance proof.
//

import SwiftUI

struct KeyboardEditorHostPreviewView: View {
    let state: KeyboardPreviewLabState

    var body: some View {
        VStack(spacing: 0) {
            editorArea

            Spacer(minLength: 0)
                .accessibilityHidden(true)

            KeyboardVisualPreviewView(panel: state.previewPanel)
                .frame(height: 350)
                .accessibilityIdentifier("editor_host_keyboard_preview")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(OpenKeyboardTheme.Surface.panelBackground)
        .ignoresSafeArea(.keyboard)
        .accessibilityIdentifier("editor_host_preview")
    }

    private var editorArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Message")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                Spacer()
                Text(state.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
            }

            Text(editorText)
                .font(.body)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                .padding(12)
                .background(OpenKeyboardTheme.Surface.panelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(OpenKeyboardTheme.Stroke.control.opacity(0.75), lineWidth: 1)
                )
                .accessibilityIdentifier("editor_host_text")
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(OpenKeyboardTheme.Surface.brandCardBackground.opacity(0.55))
    }

    private var editorText: String {
        switch state {
        case .correctionCard, .correctionOnly, .predictionOnly, .correctionDetail:
            return "i has a apple"
        case .correctionCardNext:
            return "I has a apple"
        case .correctionComplete:
            return "I have an apple."
        default:
            return "i has a apple"
        }
    }
}
