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
    private let loadGatewayConnectionError: () -> String?

    @Published var isShiftEnabled = false
    @Published var isNumbersEnabled = false
    @Published private(set) var config = AppConfig.default
    @Published private(set) var hasFullAccess = false
    @Published private(set) var gatewayConnectionError: String?
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
        hasFullAccess
            && gatewayConnectionError == nil
            && hasUsableGatewayConfig
            && !isPerformingAIAction
    }

    private var hasUsableGatewayConfig: Bool {
        config.isConfigured && config.hasCompleteGatewayRuntimeConfig
    }

    var currentCorrection: KeyboardCorrectionSuggestion? {
        suggestionState?.currentCorrection
    }

    var toolbarState: KeyboardToolbarState {
        if let actionError {
            return KeyboardToolbarState(kind: .error(message: actionError.message))
        }
        if let suggestionState,
           let correction = suggestionState.currentCorrection,
           let card = suggestionState.currentCorrectionCard {
            return KeyboardToolbarState(kind: .correctionPreview(
                count: suggestionState.correctionCount,
                explanation: card.categoryTitle,
                replacement: correction.replacement,
                original: correction.original
            ))
        }
        if let gatewayConnectionError {
            return KeyboardToolbarState(kind: .error(message: gatewayConnectionError))
        }

        return KeyboardToolbarState.current(
            hasFullAccess: hasFullAccess,
            isConfigured: hasUsableGatewayConfig,
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
        loadGatewayConnectionError: @escaping () -> String? = AppConfig.sharedGatewayConnectionError,
        productionTestFullAccess: Bool = false
    ) {
        self.textDocumentProxy = textDocumentProxy
        self.advanceToNextInputMode = advanceToNextInputMode
        self.aiService = aiService
        self.loadConfig = loadConfig
        self.loadGatewayConnectionError = loadGatewayConnectionError
        self.config = loadConfig()
        self.gatewayConnectionError = Self.normalizedGatewayConnectionError(loadGatewayConnectionError())
        self.composingBuffer = Self.debugStateEnabled ? Self.loadPersistedComposingBuffer() : ""
        let seededSuggestionState = Self.loadSeededSuggestionState()
        self.suggestionState = seededSuggestionState?.suggestionState
        self.panelMode = seededSuggestionState?.panelMode ?? Self.consumeInitialPanelModeSeed()
        self.aiStatus = seededSuggestionState?.aiStatus ?? self.aiStatus
        self.isPerformingAIAction = seededSuggestionState?.isPerformingAIAction ?? false
        self.hasFullAccess = productionTestFullAccess || seededSuggestionState != nil
        recordConfigVisibilityProbe(context: "init")
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

    func showCorrectionDetail() {
        guard currentCorrection != nil else { return }
        panelMode = .correctionDetail
    }

    func clearActionError() {
        actionError = nil
        aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        panelMode = .keyboard
    }

    func retryAfterActionError() {
        actionError = nil
        aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        panelMode = .actions
    }

    func copyActionErrorDetails() {
        guard let actionError else { return }
        UIPasteboard.general.string = "\(actionError.title): \(actionError.message)"
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

    var currentCorrectionCard: KeyboardCorrectionCard? {
        suggestionState?.currentCorrectionCard
    }

    func moveToPreviousSuggestion() {
        guard var state = suggestionState else { return }
        state.moveToPreviousCorrection()
        suggestionState = state
        panelMode = state.currentCorrection == nil ? .keyboard : .correctionDetail
    }

    func moveToNextSuggestion() {
        guard var state = suggestionState else { return }
        state.moveToNextCorrection()
        suggestionState = state
        panelMode = state.currentCorrection == nil ? .keyboard : .correctionDetail
    }

    private func finishCorrectionStep(_ state: KeyboardSuggestionState) {
        suggestionState = state
        if state.isComplete {
            suggestionState = nil
            aiStatus = "No more suggestions"
            panelMode = .correctionComplete
        } else if state.currentCorrection == nil {
            aiStatus = "Suggestions ready"
            panelMode = .keyboard
        } else {
            aiStatus = "Suggestions ready"
            panelMode = .correctionDetail
        }
    }

    func updateFullAccess(_ value: Bool) {
        hasFullAccess = value
        reloadConfig()
    }

    func reloadConfig() {
        config = loadConfig()
        gatewayConnectionError = Self.normalizedGatewayConnectionError(loadGatewayConnectionError())
        if !hasFullAccess {
            aiStatus = "Enable Allow Full Access"
        } else if let gatewayConnectionError {
            aiStatus = gatewayConnectionError
        } else {
            aiStatus = hasUsableGatewayConfig ? "AI ready · \(config.selectedModel)" : "Pair gateway in app"
        }
    }

    func refreshSeededSuggestionStateForUITests() {
        guard let seededSuggestionState = Self.loadSeededSuggestionState() else { return }
        suggestionState = seededSuggestionState.suggestionState
        panelMode = seededSuggestionState.panelMode
        aiStatus = seededSuggestionState.aiStatus
        isPerformingAIAction = seededSuggestionState.isPerformingAIAction
        if seededSuggestionState.suggestionState != nil {
            hasFullAccess = true
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
        gatewayConnectionError = Self.normalizedGatewayConnectionError(loadGatewayConnectionError())
        if let gatewayConnectionError {
            aiStatus = gatewayConnectionError
            recordDebugEvent("action_blocked_gateway_error")
            return
        }
        guard hasUsableGatewayConfig else {
            aiStatus = "Pair gateway in app"
            recordDebugEvent("action_blocked_not_configured")
            return
        }
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
                        suggestionState = KeyboardSuggestionState(response: response, sourceContext: replacementPlan.textForAI)
                        aiStatus = "Suggestions ready"
                        isPerformingAIAction = false
                        panelMode = .correctionDetail
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

    private func recordConfigVisibilityProbe(context: String) {
        guard Self.debugStateEnabled, let defaults = AppConfig.sharedDefaults() else { return }
        let diagnostic = AppConfig.redactedVisibilityDiagnostic(from: defaults).redactedDescription
        let toolbar = "toolbar.canRunAIAction=\(canRunAIAction); toolbar.actionsEnabled=\(canRunAIAction); toolbar.title=\(toolbarState.title); toolbar.subtitle=\(toolbarState.subtitle); hasFullAccess=\(hasFullAccess); gatewayConnectionErrorPresent=\(gatewayConnectionError != nil)"
        recordDebugEvent("configVisibilityProbe context=\(context); \(diagnostic); \(toolbar)")
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
        case "correctionDetail", "correctionCarousel": return .correctionDetail
        case "correctionComplete": return .correctionComplete
        default: return .keyboard
        }
    }

    private static func loadSeededSuggestionState() -> SeededKeyboardSuggestionState? {
        seededSuggestionStateRawValue().flatMap(SeededKeyboardSuggestionState.init(rawValue:))
    }

    private static func seededSuggestionStateRawValue() -> String? {
        guard KeyboardDebugStatePolicy.isPersistenceAvailable,
              let defaults = AppConfig.sharedDefaults(),
              defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled") else {
            return nil
        }
        defaults.synchronize()
        return defaults.string(forKey: "keyboardExtension.suggestionState")
    }

    private struct SeededKeyboardSuggestionState {
        let panelMode: KeyboardPanelMode
        let suggestionState: KeyboardSuggestionState?
        let aiStatus: String
        let isPerformingAIAction: Bool

        init?(rawValue: String) {
            switch rawValue {
            case "correctionCard", "correctionDetail", "correctionCarousel":
                panelMode = .correctionDetail
                suggestionState = KeyboardSuggestionState(
                    response: Self.carouselResponse,
                    sourceContext: "i has a apple and ths sentence"
                )
                aiStatus = "Suggestions ready"
                isPerformingAIAction = false
            case "correctionComplete":
                panelMode = .correctionComplete
                suggestionState = nil
                aiStatus = "No more suggestions"
                isPerformingAIAction = false
            case "analyzing":
                panelMode = .keyboard
                suggestionState = nil
                aiStatus = "Analyzing your text..."
                isPerformingAIAction = true
            default:
                return nil
            }
        }

        private static var carouselResponse: KeyboardSuggestionResponse {
            KeyboardSuggestionResponse(
                corrections: [
                    KeyboardCorrectionSuggestion(
                        id: "subject-verb",
                        label: "Subject-verb agreement",
                        original: "has",
                        replacement: "have",
                        explanation: "Use have for agreement.",
                        category: "grammar"
                    ),
                    KeyboardCorrectionSuggestion(
                        id: "article",
                        label: "Article",
                        original: "a apple",
                        replacement: "an apple",
                        explanation: "Use an before apple.",
                        category: "grammar"
                    ),
                    KeyboardCorrectionSuggestion(
                        id: "spelling-this",
                        label: "Spelling",
                        original: "ths",
                        replacement: "this",
                        explanation: "Correct the typo.",
                        category: "spelling"
                    )
                ],
                predictions: []
            )
        }
    }

    private static var debugStateEnabled: Bool {
        guard KeyboardDebugStatePolicy.isPersistenceAvailable else { return false }
        return AppConfig.sharedDefaults()?.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled") ?? false
    }

    private static func normalizedGatewayConnectionError(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
