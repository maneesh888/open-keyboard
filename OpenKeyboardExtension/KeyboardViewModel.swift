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
    private let aiService: KeyboardAIServiceProviding
    private let loadConfig: () -> AppConfig

    @Published var isShiftEnabled = false
    @Published var isNumbersEnabled = false
    @Published private(set) var config = AppConfig.default
    @Published private(set) var hasFullAccess = false
    @Published private(set) var aiStatus = "Ready"
    @Published private(set) var isPerformingAIAction = false
    @Published private(set) var panelMode: KeyboardPanelMode = .keyboard
    @Published private(set) var suggestionState: KeyboardSuggestionState?
    @Published private(set) var actionError: KeyboardActionErrorState?
    private var composingBuffer = ""

    private enum Keys {
        static let composingBuffer = "keyboardExtension.composingBuffer"
    }

    var canRunAIAction: Bool {
        hasFullAccess && config.isConfigured && !config.apiKey.isEmpty && !isPerformingAIAction
    }

    var currentCorrection: KeyboardCorrectionSuggestion? {
        suggestionState?.currentCorrection
    }

    var toolbarState: KeyboardToolbarState {
        if let actionError {
            return KeyboardToolbarState(kind: .error(message: actionError.message))
        }
        if let suggestionState,
           let correction = suggestionState.currentCorrection {
            return KeyboardToolbarState(kind: .correctionPreview(
                count: suggestionState.remainingCorrectionCount,
                explanation: correction.explanation ?? correction.label,
                replacement: correction.replacement,
                original: correction.original
            ))
        }

        return KeyboardToolbarState.current(
            hasFullAccess: hasFullAccess,
            isConfigured: config.isConfigured,
            selectedModel: config.selectedModel,
            isPerformingAIAction: isPerformingAIAction,
            aiStatus: aiStatus
        )
    }

    init(
        textDocumentProxy: UITextDocumentProxy,
        advanceToNextInputMode: @escaping () -> Void,
        aiService: KeyboardAIServiceProviding = KeyboardAIService(),
        loadConfig: @escaping () -> AppConfig = AppConfig.load,
        productionTestFullAccess: Bool = false
    ) {
        self.textDocumentProxy = textDocumentProxy
        self.advanceToNextInputMode = advanceToNextInputMode
        self.aiService = aiService
        self.loadConfig = loadConfig
        self.config = loadConfig()
        self.composingBuffer = Self.debugStateEnabled ? Self.loadPersistedComposingBuffer() : ""
        self.panelMode = Self.consumeInitialPanelModeSeed()
        self.hasFullAccess = productionTestFullAccess
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

    func clearActionError() {
        actionError = nil
        aiStatus = config.isConfigured ? "Ready" : "Pair gateway in app"
        panelMode = .keyboard
    }

    private func showActionError(_ message: String) {
        let error = KeyboardActionErrorState(message: message)
        actionError = error
        aiStatus = error.message
        isPerformingAIAction = false
        panelMode = .keyboard
    }

    func applyCurrentCorrection() {
        guard var state = suggestionState,
              let updatedText = state.textByApplyingCurrentCorrection(to: currentEditableText()) else {
            dismissCurrentCorrection()
            return
        }
        replaceEditableText(with: updatedText)
        state.applyCurrentCorrection()
        finishCorrectionStep(state)
    }

    func dismissCurrentCorrection() {
        guard var state = suggestionState else { return }
        state.dismissCurrentCorrection()
        finishCorrectionStep(state)
    }

    private func finishCorrectionStep(_ state: KeyboardSuggestionState) {
        suggestionState = state
        if state.currentCorrection == nil {
            suggestionState = nil
            aiStatus = "No more suggestions"
            panelMode = .correctionComplete
        } else {
            aiStatus = "Suggestions ready"
            panelMode = .keyboard
        }
    }

    func updateFullAccess(_ value: Bool) {
        hasFullAccess = value
        reloadConfig()
    }

    func reloadConfig() {
        config = loadConfig()
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
        config = loadConfig()
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
        actionError = nil
        panelMode = .keyboard
        isPerformingAIAction = true
        aiStatus = "\(action.title)…"
        let sanitizedKey = currentConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedURL = currentConfig.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        recordDebugEvent("action_request_start text=\(replacementPlan.textForAI.count) url=\(sanitizedURL) keyLength=\(sanitizedKey.count) model=\(currentConfig.selectedModel)")

        Task {
            do {
                let result = try await aiService.performResult(action: action, on: replacementPlan.textForAI, config: currentConfig)
                await MainActor.run {
                    recordDebugEvent("action_request_success output=\(result.displayText.count) items=\(result.items.count)")
                    switch KeyboardActionResultHandler.outcome(operation: action.operationName, result: result) {
                    case .showCorrections(let response):
                        suggestionState = KeyboardSuggestionState(response: response)
                        aiStatus = "Suggestions ready"
                        isPerformingAIAction = false
                        panelMode = .keyboard
                    case .replaceText(let output):
                        replace(plan: replacementPlan, with: output)
                        aiStatus = action == .summarize ? "Summary ready" : "No more suggestions"
                        isPerformingAIAction = false
                        panelMode = .correctionComplete
                    case .noChanges:
                        suggestionState = nil
                        aiStatus = "No changes needed"
                        isPerformingAIAction = false
                        panelMode = .correctionComplete
                    case .noUsableResult:
                        showActionError("No AI response")
                    }
                }
            } catch {
                await MainActor.run {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    recordDebugEvent("action_request_failed:\(KeyboardActionErrorState.sanitized(message))")
                    showActionError(message)
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
        composingBuffer = finalReplacement
        persistComposingBuffer()
    }

    private func currentEditableText() -> String {
        if let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty {
            return context
        }
        if composingBuffer.isEmpty, Self.debugStateEnabled {
            composingBuffer = Self.loadPersistedComposingBuffer()
        }
        return composingBuffer
    }

    private func replaceEditableText(with replacement: String) {
        let currentText = currentEditableText()
        for _ in currentText {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(replacement)
        composingBuffer = replacement
        persistComposingBuffer()
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
        guard KeyboardDebugStatePolicy.isPersistenceAvailable else { return false }
        return AppConfig.sharedDefaults()?.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled") ?? false
    }
}
