import XCTest
@testable import OpenKeyboardCore

final class ChatCompletionTests: XCTestCase {
    func testPerformWritingActionBuildsAuthorizedChatCompletionRequest() async throws {
        let body = #"{"choices":[{"message":{"content":"Corrected text."}}]}"#.data(using: .utf8)!
        let http = CapturingHTTPClient(response: HTTPResponse(statusCode: 200, data: body))
        let client = GatewayClient(config: validConfig, httpClient: http)

        let output = try await client.performWritingAction(.fixGrammar, text: "i has a apple", model: "test-model")

        XCTAssertEqual(output, "Corrected text.")
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://gateway.example/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer test-key")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["stream"] as? Bool, false)
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "user")
        XCTAssertTrue(messages.first?["content"]?.contains("i has a apple") == true)
    }

    func testPerformWritingActionTrimsCompletionContent() async throws {
        let body = #"{"choices":[{"message":{"content":"  Corrected text.\n"}}]}"#.data(using: .utf8)!
        let http = CapturingHTTPClient(response: HTTPResponse(statusCode: 200, data: body))
        let client = GatewayClient(config: validConfig, httpClient: http)

        let output = try await client.performWritingAction(.fixGrammar, text: "bad", model: "test-model")

        XCTAssertEqual(output, "Corrected text.")
    }

    func testPerformWritingActionEmptyChoicesMapsToInvalidResponse() async {
        let body = #"{"choices":[]}"#.data(using: .utf8)!
        let http = CapturingHTTPClient(response: HTTPResponse(statusCode: 200, data: body))
        let client = GatewayClient(config: validConfig, httpClient: http)

        await XCTAssertThrowsErrorAsync(try await client.performWritingAction(.summarize, text: "Hello", model: "test-model")) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }
    }

    private var validConfig: GatewayConfig {
        GatewayConfig(gatewayURL: URL(string: "https://gateway.example")!, apiKey: "test-key")
    }
}

private final class CapturingHTTPClient: HTTPClient, @unchecked Sendable {
    private let response: HTTPResponse
    private(set) var requests: [HTTPRequest] = []

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return response
    }
}
