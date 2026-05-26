import XCTest
@testable import OpenKeyboardCore

final class GatewayConfigTests: XCTestCase {
    func testValidateRejectsEmptyAPIKey() {
        let config = GatewayConfig(gatewayURL: URL(string: "https://gateway.example")!, apiKey: "")

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual(error as? GatewayConfigError, .missingAPIKey)
        }
    }

    func testValidateRejectsWhitespaceAPIKey() {
        let config = GatewayConfig(gatewayURL: URL(string: "https://gateway.example")!, apiKey: "   \n")

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual(error as? GatewayConfigError, .missingAPIKey)
        }
    }

    func testValidateRejectsUnsupportedScheme() {
        let config = GatewayConfig(gatewayURL: URL(string: "ftp://gateway.example")!, apiKey: "ok-key")

        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual(error as? GatewayConfigError, .unsupportedScheme)
        }
    }

    func testValidateAcceptsHTTPAndHTTPS() throws {
        try GatewayConfig(gatewayURL: URL(string: "http://localhost:8080")!, apiKey: "key").validate()
        try GatewayConfig(gatewayURL: URL(string: "https://gateway.example")!, apiKey: "key").validate()
    }

    func testNormalizedTrimsURLPathSlashAndAPIKeyWhitespace() {
        let config = GatewayConfig(gatewayURL: URL(string: "https://gateway.example///")!, apiKey: "  key  ")

        XCTAssertEqual(config.normalized().gatewayURL.absoluteString, "https://gateway.example")
        XCTAssertEqual(config.normalized().apiKey, "key")
    }
}
