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
    var warningMessage: String?

    static let availableActions: [KeyboardAIAction] = [
        .improve,
        .rewrite,
        // .summarize, // Keep the operation available internally, but omit it from the keyboard carousel.
        .translate(nil)
    ] + KeyboardRewriteStyle.allCases.map(KeyboardAIAction.rewriteStyle)

    init(
        sourceText: String,
        replacementPlan: KeyboardReplacementPlan,
        selectedAction: KeyboardAIAction = .improve,
        options: [KeyboardRewriteOption] = [],
        isCarouselVisible: Bool = true,
        isLoading: Bool = false,
        warningMessage: String? = nil
    ) {
        self.sourceText = sourceText
        self.replacementPlan = replacementPlan
        self.selectedAction = selectedAction
        self.options = options
        self.selectedOptionID = options.first?.id ?? ""
        self.isCarouselVisible = isCarouselVisible
        self.isLoading = isLoading
        self.warningMessage = warningMessage
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

    var selectedReplacementDiff: KeyboardReplacementDiff? {
        guard selectedAction == .improve || selectedAction.isRewrite,
              let selectedOption else {
            return nil
        }
        return KeyboardReplacementDiff(original: sourceText, replacement: selectedOption.text)
    }

    var usesScrollableActionResult: Bool {
        selectedOption != nil && !isLoading
    }

    var selectedTranslationTarget: KeyboardTranslationTarget? {
        selectedAction.translationTarget
    }

    var showsTranslationTargetSelector: Bool {
        isCarouselVisible && selectedAction.isTranslation
    }

    var isWaitingForTranslationTarget: Bool {
        selectedAction.isTranslation && selectedTranslationTarget == nil && !isLoading
    }

    var contextSelectionPrompt: String? {
        if isWaitingForTranslationTarget { return "Choose a language" }
        return nil
    }

    var actionResultViewportHeight: CGFloat {
        showsTranslationTargetSelector
            ? KeyboardPanelLayout.actionPanelContextualResultHeight
            : KeyboardPanelLayout.actionPanelScrollableResultHeight
    }

    mutating func selectAction(_ action: KeyboardAIAction) {
        guard Self.availableActions.contains(where: { $0.representsSameMode(as: action) }) else { return }
        selectedAction = action
        options = []
        selectedOptionID = ""
        warningMessage = nil
        isLoading = action.isReadyForActionPanelRequest
    }

    mutating func selectTranslationTarget(_ target: KeyboardTranslationTarget) {
        guard selectedAction.isTranslation else { return }
        selectedAction = .translate(target)
        beginLoading()
    }

    mutating func beginLoading() {
        options = []
        selectedOptionID = ""
        warningMessage = nil
        isLoading = true
    }

    mutating func finishLoading(options: [KeyboardRewriteOption]) {
        self.options = options
        selectedOptionID = options.first?.id ?? ""
        isLoading = false
        warningMessage = nil
    }

    mutating func finishLoading(warningMessage: String) {
        options = []
        selectedOptionID = ""
        isLoading = false
        self.warningMessage = warningMessage
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
    private let nextTextPredictor: NextTextPredicting
    private let typingPredictionsEnabled: Bool
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
    @Published private(set) var automaticAnalysisWarning: KeyboardActionErrorState?
    @Published private(set) var completionPanelState = KeyboardCompletionPanelState.allDone
    @Published private(set) var isGrammarCorrectionLoading = false
    @Published private(set) var typingPredictions: [KeyboardPredictionSuggestion] = []
    @Published private var hasNoIssueAnalysisResult = false
    private var composingBuffer = ""
    private var automaticAnalysisTask: Task<Void, Never>?
    private var grammarCorrectionTask: Task<Void, Never>?
    private var grammarCorrectionRequestID: UUID?
    private var actionPanelTask: Task<Void, Never>?
    private var actionPanelRequestID: UUID?
    private var shouldResumeAutomaticAnalysisOnKeyboardReturn = false
    private let automaticAnalysisDelayNanoseconds: UInt64
    private var lastAnalyzedText: String?
    private var lastKeyboardReplacementSourceText: String?
    private var lastKeyboardReplacementResultText: String?
    private var documentRevision = 0

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
            && !isSelectedModelUnavailable
            && !isPerformingAIAction
    }

    var canOpenActionPanel: Bool {
        hasFullAccess
            && gatewayConnectionError == nil
            && hasUsableGatewayConfig
            && !isSelectedModelUnavailable
            && !isManualActionInFlight
    }

    private var hasUsableGatewayConfig: Bool {
        config.isConfigured && config.hasGatewayRuntimeConfig
    }

    private var isSelectedModelUnavailable: Bool {
        hasUsableGatewayConfig
            && config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            || isSelectedModelUnavailable
            || actionError?.blocksGrammarCorrection == true
    }

    var currentCorrection: KeyboardCorrectionSuggestion? {
        suggestionState?.currentCorrection
    }

    var toolbarState: KeyboardToolbarState {
        if let actionError {
            return KeyboardToolbarState(kind: .error(kind: actionError.kind, message: actionError.message))
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
            return KeyboardToolbarState(kind: .error(kind: .gatewayUnavailable, message: gatewayConnectionError))
        }
        if isSelectedModelUnavailable {
            return KeyboardToolbarState(kind: .error(
                kind: .modelUnavailable,
                message: KeyboardAIError.modelUnavailable.localizedDescription
            ))
        }
        if let automaticAnalysisWarning {
            return KeyboardToolbarState(kind: .error(
                kind: automaticAnalysisWarning.kind,
                message: automaticAnalysisWarning.message
            ))
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
        nextTextPredictor: NextTextPredicting = AppleNaturalLanguageNextTextPredictor(),
        typingPredictionsEnabled: Bool = false,
        loadConfig: @escaping () -> AppConfig = AppConfig.load,
        loadGatewayConnectionError: @escaping () -> String? = AppConfig.sharedGatewayConnectionError,
        productionTestFullAccess: Bool = false,
        automaticAnalysisDelayNanoseconds: UInt64 = 2_500_000_000
    ) {
        self.textDocumentProxy = textDocumentProxy
        self.aiService = aiService
        self.nextTextPredictor = nextTextPredictor
        self.typingPredictionsEnabled = typingPredictionsEnabled
        self.loadConfig = loadConfig
        self.loadGatewayConnectionError = loadGatewayConnectionError
        self.automaticAnalysisDelayNanoseconds = automaticAnalysisDelayNanoseconds
        self.config = loadConfig()
        self.gatewayConnectionError = Self.normalizedGatewayConnectionError(loadGatewayConnectionError())
        // The composing buffer is runtime-only input state. UI tests may persist a
        // redacted diagnostic copy, but a later normally installed extension must
        // never restore that copy and send it instead of the host document context.
        self.composingBuffer = ""
        let seededSuggestionState = Self.loadSeededSuggestionState()
        self.suggestionState = seededSuggestionState?.suggestionState
        self.actionPanelState = seededSuggestionState?.actionPanelState
        self.rewriteOptionsState = seededSuggestionState?.rewriteOptionsState
        self.actionError = seededSuggestionState?.actionError
        self.automaticAnalysisWarning = seededSuggestionState?.automaticAnalysisWarning
        self.panelMode = seededSuggestionState?.panelMode ?? Self.consumeInitialPanelModeSeed()
        self.aiStatus = seededSuggestionState?.aiStatus ?? self.aiStatus
        self.isPerformingAIAction = seededSuggestionState?.isPerformingAIAction ?? false
        self.hasNoIssueAnalysisResult = seededSuggestionState?.hasNoIssueAnalysisResult ?? false
        self.completionPanelState = seededSuggestionState?.completionPanelState ?? .allDone
        self.hasFullAccess = productionTestFullAccess || seededSuggestionState != nil
        if self.automaticAnalysisWarning != nil {
            self.lastAnalyzedText = currentInputTextForAnalysis()
        }
        refreshTypingPredictions()
        recordConfigVisibilityProbe(context: "init")
    }

    func insert(_ character: String) {
        invalidateGrammarSessionForDocumentEdit()
        clearKeyboardReplacementTracking()
        let output = isShiftEnabled ? character.uppercased() : character
        textDocumentProxy.insertText(output)
        documentRevision += 1
        composingBuffer.append(output)
        persistComposingBuffer()
        scheduleAutomaticAnalysisAfterTextChange()

        if isShiftEnabled {
            isShiftEnabled = false
        }
    }

    func insertSpace() {
        invalidateGrammarSessionForDocumentEdit()
        clearKeyboardReplacementTracking()
        textDocumentProxy.insertText(" ")
        documentRevision += 1
        composingBuffer.append(" ")
        persistComposingBuffer()
        scheduleAutomaticAnalysisAfterTextChange()
    }

    func insertReturn() {
        invalidateGrammarSessionForDocumentEdit()
        clearKeyboardReplacementTracking()
        textDocumentProxy.insertText("\n")
        documentRevision += 1
        clearComposingBuffer()
        typingPredictions = []
        if automaticAnalysisWarning != nil {
            scheduleAutomaticAnalysisAfterTextChange()
        } else {
            clearAutomaticAnalysisState()
        }
    }

    func deleteBackward() {
        invalidateGrammarSessionForDocumentEdit()
        clearKeyboardReplacementTracking()
        textDocumentProxy.deleteBackward()
        documentRevision += 1
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
        actionPanelRequestID = nil
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
        actionPanelTask?.cancel()
        actionPanelTask = nil
        actionPanelRequestID = nil
        isPerformingAIAction = false
        guard let currentPlan = currentActionPanelReplacementPlan() else {
            invalidateActionPanelForSourceChange()
            return
        }
        state.selectAction(action)
        guard currentPlan == state.replacementPlan else {
            invalidateActionPanelForSourceChange()
            return
        }
        actionPanelState = state
        guard state.selectedAction.isReadyForActionPanelRequest else {
            aiStatus = state.contextSelectionPrompt ?? "Choose an option"
            return
        }
        requestActionPanelResult(state.selectedAction, replacementPlan: state.replacementPlan)
    }

    func selectActionPanelTranslationTarget(_ target: KeyboardTranslationTarget) {
        guard var state = actionPanelState,
              state.selectedAction.isTranslation,
              !state.isLoading else {
            return
        }
        guard let replacementPlan = currentActionPanelReplacementPlan() else {
            invalidateActionPanelForSourceChange()
            return
        }
        guard replacementPlan == state.replacementPlan else {
            invalidateActionPanelForSourceChange()
            return
        }
        state.selectTranslationTarget(target)
        actionPanelState = state
        requestActionPanelResult(state.selectedAction, replacementPlan: replacementPlan)
    }

    func applySelectedActionPanelAction() {
        guard let state = actionPanelState,
              let selectedOption = state.selectedOption else {
            return
        }
        guard let replacementPlan = currentActionPanelReplacementPlan() else {
            invalidateActionPanelForSourceChange()
            return
        }
        guard replacementPlan == state.replacementPlan else {
            invalidateActionPanelForSourceChange()
            return
        }
        actionPanelTask?.cancel()
        actionPanelTask = nil
        actionPanelRequestID = nil
        replace(plan: state.replacementPlan, with: selectedOption.text)
        actionPanelState = nil
        rewriteOptionsState = nil
        suggestionState = nil
        hasNoIssueAnalysisResult = false
        lastAnalyzedText = nil
        shouldResumeAutomaticAnalysisOnKeyboardReturn = true
        if state.selectedAction == .improve {
            completionPanelState = .improvementApplied
        } else if let target = state.selectedTranslationTarget {
            completionPanelState = .translationApplied(language: target.displayName)
        } else {
            completionPanelState = .rewriteApplied
        }
        aiStatus = state.selectedAction == .improve ? "Improvement applied" : "\(state.selectedAction.title) applied"
        panelMode = .correctionComplete
    }

    func rerunSelectedActionPanelAction() {
        guard let state = actionPanelState,
              !state.isLoading,
              state.selectedAction.isReadyForActionPanelRequest else {
            return
        }
        guard let replacementPlan = currentActionPanelReplacementPlan() else {
            invalidateActionPanelForSourceChange()
            return
        }
        guard replacementPlan == state.replacementPlan else {
            invalidateActionPanelForSourceChange()
            return
        }
        requestActionPanelResult(state.selectedAction, replacementPlan: state.replacementPlan)
    }

    func toggleActionPanelCarousel() {
        guard var state = actionPanelState else { return }
        state.toggleCarouselVisibility()
        actionPanelState = state
    }

    func copySelectedActionPanelSuggestion() {
        guard let state = actionPanelState,
              currentActionPanelReplacementPlan() == state.replacementPlan,
              let text = state.selectedOption?.text else {
            return
        }
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

        if isGrammarCorrectionLoading {
            panelMode = .correctionDetail
            return
        }
        if openCachedGrammarAnalysisForCurrentText() { return }
        requestGrammarCorrectionForCurrentText()
    }

    private func openCachedGrammarAnalysisForCurrentText() -> Bool {
        guard let sourceText = currentInputTextForAnalysis(),
              lastAnalyzedText == sourceText,
              canOpenAnalysisResult else {
            return false
        }

        automaticAnalysisTask?.cancel()
        automaticAnalysisTask = nil
        actionPanelState = nil
        rewriteOptionsState = nil
        isGrammarCorrectionLoading = false

        if currentCorrection != nil {
            aiStatus = "Suggestions ready"
            panelMode = .correctionDetail
        } else {
            completionPanelState = .noIssues
            aiStatus = "No issues found"
            panelMode = .correctionComplete
        }
        recordDebugEvent("grammar_correction_cached_result_opened text=\(sourceText.count)")
        return true
    }

    func clearActionError() {
        actionError = nil
        actionPanelState = nil
        rewriteOptionsState = nil
        aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        panelMode = .keyboard
    }

    func retryAfterActionError() {
        let recoveryScope = actionError?.scope
        actionError = nil
        rewriteOptionsState = nil
        aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        if recoveryScope == .grammar {
            actionPanelState = nil
            panelMode = .keyboard
            lastAnalyzedText = nil
            scheduleAutomaticAnalysis(delayNanoseconds: 0)
            return
        }
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

    func applyTypingPrediction(id: String) {
        guard typingPredictionsEnabled else { return }
        guard let prediction = typingPredictions.first(where: { $0.id == id }) else { return }
        invalidateGrammarSessionForDocumentEdit()
        clearKeyboardReplacementTracking()
        insertTypingPrediction(prediction)
        documentRevision += 1
        persistComposingBuffer()
        refreshTypingPredictions()
        scheduleAutomaticAnalysisAfterTextChange()
    }

    private func requestGrammarCorrectionForCurrentText() {
        actionPanelTask?.cancel()
        actionPanelTask = nil
        grammarCorrectionTask?.cancel()
        grammarCorrectionTask = nil
        grammarCorrectionRequestID = nil
        automaticAnalysisTask?.cancel()
        automaticAnalysisTask = nil

        let documentTextAtRequest = currentDocumentTextForAnalysis()
        let documentRevisionAtRequest = documentRevision
        guard let sourceText = currentInputTextForAnalysis() else {
            recordDebugEvent("grammar_correction_blocked_no_text")
            showAllDoneForEmptyText()
            return
        }

        actionError = nil
        automaticAnalysisWarning = nil
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
        lastAnalyzedText = sourceText
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
                    guard currentInputTextForAnalysis(knownStaleContextText: documentTextAtRequest) == sourceText else {
                        discardStaleGrammarCorrectionResponse(sourceText: sourceText)
                        return
                    }
                    guard documentRevision == documentRevisionAtRequest else {
                        discardStaleGrammarCorrectionResponse(sourceText: sourceText)
                        return
                    }
                    applyGrammarCorrectionResult(
                        KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result, sourceText: sourceText),
                        sourceText: sourceText,
                        documentRevision: documentRevisionAtRequest
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
                    if lastAnalyzedText == sourceText {
                        lastAnalyzedText = nil
                    }
                }
            } catch {
                await MainActor.run {
                    guard grammarCorrectionRequestID == requestID else { return }
                    grammarCorrectionTask = nil
                    grammarCorrectionRequestID = nil
                    if lastAnalyzedText == sourceText {
                        lastAnalyzedText = nil
                    }
                    recordDebugEvent("grammar_correction_request_failed:\(Self.sanitizedErrorMessage(error))")
                    isGrammarCorrectionLoading = false
                    showActionError(error, scope: .grammar)
                }
            }
        }
    }

    private func applyGrammarCorrectionResult(_ outcome: KeyboardActionProductOutcome, sourceText: String, documentRevision: Int) {
        isGrammarCorrectionLoading = false
        isPerformingAIAction = false
        grammarCorrectionTask = nil
        grammarCorrectionRequestID = nil
        lastAnalyzedText = sourceText

        switch outcome {
        case .showCorrections(let response):
            if let correctedText = response.correctedText {
                suggestionState = KeyboardSuggestionState(
                    grammarOriginal: sourceText,
                    correctedText: correctedText,
                    documentRevision: documentRevision
                )
            } else {
                suggestionState = KeyboardSuggestionState(response: response, sourceContext: sourceText)
            }
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
            showActionError(KeyboardAIError.modelCapability, scope: .grammar)
        }
    }

    private func discardStaleGrammarCorrectionResponse(sourceText: String) {
        grammarCorrectionTask = nil
        grammarCorrectionRequestID = nil
        actionPanelState = nil
        suggestionState = nil
        rewriteOptionsState = nil
        hasNoIssueAnalysisResult = false
        completionPanelState = .allDone
        isGrammarCorrectionLoading = false
        isPerformingAIAction = false
        if lastAnalyzedText == sourceText {
            lastAnalyzedText = nil
        }
        recordDebugEvent("grammar_correction_response_stale text=\(sourceText.count)")

        guard currentInputTextForAnalysis() != nil else {
            if !textDocumentProxy.hasText {
                clearComposingBuffer()
            }
            showAllDoneForEmptyText()
            return
        }

        aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        panelMode = .keyboard
        scheduleAutomaticAnalysis(delayNanoseconds: automaticAnalysisDelayNanoseconds)
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
        automaticAnalysisWarning = nil
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

    private func showActionError(
        _ sourceError: Error,
        scope: KeyboardActionErrorScope = .global
    ) {
        let keyboardError = sourceError as? KeyboardAIError
        let message = keyboardError?.errorDescription ?? sourceError.localizedDescription
        let error = KeyboardActionErrorState(
            kind: keyboardError?.actionErrorKind ?? .gatewayUnavailable,
            scope: scope,
            message: message
        )
        actionPanelTask?.cancel()
        actionPanelTask = nil
        actionPanelRequestID = nil
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

    private func invalidateActionPanelForSourceChange() {
        documentRevision += 1
        actionPanelRequestID = nil
        scheduleAutomaticAnalysisAfterTextChange()
        recordDebugEvent("action_panel_invalidated_source_changed")
    }

    private func showAutomaticAnalysisWarning(_ sourceError: Error) {
        let keyboardError = sourceError as? KeyboardAIError
        let warning = KeyboardActionErrorState(
            kind: keyboardError?.actionErrorKind ?? .gatewayUnavailable,
            scope: .grammar,
            message: keyboardError?.errorDescription ?? sourceError.localizedDescription
        )
        automaticAnalysisTask = nil
        automaticAnalysisWarning = warning
        suggestionState = nil
        rewriteOptionsState = nil
        hasNoIssueAnalysisResult = false
        aiStatus = warning.message
        isPerformingAIAction = false
        panelMode = .keyboard
    }

    func applyCurrentCorrection() {
        guard var state = suggestionState else { return }
        if let currentText = state.renderedGrammarText {
            guard currentInputTextForAnalysis() == currentText else {
                invalidateGrammarSessionForDocumentEdit()
                return
            }
            state.applyCurrentCorrection()
            guard let updatedText = state.renderedGrammarText else { return }
            replaceEditableText(with: updatedText)
            finishCorrectionStep(state)
            return
        }
        guard let updatedText = state.textByApplyingCurrentCorrection(to: currentEditableText()) else {
            dismissCurrentCorrection()
            return
        }
        replaceEditableText(with: updatedText)
        state.applyCurrentCorrection()
        finishCorrectionStep(state)
    }

    func dismissCurrentCorrection() {
        guard var state = suggestionState else { return }
        if let expectedText = state.renderedGrammarText, currentInputTextForAnalysis() != expectedText {
            invalidateGrammarSessionForDocumentEdit()
            return
        }
        state.dismissCurrentCorrection()
        finishCorrectionStep(state)
    }

    func acceptAllGrammarCorrections() {
        guard var state = suggestionState,
              let currentText = state.renderedGrammarText,
              currentInputTextForAnalysis() == currentText else {
            invalidateGrammarSessionForDocumentEdit()
            return
        }
        state.acceptAllGrammarCorrections()
        if let finalText = state.renderedGrammarText {
            replaceEditableText(with: finalText)
        }
        finishCorrectionStep(state)
    }

    func rejectAllGrammarCorrections() {
        guard var state = suggestionState else { return }
        if let expectedText = state.renderedGrammarText, currentInputTextForAnalysis() != expectedText {
            invalidateGrammarSessionForDocumentEdit()
            return
        }
        state.rejectAllGrammarCorrections()
        finishCorrectionStep(state)
    }

    func checkGrammarAgain() {
        guard !isGrammarCorrectionLoading else { return }
        suggestionState = nil
        hasNoIssueAnalysisResult = false
        lastAnalyzedText = nil
        requestGrammarCorrectionForCurrentText()
    }

    func documentDidChange() {
        if let state = actionPanelState {
            guard currentReplacementPlan() != state.replacementPlan else { return }
            invalidateActionPanelForSourceChange()
            return
        }
        let currentAnalysisText = currentInputTextForAnalysis()
        guard currentAnalysisText != lastAnalyzedText else {
            return
        }
        documentRevision += 1
        if automaticAnalysisWarning != nil {
            guard let lastAnalyzedText else {
                self.lastAnalyzedText = currentAnalysisText
                return
            }
            if currentAnalysisText != lastAnalyzedText {
                scheduleAutomaticAnalysisAfterTextChange()
            }
            return
        }
        if isPerformingAIAction, aiStatus == "Analyzing…" {
            scheduleAutomaticAnalysisAfterTextChange()
            return
        }
        guard let expectedText = suggestionState?.renderedGrammarText else { return }
        if currentAnalysisText != expectedText {
            invalidateGrammarSessionForDocumentEdit()
        }
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
            completionPanelState = .grammarReviewComplete
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
        actionPanelState = seededSuggestionState.actionPanelState
        rewriteOptionsState = seededSuggestionState.rewriteOptionsState
        actionError = seededSuggestionState.actionError
        automaticAnalysisWarning = seededSuggestionState.automaticAnalysisWarning
        panelMode = seededSuggestionState.panelMode
        aiStatus = seededSuggestionState.aiStatus
        isPerformingAIAction = seededSuggestionState.isPerformingAIAction
        hasNoIssueAnalysisResult = seededSuggestionState.hasNoIssueAnalysisResult
        completionPanelState = seededSuggestionState.completionPanelState
        if seededSuggestionState.automaticAnalysisWarning != nil {
            lastAnalyzedText = currentInputTextForAnalysis()
        }
        if seededSuggestionState.suggestionState != nil
            || seededSuggestionState.actionPanelState != nil
            || seededSuggestionState.rewriteOptionsState != nil
            || seededSuggestionState.actionError != nil
            || seededSuggestionState.automaticAnalysisWarning != nil {
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
        guard action.isReadyForRequest else {
            aiStatus = "Choose a language"
            recordDebugEvent("action_blocked_missing_translation_target")
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
        if action == .fixGrammar {
            automaticAnalysisWarning = nil
        }
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
                        showActionError(
                            KeyboardAIError.modelCapability,
                            scope: action == .fixGrammar ? .grammar : .writingAction
                        )
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    isPerformingAIAction = false
                    aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
                }
            } catch {
                await MainActor.run {
                    recordDebugEvent("action_request_failed:\(Self.sanitizedErrorMessage(error))")
                    showActionError(
                        error,
                        scope: action == .fixGrammar ? .grammar : .writingAction
                    )
                }
            }
        }
    }

    private func scheduleAutomaticAnalysisAfterTextChange() {
        if actionError?.scope == .grammar {
            actionError = nil
        }
        if automaticAnalysisWarning != nil {
            automaticAnalysisWarning = nil
            aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        }
        refreshTypingPredictions()
        let hadAIActionTask = actionPanelTask != nil
            || grammarCorrectionTask != nil
            || isGrammarCorrectionLoading
            || aiStatus == "Analyzing…"
        actionPanelTask?.cancel()
        actionPanelTask = nil
        automaticAnalysisTask?.cancel()
        automaticAnalysisTask = nil
        grammarCorrectionTask?.cancel()
        grammarCorrectionTask = nil
        grammarCorrectionRequestID = nil
        isGrammarCorrectionLoading = false
        if isPerformingAIAction, hadAIActionTask {
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
        panelMode = .keyboard
        scheduleAutomaticAnalysis(delayNanoseconds: automaticAnalysisDelayNanoseconds)
    }

    private func refreshTypingPredictions() {
        guard typingPredictionsEnabled else {
            typingPredictions = []
            return
        }

        let text = currentEditableText()
        typingPredictions = nextTextPredictor
            .predictions(for: NextTextPredictionRequest(text: text, maxSuggestions: 3))
            .map { prediction in
                KeyboardPredictionSuggestion(
                    label: prediction.kind == .completion ? "Complete" : "Next word",
                    text: prediction.text,
                    kind: prediction.kind.rawValue
                )
            }
    }

    private func requestActionPanelResult(_ action: KeyboardAIAction, replacementPlan: KeyboardReplacementPlan) {
        actionPanelTask?.cancel()
        actionPanelTask = nil
        actionPanelRequestID = nil
        guard action.isReadyForActionPanelRequest else {
            isPerformingAIAction = false
            if action.isTranslation {
                aiStatus = "Choose a language"
            }
            return
        }
        guard hasFullAccess else {
            showActionError(
                KeyboardAIError.server("Enable Allow Full Access"),
                scope: .writingAction
            )
            return
        }
        config = loadConfig()
        gatewayConnectionError = Self.normalizedGatewayConnectionError(loadGatewayConnectionError())
        if let gatewayConnectionError {
            showActionError(
                KeyboardAIError.server(gatewayConnectionError),
                scope: .writingAction
            )
            return
        }
        guard hasUsableGatewayConfig else {
            showActionError(KeyboardAIError.notConfigured, scope: .writingAction)
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
        let requestID = UUID()
        actionPanelRequestID = requestID
        recordDebugEvent("action_panel_request_start action=\(action.rawValue) text=\(replacementPlan.textForAI.count)")
        actionPanelTask = Task { [weak self] in
            do {
                guard let self else { return }
                let result = try await self.aiService.performResult(action: action, on: replacementPlan.textForAI, config: currentConfig)
                await MainActor.run {
                    guard self.actionPanelRequestID == requestID else {
                        self.recordDebugEvent("action_panel_response_discarded_stale_request")
                        return
                    }
                    guard self.panelMode == .actions,
                          var state = self.actionPanelState,
                          state.replacementPlan == replacementPlan,
                          state.selectedAction == action else {
                        self.invalidateActionPanelForSourceChange()
                        return
                    }
                    guard self.currentReplacementPlan() == replacementPlan else {
                        self.invalidateActionPanelForSourceChange()
                        return
                    }

                    let outcome = KeyboardActionResultHandler.outcome(
                        operation: action.operationName,
                        result: result,
                        sourceText: replacementPlan.textForAI
                    )
                    let options = self.actionPanelOptions(from: outcome, action: action)
                    guard !options.isEmpty else {
                        if let target = action.translationTarget {
                            self.showTranslationCapabilityWarning(
                                target: target,
                                action: action,
                                replacementPlan: replacementPlan
                            )
                        } else {
                            self.showActionError(KeyboardAIError.modelCapability, scope: .writingAction)
                        }
                        return
                    }

                    state.finishLoading(options: options)
                    self.actionPanelState = state
                    self.rewriteOptionsState = nil
                    self.aiStatus = "\(action.title) ready"
                    self.isPerformingAIAction = false
                    self.actionPanelTask = nil
                    self.actionPanelRequestID = nil
                    self.recordDebugEvent("action_panel_request_success action=\(action.rawValue) options=\(options.count)")
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let self,
                          self.actionPanelRequestID == requestID,
                          self.panelMode == .actions,
                          self.actionPanelState?.replacementPlan == replacementPlan,
                          self.actionPanelState?.selectedAction == action else {
                        return
                    }
                    self.showActionError(
                        KeyboardAIError.server("Request cancelled. Try again."),
                        scope: .writingAction
                    )
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          self.actionPanelRequestID == requestID,
                          self.panelMode == .actions,
                          self.actionPanelState?.replacementPlan == replacementPlan,
                          self.actionPanelState?.selectedAction == action,
                          self.currentReplacementPlan() == replacementPlan else {
                        return
                    }
                    self.recordDebugEvent("action_panel_request_failed:\(Self.sanitizedErrorMessage(error))")
                    if let target = Self.translationCapabilityWarningTarget(for: error, action: action) {
                        self.showTranslationCapabilityWarning(
                            target: target,
                            action: action,
                            replacementPlan: replacementPlan
                        )
                    } else {
                        self.showActionError(error, scope: .writingAction)
                    }
                }
            }
        }
    }

    private static func translationCapabilityWarningTarget(
        for error: Error,
        action: KeyboardAIAction
    ) -> KeyboardTranslationTarget? {
        guard let selectedTarget = action.translationTarget,
              let keyboardError = error as? KeyboardAIError else {
            return nil
        }
        switch keyboardError {
        case .modelCapability:
            return selectedTarget
        case .unreliableTranslation(let target):
            return target
        default:
            return nil
        }
    }

    private func showTranslationCapabilityWarning(
        target: KeyboardTranslationTarget,
        action: KeyboardAIAction,
        replacementPlan: KeyboardReplacementPlan
    ) {
        guard panelMode == .actions,
              var state = actionPanelState,
              state.replacementPlan == replacementPlan,
              state.selectedAction == action else {
            isPerformingAIAction = false
            actionPanelTask = nil
            actionPanelRequestID = nil
            return
        }
        state.finishLoading(warningMessage: target.translationCapabilityWarning)
        actionPanelState = state
        rewriteOptionsState = nil
        actionError = nil
        aiStatus = "Translation warning"
        isPerformingAIAction = false
        actionPanelTask = nil
        actionPanelRequestID = nil
        recordDebugEvent("translation_capability_warning target=\(target.rawValue)")
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
        guard automaticAnalysisWarning == nil else { return }
        guard canRunAIAction else { return }
        guard currentInputTextForAnalysis() != nil else {
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
        guard automaticAnalysisWarning == nil else { return }
        guard suggestionState == nil, !hasNoIssueAnalysisResult else { return }
        guard currentInputTextForAnalysis() != nil else {
            clearAutomaticAnalysisState()
            return
        }

        scheduleAutomaticAnalysis(delayNanoseconds: 0)
    }

    private func runAutomaticAnalysis() async {
        guard !isPerformingAIAction,
              canRunAIAction,
              panelMode == .keyboard,
              actionError == nil,
              automaticAnalysisWarning == nil else {
            return
        }
        guard let analysisText = currentInputTextForAnalysis() else {
            clearAutomaticAnalysisState()
            return
        }
        guard analysisText.count >= 3 else {
            clearAutomaticAnalysisState()
            return
        }
        if lastAnalyzedText == analysisText, canOpenAnalysisResult { return }

        let currentConfig = config
        let documentTextAtRequest = currentDocumentTextForAnalysis()
        let documentRevisionAtRequest = documentRevision
        lastAnalyzedText = analysisText
        isPerformingAIAction = true
        aiStatus = "Analyzing…"
        recordDebugEvent("automatic_analysis_start text=\(analysisText.count) model=\(currentConfig.selectedModel)")

        do {
            let result = try await aiService.performResult(action: .fixGrammar, on: analysisText, config: currentConfig)
            guard let currentAnalysisText = currentInputTextForAnalysis(knownStaleContextText: documentTextAtRequest),
                  currentAnalysisText == analysisText,
                  documentRevision == documentRevisionAtRequest else {
                isPerformingAIAction = false
                if lastAnalyzedText == analysisText {
                    lastAnalyzedText = nil
                }
                if !textDocumentProxy.hasText {
                    clearComposingBuffer()
                    clearAutomaticAnalysisState()
                } else {
                    scheduleAutomaticAnalysis(delayNanoseconds: automaticAnalysisDelayNanoseconds)
                }
                return
            }
            guard panelMode == .keyboard else {
                isPerformingAIAction = false
                return
            }
            applyAutomaticAnalysisResult(
                KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result, sourceText: analysisText),
                sourceText: analysisText,
                documentRevision: documentRevisionAtRequest
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
            recordDebugEvent("automatic_analysis_failed:\(Self.sanitizedErrorMessage(error))")
            guard !Task.isCancelled,
                  !isGrammarCorrectionLoading,
                  panelMode == .keyboard,
                  documentRevision == documentRevisionAtRequest,
                  lastAnalyzedText == analysisText,
                  currentInputTextForAnalysis(knownStaleContextText: documentTextAtRequest) == analysisText else {
                recordDebugEvent("automatic_analysis_failure_discarded_stale_request")
                return
            }
            showAutomaticAnalysisWarning(error)
        }
    }

    private func applyAutomaticAnalysisResult(_ outcome: KeyboardActionProductOutcome, sourceText: String, documentRevision: Int) {
        automaticAnalysisWarning = nil
        switch outcome {
        case .showCorrections(let response):
            if let correctedText = response.correctedText {
                suggestionState = KeyboardSuggestionState(
                    grammarOriginal: sourceText,
                    correctedText: correctedText,
                    documentRevision: documentRevision
                )
            } else {
                suggestionState = KeyboardSuggestionState(response: response, sourceContext: sourceText)
            }
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
            showAutomaticAnalysisWarning(KeyboardAIError.modelCapability)
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

    private func invalidateGrammarSessionForDocumentEdit() {
        guard suggestionState?.grammarSession != nil else { return }
        suggestionState = nil
        hasNoIssueAnalysisResult = false
        lastAnalyzedText = nil
        completionPanelState = .allDone
        aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        panelMode = .keyboard
        recordDebugEvent("grammar_correction_session_invalidated")
    }

    private func clearAutomaticAnalysisState() {
        let hadAutomaticAnalysisWarning = automaticAnalysisWarning != nil
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
        automaticAnalysisWarning = nil
        hasNoIssueAnalysisResult = false
        completionPanelState = .allDone
        lastAnalyzedText = nil
        isGrammarCorrectionLoading = false
        isPerformingAIAction = false
        if hadAutomaticAnalysisWarning {
            aiStatus = hasUsableGatewayConfig ? "Ready" : "Pair gateway in app"
        }
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
        documentRevision += 1
        automaticAnalysisWarning = nil
        composingBuffer = finalReplacement
        rememberKeyboardReplacement(
            sourceText: plan.textForAI,
            resultText: finalReplacement,
            preservesOutputWhitespace: plan.preservesOutputWhitespace
        )
        persistComposingBuffer()
        refreshTypingPredictions()
    }

    private func insertTypingPrediction(_ prediction: KeyboardPredictionSuggestion) {
        let currentText = currentEditableText()
        let predictionText = prediction.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !predictionText.isEmpty else { return }

        if prediction.kind == NextTextPredictionKind.completion.rawValue,
           let partialToken = Self.trailingPredictionToken(in: currentText) {
            for _ in partialToken {
                textDocumentProxy.deleteBackward()
            }
            if composingBuffer.hasSuffix(partialToken) {
                composingBuffer.removeLast(partialToken.count)
            }
            textDocumentProxy.insertText(predictionText)
            composingBuffer.append(predictionText)
            return
        }

        let insertionText = Self.predictionInsertionText(predictionText, after: currentText)
        textDocumentProxy.insertText(insertionText)
        composingBuffer.append(insertionText)
    }

    private func shouldPreferComposingBuffer(over context: String) -> Bool {
        guard let contextPlan = KeyboardReplacementPlanner.plan(for: context),
              let bufferPlan = KeyboardReplacementPlanner.plan(for: composingBuffer) else {
            return false
        }
        return shouldPreferComposingBuffer(contextPlan: contextPlan, bufferPlan: bufferPlan)
    }

    private func shouldPreferComposingBuffer(
        contextPlan: KeyboardReplacementPlan,
        bufferPlan: KeyboardReplacementPlan,
        knownStaleContextText: String? = nil
    ) -> Bool {
        guard let replacementResult = lastKeyboardReplacementResultText,
              bufferPlan.textForAI == replacementResult,
              contextPlan.textForAI != replacementResult else {
            return false
        }

        if contextPlan.textForAI == lastKeyboardReplacementSourceText {
            return true
        }
        if let knownStaleContextText, contextPlan.textForAI == knownStaleContextText {
            return true
        }
        if let lastAnalyzedText, contextPlan.textForAI == lastAnalyzedText {
            return true
        }
        return false
    }

    private func rememberKeyboardReplacement(
        sourceText: String?,
        resultText: String,
        preservesOutputWhitespace: Bool = false
    ) {
        lastKeyboardReplacementSourceText = sourceText
        lastKeyboardReplacementResultText = preservesOutputWhitespace
            ? KeyboardReplacementPlanner.grammarPlan(for: resultText)?.textForAI
            : KeyboardReplacementPlanner.plan(for: resultText)?.textForAI
    }

    private func clearKeyboardReplacementTracking() {
        lastKeyboardReplacementSourceText = nil
        lastKeyboardReplacementResultText = nil
    }

    private func currentEditableText() -> String {
        if let plan = currentReplacementPlan() {
            return plan.textToReplace
        }
        if let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty {
            if shouldPreferComposingBuffer(over: context) {
                return composingBuffer
            }
            return context
        }
        return composingBuffer
    }

    private func currentReplacementPlan() -> KeyboardReplacementPlan? {
        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput
        let contextAfterInput = textDocumentProxy.documentContextAfterInput
        let fallbackContext = composingBuffer.isEmpty ? nil : composingBuffer
        let contextPlan = KeyboardReplacementPlanner.plan(
            contextBeforeInput: contextBeforeInput,
            contextAfterInput: contextAfterInput
        )
        let bufferPlan = KeyboardReplacementPlanner.plan(for: fallbackContext)

        if let contextPlan,
           let bufferPlan,
           shouldPreferComposingBuffer(contextPlan: contextPlan, bufferPlan: bufferPlan) {
            return bufferPlan
        }
        return contextPlan ?? bufferPlan
    }

    private func currentActionPanelReplacementPlan() -> KeyboardReplacementPlan? {
        guard textDocumentProxy.hasText else { return nil }
        return currentReplacementPlan()
    }

    private func currentDocumentTextForAnalysis() -> String? {
        KeyboardReplacementPlanner.grammarPlan(
            contextBeforeInput: textDocumentProxy.documentContextBeforeInput,
            contextAfterInput: textDocumentProxy.documentContextAfterInput
        )?.textForAI
    }

    private func currentInputTextForAnalysis(knownStaleContextText: String? = nil) -> String? {
        guard textDocumentProxy.hasText else { return nil }

        let contextBeforeInput = textDocumentProxy.documentContextBeforeInput
        let contextAfterInput = textDocumentProxy.documentContextAfterInput
        let fallbackContext = composingBuffer.isEmpty ? nil : composingBuffer
        let bufferPlan = KeyboardReplacementPlanner.grammarPlan(for: fallbackContext)
        if let contextPlan = KeyboardReplacementPlanner.grammarPlan(
            contextBeforeInput: contextBeforeInput,
            contextAfterInput: contextAfterInput
        ) {
            if let bufferPlan,
               shouldPreferComposingBuffer(
                   contextPlan: contextPlan,
                   bufferPlan: bufferPlan,
                   knownStaleContextText: knownStaleContextText
               ) {
                return bufferPlan.textForAI
            }
            return contextPlan.textForAI
        }

        guard contextBeforeInput == nil, contextAfterInput == nil else { return nil }
        return bufferPlan?.textForAI
    }

    private func replaceEditableText(with replacement: String) {
        if let plan = KeyboardReplacementPlanner.grammarPlan(
            contextBeforeInput: textDocumentProxy.documentContextBeforeInput,
            contextAfterInput: textDocumentProxy.documentContextAfterInput
        ) {
            replace(plan: plan, with: replacement)
            return
        }
        let currentText = currentEditableText()
        let sourceText = KeyboardReplacementPlanner.grammarPlan(for: currentText)?.textForAI
        for _ in currentText {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(replacement)
        documentRevision += 1
        composingBuffer = replacement
        rememberKeyboardReplacement(sourceText: sourceText, resultText: replacement, preservesOutputWhitespace: true)
        persistComposingBuffer()
        refreshTypingPredictions()
    }

    private static func predictionInsertionText(_ prediction: String, after text: String) -> String {
        let trimmedPrediction = prediction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrediction.isEmpty else { return "" }
        guard let lastCharacter = text.last, !lastCharacter.isWhitespace else {
            return trimmedPrediction
        }
        return " \(trimmedPrediction)"
    }

    private static func trailingPredictionToken(in text: String) -> String? {
        let tokenCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'"))
        var suffix = ""
        for character in text.reversed() {
            guard character.unicodeScalars.allSatisfy({ tokenCharacters.contains($0) }) else { break }
            suffix.insert(character, at: suffix.startIndex)
        }
        return suffix.isEmpty ? nil : suffix
    }

    private func persistComposingBuffer() {
        guard Self.debugStateEnabled, let defaults = AppConfig.sharedDefaults() else { return }
        defaults.set(String(composingBuffer.suffix(500)), forKey: Keys.composingBuffer)
        defaults.synchronize()
    }

    private func clearComposingBuffer() {
        composingBuffer.removeAll()
        clearKeyboardReplacementTracking()
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

    private static func sanitizedErrorMessage(_ error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return KeyboardActionErrorState.sanitized(message)
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
        let actionPanelState: KeyboardActionPanelState?
        let rewriteOptionsState: KeyboardRewriteOptionsState?
        let actionError: KeyboardActionErrorState?
        let automaticAnalysisWarning: KeyboardActionErrorState?
        let aiStatus: String
        let isPerformingAIAction: Bool
        let hasNoIssueAnalysisResult: Bool
        let completionPanelState: KeyboardCompletionPanelState

        @MainActor
        init?(rawValue: String) {
            automaticAnalysisWarning = rawValue == "automaticModelCapabilityWarning"
                ? KeyboardActionErrorState(
                    kind: .modelCapability,
                    scope: .grammar,
                    message: KeyboardActionErrorState.modelCapabilityMessage
                )
                : nil
            switch rawValue {
            case "rewriteOptions":
                panelMode = .rewriteOptions
                suggestionState = nil
                actionPanelState = nil
                rewriteOptionsState = Self.rewriteOptionsState
                actionError = nil
                aiStatus = "1 rephrase ready"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "improvePanel":
                panelMode = .actions
                suggestionState = nil
                actionPanelState = Self.improveActionPanelState
                rewriteOptionsState = nil
                actionError = nil
                aiStatus = "Improve ready"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "actionLoadingPanel":
                panelMode = .actions
                suggestionState = nil
                actionPanelState = Self.actionLoadingPanelState
                rewriteOptionsState = nil
                actionError = nil
                aiStatus = "Improve…"
                isPerformingAIAction = true
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "rephraseComparisonPanel":
                panelMode = .actions
                suggestionState = nil
                actionPanelState = Self.rephraseComparisonActionPanelState
                rewriteOptionsState = nil
                actionError = nil
                aiStatus = "Rephrase ready"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "actionCarouselPanel":
                panelMode = .actions
                suggestionState = nil
                actionPanelState = Self.actionCarouselPanelState
                rewriteOptionsState = nil
                actionError = nil
                aiStatus = "Actions ready"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "translatePanel":
                panelMode = .actions
                suggestionState = nil
                actionPanelState = Self.translateActionPanelState
                rewriteOptionsState = nil
                actionError = nil
                aiStatus = "Translate ready"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "translationWarning":
                panelMode = .actions
                suggestionState = nil
                actionPanelState = Self.translationWarningActionPanelState
                rewriteOptionsState = nil
                actionError = nil
                aiStatus = "Translation warning"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "correctionCard", "correctionDetail", "correctionCarousel":
                panelMode = .correctionDetail
                suggestionState = KeyboardSuggestionState(
                    response: Self.carouselResponse,
                    sourceContext: "i has a apple and ths sentence"
                )
                actionPanelState = nil
                rewriteOptionsState = nil
                actionError = nil
                aiStatus = "Suggestions ready"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "correctionComplete":
                panelMode = .correctionComplete
                suggestionState = nil
                actionPanelState = nil
                rewriteOptionsState = nil
                actionError = nil
                aiStatus = "No more suggestions"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "allGood":
                panelMode = .correctionComplete
                suggestionState = nil
                actionPanelState = nil
                rewriteOptionsState = nil
                actionError = nil
                aiStatus = "No issues found"
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = true
                completionPanelState = .noIssues
            case "analyzing":
                panelMode = .keyboard
                suggestionState = nil
                actionPanelState = nil
                rewriteOptionsState = nil
                actionError = nil
                aiStatus = "Analyzing your text..."
                isPerformingAIAction = true
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "modelCapabilityError":
                panelMode = .keyboard
                suggestionState = nil
                actionPanelState = nil
                rewriteOptionsState = nil
                actionError = KeyboardActionErrorState(
                    kind: .modelCapability,
                    scope: .grammar,
                    message: KeyboardActionErrorState.modelCapabilityMessage
                )
                aiStatus = KeyboardActionErrorState.modelCapabilityMessage
                isPerformingAIAction = false
                hasNoIssueAnalysisResult = false
                completionPanelState = .allDone
            case "automaticModelCapabilityWarning":
                panelMode = .keyboard
                suggestionState = nil
                actionPanelState = nil
                rewriteOptionsState = nil
                actionError = nil
                aiStatus = KeyboardActionErrorState.modelCapabilityMessage
                isPerformingAIAction = false
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
                    KeyboardRewriteOption(
                        id: "plain-text-result",
                        title: "Rephrased",
                        text: "None of these are bulbs in the universe."
                    )
                ]
            )
        }

        private static var improveActionPanelState: KeyboardActionPanelState {
            let sourceText = "Do you know that our test phrases are essentially meaningless, making them hard to rephrase? Technically, they are being rephrased, but not very effectively. Could you add a few longer, more meaningful sentences?"
            let improvedText = """
            SCROLL TEST START

            A reliable writing workflow needs enough context to preserve the original meaning while improving clarity, structure, and tone. Short examples are useful for quick checks, but they do not reveal whether a result panel remains usable when a response contains several detailed paragraphs.

            The first section explains the problem, the audience, and the intended outcome. It should remain easy to read without forcing the surrounding controls to move. The action selector, rerun button, copy button, keyboard button, and apply button should stay fixed while only this text area scrolls.

            The second section adds enough material to exceed the visible result area. It includes complete sentences of different lengths so line wrapping behaves like realistic generated content instead of a repeated placeholder. Scrolling should feel direct, should not move the entire keyboard, and should not accidentally trigger any action buttons.

            The third section confirms that Rephrase and Summarize use the same viewport geometry as Improve. Switching between those actions must not make the extension jump in height, because a changing keyboard frame can distract the user and shift the host application's content unexpectedly.

            The fourth section provides additional content for repeated swipe testing. A user should be able to move down, pause to read, continue to the end, and then return to the beginning. The scroll indicator should accurately reflect the current position within the generated response.

            The final section is intentionally placed well below the initial viewport. Reaching the marker below proves that the complete response remains available instead of being clipped or truncated by the fixed action-panel height.

            SCROLL TEST END
            """
            let replacementPlan = KeyboardReplacementPlan(
                textToDelete: sourceText,
                textForAI: sourceText,
                leadingWhitespace: "",
                trailingWhitespace: ""
            )
            return KeyboardActionPanelState(
                sourceText: sourceText,
                replacementPlan: replacementPlan,
                selectedAction: .improve,
                options: [
                    KeyboardRewriteOption(
                        id: "improve-option-1",
                        title: "Clearer",
                        text: improvedText
                    )
                ],
                isCarouselVisible: true,
                isLoading: false
            )
        }

        private static var translateActionPanelState: KeyboardActionPanelState {
            let sourceText = "Good morning, I hope you are well."
            return KeyboardActionPanelState(
                sourceText: sourceText,
                replacementPlan: KeyboardReplacementPlan(
                    textToDelete: sourceText,
                    textForAI: sourceText,
                    leadingWhitespace: "",
                    trailingWhitespace: ""
                ),
                selectedAction: .translate(.arabic),
                options: [
                    KeyboardRewriteOption(
                        id: "translate-result-1",
                        title: "Arabic translation",
                        text: "صباح الخير، أتمنى أن تكون بخير."
                    )
                ],
                isCarouselVisible: true,
                isLoading: false
            )
        }

        private static var rephraseComparisonActionPanelState: KeyboardActionPanelState {
            let sourceText = "send the customer a update tomorrow"
            let replacementText = "Send the customer an update tomorrow."
            return KeyboardActionPanelState(
                sourceText: sourceText,
                replacementPlan: KeyboardReplacementPlan(
                    textToDelete: sourceText,
                    textForAI: sourceText,
                    leadingWhitespace: "",
                    trailingWhitespace: ""
                ),
                selectedAction: .rewrite,
                options: [
                    KeyboardRewriteOption(
                        id: "plain-text-result",
                        title: "Rephrased",
                        text: replacementText
                    )
                ],
                isCarouselVisible: true,
                isLoading: false
            )
        }

        private static var actionLoadingPanelState: KeyboardActionPanelState {
            let sourceText = "send the customer a update tomorrow"
            return KeyboardActionPanelState(
                sourceText: sourceText,
                replacementPlan: KeyboardReplacementPlan(
                    textToDelete: sourceText,
                    textForAI: sourceText,
                    leadingWhitespace: "",
                    trailingWhitespace: ""
                ),
                selectedAction: .improve,
                isCarouselVisible: true,
                isLoading: true
            )
        }

        private static var translationWarningActionPanelState: KeyboardActionPanelState {
            let sourceText = "Good morning, I hope you are well."
            return KeyboardActionPanelState(
                sourceText: sourceText,
                replacementPlan: KeyboardReplacementPlan(
                    textToDelete: sourceText,
                    textForAI: sourceText,
                    leadingWhitespace: "",
                    trailingWhitespace: ""
                ),
                selectedAction: .translate(.arabic),
                isCarouselVisible: true,
                isLoading: false,
                warningMessage: KeyboardTranslationTarget.arabic.translationCapabilityWarning
            )
        }

        private static var actionCarouselPanelState: KeyboardActionPanelState {
            let sourceText = "Please send the customer an update about the delivery."
            return KeyboardActionPanelState(
                sourceText: sourceText,
                replacementPlan: KeyboardReplacementPlan(
                    textToDelete: sourceText,
                    textForAI: sourceText,
                    leadingWhitespace: "",
                    trailingWhitespace: ""
                ),
                selectedAction: .improve,
                isCarouselVisible: true,
                isLoading: false
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
        case .rewriteStyle(let style): return style.displayName
        case .summarize: return "Summary"
        case .translate(let target): return target.map { "\($0.displayName) translation" } ?? "Translation"
        }
    }
}
