import Foundation

public struct GatewayConfig: Codable, Equatable, Sendable {
    public var gatewayURL: URL
    public var apiKey: String

    public init(gatewayURL: URL, apiKey: String) {
        self.gatewayURL = gatewayURL
        self.apiKey = apiKey
    }

    public func validate() throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw GatewayConfigError.missingAPIKey
        }

        guard let scheme = gatewayURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw GatewayConfigError.unsupportedScheme
        }

        guard gatewayURL.host?.isEmpty == false else {
            throw GatewayConfigError.missingHost
        }
    }

    public func normalized() -> GatewayConfig {
        var components = URLComponents(url: gatewayURL, resolvingAgainstBaseURL: false)
        let path = components?.path ?? ""
        components?.path = path == "/" ? "" : path.trimmingTrailingSlashes()

        return GatewayConfig(
            gatewayURL: components?.url ?? gatewayURL,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

public enum GatewayConfigError: Error, Equatable, Sendable {
    case missingAPIKey
    case unsupportedScheme
    case missingHost
}

private extension String {
    func trimmingTrailingSlashes() -> String {
        var copy = self
        while copy.last == "/" {
            copy.removeLast()
        }
        return copy
    }
}
