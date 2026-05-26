import XCTest
@testable import OpenKeyboardCore

final class UserFlowTests: XCTestCase {
    func testFixGrammarFlowFromConfigToFinalReplacement() async throws {
        let flow = try await runWritingFlow(
            action: .fixGrammar,
            typedText: "i has a apple",
            modelResponse: "I have an apple.",
            expectedPromptFragments: ["Fix grammar and spelling", "i has a apple"],
            replacementStrategy: .replaceAll
        )

        XCTAssertEqual(flow.models, ["local-llm", "cloud-llm"])
        XCTAssertEqual(flow.selectedModel, "local-llm")
        XCTAssertEqual(flow.finalText, "I have an apple.")
    }

    func testRewriteFlowUsesContextAndReplacesUserVisibleText() async throws {
        let flow = try await runWritingFlow(
            action: .rewrite,
            typedText: "this sounds bad",
            modelResponse: "This could sound better.",
            expectedPromptFragments: ["Rewrite", "clarity", "this sounds bad"],
            replacementStrategy: .replaceAll
        )

        XCTAssertEqual(flow.finalText, "This could sound better.")
    }

    func testSummarizeFlowReturnsConciseReplacement() async throws {
        let original = "Open Keyboard lets users connect a gateway, choose a model, and improve selected text from the keyboard."

        let flow = try await runWritingFlow(
            action: .summarize,
            typedText: original,
            modelResponse: "Open Keyboard improves text through a configured gateway.",
            expectedPromptFragments: ["Summarize", original],
            replacementStrategy: .replaceAll
        )

        XCTAssertEqual(flow.finalText, "Open Keyboard improves text through a configured gateway.")
    }

    func testContinueWritingFlowAppendsCompletionAtCursor() async throws {
        let flow = try await runWritingFlow(
            action: .continueWriting,
            typedText: "Once the keyboard connects",
            modelResponse: ", it can suggest the next sentence.",
            expectedPromptFragments: ["Continue writing", "Return only the continuation", "Once the keyboard connects"],
            replacementStrategy: .appendToCursor
        )

        XCTAssertEqual(flow.finalText, "Once the keyboard connects, it can suggest the next sentence.")
    }

    private func runWritingFlow(
        action: WritingAction,
        typedText: String,
        modelResponse: String,
        expectedPromptFragments: [String],
        replacementStrategy: AITextReplacementStrategy,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> WritingFlowResult {
        let config = GatewayConfig(
            gatewayURL: URL(string: "https://gateway.example/")!,
            apiKey: " test-key "
        ).normalized()
        XCTAssertNoThrow(try config.validate(), file: file, line: line)

        let http = SequencedMockHTTPClient(responses: [
            HTTPResponse(statusCode: 200, data: #"{"data":[{"id":"local-llm"},{"id":"cloud-llm"}]}"#.data(using: .utf8)!),
            HTTPResponse(statusCode: 200, data: chatCompletionData(content: modelResponse))
        ])
        let client = GatewayClient(config: config, httpClient: http)

        let models = try await client.fetchModels()
        let selectedModel = try XCTUnwrap(models.first, file: file, line: line)

        let output = try await client.performWritingAction(action, text: typedText, model: selectedModel)
        let finalText = replacementStrategy.apply(original: typedText, replacement: output)

        XCTAssertEqual(http.requests.map(\.url.absoluteString), [
            "https://gateway.example/v1/models",
            "https://gateway.example/v1/chat/completions"
        ], file: file, line: line)
        XCTAssertEqual(http.requests.map(\.headers["Authorization"]), ["Bearer test-key", "Bearer test-key"], file: file, line: line)

        let chatRequest = try XCTUnwrap(http.requests.last, file: file, line: line)
        XCTAssertEqual(chatRequest.method, "POST", file: file, line: line)
        XCTAssertEqual(chatRequest.headers["Content-Type"], "application/json", file: file, line: line)

        let body = try XCTUnwrap(chatRequest.body, file: file, line: line)
        let bodyString = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(bodyString.contains(#""model":"local-llm""#), file: file, line: line)
        XCTAssertTrue(bodyString.contains(#""stream":false"#), file: file, line: line)
        for fragment in expectedPromptFragments {
            XCTAssertTrue(bodyString.contains(fragment), "Missing prompt fragment: \(fragment)", file: file, line: line)
        }

        return WritingFlowResult(models: models, selectedModel: selectedModel, finalText: finalText)
    }
}

private struct WritingFlowResult {
    let models: [String]
    let selectedModel: String
    let finalText: String
}

private final class SequencedMockHTTPClient: HTTPClient, @unchecked Sendable {
    private var responses: [HTTPResponse]
    private(set) var requests: [HTTPRequest] = []

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            return HTTPResponse(statusCode: 500, data: Data())
        }
        return responses.removeFirst()
    }
}

private func chatCompletionData(content: String) -> Data {
    let escapedContent = content
        .replacingOccurrences(of: #"\"#, with: #"\\"#)
        .replacingOccurrences(of: #""#, with: #"\"#)
        .replacingOccurrences(of: "\n", with: #"\n"#)

    return #"{"choices":[{"message":{"content":"\#(escapedContent)"}}]}"#.data(using: .utf8)!
}
