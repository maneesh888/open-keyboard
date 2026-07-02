import XCTest

final class GatewayClientArchitectureTests: XCTestCase {
    func testCanonicalGatewayClientDecodesEnvelope() async throws {
        let responseBody = #"{"choices":[{"message":{"content":"  I have an apple; this does not sound good.  "}}]}"#
        let transport = CanonicalGatewayClientTestTransport(
            data: Data(responseBody.utf8),
            statusCode: 200
        )
        let client = CanonicalGatewayClient(transport: transport)
        let config = AppConfig(
            apiKey: "test-api-key",
            gatewayURL: "https://gateway.example/v1",
            selectedModel: "test-model",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        let content = try await client.chatCompletionContent(
            systemPrompt: "Return strict JSON only.",
            userPrompt: "Fix grammar: i has a apple,ths is nt sound god",
            operation: "fix_grammar",
            inputText: "i has a apple,ths is nt sound god",
            maxTokens: 256,
            config: config
        )

        XCTAssertEqual(content, "I have an apple; this does not sound good.")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertNil(json["operation"])
        XCTAssertNil(json["input_text"])
        XCTAssertEqual(json["max_tokens"] as? Int, 256)
        XCTAssertEqual(json["stream"] as? Bool, false)
    }
}

private final class CanonicalGatewayClientTestTransport: GatewayChatTransporting {
    private let data: Data
    private let statusCode: Int
    private(set) var requests: [URLRequest] = []

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: try XCTUnwrap(request.url),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
