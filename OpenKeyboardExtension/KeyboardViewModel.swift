//
//  KeyboardViewModel.swift
//  OpenKeyboardExtension
//

import SwiftUI
import UIKit

enum KeyboardRewriteOptionsIntent: Equatable {
    case improve
    case rephrase

    var headerTitle: String {
        switch self {
        case .improve: return "Choose an improvement"
        case .rephrase: return "Choose a rephrase"
        }
    }

    var sourceLabel: String {
        switch self {
        case .improve: return "Original"
        case .rephrase: return "Original"
        }
    }

    var toolbarStatusSingular: String {
        switch self {
        case .improve: return "1 improvement"
        case .rephrase: return "1 rewrite option"
        }
    }

    func toolbarStatus(count: Int) -> String {
        switch self {
        case .improve: return count == 1 ? toolbarStatusSingular : "\(count) improvements"
        case .rephrase: return count == 1 ? toolbarStatusSingular : "\(count) rewrite options"
        }
    }

    func readyStatus(count: Int) -> String {
        switch self {
        case .improve: return count == 1 ? "Improvement ready" : "\(count) improvements ready"
        case .rephrase: return count == 1 ? "Rewrite ready" : "\(count) rewrites ready"
        }
    }

    var completionState: KeyboardCompletionPanelState {
        switch self {
        case .improve: return .improvementApplied
        case .rephrase: return .rewriteApplied
        }
    }

    var appliedStatus: String {
        switch self {
        case .improve: return "Improvement applied"
        case .rephrase: return "Rewrite applied"
        }
    }
}

struct KeyboardRewriteOptionsState: Equatable {
    let intent: KeyboardRewriteOptionsIntent
    let sourceText: String
    let replacementPlan: KeyboardReplacementPlan
    let options: [KeyboardRewriteOption]
    var selectedOptionID: String
    var isCarouselVisible: Bool

    init(
        intent: KeyboardRewriteOptionsIntent = .rephrase,
        sourceText: String,
        replacementPlan: KeyboardReplacementPlan,
        options: [KeyboardRewriteOption],
        isCarouselVisible: Bool = true
    ) {
        self.intent = intent
        self.sourceText = sourceText
        self.replacementPlan = replacementPlan
        self.options = options
        self.selectedOptionID = options.first?.id ?? ""
        self.isCarouselVisible = isCarouselVisible
    }

    var selectedOption: KeyboardRewriteOption? {
        options.first { $0.id == selectedOptionID } ?? options.first
    }

    mutating func selectOption(id: String) {
        guard options.contains(where: { $0.id == id }) else { return }
        selectedOptionID = id
    }

    mutating func toggleCarouselVisibility() {
        isCarouselVisible.toggle()
    }
}

struct KeyboardActionPanelState: Equatable {
    let sourceText: String
    let replacementPlan: KeyboardReplacementPlan
    var selectedAction: KeyboardAIAction
    var options: [KeyboardRewriteOption]
    var selectedOptionID: String
    var isCarouselVisible: Bool
    var isLoading: Bool

    static let availableActions: [KeyboardAIAction] = [.improve, .rewrite, .summarize]

    init(
        sourceText: String,
        replacementPlan: KeyboardReplacementPlan,
        selectedAction: KeyboardAIAction = .improve,
        options: [KeyboardRewriteOption] = [],
        isCarouselVisible: Bool = true,
        isLoading: Bool = false
    ) {
        self.sourceText = sourceText
        self.replacementPlan = replacementPlan
        self.selectedAction = selectedAction
        self.options = options
        self.selectedOptionID = options.first?.id ?? ""
        self.isCarouselVisible = isCarouselVisible
        self.isLoading = isLoading
    }

    init(sourceText: String, selectedAction: KeyboardAIAction = .improve) {
        self.init(
            sourceText: sourceText,
            replacementPlan: KeyboardReplacementPlan(
                textToDelete: sourceText,
                textForAI: sourceText,
                leadingWhitespace: "",
                trailingWhitespace: ""
            ),
            selectedAction: selectedAction
        )
    }

    var selectedOption: KeyboardRewriteOption? {
        options.first { $0.id == selectedOptionID } ?? options.first
    }

    mutating func selectAction(_ action: KeyboardAIAction) {
        guard Self.availableActions.contains(action) else { return }
        selectedAction = action
        beginLoading()
    }

    mutating func beginLoading() {
        options = []
        selectedOptionID = ""
        isLoading = true
    }

    mutating func finishLoading(options: [KeyboardRewriteOption]) {
        self.options = options
        selectedOptionID = options.first?.id ?? ""
        isLoading = false
    }

    mutating func selectOption(id: String) {
        guard options.contains(where: { $0.id == id }) else { return }
        selectedOptionID = id
    }

    mutating func toggleCarouselVisibility() {
        isCarouselVisible.toggle()
    }
}

@MainActor
final class KeyboardViewModel: ObservableObject {
    private let textDocumentProxy: UITextDocumentProxy
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
    @Published private(set) var actionPanelState: KeyboardActionPanelState?
    @Published private(set) var suggestionState: KeyboardSuggestionState?
    @Published private(set) var rewriteOptionsState: KeyboardRewriteOptionsState?
    @Published private(set) var actionError: KeyboardActionErrorState?
    @Published private(set) var completionPanelState = KeyboardCompletionPanelState.allDone
    @Published private(set) var isGrammarCorrectionLoading = false
    @Published private var hasNoIssueAnalysisResult = false
    private var composingBuffer = ""
    private var automaticAnalysisTask: Task<Void, Never>?
    private var grammarCorrectionTask: Task<Void, Never>?
    private var grammarCorrectionRequestID: UUID?
    private var actionPanelTask: Task<Void, Never>?
    private var shouldResumeAutomaticAnalysisOnKeyboardReturn = false
    private let automaticAnalysisDelayNanoseconds: UInt64
    private var lastAnalyzedText: String?

    private enum Keys {
        static let composingBuffer = "keyboardExtension.composingBuffer"
        static let initialPanelMode = "keyboardExtension.initialPanelMode"
        static let initialPanelModeSeedID = "keyboardExtension.initialPanelModeSeedID"
        static let initialPanelModeSeededAt = "keyboardExtension.initialPanelModeSeededAt"
        static let suggestionState = "keyboardExtension.suggestionState"
        static let suggestionStateSeedID = "keyboardExtension.suggestionStateSeedID"
        static let suggestionStateSeededAt = "keyboardExtension.suggestionStateSeededAt"
        static let uiTestDebugStateEnabled = "keyboardExtension.uiTestDebugStateEnabled"
    }

    private static let uiTestSeedMaximumAge: TimeInterval = 30

    var canRunAIAction: Bool {
        hasFullAccess
            && gatewayConnectionError == nil
            && hasUsableGatewayConfig
            && !isPerformingAIAction
    }

    var canOpenActionPanel: Bool {
        hasFullAccess
            && gatewayConnectionError == nil
            && hasUsableGatewayConfig
            && !isManualActionInFlight
    }

    private var hasUsableGatewayConfig: Bool {
        config.isConfigured && config.hasCompleteGatewayRuntimeConfig
    }

    private var isManualActionInFlight: Bool {
        isPerformingAIAction && aiStatus != "Analyzing…"
    }

    var canOpenAnalysisResult: Bool {
        currentCorrection != nil || hasNoIssueAnalysisResult
    }

    var canOpenGrammarCorrection: Bool {
        !hasHardGrammarCorrectionBlocker
    }

    private var hasHardGrammarCorrectionBlocker: Bool {
        !hasFullAccess
            || gatewayConnectionError != nil
            || !hasUsableGatewayConfig
            || actionError != nil
    }

    var currentCorrection: KeyboardCorrectionSuggestion? {
        suggestionState?.currentCorrection
    }

    var toolbarState: KeyboardToolbarState {
        if let actionError {
            return KeyboardToolbarState(kind: .error(message: actionError.message))
        }
        if let rewriteOptionsState {
            let status = rewriteOptionsState.intent.toolbarStatus(count: rewriteOptionsState.options.count)
            return KeyboardToolbarState(kind: .actions(status: status))
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
        aiService: KeyboardAIServiceProviding = KeyboardAIService(),
        loadConfig: @escaping () -> AppConfig = AppConfig.load,
        loadGatewayConnectionError: @escaping () -> String? = AppConfig.sharedGatewayConnectionError,
        productionTestFullAccess: Bool = false,
        automaticAnalysisDelayNanoseconds: UInt64 = 2_500_000_000
    ) {
        self.textDocumentProxy = textDocumentProxy
        self.aiService = aiService
        self.loadConfig = loadConfig
        self.loadGatewayConnectionError = loadGatewayConnectionError
        self.automaticAnalysisDelayNanoseconds = automaticAnalysisDelayNanoseconds
        self.config = loadConfig()
        self.gatewayConnectionError = Self.normalizedGatewayConnectionError(loadGatewayConnectionError())
        self.composingBuffer = Self.debugStateEnabled ? Self.loadPersistedComposingBuffer() : ""
        let seededSuggestionState = Self.loadSeededSuggestionState()
        self.suggestionState = seededSuggestionState?.suggestionState
        self.rewriteOptionsState = seededSuggestionState?.rewriteOptionsState
        self.panelMode = seededSuggestionState?.panelMode ?? Self.consumeInitialPanelModeSeed()
        self.aiStatus = seededSuggestionState?.aiStatus ?? self.aiStatus
        self.isPerformingAIAction = seededSuggestionState?.isPerformingAIAction ?? false
        self.hasNoIssueAnalysisResult = seededSuggestionState?.hasNoIssueAnalysisResult ?? false
        self.completionPanelState = seededSuggestionState?.completionPanelState ?? .allDone
        self.hasFullAccess = productionTestFullAccess || seededSuggestionState != nil
        recordConfigVisibilityProbe(context: "init")
    }

    func insert(_ character: String) {
        let output = isShiftEnabled ? character.uppercased() : character
        textDocumentProxy.insertText(output)
        composingBuffer.append(output)
        persistComposingBuffer()
        scheduleAutomaticAnalysisAfterTextChange()

        if isShiftEnabled {
            isShiftEnabled = false
        }
    }

    func insertSpace() {
        textDocumentProxy.insertText(" ")
        composingBuffer.append(" ")
        persistComposingBuffer()
        scheduleAutomaticAnalysisAfterTextChange()
    }

    func insertReturn() {
        textDocumentProxy.insertText("\n")
        clearComposingBuffer()
        clearAutomaticAnalysisState()
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
        if !composingBuffer.isEmpty {
            composingBuffer.removeLast()
            persistComposingBuffer()
        }
        scheduleAutomaticAnalysisAfterTextChange()
    }

    func toggleShift() {
        isShiftEnabled.toggle()
    }

    func toggleNumbers() {
        isNumbersEnabled.toggle()
        isShiftEnabled = false
    }

    func showActionPanel() {
        guard canOpenActionPanel else { return }
        automaticAnalysisTask?.cancel()
        automaticAnalysisTask = nil
        grammarCorrectionTask?.cancel()
        grammarCorrectionTask = nil
        grammarCorrectionRequestID = nil
        isGrammarCorrectionLoading = false
        if isPerformingAIAction, aiStatus == "Analyzing…" {
            isPerformingAIAction = false
        }
        rewriteOptionsState = nil
        guard let replacementPlan = currentReplacementPlan() else {
            recordDebugEvent("action_panel_blocked_no_text")
            showAllDoneForEmptyText()
            return
        }
        actionPanelState = KeyboardActionPanelState(
            sourceText: replacementPlan.textForAI,
            replacementPlan: replacementPlan,
            selectedAction: .improve,
            isLoading: true
        )
        panelMode = .actions
        requestActionPanelResult(.improve, replacementPlan: replacementPlan)
    }

    func showKeyboardPanel() {
        let previousPanelMode = panelMode
        let hadActionPanelTask = actionPanelTask != nil
        let hadGrammarCorrectionTask = isGrammarCorrectionLoading || grammarCorrectionTask != nil
        actionPanelTask?.cancel()
        actionPanelTask = nil
        if hadGrammarCorrectionTask {
            grammarCorrectionTask?.cancel()
            grammarCorrectionTask = nil
            grammarCorrectionRequestID = nil
            isGrammarCorrectionLoading = false
        }
        if hadActionPanelTask {
            isPerformingAIAction = false
            aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        }
        if hadGrammarCorrectionTask {
            isPerformingAIAction = false
            aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        }
        actionPanelState = nil
        rewriteOptionsState = nil
        panelMode = .keyboard
        let shouldResumeAnalysis = shouldResumeAutomaticAnalysisOnKeyboardReturn
            || previousPanelMode == .actions
            || previousPanelMode == .rewriteOptions
        shouldResumeAutomaticAnalysisOnKeyboardReturn = false
        if shouldResumeAnalysis {
            resumeAutomaticAnalysisIfNeeded()
        }
    }

    func selectActionPanelAction(_ action: KeyboardAIAction) {
        guard var state = actionPanelState else { return }
        guard !state.isLoading else { return }
        state.selectAction(action)
        if let currentPlan = currentReplacementPlan(), currentPlan != state.replacementPlan {
            state = KeyboardActionPanelState(
                sourceText: currentPlan.textForAI,
                replacementPlan: currentPlan,
                selectedAction: action,
                isCarouselVisible: state.isCarouselVisible,
                isLoading: true
            )
        }
        actionPanelState = state
        requestActionPanelResult(action, replacementPlan: state.replacementPlan)
    }

    func applySelectedActionPanelAction() {
        guard let state = actionPanelState,
              let selectedOption = state.selectedOption else {
            return
        }
        actionPanelTask?.cancel()
        actionPanelTask = nil
        replace(plan: state.replacementPlan, with: selectedOption.text)
        actionPanelState = nil
        rewriteOptionsState = nil
        suggestionState = nil
        hasNoIssueAnalysisResult = false
        lastAnalyzedText = nil
        shouldResumeAutomaticAnalysisOnKeyboardReturn = true
        completionPanelState = state.selectedAction == .improve ? .improvementApplied : .rewriteApplied
        aiStatus = state.selectedAction == .improve ? "Improvement applied" : "\(state.selectedAction.title) applied"
        panelMode = .correctionComplete
    }

    func rerunSelectedActionPanelAction() {
        guard let state = actionPanelState, !state.isLoading else { return }
        let replacementPlan = currentReplacementPlan() ?? state.replacementPlan
        if replacementPlan != state.replacementPlan {
            actionPanelState = KeyboardActionPanelState(
                sourceText: replacementPlan.textForAI,
                replacementPlan: replacementPlan,
                selectedAction: state.selectedAction,
                isCarouselVisible: state.isCarouselVisible,
                isLoading: true
            )
        }
        requestActionPanelResult(state.selectedAction, replacementPlan: replacementPlan)
    }

    func toggleActionPanelCarousel() {
        guard var state = actionPanelState else { return }
        state.toggleCarouselVisibility()
        actionPanelState = state
    }

    func copySelectedActionPanelSuggestion() {
        guard let text = actionPanelState?.selectedOption?.text else { return }
        UIPasteboard.general.string = text
    }

    func showAnalysisResult() {
        if currentCorrection != nil {
            panelMode = .correctionDetail
        } else if hasNoIssueAnalysisResult {
            completionPanelState = .noIssues
            panelMode = .correctionComplete
        }
    }

    func openGrammarCorrection() {
        recordDebugEvent("grammar_correction_open_tapped")
        reloadConfig()
        guard canOpenGrammarCorrection else {
            recordDebugEvent("grammar_correction_blocked")
            return
        }

        panelMode = .correctionDetail
        if isGrammarCorrectionLoading {
            return
        }
        requestGrammarCorrectionForCurrentText()
    }

    func clearActionError() {
        actionError = nil
        actionPanelState = nil
        rewriteOptionsState = nil
        aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        panelMode = .keyboard
    }

    func retryAfterActionError() {
        actionError = nil
        rewriteOptionsState = nil
        aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        if canRunAIAction, let replacementPlan = currentReplacementPlan() {
            actionPanelState = KeyboardActionPanelState(
                sourceText: replacementPlan.textForAI,
                replacementPlan: replacementPlan,
                selectedAction: .improve,
                isLoading: true
            )
            panelMode = .actions
            requestActionPanelResult(.improve, replacementPlan: replacementPlan)
        } else {
            actionPanelState = nil
            panelMode = .keyboard
        }
    }

    func copyActionErrorDetails() {
        guard let actionError else { return }
        UIPasteboard.general.string = "\(actionError.title): \(actionError.message)"
    }

    private func requestGrammarCorrectionForCurrentText() {
        actionPanelTask?.cancel()
        actionPanelTask = nil
        grammarCorrectionTask?.cancel()
        grammarCorrectionTask = nil
        grammarCorrectionRequestID = nil
        automaticAnalysisTask?.cancel()
        automaticAnalysisTask = nil
        lastAnalyzedText = nil

        guard let replacementPlan = currentReplacementPlan() else {
            recordDebugEvent("grammar_correction_blocked_no_text")
            showAllDoneForEmptyText()
            return
        }

        actionError = nil
        actionPanelState = nil
        suggestionState = nil
        rewriteOptionsState = nil
        hasNoIssueAnalysisResult = false
        completionPanelState = .allDone
        isGrammarCorrectionLoading = true
        isPerformingAIAction = true
        aiStatus = "Checking grammar…"
        panelMode = .correctionDetail

        let currentConfig = config
        let sourceText = replacementPlan.textForAI
        let requestID = UUID()
        grammarCorrectionRequestID = requestID
        recordDebugEvent("grammar_correction_request_start text=\(sourceText.count)")

        grammarCorrectionTask = Task {
            do {
                let result = try await aiService.performResult(action: .fixGrammar, on: sourceText, config: currentConfig)
                await MainActor.run {
                    guard isGrammarCorrectionLoading,
                          grammarCorrectionRequestID == requestID else {
                        return
                    }
                    applyGrammarCorrectionResult(
                        KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result),
                        sourceText: sourceText
                    )
                    recordDebugEvent("grammar_correction_request_success")
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard grammarCorrectionRequestID == requestID else { return }
                    grammarCorrectionTask = nil
                    grammarCorrectionRequestID = nil
                    isGrammarCorrectionLoading = false
                    isPerformingAIAction = false
                    aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
                }
            } catch {
                await MainActor.run {
                    guard grammarCorrectionRequestID == requestID else { return }
                    grammarCorrectionTask = nil
                    grammarCorrectionRequestID = nil
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    recordDebugEvent("grammar_correction_request_failed:\(KeyboardActionErrorState.sanitized(message))")
                    isGrammarCorrectionLoading = false
                    showActionError(message)
                }
            }
        }
    }

    private func applyGrammarCorrectionResult(_ outcome: KeyboardActionProductOutcome, sourceText: String) {
        isGrammarCorrectionLoading = false
        isPerformingAIAction = false
        grammarCorrectionTask = nil
        grammarCorrectionRequestID = nil

        switch outcome {
        case .showCorrections(let response):
            suggestionState = KeyboardSuggestionState(response: response, sourceContext: sourceText)
            rewriteOptionsState = nil
            hasNoIssueAnalysisResult = false
            completionPanelState = .allDone
            aiStatus = "Suggestions ready"
            panelMode = .correctionDetail
        case .replaceText(let output):
            let replacement = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if replacement.isEmpty || replacement.caseInsensitiveCompare(sourceText.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
                markGrammarCorrectionAllClear()
            } else {
                suggestionState = KeyboardSuggestionState(
                    response: KeyboardSuggestionResponse(
                        corrections: [
                            KeyboardCorrectionSuggestion(
                                label: "Correct text",
                                original: sourceText,
                                replacement: replacement,
                                explanation: "Apply the suggested grammar and spelling correction.",
                                category: "grammar"
                            )
                        ],
                        predictions: [],
                        correctedText: replacement
                    ),
                    sourceContext: sourceText
                )
                rewriteOptionsState = nil
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
                aiStatus = "Suggestions ready"
                panelMode = .correctionDetail
            }
        case .noChanges:
            markGrammarCorrectionAllClear()
        case .showRewriteOptions, .noUsableResult:
            showActionError("No AI response")
        }
    }

    private func markGrammarCorrectionAllClear() {
        actionPanelState = nil
        suggestionState = nil
        rewriteOptionsState = nil
        hasNoIssueAnalysisResult = true
        completionPanelState = .noIssues
        aiStatus = "No issues found"
        panelMode = .correctionComplete
    }

    private func showAllDoneForEmptyText() {
        actionPanelTask?.cancel()
        actionPanelTask = nil
        grammarCorrectionTask?.cancel()
        grammarCorrectionTask = nil
        grammarCorrectionRequestID = nil
        automaticAnalysisTask?.cancel()
        automaticAnalysisTask = nil
        actionError = nil
        actionPanelState = nil
        suggestionState = nil
        rewriteOptionsState = nil
        hasNoIssueAnalysisResult = false
        completionPanelState = .allDone
        isGrammarCorrectionLoading = false
        isPerformingAIAction = false
        lastAnalyzedText = nil
        aiStatus = "No more suggestions"
        panelMode = .correctionComplete
    }

    private func showActionError(_ message: String) {
        let error = KeyboardActionErrorState(message: message)
        actionPanelTask?.cancel()
        actionPanelTask = nil
        grammarCorrectionTask?.cancel()
        grammarCorrectionTask = nil
        grammarCorrectionRequestID = nil
        actionError = error
        actionPanelState = nil
        rewriteOptionsState = nil
        aiStatus = error.message
        isGrammarCorrectionLoading = false
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

    func selectRewriteOption(_ optionID: String) {
        guard var state = rewriteOptionsState else { return }
        state.selectOption(id: optionID)
        rewriteOptionsState = state
    }

    func applySelectedRewriteOption() {
        guard let state = rewriteOptionsState,
              let selectedOption = state.selectedOption else {
            dismissRewriteOptions()
            return
        }
        replace(plan: state.replacementPlan, with: selectedOption.text)
        rewriteOptionsState = nil
        suggestionState = nil
        hasNoIssueAnalysisResult = false
        lastAnalyzedText = nil
        shouldResumeAutomaticAnalysisOnKeyboardReturn = true
        completionPanelState = state.intent.completionState
        aiStatus = state.intent.appliedStatus
        panelMode = .correctionComplete
    }

    func dismissRewriteOptions() {
        aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        showKeyboardPanel()
    }

    func toggleRewriteOptionsCarousel() {
        guard var state = rewriteOptionsState else { return }
        state.toggleCarouselVisibility()
        rewriteOptionsState = state
    }

    func rerunRewriteOptionsAction() {
        guard let state = rewriteOptionsState else { return }
        let selectedAction: KeyboardAIAction = state.intent == .improve ? .improve : .rewrite
        let replacementPlan = currentReplacementPlan() ?? state.replacementPlan
        actionPanelState = KeyboardActionPanelState(
            sourceText: replacementPlan.textForAI,
            replacementPlan: replacementPlan,
            selectedAction: selectedAction,
            isLoading: true
        )
        rewriteOptionsState = nil
        panelMode = .actions
        requestActionPanelResult(selectedAction, replacementPlan: replacementPlan)
    }

    func copySelectedRewriteOption() {
        guard let text = rewriteOptionsState?.selectedOption?.text else { return }
        UIPasteboard.general.string = text
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
            hasNoIssueAnalysisResult = false
            completionPanelState = .allDone
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
        startAutomaticAnalysis()
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

    func startAutomaticAnalysis() {
        scheduleAutomaticAnalysis(delayNanoseconds: automaticAnalysisDelayNanoseconds)
    }

    func refreshSeededSuggestionStateForUITests() {
        guard let seededSuggestionState = Self.loadSeededSuggestionState() else { return }
        suggestionState = seededSuggestionState.suggestionState
        rewriteOptionsState = seededSuggestionState.rewriteOptionsState
        panelMode = seededSuggestionState.panelMode
        aiStatus = seededSuggestionState.aiStatus
        isPerformingAIAction = seededSuggestionState.isPerformingAIAction
        hasNoIssueAnalysisResult = seededSuggestionState.hasNoIssueAnalysisResult
        completionPanelState = seededSuggestionState.completionPanelState
        if seededSuggestionState.suggestionState != nil || seededSuggestionState.rewriteOptionsState != nil {
            hasFullAccess = true
        }
    }

    func performAIAction(_ action: KeyboardAIAction) {
        recordDebugEvent("action_tapped:\(action.rawValue)")
        actionPanelTask?.cancel()
        actionPanelTask = nil
        automaticAnalysisTask?.cancel()
        automaticAnalysisTask = nil
        grammarCorrectionTask?.cancel()
        grammarCorrectionTask = nil
        grammarCorrectionRequestID = nil
        isGrammarCorrectionLoading = false
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
        let fallbackContext = composingBuffer.isEmpty ? nil : composingBuffer
        recordDebugEvent("action_context context=\(contextBeforeInput?.count ?? 0) buffer=\(fallbackContext?.count ?? 0)")
        guard let replacementPlan = currentReplacementPlan() else {
            recordDebugEvent("action_blocked_no_text")
            showAllDoneForEmptyText()
            return
        }

        let currentConfig = config
        actionError = nil
        actionPanelState = nil
        rewriteOptionsState = nil
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
                    switch KeyboardActionResultHandler.outcome(operation: action.operationName, result: result, sourceText: replacementPlan.textForAI) {
                    case .showCorrections(let response):
                        suggestionState = KeyboardSuggestionState(response: response, sourceContext: replacementPlan.textForAI)
                        rewriteOptionsState = nil
                        hasNoIssueAnalysisResult = false
                        aiStatus = "Suggestions ready"
                        isPerformingAIAction = false
                        panelMode = .correctionDetail
                    case .showRewriteOptions(let options):
                        suggestionState = nil
                        rewriteOptionsState = KeyboardRewriteOptionsState(
                            intent: action.rewriteOptionsIntent,
                            sourceText: replacementPlan.textForAI,
                            replacementPlan: replacementPlan,
                            options: options
                        )
                        hasNoIssueAnalysisResult = false
                        completionPanelState = .allDone
                        aiStatus = action.rewriteOptionsIntent.readyStatus(count: options.count)
                        isPerformingAIAction = false
                        panelMode = .rewriteOptions
                    case .replaceText(let output):
                        replace(plan: replacementPlan, with: output)
                        rewriteOptionsState = nil
                        hasNoIssueAnalysisResult = false
                        lastAnalyzedText = nil
                        shouldResumeAutomaticAnalysisOnKeyboardReturn = true
                        completionPanelState = .allDone
                        aiStatus = action == .summarize ? "Summary ready" : "No more suggestions"
                        isPerformingAIAction = false
                        panelMode = .correctionComplete
                    case .noChanges:
                        suggestionState = nil
                        rewriteOptionsState = nil
                        hasNoIssueAnalysisResult = true
                        completionPanelState = .noIssues
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

    private func scheduleAutomaticAnalysisAfterTextChange() {
        actionPanelTask?.cancel()
        actionPanelTask = nil
        automaticAnalysisTask?.cancel()
        automaticAnalysisTask = nil
        grammarCorrectionTask?.cancel()
        grammarCorrectionTask = nil
        grammarCorrectionRequestID = nil
        isGrammarCorrectionLoading = false
        if isPerformingAIAction, aiStatus == "Analyzing…" {
            isPerformingAIAction = false
            aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        }
        actionPanelState = nil
        suggestionState = nil
        rewriteOptionsState = nil
        hasNoIssueAnalysisResult = false
        isGrammarCorrectionLoading = false
        completionPanelState = .allDone
        lastAnalyzedText = nil
        scheduleAutomaticAnalysis(delayNanoseconds: automaticAnalysisDelayNanoseconds)
    }

    private func requestActionPanelResult(_ action: KeyboardAIAction, replacementPlan: KeyboardReplacementPlan) {
        actionPanelTask?.cancel()
        guard hasFullAccess else {
            aiStatus = "Enable Allow Full Access"
            return
        }
        config = loadConfig()
        gatewayConnectionError = Self.normalizedGatewayConnectionError(loadGatewayConnectionError())
        if let gatewayConnectionError {
            aiStatus = gatewayConnectionError
            return
        }
        guard hasUsableGatewayConfig else {
            aiStatus = "Pair gateway in app"
            return
        }

        var loadingState = actionPanelState ?? KeyboardActionPanelState(
            sourceText: replacementPlan.textForAI,
            replacementPlan: replacementPlan,
            selectedAction: action
        )
        loadingState.selectedAction = action
        loadingState.beginLoading()
        actionPanelState = loadingState
        actionError = nil
        isPerformingAIAction = true
        aiStatus = "\(action.title)…"

        let currentConfig = config
        recordDebugEvent("action_panel_request_start action=\(action.rawValue) text=\(replacementPlan.textForAI.count)")
        actionPanelTask = Task { [weak self] in
            do {
                guard let self else { return }
                let result = try await self.aiService.performResult(action: action, on: replacementPlan.textForAI, config: currentConfig)
                await MainActor.run {
                    guard self.panelMode == .actions,
                          var state = self.actionPanelState,
                          state.replacementPlan == replacementPlan,
                          state.selectedAction == action else {
                        self.isPerformingAIAction = false
                        return
                    }

                    let outcome = KeyboardActionResultHandler.outcome(
                        operation: action.operationName,
                        result: result,
                        sourceText: replacementPlan.textForAI
                    )
                    let options = self.actionPanelOptions(from: outcome, action: action)
                    guard !options.isEmpty else {
                        self.showActionError("No AI response")
                        return
                    }

                    state.finishLoading(options: options)
                    self.actionPanelState = state
                    self.rewriteOptionsState = nil
                    self.aiStatus = "\(action.title) ready"
                    self.isPerformingAIAction = false
                    self.actionPanelTask = nil
                    self.recordDebugEvent("action_panel_request_success action=\(action.rawValue) options=\(options.count)")
                }
            } catch is CancellationError {
                await MainActor.run {
                    if self?.panelMode == .actions {
                        self?.isPerformingAIAction = false
                    }
                }
            } catch {
                await MainActor.run {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self?.recordDebugEvent("action_panel_request_failed:\(KeyboardActionErrorState.sanitized(message))")
                    self?.showActionError(message)
                }
            }
        }
    }

    private func actionPanelOptions(from outcome: KeyboardActionProductOutcome, action: KeyboardAIAction) -> [KeyboardRewriteOption] {
        switch outcome {
        case .showRewriteOptions(let options):
            return options
        case .replaceText(let output):
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard KeyboardReplacementTextSafety.isSafeReplacementText(text) else { return [] }
            return [
                KeyboardRewriteOption(
                    id: "\(action.rawValue)-result-1",
                    title: action.resultOptionTitle,
                    text: text
                )
            ]
        case .showCorrections(let response):
            if let correctedText = response.correctedText,
               KeyboardReplacementTextSafety.isSafeReplacementText(correctedText) {
                return [
                    KeyboardRewriteOption(
                        id: "\(action.rawValue)-result-1",
                        title: action.resultOptionTitle,
                        text: correctedText
                    )
                ]
            }
            return []
        case .noChanges, .noUsableResult:
            return []
        }
    }

    private func scheduleAutomaticAnalysis(delayNanoseconds: UInt64) {
        automaticAnalysisTask?.cancel()
        guard panelMode == .keyboard else { return }
        guard actionError == nil else { return }
        guard canRunAIAction else { return }
        guard currentReplacementPlan() != nil else {
            clearAutomaticAnalysisState()
            return
        }

        automaticAnalysisTask = Task { [weak self] in
            do {
                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
                await self?.runAutomaticAnalysis()
            } catch {
                // A newer keystroke canceled this debounce window.
            }
        }
    }

    private func resumeAutomaticAnalysisIfNeeded() {
        guard panelMode == .keyboard else { return }
        guard actionError == nil else { return }
        guard suggestionState == nil, !hasNoIssueAnalysisResult else { return }
        guard currentReplacementPlan() != nil else {
            clearAutomaticAnalysisState()
            return
        }

        scheduleAutomaticAnalysis(delayNanoseconds: 0)
    }

    private func runAutomaticAnalysis() async {
        guard !isPerformingAIAction, canRunAIAction, panelMode == .keyboard, actionError == nil else { return }
        guard let replacementPlan = currentReplacementPlan() else {
            clearAutomaticAnalysisState()
            return
        }
        let analysisText = replacementPlan.textForAI
        guard analysisText.count >= 3 else {
            clearAutomaticAnalysisState()
            return
        }
        if lastAnalyzedText == analysisText, canOpenAnalysisResult { return }

        let currentConfig = config
        lastAnalyzedText = analysisText
        isPerformingAIAction = true
        aiStatus = "Analyzing…"
        recordDebugEvent("automatic_analysis_start text=\(analysisText.count) model=\(currentConfig.selectedModel)")

        do {
            let result = try await aiService.performResult(action: .fixGrammar, on: analysisText, config: currentConfig)
            guard currentReplacementPlan()?.textForAI == analysisText else {
                isPerformingAIAction = false
                scheduleAutomaticAnalysis(delayNanoseconds: automaticAnalysisDelayNanoseconds)
                return
            }
            guard panelMode == .keyboard else {
                isPerformingAIAction = false
                return
            }
            applyAutomaticAnalysisResult(
                KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result),
                sourceText: analysisText
            )
            recordDebugEvent("automatic_analysis_success")
        } catch is CancellationError {
            recordDebugEvent("automatic_analysis_cancelled")
            if lastAnalyzedText == analysisText, !isGrammarCorrectionLoading {
                isPerformingAIAction = false
                aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
                lastAnalyzedText = nil
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            recordDebugEvent("automatic_analysis_failed:\(KeyboardActionErrorState.sanitized(message))")
            guard !isGrammarCorrectionLoading else { return }
            aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
            suggestionState = nil
            hasNoIssueAnalysisResult = false
            isPerformingAIAction = false
        }
    }

    private func applyAutomaticAnalysisResult(_ outcome: KeyboardActionProductOutcome, sourceText: String) {
        switch outcome {
        case .showCorrections(let response):
            suggestionState = KeyboardSuggestionState(response: response, sourceContext: sourceText)
            rewriteOptionsState = nil
            hasNoIssueAnalysisResult = false
            completionPanelState = .allDone
            aiStatus = "Suggestions ready"
        case .showRewriteOptions:
            suggestionState = nil
            rewriteOptionsState = nil
            hasNoIssueAnalysisResult = false
            aiStatus = "Ready"
        case .replaceText(let output):
            let replacement = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if replacement.isEmpty || replacement.caseInsensitiveCompare(sourceText.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
                markAutomaticAnalysisAllClear()
            } else {
                suggestionState = KeyboardSuggestionState(
                    response: KeyboardSuggestionResponse(
                        corrections: [
                            KeyboardCorrectionSuggestion(
                                label: "Correct text",
                                original: sourceText,
                                replacement: replacement,
                                explanation: "Apply the suggested grammar and spelling correction.",
                                category: "grammar"
                            )
                        ],
                        predictions: [],
                        correctedText: replacement
                    ),
                    sourceContext: sourceText
                )
                rewriteOptionsState = nil
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
                aiStatus = "Suggestions ready"
            }
        case .noChanges:
            markAutomaticAnalysisAllClear()
        case .noUsableResult:
            suggestionState = nil
            rewriteOptionsState = nil
            hasNoIssueAnalysisResult = false
            aiStatus = "Ready"
        }
        isPerformingAIAction = false
        if panelMode != .correctionComplete {
            panelMode = .keyboard
        }
    }

    private func markAutomaticAnalysisAllClear() {
        actionPanelState = nil
        suggestionState = nil
        rewriteOptionsState = nil
        hasNoIssueAnalysisResult = true
        completionPanelState = .noIssues
        aiStatus = "No issues found"
    }

    private func clearAutomaticAnalysisState() {
        actionPanelTask?.cancel()
        actionPanelTask = nil
        automaticAnalysisTask?.cancel()
        automaticAnalysisTask = nil
        grammarCorrectionTask?.cancel()
        grammarCorrectionTask = nil
        grammarCorrectionRequestID = nil
        actionPanelState = nil
        suggestionState = nil
        rewriteOptionsState = nil
        hasNoIssueAnalysisResult = false
        completionPanelState = .allDone
        lastAnalyzedText = nil
        isGrammarCorrectionLoading = false
        isPerformingAIAction = false
    }

    private func replace(plan: KeyboardReplacementPlan, with replacement: String) {
        let finalReplacement = plan.replacementText(from: replacement)
        guard !finalReplacement.isEmpty else { return }

        if !plan.textAfterCursorToDelete.isEmpty {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: plan.textAfterCursorToDelete.count)
            for _ in plan.textAfterCursorToDelete {
                textDocumentProxy.deleteBackward()
            }
        }
        for _ in plan.textToDelete {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(finalReplacement)
        composingBuffer = finalReplacement
        persistComposingBuffer()
    }

    private func currentEditableText() -> String {
        if let plan = currentReplacementPlan() {
            return plan.textToReplace
        }
        if let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty {
            return context
        }
        if composingBuffer.isEmpty, Self.debugStateEnabled {
            composingBuffer = Self.loadPersistedComposingBuffer()
        }
        return composingBuffer
    }

    private func currentReplacementPlan() -> KeyboardReplacementPlan? {
        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput
        let contextAfterInput = textDocumentProxy.documentContextAfterInput
        if composingBuffer.isEmpty, Self.debugStateEnabled {
            composingBuffer = Self.loadPersistedComposingBuffer()
        }
        let fallbackContext = composingBuffer.isEmpty ? nil : composingBuffer
        return KeyboardReplacementPlanner.plan(
            contextBeforeInput: contextBeforeInput,
            contextAfterInput: contextAfterInput
        ) ?? KeyboardReplacementPlanner.plan(for: fallbackContext)
    }

    private func replaceEditableText(with replacement: String) {
        if let plan = currentReplacementPlan() {
            replace(plan: plan, with: replacement)
            return
        }
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
        let toolbar = "toolbar.canRunAIAction=\(canRunAIAction); toolbar.actionsEnabled=\(canOpenActionPanel); toolbar.title=\(toolbarState.title); toolbar.subtitle=\(toolbarState.subtitle); hasFullAccess=\(hasFullAccess); gatewayConnectionErrorPresent=\(gatewayConnectionError != nil)"
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
              let rawValue = consumeOneShotSeed(
                valueKey: Keys.initialPanelMode,
                seedIDKey: Keys.initialPanelModeSeedID,
                seededAtKey: Keys.initialPanelModeSeededAt,
                defaults: defaults
              ) else {
            return .keyboard
        }

        switch rawValue {
        case "rewriteOptions": return .rewriteOptions
        case "actions": return .actions
        case "correctionDetail", "correctionCarousel": return .correctionDetail
        case "correctionComplete": return .correctionComplete
        default: return .keyboard
        }
    }

    private static func loadSeededSuggestionState() -> SeededKeyboardSuggestionState? {
        consumeSeededSuggestionStateRawValue().flatMap(SeededKeyboardSuggestionState.init(rawValue:))
    }

    private static func consumeSeededSuggestionStateRawValue() -> String? {
        guard KeyboardDebugStatePolicy.isPersistenceAvailable,
              let defaults = AppConfig.sharedDefaults(),
              defaults.bool(forKey: Keys.uiTestDebugStateEnabled) else {
            return nil
        }

        let rawValue = consumeOneShotSeed(
            valueKey: Keys.suggestionState,
            seedIDKey: Keys.suggestionStateSeedID,
            seededAtKey: Keys.suggestionStateSeededAt,
            defaults: defaults
        )

        if rawValue != nil {
            defaults.removeObject(forKey: Keys.initialPanelMode)
            defaults.removeObject(forKey: Keys.initialPanelModeSeedID)
            defaults.removeObject(forKey: Keys.initialPanelModeSeededAt)
            defaults.synchronize()
        }

        return rawValue
    }

    private static func consumeOneShotSeed(valueKey: String, seedIDKey: String, seededAtKey: String, defaults: UserDefaults) -> String? {
        defaults.synchronize()
        let rawValue = defaults.string(forKey: valueKey)
        let seedID = defaults.string(forKey: seedIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let seededAt = defaults.object(forKey: seededAtKey) as? TimeInterval
        defaults.removeObject(forKey: valueKey)
        defaults.removeObject(forKey: seedIDKey)
        defaults.removeObject(forKey: seededAtKey)
        defaults.synchronize()

        guard !seedID.isEmpty, let seededAt else {
            return nil
        }

        let seedAge = Date().timeIntervalSince1970 - seededAt
        guard seedAge >= 0, seedAge <= uiTestSeedMaximumAge else {
            return nil
        }
        return rawValue
    }

    private struct SeededKeyboardSuggestionState {
        let panelMode: KeyboardPanelMode
        let suggestionState: KeyboardSuggestionState?
        let rewriteOptionsState: KeyboardRewriteOptionsState?
        let aiStatus: String
        let isPerformingAIAction: Bool
        let hasNoIssueAnalysisResult: Bool
        let completionPanelState: KeyboardCompletionPanelState

        init?(rawValue: String) {
            switch rawValue {
            case "rewriteOptions":
                panelMode = .rewriteOptions
                suggestionState = nil
                rewriteOptionsState = Self.rewriteOptionsState
                aiStatus = "3 rewrites ready"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "correctionCard", "correctionDetail", "correctionCarousel":
                panelMode = .correctionDetail
                suggestionState = KeyboardSuggestionState(
                    response: Self.carouselResponse,
                    sourceContext: "i has a apple and ths sentence"
                )
                rewriteOptionsState = nil
                aiStatus = "Suggestions ready"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "correctionComplete":
                panelMode = .correctionComplete
                suggestionState = nil
                rewriteOptionsState = nil
                aiStatus = "No more suggestions"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "allGood":
                panelMode = .correctionComplete
                suggestionState = nil
                rewriteOptionsState = nil
                aiStatus = "No issues found"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = true
                completionPanelState = .noIssues
            case "analyzing":
                panelMode = .keyboard
                suggestionState = nil
                rewriteOptionsState = nil
                aiStatus = "Analyzing your text..."
                isPerformingAIAction = true
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
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

        private static var rewriteOptionsState: KeyboardRewriteOptionsState {
            let sourceText = "All of these are no bulb in the universe."
            return KeyboardRewriteOptionsState(
                intent: .rephrase,
                sourceText: sourceText,
                replacementPlan: KeyboardReplacementPlan(
                    textToDelete: sourceText,
                    textForAI: sourceText,
                    leadingWhitespace: "",
                    trailingWhitespace: ""
                ),
                options: [
                    KeyboardRewriteOption(id: "rewrite-option-1", title: "Clearer", text: "None of these are bulbs in the universe."),
                    KeyboardRewriteOption(id: "rewrite-option-2", title: "Natural", text: "There are no bulbs anywhere in the universe."),
                    KeyboardRewriteOption(id: "rewrite-option-3", title: "Concise", text: "No bulbs exist in the universe.")
                ]
            )
        }
    }

    private static var debugStateEnabled: Bool {
        guard KeyboardDebugStatePolicy.isPersistenceAvailable else { return false }
        return AppConfig.sharedDefaults()?.bool(forKey: Keys.uiTestDebugStateEnabled) ?? false
    }

    private static func normalizedGatewayConnectionError(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension KeyboardAIAction {
    var rewriteOptionsIntent: KeyboardRewriteOptionsIntent {
        self == .improve ? .improve : .rephrase
    }

    var resultOptionTitle: String {
        switch self {
        case .improve: return "Improved"
        case .fixGrammar: return "Corrected"
        case .rewrite: return "Rephrased"
        case .summarize: return "Summary"
        }
    }
}
