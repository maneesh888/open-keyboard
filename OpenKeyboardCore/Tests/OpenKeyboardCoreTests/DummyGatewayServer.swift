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
        case chatStructuredCorrection(
            operation: String = "fix_grammar",
            correctedText: String,
            items: [WritingItem] = [],
            summary: String? = nil
        )
        case chatStructuredItemsAlias(
            operation: String = "fix_grammar",
            correctedText: String? = nil,
            items: [WritingItem],
            summary: String? = nil
        )
        case chatPlainText(String)
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
            case let .chatStructuredCorrection(operation, correctedText, items, summary):
                return .chat(content: Self.structuredBody(operation: operation, correctedText: correctedText, itemsKey: "results", items: items, summary: summary))
            case let .chatStructuredItemsAlias(operation, correctedText, items, summary):
                return .chat(content: Self.structuredBody(operation: operation, correctedText: correctedText, itemsKey: "items", items: items, summary: summary))
            case .chatPlainText(let content):
                return .chat(content: content)
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

        private static func structuredBody(
            operation: String,
            correctedText: String?,
            itemsKey: String,
            items: [WritingItem],
            summary: String?
        ) -> String {
            var fields = [#""operation":"\#(jsonEscaped(operation))""#]
            if !items.isEmpty {
                fields.append(#""\#(itemsKey)":[\#(items.map(\.json).joined(separator: ","))]"#)
            } else {
                fields.append(#""\#(itemsKey)":[]"#)
            }
            if let summary {
                fields.append(#""summary":"\#(jsonEscaped(summary))""#)
            }
            if let correctedText {
                fields.append(#""corrected_text":"\#(jsonEscaped(correctedText))""#)
            }
            return "{\(fields.joined(separator: ","))}"
        }
    }

    struct WritingItem: Sendable {
        var id: String
        var type: String
        var title: String
        var text: String
        var original: String?
        var replacement: String?
        var range: WritingActionTextRange?
        var confidence: Double?
        var explanation: String?

        init(
            id: String = "item-1",
            type: String = "correction",
            title: String = "Grammar correction",
            text: String,
            original: String? = nil,
            replacement: String? = nil,
            range: WritingActionTextRange? = nil,
            confidence: Double? = nil,
            explanation: String? = nil
        ) {
            self.id = id
            self.type = type
            self.title = title
            self.text = text
            self.original = original
            self.replacement = replacement
            self.range = range
            self.confidence = confidence
            self.explanation = explanation
        }

        var json: String {
            var fields = [
                #""id":"\#(Self.escape(id))""#,
                #""type":"\#(Self.escape(type))""#,
                #""title":"\#(Self.escape(title))""#,
                #""text":"\#(Self.escape(text))""#
            ]
            if let original { fields.append(#""original":"\#(Self.escape(original))""#) }
            if let replacement { fields.append(#""replacement":"\#(Self.escape(replacement))""#) }
            if let range { fields.append(#""range":{"start":\#(range.start),"end":\#(range.end)}"#) }
            if let confidence { fields.append(#""confidence":\#(confidence)"#) }
            if let explanation { fields.append(#""explanation":"\#(Self.escape(explanation))""#) }
            return "{\(fields.joined(separator: ","))}"
        }

        private static func escape(_ value: String) -> String { DummyGatewayServer.jsonEscaped(value) }
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
