import XCTest
import UIKit

@MainActor
final class KeyboardViewModelActionErrorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppConfig.clearGatewayConnectionError()
    }

    override func tearDown() {
        UIPasteboard.general.string = nil
        AppConfig.clearGatewayConnectionError()
        super.tearDown()
    }

    func testLocalNLPPredictionsAreDisabledByDefault() {
        let predictor = RecordingNextTextPredictor()
        let viewModel = KeyboardViewModel(
            textDocumentProxy: FakeTextDocumentProxy(text: ""),
            aiService: FailingKeyboardAIService(),
            nextTextPredictor: predictor,
            loadConfig: { Self.configuredGateway }
        )

        viewModel.insert("H")
        viewModel.insert("i")

        XCTAssertTrue(viewModel.typingPredictions.isEmpty)
        XCTAssertTrue(predictor.requests.isEmpty)
    }

    func testLocalNLPPredictionsUpdateWhileTyping() {
        let predictor = AppleNaturalLanguageNextTextPredictor(corpus: NextTextPredictionCorpus(texts: [
            "How are you?",
            "How can I help?",
            "How is everything?"
        ]))
        let viewModel = KeyboardViewModel(
            textDocumentProxy: FakeTextDocumentProxy(text: ""),
            aiService: FailingKeyboardAIService(),
            nextTextPredictor: predictor,
            typingPredictionsEnabled: true,
            loadConfig: { Self.configuredGateway }
        )

        viewModel.insert("H")
        viewModel.insert("o")

        XCTAssertEqual(viewModel.typingPredictions.first?.text, "how")
        XCTAssertEqual(viewModel.typingPredictions.first?.kind, NextTextPredictionKind.completion.rawValue)

        viewModel.insert("w")
        viewModel.insertSpace()

        XCTAssertEqual(viewModel.typingPredictions.map(\.text), ["are", "can", "is"])
        XCTAssertTrue(viewModel.typingPredictions.allSatisfy { $0.kind == NextTextPredictionKind.nextWord.rawValue })
    }

    func testApplyingCompletionPredictionReplacesPartialWord() throws {
        let proxy = FakeTextDocumentProxy(text: "Ho")
        let predictor = AppleNaturalLanguageNextTextPredictor(corpus: NextTextPredictionCorpus(texts: [
            "Hope this helps.",
            "Home screen is ready."
        ]))
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: FailingKeyboardAIService(),
            nextTextPredictor: predictor,
            typingPredictionsEnabled: true,
            loadConfig: { Self.configuredGateway }
        )

        let prediction = try XCTUnwrap(viewModel.typingPredictions.first { $0.text == "hope" })
        viewModel.applyTypingPrediction(id: prediction.id)

        XCTAssertEqual(proxy.text, "hope")
    }

    func testApplyingNextWordPredictionInsertsSeparatedWord() throws {
        let proxy = FakeTextDocumentProxy(text: "How ")
        let predictor = AppleNaturalLanguageNextTextPredictor(corpus: NextTextPredictionCorpus(texts: [
            "How are you?",
            "How can I help?"
        ]))
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: FailingKeyboardAIService(),
            nextTextPredictor: predictor,
            typingPredictionsEnabled: true,
            loadConfig: { Self.configuredGateway }
        )

        let prediction = try XCTUnwrap(viewModel.typingPredictions.first { $0.text == "are" })
        viewModel.applyTypingPrediction(id: prediction.id)

        XCTAssertEqual(proxy.text, "How are")
    }

    func testLegacyPersistedRewriteSeedIsIgnoredAndCleared() throws {
        try withSharedKeyboardDebugSeedDefaults { defaults in
            defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
            defaults.set("rewriteOptions", forKey: "keyboardExtension.suggestionState")
            defaults.set("rewriteOptions", forKey: "keyboardExtension.initialPanelMode")
            defaults.removeObject(forKey: "keyboardExtension.suggestionStateSeedID")
            defaults.removeObject(forKey: "keyboardExtension.initialPanelModeSeedID")
            defaults.synchronize()

            let viewModel = KeyboardViewModel(
                textDocumentProxy: FakeTextDocumentProxy(text: "plain text"),
                aiService: FailingKeyboardAIService(),
                loadConfig: { Self.configuredGateway },
                productionTestFullAccess: true
            )

            XCTAssertEqual(viewModel.panelMode, .keyboard)
            XCTAssertNil(viewModel.rewriteOptionsState)
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionState"))
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.initialPanelMode"))
        }
    }

    func testStalePersistedRewriteSeedIsIgnoredAndCleared() throws {
        try withSharedKeyboardDebugSeedDefaults { defaults in
            let staleSeededAt = Date().timeIntervalSince1970 - 3_600
            defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
            defaults.set("rewriteOptions", forKey: "keyboardExtension.suggestionState")
            defaults.set("rewrite-seed", forKey: "keyboardExtension.suggestionStateSeedID")
            defaults.set(staleSeededAt, forKey: "keyboardExtension.suggestionStateSeededAt")
            defaults.set("rewriteOptions", forKey: "keyboardExtension.initialPanelMode")
            defaults.set("panel-seed", forKey: "keyboardExtension.initialPanelModeSeedID")
            defaults.set(staleSeededAt, forKey: "keyboardExtension.initialPanelModeSeededAt")
            defaults.synchronize()

            let viewModel = KeyboardViewModel(
                textDocumentProxy: FakeTextDocumentProxy(text: "plain text"),
                aiService: FailingKeyboardAIService(),
                loadConfig: { Self.configuredGateway },
                productionTestFullAccess: true
            )

            XCTAssertEqual(viewModel.panelMode, .keyboard)
            XCTAssertNil(viewModel.rewriteOptionsState)
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionState"))
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionStateSeedID"))
            XCTAssertNil(defaults.object(forKey: "keyboardExtension.suggestionStateSeededAt"))
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.initialPanelMode"))
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.initialPanelModeSeedID"))
            XCTAssertNil(defaults.object(forKey: "keyboardExtension.initialPanelModeSeededAt"))
        }
    }

    func testSeededRewriteOptionsStateIsOneShot() throws {
        try withSharedKeyboardDebugSeedDefaults { defaults in
            let seededAt = Date().timeIntervalSince1970
            defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
            defaults.set("rewriteOptions", forKey: "keyboardExtension.suggestionState")
            defaults.set("rewrite-seed", forKey: "keyboardExtension.suggestionStateSeedID")
            defaults.set(seededAt, forKey: "keyboardExtension.suggestionStateSeededAt")
            defaults.set("rewriteOptions", forKey: "keyboardExtension.initialPanelMode")
            defaults.set("panel-seed", forKey: "keyboardExtension.initialPanelModeSeedID")
            defaults.set(seededAt, forKey: "keyboardExtension.initialPanelModeSeededAt")
            defaults.synchronize()

            let viewModel = KeyboardViewModel(
                textDocumentProxy: FakeTextDocumentProxy(text: "All of these are no bulb in the universe."),
                aiService: FailingKeyboardAIService(),
                loadConfig: { Self.configuredGateway }
            )

            XCTAssertEqual(viewModel.panelMode, .rewriteOptions)
            XCTAssertEqual(viewModel.rewriteOptionsState?.sourceText, "All of these are no bulb in the universe.")
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionState"))
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionStateSeedID"))
            XCTAssertNil(defaults.object(forKey: "keyboardExtension.suggestionStateSeededAt"))
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.initialPanelMode"))
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.initialPanelModeSeedID"))
            XCTAssertNil(defaults.object(forKey: "keyboardExtension.initialPanelModeSeededAt"))
        }
    }

    func testSeededImprovePanelStateIsOneShot() throws {
        try withSharedKeyboardDebugSeedDefaults { defaults in
            let seededAt = Date().timeIntervalSince1970
            defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
            defaults.set("improvePanel", forKey: "keyboardExtension.suggestionState")
            defaults.set("improve-seed", forKey: "keyboardExtension.suggestionStateSeedID")
            defaults.set(seededAt, forKey: "keyboardExtension.suggestionStateSeededAt")
            defaults.synchronize()

            let viewModel = KeyboardViewModel(
                textDocumentProxy: FakeTextDocumentProxy(text: "Long text for the improve panel."),
                aiService: FailingKeyboardAIService(),
                loadConfig: { Self.configuredGateway }
            )

            XCTAssertEqual(viewModel.panelMode, .actions)
            XCTAssertEqual(viewModel.actionPanelState?.selectedAction, .improve)
            XCTAssertEqual(viewModel.actionPanelState?.isLoading, false)
            let seededResult = try XCTUnwrap(viewModel.actionPanelState?.selectedOption?.text)
            XCTAssertTrue(seededResult.contains("SCROLL TEST START"))
            XCTAssertTrue(seededResult.contains("SCROLL TEST END"))
            XCTAssertNil(viewModel.rewriteOptionsState)
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionState"))
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionStateSeedID"))
            XCTAssertNil(defaults.object(forKey: "keyboardExtension.suggestionStateSeededAt"))
        }
    }

    func testSeededTranslatePanelStateIsOneShot() throws {
        try withSharedKeyboardDebugSeedDefaults { defaults in
            let seededAt = Date().timeIntervalSince1970
            defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
            defaults.set("translatePanel", forKey: "keyboardExtension.suggestionState")
            defaults.set("translate-seed", forKey: "keyboardExtension.suggestionStateSeedID")
            defaults.set(seededAt, forKey: "keyboardExtension.suggestionStateSeededAt")
            defaults.synchronize()

            let viewModel = KeyboardViewModel(
                textDocumentProxy: FakeTextDocumentProxy(text: "Good morning, I hope you are well."),
                aiService: FailingKeyboardAIService(),
                loadConfig: { Self.configuredGateway }
            )

            XCTAssertEqual(viewModel.panelMode, .actions)
            XCTAssertEqual(viewModel.actionPanelState?.selectedAction, .translate(.arabic))
            XCTAssertEqual(viewModel.actionPanelState?.selectedTranslationTarget, .arabic)
            XCTAssertEqual(viewModel.actionPanelState?.isLoading, false)
            XCTAssertEqual(
                viewModel.actionPanelState?.selectedOption?.text,
                "صباح الخير، أتمنى أن تكون بخير."
            )
            XCTAssertNil(viewModel.rewriteOptionsState)
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionState"))
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionStateSeedID"))
            XCTAssertNil(defaults.object(forKey: "keyboardExtension.suggestionStateSeededAt"))
        }
    }

    func testSeededActionCarouselPanelStateIsOneShot() throws {
        try withSharedKeyboardDebugSeedDefaults { defaults in
            let seededAt = Date().timeIntervalSince1970
            defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
            defaults.set("actionCarouselPanel", forKey: "keyboardExtension.suggestionState")
            defaults.set("action-carousel-seed", forKey: "keyboardExtension.suggestionStateSeedID")
            defaults.set(seededAt, forKey: "keyboardExtension.suggestionStateSeededAt")
            defaults.synchronize()

            let viewModel = KeyboardViewModel(
                textDocumentProxy: FakeTextDocumentProxy(text: "Please send the customer an update about the delivery."),
                aiService: FailingKeyboardAIService(),
                loadConfig: { Self.configuredGateway }
            )

            XCTAssertEqual(viewModel.panelMode, .actions)
            XCTAssertEqual(viewModel.actionPanelState?.selectedAction, .improve)
            XCTAssertFalse(viewModel.actionPanelState?.showsTranslationTargetSelector ?? true)
            XCTAssertNil(viewModel.actionPanelState?.contextSelectionPrompt)
            XCTAssertEqual(viewModel.actionPanelState?.isLoading, false)
            XCTAssertNil(viewModel.actionPanelState?.selectedOption)
            XCTAssertEqual(
                viewModel.actionPanelState?.actionResultViewportHeight,
                KeyboardPanelLayout.actionPanelScrollableResultHeight
            )
            XCTAssertNil(viewModel.rewriteOptionsState)
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionState"))
            XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionStateSeedID"))
            XCTAssertNil(defaults.object(forKey: "keyboardExtension.suggestionStateSeededAt"))
        }
    }

    func testActionPanelUsesOneHeightAndScrollsLoadedResultsForEveryAction() {
        let sourceText = "Please make this clearer."
        let replacementPlan = KeyboardReplacementPlan(
            textToDelete: sourceText,
            textForAI: sourceText,
            leadingWhitespace: "",
            trailingWhitespace: ""
        )
        let option = KeyboardRewriteOption(
            id: "improve-option-1",
            title: "Clearer",
            text: "Please make this message clearer and easier to understand."
        )

        var loadingImproveState = KeyboardActionPanelState(
            sourceText: sourceText,
            replacementPlan: replacementPlan,
            selectedAction: .improve
        )
        loadingImproveState.beginLoading()

        let emptyImproveState = KeyboardActionPanelState(
            sourceText: sourceText,
            replacementPlan: replacementPlan,
            selectedAction: .improve
        )
        let loadedImproveState = KeyboardActionPanelState(
            sourceText: sourceText,
            replacementPlan: replacementPlan,
            selectedAction: .improve,
            options: [option],
            isLoading: false
        )
        let loadedRewriteState = KeyboardActionPanelState(
            sourceText: sourceText,
            replacementPlan: replacementPlan,
            selectedAction: .rewrite,
            options: [option],
            isLoading: false
        )
        let loadedSummarizeState = KeyboardActionPanelState(
            sourceText: sourceText,
            replacementPlan: replacementPlan,
            selectedAction: .summarize,
            options: [option],
            isLoading: false
        )

        XCTAssertFalse(loadingImproveState.usesScrollableActionResult)
        XCTAssertFalse(emptyImproveState.usesScrollableActionResult)
        XCTAssertTrue(loadedImproveState.usesScrollableActionResult)
        XCTAssertTrue(loadedRewriteState.usesScrollableActionResult)
        XCTAssertTrue(loadedSummarizeState.usesScrollableActionResult)
        XCTAssertEqual(
            KeyboardPanelLayout.keyboardHeight(for: .actions, actionPanelState: loadingImproveState),
            KeyboardPanelLayout.actionPanelHeight
        )
        XCTAssertEqual(
            KeyboardPanelLayout.keyboardHeight(for: .actions, actionPanelState: emptyImproveState),
            KeyboardPanelLayout.actionPanelHeight
        )
        XCTAssertEqual(
            KeyboardPanelLayout.keyboardHeight(for: .actions, actionPanelState: loadedRewriteState),
            KeyboardPanelLayout.actionPanelHeight
        )
        XCTAssertEqual(
            KeyboardPanelLayout.keyboardHeight(for: .actions, actionPanelState: loadedImproveState),
            KeyboardPanelLayout.actionPanelHeight
        )
        XCTAssertEqual(
            KeyboardPanelLayout.keyboardHeight(for: .actions, actionPanelState: loadedSummarizeState),
            KeyboardPanelLayout.actionPanelHeight
        )
        XCTAssertEqual(
            KeyboardPanelLayout.keyboardHeight(for: .keyboard, actionPanelState: loadedImproveState),
            KeyboardPanelLayout.preferredKeyboardHeight
        )
        XCTAssertEqual(
            KeyboardPanelLayout.keyboardHeight(for: .rewriteOptions, actionPanelState: loadedImproveState),
            KeyboardPanelLayout.preferredKeyboardHeight
        )
        XCTAssertEqual(
            KeyboardPanelLayout.keyboardHeight(for: .correctionDetail, actionPanelState: loadedImproveState),
            KeyboardPanelLayout.preferredKeyboardHeight
        )
        XCTAssertEqual(
            KeyboardPanelLayout.keyboardHeight(for: .correctionComplete, actionPanelState: loadedImproveState),
            KeyboardPanelLayout.preferredKeyboardHeight
        )
    }

    func testRewriteFailureShowsSanitizedErrorAndPreservesText() async {
        await assertGatewayFailureShowsErrorAndPreservesText(for: .rewrite)
    }

    func testFixGrammarFailureShowsSanitizedErrorAndPreservesText() async {
        await assertGatewayFailureShowsErrorAndPreservesText(for: .fixGrammar)
    }

    func testTypedGatewayFailuresReachDistinctKeyboardErrorTitles() async {
        let cases: [(KeyboardAIError, String)] = [
            (.timeout, "Request timed out"),
            (.transport, "AI unavailable"),
            (.modelUnavailable, "Model unavailable"),
            (.unauthorized, "Invalid API key")
        ]

        for (error, expectedTitle) in cases {
            let proxy = FakeTextDocumentProxy(text: "Keep this text safe.")
            let viewModel = KeyboardViewModel(
                textDocumentProxy: proxy,
                aiService: ThrowingKeyboardAIService(error: error),
                loadConfig: { Self.configuredGateway },
                productionTestFullAccess: true
            )

            viewModel.performAIAction(.rewrite)
            await waitUntil { viewModel.actionError != nil }

            XCTAssertEqual(viewModel.actionError?.title, expectedTitle)
            XCTAssertEqual(viewModel.toolbarState.title, expectedTitle)
            XCTAssertEqual(proxy.text, "Keep this text safe.")
        }
    }

    func testTimeoutStopsLoadingAndPreservesTypedText() async {
        let source = "Keep this text exactly as typed."
        let proxy = FakeTextDocumentProxy(text: source)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: ThrowingKeyboardAIService(error: KeyboardAIError.timeout),
            loadConfig: { Self.configuredGateway },
            loadGatewayConnectionError: { nil },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.improve)
        await waitUntil { viewModel.actionError != nil }

        XCTAssertFalse(viewModel.isPerformingAIAction)
        XCTAssertEqual(viewModel.actionError?.kind, .timeout)
        XCTAssertEqual(viewModel.actionError?.title, "Request timed out")
        XCTAssertEqual(
            viewModel.actionError?.message,
            "The AI request took longer than 15 seconds. Try again or choose a faster model."
        )
        XCTAssertEqual(proxy.text, source)
    }

    func testMissingSelectedModelUsesRealServicePreflightAndDistinctTitle() async {
        let source = "Keep this text safe."
        let proxy = FakeTextDocumentProxy(text: source)
        let config = AppConfig(
            apiKey: "test-key",
            gatewayURL: "https://mock.local.invalid",
            selectedModel: "",
            isConfigured: true,
            supportsStructuredCorrections: false,
            structuredCorrectionSchemaVersion: ""
        )
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: KeyboardAIService(),
            loadConfig: { config },
            productionTestFullAccess: true
        )

        XCTAssertFalse(viewModel.canRunAIAction)
        XCTAssertEqual(viewModel.toolbarState.title, "Model unavailable")

        viewModel.performAIAction(.rewrite)
        await waitUntil { viewModel.actionError != nil }

        XCTAssertEqual(viewModel.actionError?.kind, .modelUnavailable)
        XCTAssertEqual(viewModel.actionError?.title, "Model unavailable")
        XCTAssertEqual(viewModel.toolbarState.title, "Model unavailable")
        XCTAssertEqual(proxy.text, source)
    }

    func testMissingPlainGrammarOutputShowsUnusableResponseAndPreservesText() async {
        let source = "The app works well."
        let proxy = FakeTextDocumentProxy(text: source)
        let result = KeyboardActionOperationResult(
            operation: "fix_grammar",
            items: []
        )
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: SuccessfulKeyboardAIService(result: result),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.fixGrammar)
        await waitUntil { viewModel.actionError != nil }

        XCTAssertEqual(viewModel.actionError?.kind, .modelCapability)
        XCTAssertEqual(viewModel.actionError?.title, "Model not compatible")
        XCTAssertEqual(viewModel.actionError?.message, KeyboardActionErrorState.modelCapabilityMessage)
        XCTAssertEqual(proxy.text, source)
    }

    func testModelCapabilityFailureIsOperationScopedForManualGrammar() async {
        let original = "i has a apple"
        let proxy = FakeTextDocumentProxy(text: original)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: ThrowingKeyboardAIService(error: .modelCapability),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.openGrammarCorrection()
        await waitUntil { viewModel.actionError != nil }

        XCTAssertEqual(viewModel.actionError?.title, "Model not compatible")
        XCTAssertEqual(viewModel.actionError?.message, KeyboardActionErrorState.modelCapabilityMessage)
        XCTAssertEqual(viewModel.toolbarState.title, "Model not compatible")
        XCTAssertNotEqual(viewModel.toolbarState.title, "AI unavailable")
        XCTAssertEqual(proxy.text, original)
        XCTAssertTrue(viewModel.canOpenActionPanel, "A grammar capability failure must not disable unrelated writing actions")
    }

    func testModelCapabilityFailureIsShownForRewriteActionPanelAndPreservesText() async {
        let original = "Please keep these words."
        let proxy = FakeTextDocumentProxy(text: original)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: ThrowingKeyboardAIService(error: .modelCapability),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.showActionPanel()
        await waitUntil { viewModel.actionError != nil }

        XCTAssertEqual(viewModel.actionError?.title, "Model not compatible")
        XCTAssertEqual(viewModel.actionError?.message, KeyboardActionErrorState.modelCapabilityMessage)
        XCTAssertEqual(proxy.text, original)
        XCTAssertTrue(viewModel.canOpenActionPanel)
        XCTAssertTrue(viewModel.canOpenGrammarCorrection, "A rewrite capability failure must not disable grammar correction")
    }

    func testAutomaticGrammarCapabilityFailureShowsTypedStateAndPreservesText() async {
        let original = "i has a apple"
        let proxy = FakeTextDocumentProxy(text: "")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: ThrowingKeyboardAIService(error: .modelCapability),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true,
            automaticAnalysisDelayNanoseconds: 0
        )

        viewModel.insert(original)
        await waitUntil { viewModel.actionError != nil }

        XCTAssertEqual(viewModel.toolbarState.title, "Model not compatible")
        XCTAssertEqual(proxy.text, original)
        XCTAssertTrue(viewModel.canOpenActionPanel)
    }

    func testCancellationDoesNotCreateKeyboardErrorOrChangeText() async {
        let original = "Please keep these words."
        let proxy = FakeTextDocumentProxy(text: original)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: CancellingKeyboardAIService(),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.rewrite)
        await waitUntil { !viewModel.isPerformingAIAction }

        XCTAssertNil(viewModel.actionError)
        XCTAssertEqual(viewModel.toolbarState.title, "Open Keyboard AI")
        XCTAssertEqual(proxy.text, original)
    }

    func testFailureKeepsStickyErrorUntilExplicitRecoveryActions() async {
        let proxy = FakeTextDocumentProxy(text: "please make this better")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: FailingKeyboardAIService(),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.rewrite)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(viewModel.actionError)
        XCTAssertEqual(viewModel.panelMode, .keyboard)
        XCTAssertEqual(viewModel.toolbarState.title, "AI unavailable")
        XCTAssertEqual(proxy.text, "please make this better")

        viewModel.copyActionErrorDetails()
        XCTAssertEqual(UIPasteboard.general.string, "AI unavailable: Unable to reach gateway.")

        viewModel.retryAfterActionError()
        XCTAssertNil(viewModel.actionError)
        XCTAssertEqual(viewModel.panelMode, .actions)
        XCTAssertEqual(viewModel.actionPanelState?.sourceText, "please make this better")
        XCTAssertEqual(proxy.text, "please make this better")

        viewModel.performAIAction(.rewrite)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNotNil(viewModel.actionError)

        viewModel.clearActionError()
        XCTAssertNil(viewModel.actionError)
        XCTAssertEqual(viewModel.panelMode, .keyboard)
    }

    func testActionPanelStartsImproveFromTopRightTrigger() async {
        let sourceText = "All of these are no bulb in the universe."
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let service = SequencedKeyboardAIService(results: [
            Self.structuredRewriteResult(),
            Self.structuredRewriteResult(),
            Self.structuredRewriteResult()
        ])
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.showActionPanel()

        XCTAssertEqual(viewModel.panelMode, .actions)
        XCTAssertEqual(viewModel.actionPanelState?.sourceText, sourceText)
        XCTAssertEqual(viewModel.actionPanelState?.selectedAction, .improve)
        XCTAssertTrue(viewModel.actionPanelState?.isLoading ?? false)
        XCTAssertEqual(proxy.text, sourceText)

        await waitUntil { viewModel.actionPanelState?.selectedOption?.text == "Please make this clearer." && !viewModel.isPerformingAIAction }

        XCTAssertEqual(viewModel.panelMode, .actions)
        XCTAssertEqual(viewModel.actionPanelState?.selectedAction, .improve)
        XCTAssertEqual(viewModel.actionPanelState?.selectedOption?.text, "Please make this clearer.")
        XCTAssertEqual(proxy.text, sourceText)

        viewModel.selectActionPanelAction(.rewrite)

        XCTAssertEqual(viewModel.panelMode, .actions)
        XCTAssertEqual(viewModel.actionPanelState?.sourceText, sourceText)
        XCTAssertEqual(viewModel.actionPanelState?.selectedAction, .rewrite)
        XCTAssertTrue(viewModel.actionPanelState?.isLoading ?? false)
        XCTAssertNil(viewModel.actionPanelState?.selectedOption)
        await waitUntil {
            service.requestedActions.count == 2
                && viewModel.actionPanelState?.selectedOption != nil
                && !viewModel.isPerformingAIAction
        }

        XCTAssertEqual(service.requestedActions, [.improve, .rewrite])
        XCTAssertEqual(viewModel.actionPanelState?.selectedAction, .rewrite)
        XCTAssertEqual(
            viewModel.actionPanelState?.actionResultViewportHeight,
            KeyboardPanelLayout.actionPanelScrollableResultHeight
        )

        viewModel.selectActionPanelAction(.rewriteStyle(.professional))
        await waitUntil {
            service.requestedActions.count == 3
                && viewModel.actionPanelState?.selectedOption != nil
                && !viewModel.isPerformingAIAction
        }

        XCTAssertEqual(viewModel.panelMode, .actions)
        XCTAssertEqual(service.requestedActions, [.improve, .rewrite, .rewriteStyle(.professional)])
        XCTAssertEqual(viewModel.actionPanelState?.selectedAction, .rewriteStyle(.professional))
        XCTAssertFalse(viewModel.actionPanelState?.showsTranslationTargetSelector ?? true)
        XCTAssertEqual(viewModel.actionPanelState?.actionResultViewportHeight, KeyboardPanelLayout.actionPanelScrollableResultHeight)
        XCTAssertEqual(viewModel.actionPanelState?.selectedOption?.text, "Please make this clearer.")
        XCTAssertEqual(proxy.text, sourceText)
    }

    func testTranslateWaitsForTargetThenAppliesSelectedLanguageResult() async {
        let sourceText = "Good morning, I hope you are well."
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let service = SequencedKeyboardAIService(results: [
            Self.structuredRewriteResult(),
            Self.structuredTranslationResult()
        ])
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.showActionPanel()
        await waitUntil { service.requestedActions.count == 1 && !viewModel.isPerformingAIAction }

        viewModel.selectActionPanelAction(.translate(nil))

        XCTAssertEqual(service.requestedActions, [.improve])
        XCTAssertEqual(viewModel.actionPanelState?.selectedAction, .translate(nil))
        XCTAssertTrue(viewModel.actionPanelState?.isWaitingForTranslationTarget ?? false)
        XCTAssertFalse(viewModel.actionPanelState?.isLoading ?? true)
        XCTAssertNil(viewModel.actionPanelState?.selectedOption)
        XCTAssertEqual(viewModel.aiStatus, "Choose a language")
        XCTAssertEqual(proxy.text, sourceText)

        viewModel.selectActionPanelTranslationTarget(.dutch)
        await waitUntil {
            service.requestedActions.count == 2
                && viewModel.actionPanelState?.selectedOption?.text == "Goedemorgen, ik hoop dat het goed met je gaat."
                && !viewModel.isPerformingAIAction
        }

        XCTAssertEqual(service.requestedActions, [.improve, .translate(.dutch)])
        XCTAssertEqual(viewModel.actionPanelState?.selectedTranslationTarget, .dutch)
        XCTAssertEqual(viewModel.actionPanelState?.actionResultViewportHeight, KeyboardPanelLayout.actionPanelContextualResultHeight)
        XCTAssertEqual(proxy.text, sourceText)

        viewModel.applySelectedActionPanelAction()

        XCTAssertEqual(proxy.text, "Goedemorgen, ik hoop dat het goed met je gaat.")
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
        XCTAssertEqual(viewModel.completionPanelState.title, "Translation applied")
        XCTAssertEqual(
            viewModel.completionPanelState.message,
            "The Dutch translation replaced the original text."
        )
    }

    func testTranslationTargetSelectionDoesNotReuseCapturedTextAfterHostClears() async {
        let sourceText = "Good morning, I hope you are well."
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let service = SequencedKeyboardAIService(results: [
            Self.structuredRewriteResult(),
            Self.structuredTranslationResult()
        ])
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.showActionPanel()
        await waitUntil { service.requestedActions.count == 1 && !viewModel.isPerformingAIAction }
        viewModel.selectActionPanelAction(.translate(nil))

        proxy.replaceTextForTest("")
        viewModel.selectActionPanelTranslationTarget(.dutch)

        XCTAssertEqual(service.requestedActions, [.improve])
        XCTAssertEqual(service.requestedTexts, [sourceText])
        XCTAssertEqual(proxy.text, "")
        XCTAssertNil(viewModel.actionPanelState)
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
    }

    func testActionSwitchDoesNotRequestCapturedTextAfterHostClears() async {
        let sourceText = "Good morning, I hope you are well."
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let service = SequencedKeyboardAIService(results: [
            Self.structuredRewriteResult(),
            Self.structuredRewriteResult()
        ])
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.showActionPanel()
        await waitUntil { service.requestedActions.count == 1 && !viewModel.isPerformingAIAction }

        proxy.replaceTextForTest("")
        viewModel.selectActionPanelAction(.summarize)

        XCTAssertEqual(service.requestedActions, [.improve])
        XCTAssertEqual(service.requestedTexts, [sourceText])
        XCTAssertEqual(proxy.text, "")
        XCTAssertNil(viewModel.actionPanelState)
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
    }

    func testActionRerunDoesNotRequestCapturedTextAfterHostClears() async {
        let sourceText = "Good morning, I hope you are well."
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let service = SequencedKeyboardAIService(results: [
            Self.structuredRewriteResult(),
            Self.structuredRewriteResult()
        ])
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.showActionPanel()
        await waitUntil { service.requestedActions.count == 1 && !viewModel.isPerformingAIAction }

        proxy.replaceTextForTest("")
        viewModel.rerunSelectedActionPanelAction()

        XCTAssertEqual(service.requestedActions, [.improve])
        XCTAssertEqual(service.requestedTexts, [sourceText])
        XCTAssertEqual(proxy.text, "")
        XCTAssertNil(viewModel.actionPanelState)
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
    }

    func testTranslationApplyRefreshesResultInsteadOfReplacingChangedHostText() async {
        let sourceText = "Good morning, I hope you are well."
        let changedText = "This host text changed before Apply."
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let service = SequencedKeyboardAIService(results: [
            Self.structuredRewriteResult(),
            Self.structuredTranslationResult(),
            Self.structuredTranslationResult()
        ])
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.showActionPanel()
        await waitUntil { service.requestedActions.count == 1 && !viewModel.isPerformingAIAction }
        viewModel.selectActionPanelAction(.translate(nil))
        viewModel.selectActionPanelTranslationTarget(.dutch)
        await waitUntil {
            service.requestedActions.count == 2
                && viewModel.actionPanelState?.selectedOption != nil
                && !viewModel.isPerformingAIAction
        }

        proxy.replaceTextForTest(changedText)
        viewModel.applySelectedActionPanelAction()

        XCTAssertEqual(proxy.text, changedText)
        XCTAssertEqual(viewModel.actionPanelState?.sourceText, changedText)
        XCTAssertEqual(viewModel.actionPanelState?.selectedAction, .translate(.dutch))
        await waitUntil {
            service.requestedActions.count == 3
                && viewModel.actionPanelState?.selectedOption != nil
                && !viewModel.isPerformingAIAction
        }
        XCTAssertEqual(service.requestedTexts, [sourceText, sourceText, changedText])
        XCTAssertEqual(proxy.text, changedText)

        viewModel.applySelectedActionPanelAction()

        XCTAssertEqual(proxy.text, "Goedemorgen, ik hoop dat het goed met je gaat.")
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
    }

    func testTranslationTargetsMatchPopularStarterCatalog() {
        XCTAssertEqual(
            KeyboardTranslationTarget.allCases.map(\.displayName),
            [
                "Arabic",
                "Malayalam",
                "Hindi",
                "Urdu",
                "English (American)",
                "Bengali",
                "Marathi",
                "Telugu",
                "Tamil",
                "Chinese (Simplified)",
                "Spanish",
                "French",
                "Portuguese",
                "Russian",
                "Dutch"
            ]
        )
        XCTAssertEqual(
            KeyboardTranslationTarget.allCases.map(\.rawValue),
            ["ar", "ml", "hi", "ur", "en-US", "bn", "mr", "te", "ta", "zh-Hans", "es", "fr", "pt", "ru", "nl"]
        )
        XCTAssertEqual(
            KeyboardTranslationTarget.allCases.map(\.promptLanguage),
            [
                "Modern Standard Arabic",
                "Malayalam",
                "Hindi",
                "Urdu",
                "American English",
                "Bengali",
                "Marathi",
                "Telugu",
                "Tamil",
                "Simplified Chinese",
                "Spanish",
                "French",
                "Portuguese",
                "Russian",
                "Dutch"
            ]
        )
        XCTAssertTrue(
            KeyboardActionPanelState.availableActions.contains { $0.representsSameMode(as: .translate(nil)) }
        )
        XCTAssertEqual(
            KeyboardActionPanelState.availableActions.map(\.rawValue),
            [
                "improve",
                "rewrite",
                "translate",
                "rewrite_shorten",
                "rewrite_friendly",
                "rewrite_formal",
                "rewrite_compassionate",
                "rewrite_confident",
                "rewrite_engaging",
                "rewrite_fluent",
                "rewrite_diplomatic",
                "rewrite_empathetic",
                "rewrite_exciting",
                "rewrite_cooperative",
                "rewrite_assertive",
                "rewrite_detailed",
                "rewrite_casual",
                "rewrite_professional"
            ]
        )
        XCTAssertFalse(
            KeyboardActionPanelState.availableActions.contains { $0.representsSameMode(as: .summarize) }
        )
    }

    func testMalayalamTranslationTargetBuildsTypedPrompt() throws {
        let prompt = try XCTUnwrap(
            KeyboardAIAction.translate(.malayalam).prompt(for: "Please translate this sentence.")
        )

        XCTAssertTrue(prompt.contains("Operation: translate"))
        XCTAssertTrue(prompt.contains("language identified by target_language"))
        XCTAssertTrue(prompt.contains("\"target_language\":\"Malayalam\""))
        XCTAssertTrue(prompt.contains("Please translate this sentence."))
    }

    func testRewriteStylesMatchScreenshotCatalogAndBuildTypedPrompt() throws {
        XCTAssertEqual(
            KeyboardRewriteStyle.allCases.map(\.displayName),
            [
                "Shorten",
                "Friendly",
                "Formal",
                "Compassionate",
                "Confident",
                "Engaging",
                "Fluent",
                "Diplomatic",
                "Empathetic",
                "Exciting",
                "Cooperative",
                "Assertive",
                "Detailed",
                "Casual",
                "Professional"
            ]
        )

        let prompt = try XCTUnwrap(
            KeyboardAIAction.rewriteStyle(.professional).prompt(for: "send the customer an update")
        )

        XCTAssertTrue(prompt.contains("Operation: rewrite"))
        XCTAssertTrue(prompt.contains("polished, professional tone"))
        XCTAssertTrue(prompt.contains("send the customer an update"))
        XCTAssertEqual(KeyboardAIAction.rewriteStyle(.professional).operationName, "rewrite")
        XCTAssertEqual(KeyboardAIAction.rewriteStyle(.professional).rawValue, "rewrite_professional")
        XCTAssertFalse(KeyboardAIAction.rewrite.representsSameMode(as: .rewriteStyle(.professional)))
        XCTAssertEqual(
            Set(KeyboardActionPanelState.availableActions.map(\.id)).count,
            KeyboardActionPanelState.availableActions.count
        )
    }

    func testActionPanelCopyToggleAndApplyGeneratedSuggestion() async {
        let proxy = FakeTextDocumentProxy(text: "please make this better")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: SuccessfulKeyboardAIService(result: Self.structuredRewriteResult()),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.showActionPanel()
        await waitUntil { viewModel.actionPanelState?.selectedOption?.text == "Please make this clearer." && !viewModel.isPerformingAIAction }

        XCTAssertEqual(viewModel.actionPanelState?.isCarouselVisible, true)
        viewModel.toggleActionPanelCarousel()
        XCTAssertEqual(viewModel.actionPanelState?.isCarouselVisible, false)

        viewModel.copySelectedActionPanelSuggestion()
        XCTAssertEqual(UIPasteboard.general.string, "Please make this clearer.")

        viewModel.applySelectedActionPanelAction()

        XCTAssertEqual(proxy.text, "Please make this clearer.")
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
        XCTAssertNil(viewModel.actionPanelState)
        XCTAssertEqual(viewModel.completionPanelState, .improvementApplied)
    }

    func testImproveUsesCurrentLineAcrossCursor() async {
        let beforeCursor = "it’s never going to be a penalty, gk can’t have handball"
        let afterCursor = " in the box"
        let sourceText = beforeCursor + afterCursor
        let proxy = FakeTextDocumentProxy(text: sourceText, cursorOffset: beforeCursor.count)
        let service = SequencedKeyboardAIService(results: [Self.structuredRewriteResult()])
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.improve)
        await waitUntil { service.requestedTexts.count == 1 && !viewModel.isPerformingAIAction }

        XCTAssertEqual(service.requestedTexts, [sourceText])
        XCTAssertEqual(viewModel.rewriteOptionsState?.sourceText, sourceText)
    }

    func testActionPanelRerunUsesEditedCurrentLineAcrossCursor() async {
        let originalText = "it’s never going to be a penalty, gk can’t have in the box"
        let beforeCursor = "it’s never going to be a penalty, gk can’t have handball"
        let afterCursor = " in the box"
        let editedText = beforeCursor + afterCursor
        let proxy = FakeTextDocumentProxy(text: originalText)
        let service = SequencedKeyboardAIService(results: [
            Self.structuredRewriteResult(),
            Self.structuredRewriteResult()
        ])
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.showActionPanel()
        await waitUntil { service.requestedTexts.count == 1 && !viewModel.isPerformingAIAction }

        proxy.replaceTextForTest(editedText, cursorOffset: beforeCursor.count)
        viewModel.rerunSelectedActionPanelAction()
        await waitUntil { service.requestedTexts.count == 2 && !viewModel.isPerformingAIAction }

        XCTAssertEqual(service.requestedTexts, [originalText, editedText])
        XCTAssertEqual(viewModel.actionPanelState?.sourceText, editedText)
    }

    func testApplyingActionPanelSuggestionReplacesCurrentLineAcrossCursor() async {
        let beforeCursor = "it’s never going to be a penalty, gk can’t have handball"
        let afterCursor = " in the box"
        let sourceText = beforeCursor + afterCursor
        let proxy = FakeTextDocumentProxy(text: sourceText, cursorOffset: beforeCursor.count)
        let service = SequencedKeyboardAIService(results: [Self.structuredRewriteResult()])
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.showActionPanel()
        await waitUntil { viewModel.actionPanelState?.selectedOption?.text == "Please make this clearer." && !viewModel.isPerformingAIAction }
        viewModel.applySelectedActionPanelAction()

        XCTAssertEqual(service.requestedTexts, [sourceText])
        XCTAssertEqual(proxy.text, "Please make this clearer.")
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
    }

    func testReturningFromActionPanelResumesGrammarCorrectionLane() async {
        let sourceText = "i has a apple and ths"
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: SuccessfulKeyboardAIService(result: Self.grammarCorrectionResult()),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true,
            automaticAnalysisDelayNanoseconds: 0
        )

        viewModel.showActionPanel()

        XCTAssertEqual(viewModel.panelMode, .actions)
        XCTAssertFalse(viewModel.canOpenAnalysisResult)
        XCTAssertNil(viewModel.currentCorrection)

        viewModel.showKeyboardPanel()
        await waitUntil { viewModel.suggestionState?.correctionCount == 2 && !viewModel.isPerformingAIAction }

        XCTAssertEqual(viewModel.panelMode, .keyboard)
        XCTAssertEqual(proxy.text, sourceText)
        XCTAssertTrue(viewModel.canOpenAnalysisResult)
        XCTAssertTrue(viewModel.toolbarState.showsIssueCount)
        XCTAssertEqual(viewModel.toolbarState.issueCount, 2)

        viewModel.showAnalysisResult()

        XCTAssertEqual(viewModel.panelMode, .correctionDetail)
        XCTAssertEqual(viewModel.currentCorrectionCard?.categoryTitle, "Subject-verb agreement")
    }

    func testCompletedActionPanelKeepsExistingGrammarCorrectionLane() async {
        let sourceText = "i has a apple and ths"
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let service = RoutingKeyboardAIService(
            grammarResult: Self.grammarCorrectionResult(),
            rewriteResult: Self.structuredRewriteResult()
        )
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true,
            automaticAnalysisDelayNanoseconds: 0
        )

        viewModel.startAutomaticAnalysis()
        await waitUntil { viewModel.suggestionState?.correctionCount == 2 && !viewModel.isPerformingAIAction }

        XCTAssertTrue(viewModel.canOpenAnalysisResult)

        viewModel.showActionPanel()
        await waitUntil { viewModel.actionPanelState?.selectedOption?.text == "Please make this clearer." && !viewModel.isPerformingAIAction }

        XCTAssertEqual(viewModel.panelMode, .actions)
        XCTAssertEqual(viewModel.suggestionState?.correctionCount, 2)
        XCTAssertTrue(viewModel.canOpenAnalysisResult)

        viewModel.showKeyboardPanel()

        XCTAssertEqual(viewModel.panelMode, .keyboard)
        XCTAssertEqual(viewModel.suggestionState?.correctionCount, 2)
        XCTAssertTrue(viewModel.canOpenGrammarCorrection)

        viewModel.openGrammarCorrection()

        XCTAssertEqual(viewModel.panelMode, .correctionDetail)
        XCTAssertFalse(viewModel.isGrammarCorrectionLoading)
        XCTAssertEqual(service.requestedActions, [.fixGrammar, .improve])
        XCTAssertEqual(viewModel.currentCorrectionCard?.categoryTitle, "Subject-verb agreement")
    }

    func testLeftGrammarCorrectionButtonStartsGrammarAnalysisWithoutStoredResult() async {
        let sourceText = "i has a apple and ths"
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: SuccessfulKeyboardAIService(result: Self.grammarCorrectionResult()),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        XCTAssertFalse(viewModel.canOpenAnalysisResult)
        XCTAssertTrue(viewModel.canOpenGrammarCorrection)

        viewModel.openGrammarCorrection()
        await waitUntil { viewModel.panelMode == .correctionDetail && !viewModel.isPerformingAIAction }

        XCTAssertEqual(proxy.text, sourceText)
        XCTAssertEqual(viewModel.suggestionState?.correctionCount, 2)
        XCTAssertEqual(viewModel.currentCorrectionCard?.categoryTitle, "Subject-verb agreement")
    }

    func testLeftGrammarCorrectionButtonReopensSameTextCorrectionsWithoutRequestingAgain() async {
        let sourceText = "i has a apple and ths"
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let service = DelayedRecordingKeyboardAIService(result: Self.grammarCorrectionResult())
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.openGrammarCorrection()
        await waitUntil { viewModel.panelMode == .correctionDetail && !viewModel.isGrammarCorrectionLoading }

        XCTAssertEqual(service.requestedActions, [.fixGrammar])

        viewModel.showKeyboardPanel()
        viewModel.openGrammarCorrection()

        XCTAssertEqual(viewModel.panelMode, .correctionDetail)
        XCTAssertFalse(viewModel.isGrammarCorrectionLoading)
        XCTAssertEqual(service.requestedActions, [.fixGrammar])
        XCTAssertEqual(viewModel.currentCorrectionCard?.categoryTitle, "Subject-verb agreement")
    }

    func testGrammarCorrectionButtonIsDisabledOnlyForHardBlockers() async {
        let noTextProxy = FakeTextDocumentProxy(text: "")
        let noTextViewModel = KeyboardViewModel(
            textDocumentProxy: noTextProxy,
            aiService: SuccessfulKeyboardAIService(result: Self.grammarCorrectionResult()),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )
        XCTAssertTrue(noTextViewModel.canOpenGrammarCorrection)

        var unverifiedCapabilityConfig = Self.configuredGateway
        unverifiedCapabilityConfig.supportsStructuredCorrections = false
        unverifiedCapabilityConfig.structuredCorrectionSchemaVersion = ""
        let unverifiedCapabilityViewModel = KeyboardViewModel(
            textDocumentProxy: FakeTextDocumentProxy(text: "i has a apple"),
            aiService: SuccessfulKeyboardAIService(result: Self.grammarCorrectionResult()),
            loadConfig: { unverifiedCapabilityConfig },
            productionTestFullAccess: true
        )
        XCTAssertTrue(unverifiedCapabilityViewModel.canRunAIAction)
        XCTAssertTrue(unverifiedCapabilityViewModel.canOpenGrammarCorrection)

        let noFullAccessViewModel = KeyboardViewModel(
            textDocumentProxy: FakeTextDocumentProxy(text: "i has a apple"),
            aiService: SuccessfulKeyboardAIService(result: Self.grammarCorrectionResult()),
            loadConfig: { Self.configuredGateway }
        )
        XCTAssertFalse(noFullAccessViewModel.canOpenGrammarCorrection)

        let gatewayErrorViewModel = KeyboardViewModel(
            textDocumentProxy: FakeTextDocumentProxy(text: "i has a apple"),
            aiService: SuccessfulKeyboardAIService(result: Self.grammarCorrectionResult()),
            loadConfig: { Self.configuredGateway },
            loadGatewayConnectionError: { "Gateway timed out. Open the app to retry." },
            productionTestFullAccess: true
        )
        XCTAssertFalse(gatewayErrorViewModel.canOpenGrammarCorrection)

        let incompleteConfig = AppConfig(
            apiKey: "",
            gatewayURL: "https://mock.local.invalid",
            selectedModel: "test-model",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "test"
        )
        let notConfiguredViewModel = KeyboardViewModel(
            textDocumentProxy: FakeTextDocumentProxy(text: "i has a apple"),
            aiService: SuccessfulKeyboardAIService(result: Self.grammarCorrectionResult()),
            loadConfig: { incompleteConfig },
            productionTestFullAccess: true
        )
        XCTAssertFalse(notConfiguredViewModel.canOpenGrammarCorrection)

        let visibleErrorViewModel = KeyboardViewModel(
            textDocumentProxy: FakeTextDocumentProxy(text: "i has a apple"),
            aiService: FailingKeyboardAIService(),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )
        visibleErrorViewModel.performAIAction(.rewrite)
        await waitUntil { visibleErrorViewModel.actionError != nil }
        XCTAssertFalse(visibleErrorViewModel.canOpenGrammarCorrection)
    }

    func testOpeningGrammarCorrectionWithEmptyTextShowsAllDoneWithoutGatewayRequest() throws {
        try withSharedKeyboardDebugSeedDefaults { defaults in
            defaults.set(false, forKey: "keyboardExtension.uiTestDebugStateEnabled")
            defaults.removeObject(forKey: "keyboardExtension.composingBuffer")
            let proxy = FakeTextDocumentProxy(text: "")
            let service = SequencedKeyboardAIService(results: [Self.grammarCorrectionResult()])
            let viewModel = KeyboardViewModel(
                textDocumentProxy: proxy,
                aiService: service,
                loadConfig: { Self.configuredGateway },
                productionTestFullAccess: true
            )

            viewModel.openGrammarCorrection()

            XCTAssertNil(viewModel.actionError)
            XCTAssertEqual(viewModel.panelMode, .correctionComplete)
            XCTAssertEqual(viewModel.completionPanelState, .allDone)
            XCTAssertFalse(viewModel.isPerformingAIAction)
            XCTAssertFalse(viewModel.isGrammarCorrectionLoading)
            XCTAssertTrue(service.requestedActions.isEmpty)
            XCTAssertEqual(proxy.text, "")
        }
    }

    func testAIActionWithEmptyTextShowsAllDoneWithoutGatewayRequest() throws {
        try withSharedKeyboardDebugSeedDefaults { defaults in
            defaults.set(false, forKey: "keyboardExtension.uiTestDebugStateEnabled")
            defaults.removeObject(forKey: "keyboardExtension.composingBuffer")
            let proxy = FakeTextDocumentProxy(text: "")
            let service = SequencedKeyboardAIService(results: [Self.structuredRewriteResult()])
            let viewModel = KeyboardViewModel(
                textDocumentProxy: proxy,
                aiService: service,
                loadConfig: { Self.configuredGateway },
                productionTestFullAccess: true
            )

            viewModel.performAIAction(.rewrite)

            XCTAssertNil(viewModel.actionError)
            XCTAssertEqual(viewModel.panelMode, .correctionComplete)
            XCTAssertEqual(viewModel.completionPanelState, .allDone)
            XCTAssertFalse(viewModel.isPerformingAIAction)
            XCTAssertTrue(service.requestedActions.isEmpty)
            XCTAssertEqual(proxy.text, "")
        }
    }

    func testActionPanelWithEmptyTextShowsAllDoneWithoutGatewayRequest() throws {
        try withSharedKeyboardDebugSeedDefaults { defaults in
            defaults.set(false, forKey: "keyboardExtension.uiTestDebugStateEnabled")
            defaults.removeObject(forKey: "keyboardExtension.composingBuffer")
            let proxy = FakeTextDocumentProxy(text: "")
            let service = SequencedKeyboardAIService(results: [Self.structuredRewriteResult()])
            let viewModel = KeyboardViewModel(
                textDocumentProxy: proxy,
                aiService: service,
                loadConfig: { Self.configuredGateway },
                productionTestFullAccess: true
            )

            viewModel.showActionPanel()

            XCTAssertNil(viewModel.actionError)
            XCTAssertEqual(viewModel.panelMode, .correctionComplete)
            XCTAssertEqual(viewModel.completionPanelState, .allDone)
            XCTAssertFalse(viewModel.isPerformingAIAction)
            XCTAssertNil(viewModel.actionPanelState)
            XCTAssertTrue(service.requestedActions.isEmpty)
            XCTAssertEqual(proxy.text, "")
        }
    }

    func testOpeningGrammarCorrectionImmediatelyShowsLoadingAndRequestsFixGrammar() async {
        let sourceText = "i has a apple and ths"
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let service = DelayedRecordingKeyboardAIService(result: Self.grammarCorrectionResult())
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.openGrammarCorrection()

        XCTAssertEqual(viewModel.panelMode, .correctionDetail)
        XCTAssertTrue(viewModel.isGrammarCorrectionLoading)
        XCTAssertEqual(viewModel.aiStatus, "Checking grammar…")
        await waitUntil { service.requestedActions == [.fixGrammar] }

        await waitUntil { viewModel.panelMode == .correctionDetail && !viewModel.isGrammarCorrectionLoading }

        XCTAssertEqual(proxy.text, sourceText)
        XCTAssertEqual(viewModel.suggestionState?.correctionCount, 2)
        XCTAssertEqual(viewModel.currentCorrectionCard?.categoryTitle, "Subject-verb agreement")
    }

    func testDelayedManualGrammarResponseIsDiscardedWhenInputIsClearedBeforeResponseReturns() async {
        let sourceText = "i has a apple and ths"
        let proxy = FakeTextDocumentProxy(text: "")
        let service = DelayedSequencedKeyboardAIService(
            results: [Self.grammarCorrectionResult()],
            delays: [50_000_000]
        )
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true,
            automaticAnalysisDelayNanoseconds: 1_000_000_000
        )

        for character in sourceText {
            viewModel.insert(String(character))
        }
        XCTAssertEqual(proxy.text, sourceText)

        viewModel.openGrammarCorrection()
        await waitUntil { service.requestedTexts == [sourceText] && viewModel.isGrammarCorrectionLoading }

        proxy.replaceTextForTest("")
        await waitUntil { !viewModel.isGrammarCorrectionLoading && !viewModel.isPerformingAIAction }

        XCTAssertEqual(service.requestedTexts, [sourceText])
        XCTAssertEqual(proxy.text, "")
        XCTAssertNil(viewModel.suggestionState)
        XCTAssertNil(viewModel.currentCorrection)
        XCTAssertFalse(viewModel.canOpenAnalysisResult)
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
        XCTAssertEqual(viewModel.completionPanelState, .allDone)
        XCTAssertEqual(viewModel.aiStatus, "No more suggestions")
    }

    func testTypingDuringManualGrammarRequestSchedulesFreshAnalysisForUpdatedText() async {
        let sourceText = "i has a apple and ths"
        let updatedText = "\(sourceText) now"
        let proxy = FakeTextDocumentProxy(text: "")
        let service = DelayedSequencedKeyboardAIService(
            results: [
                Self.grammarCorrectionResult(),
                Self.noIssueGrammarResult()
            ],
            delays: [50_000_000, 0]
        )
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true,
            automaticAnalysisDelayNanoseconds: 10_000_000
        )

        for character in sourceText {
            viewModel.insert(String(character))
        }
        viewModel.openGrammarCorrection()
        await waitUntil { service.requestedTexts == [sourceText] && viewModel.isGrammarCorrectionLoading }

        viewModel.insert(" now")
        await waitUntil { service.requestedTexts == [sourceText, updatedText] && !viewModel.isPerformingAIAction }

        XCTAssertEqual(proxy.text, updatedText)
        XCTAssertNil(viewModel.suggestionState)
        XCTAssertNil(viewModel.currentCorrection)
        XCTAssertFalse(viewModel.isGrammarCorrectionLoading)
        XCTAssertEqual(viewModel.panelMode, .keyboard)
        XCTAssertEqual(viewModel.completionPanelState, .noIssues)
        XCTAssertEqual(viewModel.aiStatus, "No issues found")
    }

    func testManualGrammarLoadingSurvivesCancelledAutomaticAnalysis() async {
        let sourceText = "i has a apple and ths"
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let service = CancellableDelayedRecordingKeyboardAIService(result: Self.grammarCorrectionResult())
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true,
            automaticAnalysisDelayNanoseconds: 0
        )

        viewModel.startAutomaticAnalysis()
        await waitUntil {
            service.requestedActions == [.fixGrammar]
                && viewModel.aiStatus == "Analyzing…"
                && viewModel.isPerformingAIAction
        }

        viewModel.openGrammarCorrection()

        XCTAssertEqual(viewModel.panelMode, .correctionDetail)
        XCTAssertTrue(viewModel.isGrammarCorrectionLoading)
        XCTAssertEqual(viewModel.aiStatus, "Checking grammar…")
        await waitUntil { service.requestedActions == [.fixGrammar, .fixGrammar] }

        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertTrue(viewModel.isGrammarCorrectionLoading)
        XCTAssertEqual(viewModel.aiStatus, "Checking grammar…")

        await waitUntil {
            viewModel.currentCorrectionCard?.categoryTitle == "Subject-verb agreement"
                && !viewModel.isGrammarCorrectionLoading
        }

        XCTAssertEqual(service.requestedActions, [.fixGrammar, .fixGrammar])
        XCTAssertEqual(viewModel.aiStatus, "Suggestions ready")
        XCTAssertEqual(proxy.text, sourceText)
    }

    func testGrammarCorrectionReopensSameTextNoIssuesAndRequestsAgainAfterTextChanges() async {
        let proxy = FakeTextDocumentProxy(text: "The app works well.")
        let service = SequencedKeyboardAIService(results: [
            Self.noIssueGrammarResult(),
            Self.plainGrammarResult("The app works well. and this")
        ])
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.openGrammarCorrection()
        await waitUntil { viewModel.panelMode == .correctionComplete && viewModel.canOpenAnalysisResult }

        XCTAssertEqual(viewModel.completionPanelState, .noIssues)
        XCTAssertEqual(service.requestedActions, [.fixGrammar])

        viewModel.showKeyboardPanel()
        viewModel.openGrammarCorrection()

        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
        XCTAssertEqual(viewModel.completionPanelState, .noIssues)
        XCTAssertEqual(service.requestedActions, [.fixGrammar])

        viewModel.showKeyboardPanel()
        viewModel.insert(" and ths")
        viewModel.openGrammarCorrection()
        await waitUntil { viewModel.panelMode == .correctionDetail && viewModel.currentCorrection != nil }

        XCTAssertEqual(service.requestedActions, [.fixGrammar, .fixGrammar])
        XCTAssertEqual(viewModel.currentCorrectionCard?.categoryTitle, "Spelling")
    }

    func testGrammarCorrectionFailureShowsMiddleErrorState() async {
        let proxy = FakeTextDocumentProxy(text: "i has a apple")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: FailingKeyboardAIService(),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.openGrammarCorrection()
        await waitUntil { viewModel.actionError != nil }

        XCTAssertEqual(viewModel.panelMode, .keyboard)
        XCTAssertEqual(viewModel.actionError?.message, "Unable to reach gateway.")
        XCTAssertFalse(viewModel.isGrammarCorrectionLoading)
        XCTAssertFalse(viewModel.canOpenGrammarCorrection)
        XCTAssertEqual(proxy.text, "i has a apple")
    }

    func testApplyingActionPanelSuggestionRestartsGrammarLaneAfterReturningToKeyboard() async {
        let proxy = FakeTextDocumentProxy(text: "i has a apple and ths")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: RoutingKeyboardAIService(
                grammarResult: Self.noIssueGrammarResult(),
                rewriteResult: Self.structuredRewriteResult()
            ),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true,
            automaticAnalysisDelayNanoseconds: 0
        )

        viewModel.showActionPanel()
        await waitUntil { viewModel.actionPanelState?.selectedOption?.text == "Please make this clearer." && !viewModel.isPerformingAIAction }

        viewModel.applySelectedActionPanelAction()

        XCTAssertEqual(proxy.text, "Please make this clearer.")
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
        XCTAssertFalse(viewModel.canOpenAnalysisResult)

        viewModel.showKeyboardPanel()
        await waitUntil { viewModel.canOpenAnalysisResult && !viewModel.isPerformingAIAction }

        XCTAssertEqual(viewModel.panelMode, .keyboard)
        XCTAssertEqual(viewModel.toolbarState.subtitle, "No issues found")
    }

    func testActionPanelCancelsAutomaticAnalysisAndKeepsRealSourceText() async {
        let sourceText = "All of these are no bulb in the universe."
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: DelayedKeyboardAIService(result: Self.grammarCorrectionResult()),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true,
            automaticAnalysisDelayNanoseconds: 0
        )

        viewModel.startAutomaticAnalysis()
        await waitUntil { viewModel.isPerformingAIAction }

        XCTAssertTrue(viewModel.canOpenActionPanel)
        XCTAssertFalse(viewModel.canRunAIAction)

        viewModel.showActionPanel()

        XCTAssertEqual(viewModel.panelMode, .actions)
        XCTAssertEqual(viewModel.actionPanelState?.sourceText, sourceText)
        XCTAssertTrue(viewModel.actionPanelState?.isLoading ?? false)
        XCTAssertTrue(viewModel.isPerformingAIAction)

        try? await Task.sleep(nanoseconds: 90_000_000)

        XCTAssertEqual(viewModel.panelMode, .actions)
        XCTAssertEqual(viewModel.actionPanelState?.sourceText, sourceText)
        XCTAssertEqual(viewModel.actionPanelState?.selectedAction, .improve)
        XCTAssertNotNil(viewModel.actionPanelState?.selectedOption)
        XCTAssertNil(viewModel.currentCorrection)
        XCTAssertEqual(proxy.text, sourceText)
    }

    func testInvalidStructuredResponseCopyIsSpecificAndSanitized() async {
        let proxy = FakeTextDocumentProxy(text: "i has a apple,ths is nt sound sound")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: InvalidRawResponseKeyboardAIService(),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.fixGrammar)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(proxy.text, "i has a apple,ths is nt sound sound")
        XCTAssertEqual(viewModel.actionError?.message, "Gateway returned an invalid response.")
        XCTAssertEqual(viewModel.toolbarState.title, "AI unavailable")
        XCTAssertEqual(viewModel.toolbarState.subtitle, "Gateway returned an invalid response.")
        XCTAssertFalse(viewModel.toolbarState.subtitle.localizedCaseInsensitiveContains("Analysis failed"))
        XCTAssertFalse(viewModel.toolbarState.subtitle.contains("{"))
        XCTAssertNil(viewModel.currentCorrection)
        XCTAssertFalse(viewModel.isPerformingAIAction)

        viewModel.copyActionErrorDetails()
        XCTAssertEqual(UIPasteboard.general.string, "AI unavailable: Gateway returned an invalid response.")
    }

    func testErrorTextOperationResultShowsErrorAndNeverReplacesDocumentText() async {
        let original = "Keep my original words."
        let proxy = FakeTextDocumentProxy(text: original)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: ErrorTextResultKeyboardAIService(),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.rewrite)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(proxy.text, original)
        XCTAssertEqual(viewModel.actionError?.message, KeyboardActionErrorState.modelCapabilityMessage)
        XCTAssertEqual(viewModel.toolbarState.title, "Model not compatible")
        XCTAssertNotEqual(viewModel.toolbarState.subtitle, "Ready")
        XCTAssertFalse(proxy.text.contains("no safe keyboard text could be extracted"))
        XCTAssertFalse(viewModel.isPerformingAIAction)
    }

    func testKnownGatewayErrorsDoNotUseGenericAnalysisFailedCopy() {
        let cases: [NetworkError] = [
            .unauthorized,
            .modelUnavailable,
            .unusableCorrection,
            .timeout
        ]

        for error in cases {
            let message = NetworkManager.userFacingSmokeErrorMessage(for: error, model: "test-model")
            XCTAssertFalse(message.localizedCaseInsensitiveContains("Analysis failed"), "Known gateway error should be specific: \(message)")
            XCTAssertFalse(message.contains("{"), "Known gateway error must be sanitized: \(message)")
        }
    }

    private func withSharedKeyboardDebugSeedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let defaults = try XCTUnwrap(AppConfig.sharedDefaults())
        let keys = [
            "keyboardExtension.uiTestDebugStateEnabled",
            "keyboardExtension.suggestionState",
            "keyboardExtension.suggestionStateSeedID",
            "keyboardExtension.suggestionStateSeededAt",
            "keyboardExtension.initialPanelMode",
            "keyboardExtension.initialPanelModeSeedID",
            "keyboardExtension.initialPanelModeSeededAt",
            "keyboardExtension.composingBuffer"
        ]
        let originalValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0) as Any?) })
        defer {
            for key in keys {
                defaults.removeObject(forKey: key)
                if let value = originalValues[key] ?? nil {
                    defaults.set(value, forKey: key)
                }
            }
            defaults.synchronize()
        }

        for key in keys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()

        try body(defaults)
    }

    func testPersistedGatewayConnectionErrorBlocksKeyboardActions() {
        let proxy = FakeTextDocumentProxy(text: "please make this better")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: FailingKeyboardAIService(),
            loadConfig: { Self.configuredGateway },
            loadGatewayConnectionError: { "Gateway timed out. Open the app to retry." },
            productionTestFullAccess: true
        )

        XCTAssertFalse(viewModel.canRunAIAction)
        XCTAssertEqual(viewModel.toolbarState.title, "AI unavailable")
        XCTAssertEqual(viewModel.toolbarState.subtitle, "Gateway timed out. Open the app to retry.")
        XCTAssertEqual(viewModel.panelMode, .keyboard)

        viewModel.showActionPanel()

        XCTAssertEqual(viewModel.panelMode, .keyboard)
        XCTAssertEqual(proxy.text, "please make this better")
    }

    func testConfiguredFlagWithoutCompleteRuntimeConfigBlocksKeyboardActions() {
        let incompleteConfig = AppConfig(
            apiKey: "",
            gatewayURL: "https://mock.local.invalid",
            selectedModel: "test-model",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
        let proxy = FakeTextDocumentProxy(text: "please make this better")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: FailingKeyboardAIService(),
            loadConfig: { incompleteConfig },
            productionTestFullAccess: true
        )

        XCTAssertFalse(viewModel.canRunAIAction)
        XCTAssertEqual(viewModel.toolbarState.kind, .notConfigured)

        viewModel.showActionPanel()
        viewModel.performAIAction(.rewrite)

        XCTAssertEqual(viewModel.panelMode, .keyboard)
        XCTAssertEqual(viewModel.toolbarState.title, "Gateway not configured")
        XCTAssertEqual(proxy.text, "please make this better")
    }

    func testFixGrammarPlainTextCorrectionsOpenDetailWithoutReplacingText() async {
        let proxy = FakeTextDocumentProxy(text: "i has a apple and ths")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: SuccessfulKeyboardAIService(result: Self.grammarCorrectionResult()),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.fixGrammar)
        await waitUntil { !viewModel.isPerformingAIAction }

        XCTAssertEqual(viewModel.panelMode, .correctionDetail)
        XCTAssertEqual(viewModel.suggestionState?.correctionCount, 2)
        XCTAssertEqual(viewModel.suggestionState?.correctionProgressText, "1 of 2")
        XCTAssertEqual(viewModel.currentCorrectionCard?.categoryTitle, "Subject-verb agreement")
        XCTAssertEqual(proxy.text, "i has a apple and ths")
    }

    func testRewriteShowsOptionsBeforeApplyingSelectedRewrite() async {
        let proxy = FakeTextDocumentProxy(text: "please make this better")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: SuccessfulKeyboardAIService(result: Self.structuredRewriteResult()),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.rewrite)
        await waitUntil { !viewModel.isPerformingAIAction }

        XCTAssertEqual(proxy.text, "please make this better")
        XCTAssertEqual(viewModel.panelMode, .rewriteOptions)
        XCTAssertEqual(viewModel.rewriteOptionsState?.sourceText, "please make this better")
        XCTAssertEqual(viewModel.rewriteOptionsState?.options.map(\.text), [
            "Please make this clearer.",
            "Could you make this better?"
        ])
        XCTAssertEqual(viewModel.rewriteOptionsState?.selectedOption?.text, "Please make this clearer.")

        viewModel.selectRewriteOption("rewrite-option-2")
        XCTAssertEqual(viewModel.rewriteOptionsState?.selectedOption?.text, "Could you make this better?")

        viewModel.applySelectedRewriteOption()

        XCTAssertEqual(proxy.text, "Could you make this better?")
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
        XCTAssertNil(viewModel.rewriteOptionsState)
        XCTAssertEqual(viewModel.completionPanelState, .rewriteApplied)
    }

    func testImproveShowsImprovementOptionsBeforeApplyingSelectedImprovement() async {
        let proxy = FakeTextDocumentProxy(text: "please make this better")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: SuccessfulKeyboardAIService(result: Self.structuredRewriteResult()),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.improve)
        await waitUntil { !viewModel.isPerformingAIAction }

        XCTAssertEqual(proxy.text, "please make this better")
        XCTAssertEqual(viewModel.panelMode, .rewriteOptions)
        XCTAssertEqual(viewModel.rewriteOptionsState?.intent, .improve)
        XCTAssertEqual(viewModel.rewriteOptionsState?.intent.headerTitle, "Choose an improvement")
        XCTAssertEqual(viewModel.rewriteOptionsState?.selectedOption?.text, "Please make this clearer.")
        XCTAssertEqual(viewModel.toolbarState.subtitle, "2 improvements")

        viewModel.applySelectedRewriteOption()

        XCTAssertEqual(proxy.text, "Please make this clearer.")
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
        XCTAssertNil(viewModel.rewriteOptionsState)
        XCTAssertEqual(viewModel.completionPanelState, .improvementApplied)
    }

    func testAutomaticGrammarAnalysisShowsIssueCountBeforeOpeningCarousel() async {
        let proxy = FakeTextDocumentProxy(text: "")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: SuccessfulKeyboardAIService(result: Self.grammarCorrectionResult()),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true,
            automaticAnalysisDelayNanoseconds: 0
        )

        viewModel.insert("i has a apple and ths")
        await waitUntil { viewModel.suggestionState?.correctionCount == 2 && !viewModel.isPerformingAIAction }

        XCTAssertEqual(proxy.text, "i has a apple and ths")
        XCTAssertEqual(viewModel.panelMode, .keyboard)
        XCTAssertEqual(viewModel.toolbarState.issueCount, 2)
        XCTAssertTrue(viewModel.toolbarState.showsIssueCount)
        XCTAssertTrue(viewModel.canOpenAnalysisResult)

        viewModel.showAnalysisResult()

        XCTAssertEqual(viewModel.panelMode, .correctionDetail)
        XCTAssertEqual(viewModel.currentCorrectionCard?.categoryTitle, "Subject-verb agreement")
    }

    func testAutomaticGrammarAnalysisOpensNoIssuesScreenWhenAllClear() async {
        let proxy = FakeTextDocumentProxy(text: "")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: SuccessfulKeyboardAIService(result: Self.noIssueGrammarResult()),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true,
            automaticAnalysisDelayNanoseconds: 0
        )

        viewModel.insert("The app works well.")
        await waitUntil { viewModel.canOpenAnalysisResult && !viewModel.isPerformingAIAction }

        XCTAssertEqual(proxy.text, "The app works well.")
        XCTAssertEqual(viewModel.panelMode, .keyboard)
        XCTAssertFalse(viewModel.toolbarState.showsIssueCount)
        XCTAssertEqual(viewModel.toolbarState.subtitle, "No issues found")
        XCTAssertEqual(viewModel.completionPanelState, .noIssues)

        viewModel.showAnalysisResult()

        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
        XCTAssertEqual(viewModel.completionPanelState.title, "No issues found")
        XCTAssertEqual(viewModel.completionPanelState.message, "There are no grammar or spelling suggestions.")
    }

    func testAcceptingCurrentVisibleCorrectionKeepsCarouselUntilComplete() async {
        let proxy = FakeTextDocumentProxy(text: "i has a apple and ths")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: SuccessfulKeyboardAIService(result: Self.grammarCorrectionResult()),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.fixGrammar)
        await waitUntil { !viewModel.isPerformingAIAction }

        viewModel.moveToNextSuggestion()
        XCTAssertEqual(viewModel.currentCorrection?.original, "ths")

        viewModel.applyCurrentCorrection()
        XCTAssertEqual(proxy.text, "i has a apple and this")
        XCTAssertEqual(viewModel.panelMode, .correctionDetail)
        XCTAssertEqual(viewModel.currentCorrection?.original, "has")
        XCTAssertNil(viewModel.suggestionState?.correctionProgressText)

        viewModel.applyCurrentCorrection()
        XCTAssertEqual(proxy.text, "i have a apple and this")
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
        XCTAssertNil(viewModel.suggestionState)
    }

    func testGrammarCorrectionAfterCompletedCarouselUsesCurrentTextWhenDocumentContextIsStale() async {
        let sourceText = "i has a apple and ths"
        let correctedText = "i have a apple and this"
        let proxy = FakeTextDocumentProxy(text: sourceText)
        let service = SequencedKeyboardAIService(results: [
            Self.grammarCorrectionResult(),
            Self.noIssueGrammarResult()
        ])
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.openGrammarCorrection()
        await waitUntil { viewModel.panelMode == .correctionDetail && !viewModel.isGrammarCorrectionLoading }

        viewModel.applyCurrentCorrection()
        viewModel.applyCurrentCorrection()

        XCTAssertEqual(proxy.text, correctedText)
        XCTAssertEqual(viewModel.panelMode, .correctionComplete)

        proxy.documentContextBeforeInputOverride = sourceText
        viewModel.showKeyboardPanel()
        viewModel.openGrammarCorrection()

        await waitUntil { service.requestedTexts.count == 2 && !viewModel.isGrammarCorrectionLoading }

        XCTAssertEqual(service.requestedTexts, [sourceText, correctedText])
        XCTAssertEqual(viewModel.completionPanelState, .noIssues)
    }

    func testStaleArticleCorrectionIsFilteredBeforePresentation() async {
        let text = "Yesterday I has an apple before the meeting, and this message still sound wrong."
        let proxy = FakeTextDocumentProxy(text: text)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: SuccessfulKeyboardAIService(result: Self.staleArticleGrammarResult()),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.fixGrammar)
        await waitUntil { !viewModel.isPerformingAIAction }

        XCTAssertEqual(viewModel.currentCorrection?.original, "has")
        XCTAssertEqual(viewModel.currentCorrection?.replacement, "had")
        XCTAssertEqual(proxy.text, text)
        XCTAssertFalse(proxy.text.contains("ann apple"))
    }

    func testPlainGrammarMixedChoicesThenCheckAgainUsesOneNewRequestWithCurrentText() async {
        let source = "Our support team definately need clearer notes before they reply about the refnd."
        let corrected = "Our support team definitely needs clearer notes before they reply about the refund."
        let mixedResult = "Our support team definitely need clearer notes before they reply about the refund."
        let service = SequencedKeyboardAIService(results: [
            Self.plainGrammarResult(corrected),
            Self.plainGrammarResult(mixedResult)
        ])
        let proxy = FakeTextDocumentProxy(text: source)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.openGrammarCorrection()
        await waitUntil { viewModel.suggestionState?.correctionCount == 3 && !viewModel.isGrammarCorrectionLoading }
        viewModel.applyCurrentCorrection()
        viewModel.dismissCurrentCorrection()
        viewModel.acceptAllGrammarCorrections()

        XCTAssertEqual(proxy.text, mixedResult)
        XCTAssertEqual(viewModel.completionPanelState, .grammarReviewComplete)

        viewModel.checkGrammarAgain()
        await waitUntil { service.requestedTexts.count == 2 && !viewModel.isGrammarCorrectionLoading }

        XCTAssertEqual(service.requestedTexts, [source, mixedResult])
        XCTAssertEqual(viewModel.completionPanelState, .noIssues)
    }

    func testRejectAllKeepsOriginalAndManualDocumentEditInvalidatesGrammarSession() async {
        let source = "i has teh note."
        let corrected = "I have the note."
        let service = SuccessfulKeyboardAIService(result: Self.plainGrammarResult(corrected))
        let proxy = FakeTextDocumentProxy(text: source)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.openGrammarCorrection()
        await waitUntil { viewModel.suggestionState != nil && !viewModel.isGrammarCorrectionLoading }
        viewModel.rejectAllGrammarCorrections()
        XCTAssertEqual(proxy.text, source)
        XCTAssertEqual(viewModel.completionPanelState, .grammarReviewComplete)

        viewModel.checkGrammarAgain()
        await waitUntil { viewModel.suggestionState != nil && !viewModel.isGrammarCorrectionLoading }
        proxy.replaceTextForTest(source + " Manual edit")
        viewModel.documentDidChange()

        XCTAssertNil(viewModel.suggestionState)
        XCTAssertEqual(viewModel.panelMode, .keyboard)
    }

    func testGrammarRequestUsesExactWholeMultilineDocumentIncludingWhitespaceAndEmoji() async {
        let source = "  First paragraph is clean. 🙂\n\nSecond paragraf need correction.  "
        let service = SequencedKeyboardAIService(results: [Self.plainGrammarResult(source)])
        let proxy = FakeTextDocumentProxy(text: source, cursorOffset: 20)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: service,
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.openGrammarCorrection()
        await waitUntil { service.requestedTexts.count == 1 && !viewModel.isGrammarCorrectionLoading }

        XCTAssertEqual(service.requestedTexts, [source])
        XCTAssertEqual(proxy.text, source)
        XCTAssertEqual(viewModel.completionPanelState, .noIssues)
    }

    private func assertGatewayFailureShowsErrorAndPreservesText(for action: KeyboardAIAction, file: StaticString = #filePath, line: UInt = #line) async {
        let proxy = FakeTextDocumentProxy(text: "please make this better")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            aiService: FailingKeyboardAIService(),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(action)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(proxy.text, "please make this better", "Failed \(action.title) must preserve original typed text", file: file, line: line)
        XCTAssertNotNil(viewModel.actionError, "Failed \(action.title) should expose a visible keyboard error state", file: file, line: line)
        XCTAssertEqual(viewModel.actionError?.title, "AI unavailable", file: file, line: line)
        XCTAssertEqual(viewModel.actionError?.message, "Unable to reach gateway.", file: file, line: line)
        XCTAssertEqual(viewModel.toolbarState.title, "AI unavailable", file: file, line: line)
        XCTAssertEqual(viewModel.toolbarState.subtitle, "Unable to reach gateway.", file: file, line: line)
        XCTAssertNotEqual(viewModel.toolbarState.subtitle, "Ready", file: file, line: line)
        XCTAssertFalse(viewModel.isPerformingAIAction, file: file, line: line)
        XCTAssertNil(viewModel.currentCorrection, "Failed \(action.title) must not show stale correction preview", file: file, line: line)
    }

    private static let configuredGateway = AppConfig(
        apiKey: "test-key",
        gatewayURL: "https://mock.local.invalid",
        selectedModel: "test-model",
        isConfigured: true,
        supportsStructuredCorrections: true,
        structuredCorrectionSchemaVersion: "test"
    )

    private static func grammarCorrectionResult() -> KeyboardActionOperationResult {
        plainGrammarResult("i have a apple and this")
    }

    private static func noIssueGrammarResult() -> KeyboardActionOperationResult {
        KeyboardActionOperationResult(
            operation: "fix_grammar",
            items: [],
            isNoChangeResult: true
        )
    }

    private static func plainGrammarResult(_ correctedText: String) -> KeyboardActionOperationResult {
        KeyboardActionOperationResult(
            operation: "fix_grammar",
            items: [],
            correctedText: correctedText
        )
    }

    private static func structuredRewriteResult() -> KeyboardActionOperationResult {
        KeyboardActionOperationResult(
            operation: "rewrite",
            items: [
                KeyboardActionOperationResult.Item(
                    id: "clear",
                    type: "suggestion",
                    title: "Clearer",
                    text: "Please make this clearer.",
                    replacement: "Please make this clearer."
                ),
                KeyboardActionOperationResult.Item(
                    id: "friendly",
                    type: "suggestion",
                    title: "Friendly",
                    text: "Could you make this better?",
                    replacement: "Could you make this better?"
                )
            ],
            correctedText: "Please make this clearer.",
            isStructuredResponse: true
        )
    }

    private static func structuredTranslationResult() -> KeyboardActionOperationResult {
        KeyboardActionOperationResult(
            operation: "translate",
            items: [
                KeyboardActionOperationResult.Item(
                    id: "translation-1",
                    type: "translation",
                    title: "Dutch translation",
                    text: "Goedemorgen, ik hoop dat het goed met je gaat.",
                    replacement: "Goedemorgen, ik hoop dat het goed met je gaat."
                )
            ],
            correctedText: "Goedemorgen, ik hoop dat het goed met je gaat.",
            isStructuredResponse: true
        )
    }

    private static func staleArticleGrammarResult() -> KeyboardActionOperationResult {
        plainGrammarResult("Yesterday I had an apple before the meeting, and this message still sounds wrong.")
    }

    private func waitUntil(_ predicate: @MainActor @escaping () -> Bool) async {
        for _ in 0..<100 {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for async keyboard action")
    }
}

private final class SuccessfulKeyboardAIService: KeyboardAIServiceProviding {
    let result: KeyboardActionOperationResult

    init(result: KeyboardActionOperationResult) {
        self.result = result
    }

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        result.suggestionResponse()
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        result.displayText
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        result
    }
}

private final class RoutingKeyboardAIService: KeyboardAIServiceProviding {
    let grammarResult: KeyboardActionOperationResult
    let rewriteResult: KeyboardActionOperationResult
    private(set) var requestedActions: [KeyboardAIAction] = []

    init(grammarResult: KeyboardActionOperationResult, rewriteResult: KeyboardActionOperationResult) {
        self.grammarResult = grammarResult
        self.rewriteResult = rewriteResult
    }

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        grammarResult.suggestionResponse()
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        try await performResult(action: action, on: text, config: config).displayText
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        requestedActions.append(action)
        return action == .fixGrammar ? grammarResult : rewriteResult
    }
}

private final class DelayedRecordingKeyboardAIService: KeyboardAIServiceProviding {
    let result: KeyboardActionOperationResult
    private(set) var requestedActions: [KeyboardAIAction] = []

    init(result: KeyboardActionOperationResult) {
        self.result = result
    }

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        result.suggestionResponse()
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        try await performResult(action: action, on: text, config: config).displayText
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        requestedActions.append(action)
        try? await Task.sleep(nanoseconds: 50_000_000)
        return result
    }
}

private final class CancellableDelayedRecordingKeyboardAIService: KeyboardAIServiceProviding {
    let result: KeyboardActionOperationResult
    private(set) var requestedActions: [KeyboardAIAction] = []

    init(result: KeyboardActionOperationResult) {
        self.result = result
    }

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        result.suggestionResponse()
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        try await performResult(action: action, on: text, config: config).displayText
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        requestedActions.append(action)
        let delay: UInt64 = requestedActions.count == 1 ? 1_000_000_000 : 100_000_000
        try await Task.sleep(nanoseconds: delay)
        return result
    }
}

private final class SequencedKeyboardAIService: KeyboardAIServiceProviding {
    private var results: [KeyboardActionOperationResult]
    private(set) var requestedActions: [KeyboardAIAction] = []
    private(set) var requestedTexts: [String] = []

    init(results: [KeyboardActionOperationResult]) {
        self.results = results
    }

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        try nextResult().suggestionResponse()
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        try await performResult(action: action, on: text, config: config).displayText
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        requestedActions.append(action)
        requestedTexts.append(text)
        return try nextResult()
    }

    private func nextResult() throws -> KeyboardActionOperationResult {
        guard !results.isEmpty else {
            throw KeyboardAIError.invalidResponse
        }
        return results.removeFirst()
    }
}

private final class DelayedSequencedKeyboardAIService: KeyboardAIServiceProviding {
    private var results: [KeyboardActionOperationResult]
    private let delays: [UInt64]
    private(set) var requestedActions: [KeyboardAIAction] = []
    private(set) var requestedTexts: [String] = []

    init(results: [KeyboardActionOperationResult], delays: [UInt64]) {
        self.results = results
        self.delays = delays
    }

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        let result = try await performResult(action: .fixGrammar, on: text, config: config)
        return try result.suggestionResponse()
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        try await performResult(action: action, on: text, config: config).displayText
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        let requestIndex = requestedActions.count
        requestedActions.append(action)
        requestedTexts.append(text)
        let result = try nextResult()
        let delay = requestIndex < delays.count ? delays[requestIndex] : 0
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        return result
    }

    private func nextResult() throws -> KeyboardActionOperationResult {
        guard !results.isEmpty else {
            throw KeyboardAIError.invalidResponse
        }
        return results.removeFirst()
    }
}

private final class DelayedKeyboardAIService: KeyboardAIServiceProviding {
    let result: KeyboardActionOperationResult

    init(result: KeyboardActionOperationResult) {
        self.result = result
    }

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        try? await Task.sleep(nanoseconds: 50_000_000)
        return result.suggestionResponse()
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        try? await Task.sleep(nanoseconds: 50_000_000)
        return result.displayText
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        try? await Task.sleep(nanoseconds: 50_000_000)
        return result
    }
}

private final class ErrorTextResultKeyboardAIService: KeyboardAIServiceProviding {
    private let errorText = "The model returned malformed JSON and no safe keyboard text could be extracted."

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        throw KeyboardAIError.invalidResponse
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        errorText
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        KeyboardActionOperationResult(
            operation: action.operationName,
            items: [KeyboardActionOperationResult.Item(id: "error-1", type: "warning", title: "Error", text: errorText, replacement: errorText)],
            isStructuredResponse: true
        )
    }
}

private final class InvalidRawResponseKeyboardAIService: KeyboardAIServiceProviding {
    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        throw KeyboardAIError.server("Gateway failed {\"api_key\":\"secret-token\",\"stack\":[1,2,3]}")
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        throw KeyboardAIError.server("Gateway failed {\"api_key\":\"secret-token\",\"stack\":[1,2,3]}")
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        throw KeyboardAIError.server("Gateway failed {\"api_key\":\"secret-token\",\"stack\":[1,2,3]}")
    }
}

private final class RecordingNextTextPredictor: NextTextPredicting {
    private(set) var requests: [NextTextPredictionRequest] = []

    func predictions(for request: NextTextPredictionRequest) -> [NextTextPrediction] {
        requests.append(request)
        return [NextTextPrediction(text: "hidden", kind: .nextWord, score: 1)]
    }
}

private final class FailingKeyboardAIService: KeyboardAIServiceProviding {
    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        throw KeyboardAIError.server("Unable to reach gateway.")
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        throw KeyboardAIError.server("Unable to reach gateway.")
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        throw KeyboardAIError.server("Unable to reach gateway.")
    }
}

private final class ThrowingKeyboardAIService: KeyboardAIServiceProviding {
    let error: KeyboardAIError

    init(error: KeyboardAIError) {
        self.error = error
    }

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        throw error
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        throw error
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        throw error
    }
}

private final class CancellingKeyboardAIService: KeyboardAIServiceProviding {
    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        throw CancellationError()
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        throw CancellationError()
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        throw CancellationError()
    }
}

private final class FakeTextDocumentProxy: NSObject, UITextDocumentProxy {
    var text: String
    var documentContextBeforeInputOverride: String?
    var documentContextAfterInputOverride: String?
    private var cursorOffset: Int

    init(text: String, cursorOffset: Int? = nil) {
        self.text = text
        self.cursorOffset = min(max(cursorOffset ?? text.count, 0), text.count)
        super.init()
    }

    func replaceTextForTest(_ text: String, cursorOffset: Int? = nil) {
        self.text = text
        self.cursorOffset = min(max(cursorOffset ?? text.count, 0), text.count)
        documentContextBeforeInputOverride = nil
        documentContextAfterInputOverride = nil
    }

    var documentContextBeforeInput: String? {
        documentContextBeforeInputOverride ?? String(text.prefix(cursorOffset))
    }
    var documentContextAfterInput: String? {
        documentContextAfterInputOverride ?? String(text.dropFirst(cursorOffset))
    }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }
    var keyboardType: UIKeyboardType { .default }
    var hasText: Bool { !text.isEmpty }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        cursorOffset = min(max(cursorOffset + offset, 0), text.count)
    }
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}

    func insertText(_ text: String) {
        let index = self.text.index(self.text.startIndex, offsetBy: cursorOffset)
        self.text.insert(contentsOf: text, at: index)
        cursorOffset += text.count
    }

    func deleteBackward() {
        guard cursorOffset > 0, !text.isEmpty else { return }
        let index = text.index(text.startIndex, offsetBy: cursorOffset - 1)
        text.remove(at: index)
        cursorOffset -= 1
    }
}
