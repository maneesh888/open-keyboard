import Foundation

public protocol KeyValueStoring: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
}

public final class GatewayConfigStore: @unchecked Sendable {
    private enum Keys {
        static let gatewayURL = "openKeyboard.gatewayURL"
        static let apiKey = "openKeyboard.apiKey"
    }

    private let storage: KeyValueStoring

    public init(storage: KeyValueStoring) {
        self.storage = storage
    }

    public func load() throws -> GatewayConfig {
        guard let gatewayURLString = storage.string(forKey: Keys.gatewayURL),
              let apiKey = storage.string(forKey: Keys.apiKey),
              let gatewayURL = URL(string: gatewayURLString) else {
            throw GatewayConfigStoreError.missingConfig
        }

        let config = GatewayConfig(gatewayURL: gatewayURL, apiKey: apiKey).normalized()
        try config.validate()
        return config
    }

    public func save(_ config: GatewayConfig) throws {
        let normalized = config.normalized()
        try normalized.validate()
        storage.set(normalized.gatewayURL.absoluteString, forKey: Keys.gatewayURL)
        storage.set(normalized.apiKey, forKey: Keys.apiKey)
    }
}

public enum GatewayConfigStoreError: Error, Equatable, Sendable {
    case missingConfig
}

public final class InMemoryKeyValueStore: KeyValueStoring, @unchecked Sendable {
    private var values: [String: String] = [:]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public func string(forKey key: String) -> String? {
        values[key]
    }

    public func set(_ value: String, forKey key: String) {
        values[key] = value
    }
}

extension UserDefaults: KeyValueStoring {
    public func set(_ value: String, forKey key: String) {
        set(value as NSString, forKey: key)
    }
}
