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
    @Published private(set) var analysisErrorMessage = "Analysis failed. The selected model did not respond."
    @Published private(set) var suggestionState: KeyboardSuggestionState?
    private var composingBuffer = ""
    private var analysisTask: Task<Void, Never>?
    private let analysisTimeoutSeconds: UInt64 = 20
    private let seededSuggestionState: SeededKeyboardSuggestionState?

    private enum Keys {
        static let composingBuffer = "keyboardExtension.composingBuffer"
    }


    var configProbeAccessibilityValue: String {
#if DEBUG
        sanitizedConfigProbe(context: "accessibility")
#else
        ""
#endif
    }

    var canRunAIAction: Bool {
        hasFullAccess && config.isConfigured && !config.apiKey.isEmpty && !isPerformingAIAction
    }

    var toolbarState: KeyboardToolbarState {
        if let seededSuggestionState, suggestionState == nil {
            return seededSuggestionState.toolbarState
        }

        if let suggestionState,
           let correction = suggestionState.currentCorrection {
            let card = KeyboardCorrectionCard(correction: correction)
            return KeyboardToolbarState(kind: .correctionPreview(
                count: suggestionState.remainingCorrectionCount,
                explanation: card.categoryTitle,
                replacement: correction.replacement,
                original: correction.original,
                prediction: suggestionState.compactPredictionText
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
        productionTestState: String? = nil,
        productionTestFullAccess: Bool = false
    ) {
        self.textDocumentProxy = textDocumentProxy
        self.advanceToNextInputMode = advanceToNextInputMode
        self.aiService = aiService
        self.loadConfig = loadConfig
        self.config = loadConfig()
        self.seededSuggestionState = productionTestState.flatMap(SeededKeyboardSuggestionState.init(rawValue:)) ?? Self.loadSeededSuggestionState()
        self.composingBuffer = Self.debugStateEnabled ? Self.loadPersistedComposingBuffer() : ""
        self.panelMode = seededSuggestionState?.panelMode ?? Self.consumeInitialPanelModeSeed()
        self.suggestionState = seededSuggestionState?.suggestionState
        self.hasFullAccess = productionTestFullAccess
        emitConfigProbe(context: "init")
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

    func handleToolbarLogoTap() {
        if isPerformingAIAction {
            panelMode = .analyzing
            return
        }
        guard canRunAIAction else { return }
        if toolbarState.showsIssueCount {
            panelMode = .correctionDetail
            return
        }
        if aiStatus == "No issues found" || aiStatus == "No more suggestions" {
            panelMode = .allGood
            return
        }
        startAnalysis()
    }

    func retryAnalysis() {
        startAnalysis()
    }

    func showKeyboardPanel() {
        analysisTask?.cancel()
        analysisTask = nil
        if isPerformingAIAction {
            isPerformingAIAction = false
            aiStatus = "Ready"
        }
        panelMode = .keyboard
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
        emitConfigProbe(context: "reloadConfig")
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
                    case .noUsableResult:
                        aiStatus = "Gateway connected, but the selected model returned no usable text."
                        isPerformingAIAction = false
                    }
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


    private func startAnalysis() {
        analysisTask?.cancel()
        let context = currentAnalysisContext()
        guard !context.isEmpty else {
            analysisErrorMessage = "Type text first, then try analysis again."
            aiStatus = "Type text first"
            isPerformingAIAction = false
            panelMode = .analysisFailed
            return
        }

        let currentConfig = config
        analysisErrorMessage = "Analysis failed. The selected model did not respond."
        isPerformingAIAction = true
        aiStatus = "Analyzing your text..."
        panelMode = .keyboard

        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.withTimeout(seconds: self.analysisTimeoutSeconds) {
                    try await self.aiService.analyzeSuggestions(for: context, config: currentConfig)
                }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.isPerformingAIAction = false
                    if response.corrections.isEmpty, response.predictions.isEmpty {
                        self.suggestionState = nil
                        self.aiStatus = "No issues found"
                        self.panelMode = .allGood
                    } else {
                        let state = KeyboardSuggestionState(response: response, sourceContext: context)
                        self.suggestionState = state
                        if state.currentCorrection != nil {
                            self.aiStatus = "Suggestions ready"
                            self.panelMode = .correctionDetail
                        } else {
                            self.aiStatus = "Suggestions ready"
                            self.panelMode = .keyboard
                        }
                    }
                    self.analysisTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isPerformingAIAction = false
                    self.aiStatus = "Ready"
                    self.analysisTask = nil
                }
            } catch {
                await MainActor.run {
                    self.analysisErrorMessage = self.analysisFailureMessage(for: error, model: currentConfig.selectedModel)
                    self.aiStatus = "Analysis failed"
                    self.isPerformingAIAction = false
                    self.panelMode = .analysisFailed
                    self.analysisTask = nil
                    self.recordDebugEvent("analysis_failed:(self.analysisErrorMessage)")
                }
            }
        }
    }

    var currentCorrectionCard: KeyboardCorrectionCard? {
        suggestionState?.currentCorrectionCard
    }

    func applyCurrentSuggestion() {
        guard var state = suggestionState,
              let correction = state.currentCorrection else { return }
        applyCorrection(correction)
        state.applyCurrentCorrection()
        updateSuggestionStateAfterAction(state)
    }

    func dismissCurrentSuggestion() {
        guard var state = suggestionState else { return }
        state.dismissCurrentCorrection()
        updateSuggestionStateAfterAction(state)
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

    private func updateSuggestionStateAfterAction(_ state: KeyboardSuggestionState) {
        if state.isComplete {
            suggestionState = nil
            aiStatus = "No more suggestions"
            panelMode = .correctionComplete
        } else {
            suggestionState = state
            aiStatus = "Suggestions ready"
            panelMode = state.currentCorrection == nil ? .keyboard : .correctionDetail
        }
    }

    private func applyCorrection(_ correction: KeyboardCorrectionSuggestion) {
        let original = correction.original.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = correction.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, !replacement.isEmpty else { return }
        let context = textDocumentProxy.documentContextBeforeInput ?? composingBuffer
        guard context.hasSuffix(original) else { return }
        for _ in original { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(replacement)
        composingBuffer = String((String(context.dropLast(original.count)) + replacement).suffix(500))
        persistComposingBuffer()
    }

    private func currentAnalysisContext() -> String {
        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !contextBeforeInput.isEmpty { return contextBeforeInput }
        if composingBuffer.isEmpty, Self.debugStateEnabled {
            composingBuffer = Self.loadPersistedComposingBuffer()
        }
        return composingBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func withTimeout<T>(seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw KeyboardAIError.timeout
            }
            guard let result = try await group.next() else { throw KeyboardAIError.invalidResponse }
            group.cancelAll()
            return result
        }
    }

    private func analysisFailureMessage(for error: Error, model: String) -> String {
        let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let trimmed = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerModel = model.lowercased()
        let lowerMessage = trimmed.lowercased()

        if lowerModel.contains("apple-foundationmodel") || lowerMessage.contains("foundationmodels") || lowerMessage.contains("generationerror") {
            return "Analysis failed. Apple Foundation model did not respond. Try again or switch to another gateway model."
        }
        if lowerMessage.contains("timed out") || lowerMessage.contains("timeout") {
            return "Analysis timed out. Try again or choose a faster model."
        }
        if lowerMessage.contains("model") || lowerMessage.contains("gateway") || lowerMessage.contains("api key") || lowerMessage.contains("network") || lowerMessage.contains("url") {
            return trimmed.hasPrefix("Analysis") ? trimmed : "Analysis failed. \(trimmed)"
        }
        return "Analysis failed. The selected model returned no usable correction. Try again or switch models."
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



    private func sanitizedConfigProbe(context: String) -> String {
#if DEBUG
        let defaults = AppConfig.sharedDefaults()
        let legacyAPIKeyPresent = !(defaults?.string(forKey: AppConfig.apiKeyKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let keychainAPIKeyPresent = !(AppConfig.secretStore.loadAPIKey() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let gatewayURL = sanitizedGatewayURL(config.gatewayURL)
        let toolbarReason: String
        if !hasFullAccess {
            toolbarReason = "fullAccessRequired"
        } else if !config.isConfigured {
            toolbarReason = "notConfigured"
        } else if isPerformingAIAction {
            toolbarReason = "loading"
        } else {
            toolbarReason = "actions"
        }

        return [
            "context=\(context)",
            "debugFlag=\(Self.debugStateEnabled)",
            "appGroupSuite=\(AppConfig.appGroupIdentifier)",
            "sharedDefaultsAvailable=\(defaults != nil)",
            "gatewayURL=\(gatewayURL)",
            "selectedModel=\(config.selectedModel.isEmpty ? "<empty>" : config.selectedModel)",
            "appConfigIsConfigured=\(config.isConfigured)",
            "legacyDefaultsAPIKeyPresent=\(legacyAPIKeyPresent)",
            "keychainAPIKeyPresent=\(keychainAPIKeyPresent)",
            "loadedAPIKeyPresent=\(!config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)",
            "hasFullAccess=\(hasFullAccess)",
            "toolbarReason=\(toolbarReason)",
            "toolbarTitle=\(toolbarState.title)"
        ].joined(separator: "\n")
#else
        return ""
#endif
    }

    private func emitConfigProbe(context: String) {
#if DEBUG
        let probe = sanitizedConfigProbe(context: context)
        NSLog("Keyboard config probe: \(probe.replacingOccurrences(of: "\n", with: "; "))")

        guard let defaults = AppConfig.sharedDefaults() else {
            NSLog("Keyboard config probe storage: sharedDefaultsAvailable=false context=\(context)")
            return
        }

        defaults.set(probe, forKey: "keyboardExtension.configProbe")
        defaults.synchronize()
#endif
    }

    private func sanitizedGatewayURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "<empty>" }
        guard var components = URLComponents(string: trimmed) else { return "<invalid-or-non-url-present>" }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "<url-present>"
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

    nonisolated private static let seededSubjectVerbCorrection = KeyboardCorrectionSuggestion(
        id: "seed-subject-verb",
        label: "Subject-verb agreement",
        original: "i has",
        replacement: "I have",
        explanation: "Use “I have” for first-person agreement.",
        category: "grammar"
    )

    nonisolated private static let seededArticleCorrection = KeyboardCorrectionSuggestion(
        id: "seed-article",
        label: "Article",
        original: "a apple",
        replacement: "an apple",
        explanation: "Use “an” before a vowel sound.",
        category: "grammar"
    )

    nonisolated private static let seededSpellingCorrection = KeyboardCorrectionSuggestion(
        id: "seed-spelling",
        label: "Spelling",
        original: "ths",
        replacement: "this",
        explanation: "Correct the misspelling.",
        category: "spelling"
    )

    nonisolated private static var seededMultiCorrectionState: KeyboardSuggestionState {
        KeyboardSuggestionState(response: KeyboardSuggestionResponse(
            corrections: [seededSubjectVerbCorrection, seededArticleCorrection, seededSpellingCorrection],
            predictions: []
        ))
    }

    private static func loadPersistedComposingBuffer() -> String {
        guard debugStateEnabled else { return "" }
        return AppConfig.sharedDefaults()?.string(forKey: Keys.composingBuffer) ?? ""
    }

    private static func loadSeededSuggestionState() -> SeededKeyboardSuggestionState? {
        guard debugStateEnabled,
              let rawValue = AppConfig.sharedDefaults()?.string(forKey: "keyboardExtension.suggestionState") else { return nil }
        return SeededKeyboardSuggestionState(rawValue: rawValue)
    }

    private enum SeededKeyboardSuggestionState: String {
        case correctionCard
        case correctionOnly
        case correctionComplete
        case allGood
        case analysisFailed
        case analyzing
        case correctionDetail
        case correctionCarousel
        case ready

        var panelMode: KeyboardPanelMode {
            switch self {
            case .correctionDetail, .correctionCarousel: return .correctionDetail
            case .correctionComplete: return .correctionComplete
            case .allGood: return .allGood
            case .analysisFailed: return .analysisFailed
            case .analyzing: return .analyzing
            case .ready: return .keyboard
            default: return .keyboard
            }
        }

        var suggestionState: KeyboardSuggestionState? {
            switch self {
            case .correctionDetail:
                return KeyboardSuggestionState(response: KeyboardSuggestionResponse(corrections: [KeyboardViewModel.seededSubjectVerbCorrection], predictions: []))
            case .correctionCarousel:
                return KeyboardViewModel.seededMultiCorrectionState
            default:
                return nil
            }
        }

        var toolbarState: KeyboardToolbarState {
            switch self {
            case .correctionCard:
                return KeyboardToolbarState(kind: .correctionPreview(count: 3, explanation: "Correct capitalization", replacement: "I", original: "i", prediction: nil))
            case .correctionOnly:
                return KeyboardToolbarState(kind: .correctionPreview(count: 1, explanation: "Correct article", replacement: "an", original: "a", prediction: nil))
            case .correctionDetail:
                let card = KeyboardCorrectionCard(correction: KeyboardViewModel.seededSubjectVerbCorrection)
                return KeyboardToolbarState(kind: .correctionPreview(count: 1, explanation: card.categoryTitle, replacement: card.replacement, original: card.original, prediction: nil))
            case .correctionCarousel:
                let card = KeyboardCorrectionCard(correction: KeyboardViewModel.seededSubjectVerbCorrection)
                return KeyboardToolbarState(kind: .correctionPreview(count: 3, explanation: card.categoryTitle, replacement: card.replacement, original: card.original, prediction: nil))
            case .correctionComplete:
                return KeyboardToolbarState(kind: .actions(status: "No more suggestions"))
            case .allGood:
                return KeyboardToolbarState(kind: .actions(status: "No issues found"))
            case .analysisFailed:
                return KeyboardToolbarState(kind: .actions(status: "Analysis failed"))
            case .analyzing:
                return KeyboardToolbarState(kind: .actions(status: "Analyzing"))
            case .ready:
                return KeyboardToolbarState(kind: .actions(status: "AI ready · ui-test-model"))
            }
        }
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
        case "allGood": return .allGood
        case "analysisFailed": return .analysisFailed
        case "analyzing": return .analyzing
        default: return .keyboard
        }
    }

    private static var debugStateEnabled: Bool {
        guard KeyboardDebugStatePolicy.isPersistenceAvailable else { return false }
        return AppConfig.sharedDefaults()?.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled") ?? false
    }
}
