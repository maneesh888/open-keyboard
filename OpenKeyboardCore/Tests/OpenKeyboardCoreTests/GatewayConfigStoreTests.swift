import XCTest
@testable import OpenKeyboardCore

final class GatewayConfigStoreTests: XCTestCase {
    func testLoadThrowsWhenConfigMissing() {
        let store = GatewayConfigStore(storage: InMemoryKeyValueStore())

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? GatewayConfigStoreError, .missingConfig)
        }
    }

    func testSaveAndLoadRoundTrip() throws {
        let storage = InMemoryKeyValueStore()
        let store = GatewayConfigStore(storage: storage)
        let config = GatewayConfig(gatewayURL: URL(string: "https://gateway.example")!, apiKey: "secret")

        try store.save(config)

        XCTAssertEqual(try store.load(), config)
    }

    func testSaveStoresNormalizedConfig() throws {
        let storage = InMemoryKeyValueStore()
        let store = GatewayConfigStore(storage: storage)
        let config = GatewayConfig(gatewayURL: URL(string: "https://gateway.example/")!, apiKey: " secret ")

        try store.save(config)

        XCTAssertEqual(try store.load().gatewayURL.absoluteString, "https://gateway.example")
        XCTAssertEqual(try store.load().apiKey, "secret")
    }
}
