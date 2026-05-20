//
//  KeyboardViewModel.swift
//  OpenKeyboardExtension
//

import SwiftUI
import UIKit

@MainActor
final class KeyboardViewModel: ObservableObject {
    private let textDocumentProxy: UITextDocumentProxy
    private let advanceToNextInputMode: () -> Void

    @Published var isShiftEnabled = false
    @Published private(set) var config = AppConfig.load()

    init(
        textDocumentProxy: UITextDocumentProxy,
        advanceToNextInputMode: @escaping () -> Void
    ) {
        self.textDocumentProxy = textDocumentProxy
        self.advanceToNextInputMode = advanceToNextInputMode
    }

    func insert(_ character: String) {
        let output = isShiftEnabled ? character.uppercased() : character
        textDocumentProxy.insertText(output)

        if isShiftEnabled {
            isShiftEnabled = false
        }
    }

    func insertSpace() {
        textDocumentProxy.insertText(" ")
    }

    func insertReturn() {
        textDocumentProxy.insertText("\n")
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    func toggleShift() {
        isShiftEnabled.toggle()
    }

    func switchKeyboard() {
        advanceToNextInputMode()
    }

    func reloadConfig() {
        config = AppConfig.load()
    }
}
