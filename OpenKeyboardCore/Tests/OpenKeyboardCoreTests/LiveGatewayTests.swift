import XCTest
@testable import OpenKeyboardCore

final class LiveGatewayTests: XCTestCase {
    func testLiveGatewayHealthModelsAndChatWhenConfigured() async throws {
        guard let gatewayURLString = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_LIVE_GATEWAY_URL"],
              let gatewayURL = URL(string: gatewayURLString),
              let apiKey = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_LIVE_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("Set OPEN_KEYBOARD_LIVE_GATEWAY_URL and OPEN_KEYBOARD_LIVE_API_KEY to run live gateway smoke tests.")
        }

        let model = ProcessInfo.processInfo.environment["OPEN_KEYBOARD_LIVE_MODEL"] ?? "gpt-oss:120b"
        let client = GatewayClient(
            config: GatewayConfig(gatewayURL: gatewayURL, apiKey: apiKey),
            httpClient: URLSessionHTTPClient()
        )

        let isHealthy = try await client.checkHealth()
        XCTAssertTrue(isHealthy)
        _ = try await client.fetchModels()

        let output = try await client.performWritingAction(
            .fixGrammar,
            text: "i has a apple",
            model: model
        )

        XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
