import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OpenKeyboardCore

/// Test-only direct transport retained for opt-in legacy Core gateway fixtures.
/// Production app and extension traffic is owned by Universal AI Connector.
final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        request.headers.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GatewayClientError.invalidResponse
        }

        return HTTPResponse(statusCode: httpResponse.statusCode, data: data)
    }
}
