import Foundation
import XCTest
@testable import OpenKeyboardCore

final class GatewayNetworkResilienceTests: XCTestCase {
    func testTimeoutMapsToTypedUserDisplayableError() async {
        let client = GatewayClient(config: validConfig, httpClient: ThrowingHTTPClient(error: URLError(.timedOut)))

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .timedOut)
            XCTAssertEqual((error as? GatewayClientError)?.userMessage, "The gateway request timed out. Check your connection and try again.")
        }
    }

    func testOfflineNetworkFailuresMapToNetworkUnavailable() async {
        let client = GatewayClient(config: validConfig, httpClient: ThrowingHTTPClient(error: URLError(.notConnectedToInternet)))

        await XCTAssertThrowsErrorAsync(try await client.checkHealth()) { error in
            XCTAssertEqual(error as? GatewayClientError, .networkUnavailable)
            XCTAssertEqual((error as? GatewayClientError)?.userMessage, "The gateway is unreachable. Check your network or gateway URL.")
        }
    }

    func testCancellationPropagatesAsTypedCancellation() async {
        let client = GatewayClient(config: validConfig, httpClient: ThrowingHTTPClient(error: CancellationError()))

        await XCTAssertThrowsErrorAsync(try await client.performWritingAction(.fixGrammar, text: "helo", model: "test-model")) { error in
            XCTAssertEqual(error as? GatewayClientError, .cancelled)
            XCTAssertEqual((error as? GatewayClientError)?.userMessage, "The gateway request was cancelled.")
        }
    }

    func testUnknownURLErrorMapsToRetryableTransportFailure() async {
        let client = GatewayClient(config: validConfig, httpClient: ThrowingHTTPClient(error: URLError(.secureConnectionFailed)))

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .transportError)
            XCTAssertEqual((error as? GatewayClientError)?.userMessage, "The gateway request failed before a response was received.")
        }
    }

    func testUnknownNonURLErrorMapsToRetryableTransportFailure() async {
        let client = GatewayClient(config: validConfig, httpClient: ThrowingHTTPClient(error: MockTransportError()))

        await XCTAssertThrowsErrorAsync(try await client.fetchModels()) { error in
            XCTAssertEqual(error as? GatewayClientError, .transportError)
            XCTAssertEqual((error as? GatewayClientError)?.userMessage, "The gateway request failed before a response was received.")
        }
    }

    private var validConfig: GatewayConfig {
        GatewayConfig(gatewayURL: URL(string: "https://gateway.example")!, apiKey: "test-key")
    }
}

private final class ThrowingHTTPClient: HTTPClient, @unchecked Sendable {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        throw error
    }
}

private struct MockTransportError: Error {}
