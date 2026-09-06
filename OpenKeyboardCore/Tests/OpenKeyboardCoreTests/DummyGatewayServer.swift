import Foundation
@testable import OpenKeyboardCore

/// Test-only gateway fixture that exercises the real `GatewayClient` request,
/// status mapping, and response parsing path without calling a live server.
///
/// Keep gateway response bodies centralized here. Network-layer tests should
/// configure typed responses instead of copying ad-hoc JSON fixtures inline.
final class DummyGatewayServer: HTTPClient, @unchecked Sendable {
    enum RouteResponse: Sendable {
        case healthOK
        case healthMalformed
        case models([String])
        case malformedModels
        case chatPlainText(String)
        case chatTruncated(String)
        case chatRawContent(String)
        case chatEmptyChoices
        case malformedJSON
        case empty
        case status(Int)

        var httpResponse: HTTPResponse {
            switch self {
            case .healthOK:
                return .json(#"{"status":"ok"}"#)
            case .healthMalformed:
                return .json(#"{"status":123}"#)
            case .models(let models):
                return .json(Self.modelsBody(models))
            case .malformedModels:
                return .json(#"{"data":123}"#)
            case .chatPlainText(let content):
                return .chat(content: content)
            case .chatTruncated(let content):
                return .json(#"{"choices":[{"message":{"content":"\#(DummyGatewayServer.jsonEscaped(content))"},"finish_reason":"length"}]}"#)
            case .chatRawContent(let content):
                return .chat(content: content)
            case .chatEmptyChoices:
                return .json(#"{"choices":[]}"#)
            case .malformedJSON:
                return .json(#"{"not valid""#)
            case .empty:
                return HTTPResponse(statusCode: 200, data: Data())
            case .status(let statusCode):
                return HTTPResponse(statusCode: statusCode, data: Data())
            }
        }

        private static func modelsBody(_ models: [String]) -> String {
            let data = models.map { #"{"id":"\#(jsonEscaped($0))"}"# }.joined(separator: ",")
            return #"{"data":[\#(data)]}"#
        }

    }

    private var queuedResponses: [RouteResponse]
    private(set) var requests: [HTTPRequest] = []

    init(_ responses: [RouteResponse]) {
        self.queuedResponses = responses
    }

    convenience init(_ response: RouteResponse) {
        self.init([response])
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !queuedResponses.isEmpty else {
            return RouteResponse.status(500).httpResponse
        }
        return queuedResponses.removeFirst().httpResponse
    }

    var requestedURLs: [String] { requests.map(\.url.absoluteString) }
    var authorizationHeaders: [String?] { requests.map { $0.headers["Authorization"] } }

    static let validConfig = GatewayConfig(gatewayURL: URL(string: "https://gateway.example")!, apiKey: "test-key")

    static func chatBody(content: String) -> Data {
        HTTPResponse.chat(content: content).data
    }

    static func jsonEscaped(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        let encoded = String(data: data, encoding: .utf8)!
        return String(encoded.dropFirst().dropLast())
    }
}

private extension HTTPResponse {
    static func json(_ body: String, statusCode: Int = 200) -> HTTPResponse {
        HTTPResponse(statusCode: statusCode, data: body.data(using: .utf8)!)
    }

    static func chat(content: String) -> HTTPResponse {
        .json(#"{"choices":[{"message":{"content":"\#(DummyGatewayServer.jsonEscaped(content))"}}]}"#)
    }
}
