import XCTest
import UIKit

@MainActor
final class KeyboardViewModelActionErrorTests: XCTestCase {
    override func tearDown() {
        UIPasteboard.general.string = nil
        super.tearDown()
    }

    func testRewriteFailureShowsSanitizedErrorAndPreservesText() async {
        await assertGatewayFailureShowsErrorAndPreservesText(for: .rewrite)
    }

    func testFixGrammarFailureShowsSanitizedErrorAndPreservesText() async {
        await assertGatewayFailureShowsErrorAndPreservesText(for: .fixGrammar)
    }

    func testFailureKeepsStickyErrorUntilExplicitRecoveryActions() async {
        let proxy = FakeTextDocumentProxy(text: "please make this better")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            advanceToNextInputMode: {},
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
        XCTAssertEqual(UIPasteboard.general.string, "Gateway error: Unable to reach gateway.")

        viewModel.retryAfterActionError()
        XCTAssertNil(viewModel.actionError)
        XCTAssertEqual(viewModel.panelMode, .actions)
        XCTAssertEqual(proxy.text, "please make this better")

        viewModel.performAIAction(.rewrite)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNotNil(viewModel.actionError)

        viewModel.clearActionError()
        XCTAssertNil(viewModel.actionError)
        XCTAssertEqual(viewModel.panelMode, .keyboard)
    }

    func testInvalidStructuredResponseCopyIsSpecificAndSanitized() async {
        let proxy = FakeTextDocumentProxy(text: "i has a apple,ths is nt sound sound")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            advanceToNextInputMode: {},
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
        XCTAssertEqual(UIPasteboard.general.string, "Gateway error: Gateway returned an invalid response.")
    }

    func testErrorTextOperationResultShowsErrorAndNeverReplacesDocumentText() async {
        let original = "Keep my original words."
        let proxy = FakeTextDocumentProxy(text: original)
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            advanceToNextInputMode: {},
            aiService: ErrorTextResultKeyboardAIService(),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.rewrite)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(proxy.text, original)
        XCTAssertEqual(viewModel.actionError?.message, "No AI response")
        XCTAssertEqual(viewModel.toolbarState.title, "AI unavailable")
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

    private func assertGatewayFailureShowsErrorAndPreservesText(for action: KeyboardAIAction, file: StaticString = #filePath, line: UInt = #line) async {
        let proxy = FakeTextDocumentProxy(text: "please make this better")
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            advanceToNextInputMode: {},
            aiService: FailingKeyboardAIService(),
            loadConfig: { Self.configuredGateway },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(action)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(proxy.text, "please make this better", "Failed \(action.title) must preserve original typed text", file: file, line: line)
        XCTAssertNotNil(viewModel.actionError, "Failed \(action.title) should expose a visible keyboard error state", file: file, line: line)
        XCTAssertEqual(viewModel.actionError?.title, "Gateway error", file: file, line: line)
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

private final class FakeTextDocumentProxy: NSObject, UITextDocumentProxy {
    var text: String

    init(text: String) {
        self.text = text
        super.init()
    }

    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }
    var keyboardType: UIKeyboardType { .default }
    var hasText: Bool { !text.isEmpty }

    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}

    func insertText(_ text: String) {
        self.text += text
    }

    func deleteBackward() {
        guard !text.isEmpty else { return }
        text.removeLast()
    }
}
