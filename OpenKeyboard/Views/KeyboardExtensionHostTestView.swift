#if DEBUG
//
//  KeyboardExtensionHostTestView.swift
//  OpenKeyboard
//

import SwiftUI
import UIKit

struct KeyboardExtensionHostTestView: View {
    @State private var text = ""
    private let autoFocusEditor = ProcessInfo.processInfo.arguments.contains("--keyboard-host-autofocus")

    var body: some View {
        VStack(spacing: 16) {
            Text("Keyboard Extension Host")
                .font(.title2.bold())
                .accessibilityIdentifier("keyboard_host_title")

            Text("Use this plain text area to switch to Open Keyboard and verify the real extension AI bar.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            KeyboardHostTextView(text: $text, autoFocus: autoFocusEditor)
                .frame(minHeight: 180)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .accessibilityIdentifier("keyboard_host_text_editor")

            Spacer()
        }
        .padding(20)
    }
}

private struct KeyboardHostTextView: UIViewRepresentable {
    @Binding var text: String
    let autoFocus: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.spellCheckingType = .no
        textView.keyboardType = .default
        textView.accessibilityIdentifier = "keyboard_host_text_editor"
        if autoFocus {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}
#endif
