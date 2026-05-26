import XCTest
@testable import OpenKeyboardCore

final class GatewayClientTests: XCTestCase {
    func testHealthBuildsAuthorizedRequest() async throws {
        let http = MockHTTPClient(response: HTTPResponse(statusCode: 200, data: #"{"status":"ok"}"#.data(using: .utf8)!))
        let client = GatewayClient(config: validConfig, httpClient: http)

        let result = try await client.checkHealth()

        XCTAssertTrue(result)
        XCTAssertEqual(http.requests.first?.url.absoluteString, "https://gateway.example/health")
        XCTAssertEqual(http.requests.first?.headers["Authorization"], "Bearer test-key")
        XCTAssertEqual(http.requests.first?.method, "GET")
    }

    func testFetchModelsParsesOpenAICompatibleResponse() async throws {
        let body = #"{"data":[{"id":"gpt-oss:120b"},{"id":"llama3.2"}]}"#.data(using: .utf8)!
        let http = MockHTTPClient(response: HTTPResponse(statusCode: 200, data: body))
        let client = GatewayClient(config: validConfig, httpClient: http)

        let models = try await client.fetchModels()

        XCTAssertEqual(models, ["gpt-oss:120b", "llama3.2"])
        XCTAssertEqual(http.requests.first?.url.absoluteString, "https://gateway.example/v1/models")
        XCTAssertEqual(http.requests.first?.headers["Authorization"], "Bearer test-key")
    }

    func testUnauthorizedMapsToTypedError() async {
        let http = MockHTTPClient(response: HTTPResponse(statusCode: 401, data: Data()))
        let client = GatewayClient(config: validConfig, httpClient: http)

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .unauthorized)
        }
    }

    func testRateLimitMapsToTypedError() async {
        let http = MockHTTPClient(response: HTTPResponse(statusCode: 429, data: Data()))
        let client = GatewayClient(config: validConfig, httpClient: http)

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .rateLimited)
        }
    }

    func testServerErrorIncludesStatusCode() async {
        let http = MockHTTPClient(response: HTTPResponse(statusCode: 503, data: Data()))
        let client = GatewayClient(config: validConfig, httpClient: http)

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .serverError(statusCode: 503))
        }
    }

    func testInvalidModelsJSONMapsToDecodingError() async {
        let http = MockHTTPClient(response: HTTPResponse(statusCode: 200, data: #"{"data":123}"#.data(using: .utf8)!))
        let client = GatewayClient(config: validConfig, httpClient: http)

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }
    }


    func testForbiddenMapsToTypedError() async {
        let http = MockHTTPClient(response: HTTPResponse(statusCode: 403, data: Data()))
        let client = GatewayClient(config: validConfig, httpClient: http)

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .forbidden)
        }
    }

    func testUnexpectedStatusIncludesStatusCode() async {
        let http = MockHTTPClient(response: HTTPResponse(statusCode: 418, data: Data()))
        let client = GatewayClient(config: validConfig, httpClient: http)

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .unexpectedStatus(statusCode: 418))
        }
    }

    func testHealthInvalidJSONMapsToInvalidResponse() async {
        let http = MockHTTPClient(response: HTTPResponse(statusCode: 200, data: #"{"status":123}"#.data(using: .utf8)!))
        let client = GatewayClient(config: validConfig, httpClient: http)

        await XCTAssertThrowsErrorAsync(try await client.checkHealth()) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }
    }


    private var validConfig: GatewayConfig {
        GatewayConfig(gatewayURL: URL(string: "https://gateway.example")!, apiKey: "test-key")
    }
}

private final class MockHTTPClient: HTTPClient, @unchecked Sendable {
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

