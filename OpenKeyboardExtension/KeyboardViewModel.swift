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
    private let aiService = KeyboardAIService()

    @Published var isShiftEnabled = false
    @Published var isNumbersEnabled = false
    @Published private(set) var config = AppConfig.load()
    @Published private(set) var hasFullAccess = false
    @Published private(set) var aiStatus = "Ready"
    @Published private(set) var isPerformingAIAction = false
    @Published private(set) var panelMode: KeyboardPanelMode = .keyboard
    private var composingBuffer = ""

    private enum Keys {
        static let composingBuffer = "keyboardExtension.composingBuffer"
    }

    var canRunAIAction: Bool {
        hasFullAccess && config.isConfigured && !config.apiKey.isEmpty && !isPerformingAIAction
    }

    var toolbarState: KeyboardToolbarState {
        KeyboardToolbarState.current(
            hasFullAccess: hasFullAccess,
            isConfigured: config.isConfigured,
            selectedModel: config.selectedModel,
            isPerformingAIAction: isPerformingAIAction,
            aiStatus: aiStatus
        )
    }

    init(
        textDocumentProxy: UITextDocumentProxy,
        advanceToNextInputMode: @escaping () -> Void
    ) {
        self.textDocumentProxy = textDocumentProxy
        self.advanceToNextInputMode = advanceToNextInputMode
        self.composingBuffer = Self.debugStateEnabled ? Self.loadPersistedComposingBuffer() : ""
        self.panelMode = Self.consumeInitialPanelModeSeed()
    }

    func insert(_ character: String) {
        let output = isShiftEnabled ? character.uppercased() : character
        textDocumentProxy.insertText(output)
        composingBuffer.append(output)
        persistComposingBuffer()

        if isShiftEnabled {
            isShiftEnabled = false
        }
    }

    func insertSpace() {
        textDocumentProxy.insertText(" ")
        composingBuffer.append(" ")
        persistComposingBuffer()
    }

    func insertReturn() {
        textDocumentProxy.insertText("\n")
        clearComposingBuffer()
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
        if !composingBuffer.isEmpty {
            composingBuffer.removeLast()
            persistComposingBuffer()
        }
    }

    func toggleShift() {
        isShiftEnabled.toggle()
    }

    func toggleNumbers() {
        isNumbersEnabled.toggle()
        isShiftEnabled = false
    }

    func switchKeyboard() {
        advanceToNextInputMode()
    }

    func showActionPanel() {
        guard canRunAIAction else { return }
        panelMode = .actions
    }

    func showKeyboardPanel() {
        panelMode = .keyboard
    }

    func updateFullAccess(_ value: Bool) {
        hasFullAccess = value
        reloadConfig()
    }

    func reloadConfig() {
        config = AppConfig.load()
        if !hasFullAccess {
            aiStatus = "Enable Allow Full Access"
        } else {
            aiStatus = config.isConfigured ? "AI ready · \(config.selectedModel)" : "Pair gateway in app"
        }
    }

    func performAIAction(_ action: KeyboardAIAction) {
        recordDebugEvent("action_tapped:\(action.rawValue)")
        guard !isPerformingAIAction else {
            recordDebugEvent("action_ignored_busy")
            return
        }
        guard hasFullAccess else {
            aiStatus = "Enable Allow Full Access"
            recordDebugEvent("action_blocked_no_full_access")
            return
        }
        config = AppConfig.load()
        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput
        if composingBuffer.isEmpty, Self.debugStateEnabled {
            composingBuffer = Self.loadPersistedComposingBuffer()
        }
        let fallbackContext = composingBuffer.isEmpty ? nil : composingBuffer
        recordDebugEvent("action_context context=\(contextBeforeInput?.count ?? 0) buffer=\(fallbackContext?.count ?? 0)")
        guard let replacementPlan = KeyboardReplacementPlanner.plan(for: contextBeforeInput) ?? KeyboardReplacementPlanner.plan(for: fallbackContext) else {
            aiStatus = "Type text first"
            recordDebugEvent("action_blocked_no_text")
            return
        }

        let currentConfig = config
        panelMode = .keyboard
        isPerformingAIAction = true
        aiStatus = "\(action.title)…"
        let sanitizedKey = currentConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedURL = currentConfig.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        recordDebugEvent("action_request_start text=\(replacementPlan.textForAI.count) url=\(sanitizedURL) keyLength=\(sanitizedKey.count) model=\(currentConfig.selectedModel)")

        Task {
            do {
                let output = try await aiService.perform(action: action, on: replacementPlan.textForAI, config: currentConfig)
                await MainActor.run {
                    recordDebugEvent("action_request_success output=\(output.count)")
                    replace(plan: replacementPlan, with: output)
                    aiStatus = "No more suggestions"
                    isPerformingAIAction = false
                    panelMode = .correctionComplete
                }
            } catch {
                await MainActor.run {
                    recordDebugEvent("action_request_failed:\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
                    aiStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isPerformingAIAction = false
                }
            }
        }
    }

    private func replace(plan: KeyboardReplacementPlan, with replacement: String) {
        let finalReplacement = plan.replacementText(from: replacement)
        guard !finalReplacement.isEmpty else { return }

        for _ in plan.textToDelete {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(finalReplacement)
        clearComposingBuffer()
    }

    private func persistComposingBuffer() {
        guard Self.debugStateEnabled, let defaults = AppConfig.sharedDefaults() else { return }
        defaults.set(String(composingBuffer.suffix(500)), forKey: Keys.composingBuffer)
        defaults.synchronize()
    }

    private func clearComposingBuffer() {
        composingBuffer.removeAll()
        guard Self.debugStateEnabled, let defaults = AppConfig.sharedDefaults() else { return }
        defaults.removeObject(forKey: Keys.composingBuffer)
        defaults.synchronize()
    }

    private func recordDebugEvent(_ event: String) {
        guard Self.debugStateEnabled, let defaults = AppConfig.sharedDefaults() else { return }
        defaults.set(event, forKey: "keyboardExtension.lastDebugEvent")
        let existing = defaults.string(forKey: "keyboardExtension.debugEvents") ?? ""
        let lines = (existing.isEmpty ? [] : existing.components(separatedBy: "\n")) + [event]
        defaults.set(lines.suffix(20).joined(separator: "\n"), forKey: "keyboardExtension.debugEvents")
        defaults.synchronize()
    }

    private static func loadPersistedComposingBuffer() -> String {
        guard debugStateEnabled else { return "" }
        return AppConfig.sharedDefaults()?.string(forKey: Keys.composingBuffer) ?? ""
    }

    private static func consumeInitialPanelModeSeed() -> KeyboardPanelMode {
        guard debugStateEnabled,
              let defaults = AppConfig.sharedDefaults(),
              let rawValue = defaults.string(forKey: "keyboardExtension.initialPanelMode") else {
            return .keyboard
        }
        defaults.removeObject(forKey: "keyboardExtension.initialPanelMode")
        defaults.synchronize()

        switch rawValue {
        case "actions": return .actions
        case "correctionComplete": return .correctionComplete
        default: return .keyboard
        }
    }

    private static var debugStateEnabled: Bool {
        AppConfig.sharedDefaults()?.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled") ?? false
    }
}
