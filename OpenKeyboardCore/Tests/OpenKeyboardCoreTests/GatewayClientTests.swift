import XCTest
@testable import OpenKeyboardCore

final class GatewayClientTests: XCTestCase {
    func testHealthBuildsAuthorizedRequest() async throws {
        let server = DummyGatewayServer(.healthOK)
        let client = GatewayClient(config: validConfig, httpClient: server)

        let result = try await client.checkHealth()

        XCTAssertTrue(result)
        XCTAssertEqual(server.requests.first?.url.absoluteString, "https://gateway.example/health")
        XCTAssertEqual(server.requests.first?.headers["Authorization"], "Bearer test-key")
        XCTAssertEqual(server.requests.first?.method, "GET")
    }

    func testFetchModelsParsesOpenAICompatibleResponse() async throws {
        let server = DummyGatewayServer(.models(["gpt-oss:120b", "llama3.2"]))
        let client = GatewayClient(config: validConfig, httpClient: server)

        let models = try await client.fetchModels()

        XCTAssertEqual(models, ["gpt-oss:120b", "llama3.2"])
        XCTAssertEqual(server.requests.first?.url.absoluteString, "https://gateway.example/v1/models")
        XCTAssertEqual(server.requests.first?.headers["Authorization"], "Bearer test-key")
    }

    func testUnauthorizedMapsToTypedError() async {
        let server = DummyGatewayServer(.status(401))
        let client = GatewayClient(config: validConfig, httpClient: server)

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .unauthorized)
        }
    }

    func testRateLimitMapsToTypedError() async {
        let server = DummyGatewayServer(.status(429))
        let client = GatewayClient(config: validConfig, httpClient: server)

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .rateLimited)
        }
    }

    func testServerErrorIncludesStatusCode() async {
        let server = DummyGatewayServer(.status(503))
        let client = GatewayClient(config: validConfig, httpClient: server)

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .serverError(statusCode: 503))
        }
    }

    func testInvalidModelsJSONMapsToDecodingError() async {
        let server = DummyGatewayServer(.malformedModels)
        let client = GatewayClient(config: validConfig, httpClient: server)

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }
    }

    func testForbiddenMapsToTypedError() async {
        let server = DummyGatewayServer(.status(403))
        let client = GatewayClient(config: validConfig, httpClient: server)

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .forbidden)
        }
    }

    func testUnexpectedStatusIncludesStatusCode() async {
        let server = DummyGatewayServer(.status(418))
        let client = GatewayClient(config: validConfig, httpClient: server)

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .unexpectedStatus(statusCode: 418))
        }
    }

    func testHealthInvalidJSONMapsToInvalidResponse() async {
        let server = DummyGatewayServer(.healthMalformed)
        let client = GatewayClient(config: validConfig, httpClient: server)

        await XCTAssertThrowsErrorAsync(try await client.checkHealth()) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }
    }

    private var validConfig: GatewayConfig { DummyGatewayServer.validConfig }
}
