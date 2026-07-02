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
        case chatComplexSpellFix
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
            case .chatComplexSpellFix:
                return .chat(content: Self.structuredBody(
                    operation: "fix_grammar",
                    correctedText: DummyGatewayServer.complexSpellFixCorrectedText,
                    itemsKey: "results",
                    items: DummyGatewayServer.complexSpellFixItems,
                    summary: "Eleven corrections found."
                ))
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
        var category: String?

        init(
            id: String = "item-1",
            type: String = "correction",
            title: String = "Grammar correction",
            text: String,
            original: String? = nil,
            replacement: String? = nil,
            range: WritingActionTextRange? = nil,
            confidence: Double? = nil,
            explanation: String? = nil,
            category: String? = nil
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
            self.category = category
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
            if let category { fields.append(#""category":"\#(Self.escape(category))""#) }
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
    static let complexSpellFixOriginalText = "i definately recieve teh adress tomorow, and seperate files wont upload because its recieve limit is to low."
    static let complexSpellFixCorrectedText = "I definitely receive the address tomorrow, and separate files won't upload because their receive limit is too low."
    static let complexSpellFixReplacements = [
        "I",
        "definitely",
        "receive",
        "the",
        "address",
        "tomorrow",
        "separate",
        "won't",
        "their",
        "receive",
        "too low"
    ]
    static let complexSpellFixItems: [WritingItem] = [
        .init(id: "cap-i", title: "Capitalization", text: "Capitalize the pronoun.", original: "i", replacement: "I", range: WritingActionTextRange(start: 0, end: 1), confidence: 0.99, explanation: "Capitalize the standalone pronoun I.", category: "capitalization"),
        .init(id: "spell-definitely", title: "Spelling", text: "Correct definitely.", original: "definately", replacement: "definitely", range: WritingActionTextRange(start: 2, end: 12), confidence: 0.99, explanation: "Correct the misspelling.", category: "spelling"),
        .init(id: "spell-receive-1", title: "Spelling", text: "Correct receive.", original: "recieve", replacement: "receive", range: WritingActionTextRange(start: 13, end: 20), confidence: 0.98, explanation: "Use receive after c.", category: "spelling"),
        .init(id: "spell-the", title: "Spelling", text: "Correct the.", original: "teh", replacement: "the", range: WritingActionTextRange(start: 21, end: 24), confidence: 0.97, category: "spelling"),
        .init(id: "spell-address", title: "Spelling", text: "Correct address.", original: "adress", replacement: "address", range: WritingActionTextRange(start: 25, end: 31), confidence: 0.98, category: "spelling"),
        .init(id: "spell-tomorrow", title: "Spelling", text: "Correct tomorrow.", original: "tomorow", replacement: "tomorrow", range: WritingActionTextRange(start: 32, end: 39), confidence: 0.97, category: "spelling"),
        .init(id: "spell-separate", title: "Spelling", text: "Correct separate.", original: "seperate", replacement: "separate", range: WritingActionTextRange(start: 45, end: 53), confidence: 0.95, category: "spelling"),
        .init(id: "contract-wont", title: "Contraction", text: "Add apostrophe.", original: "wont", replacement: "won't", range: WritingActionTextRange(start: 60, end: 64), confidence: 0.93, category: "grammar"),
        .init(id: "pronoun-its", title: "Pronoun agreement", text: "Use a plural possessive pronoun.", original: "its", replacement: "their", range: WritingActionTextRange(start: 80, end: 83), confidence: 0.88, explanation: "Files is plural.", category: "grammar"),
        .init(id: "spell-receive-2", title: "Spelling", text: "Correct the second receive.", original: "recieve", replacement: "receive", range: WritingActionTextRange(start: 84, end: 91), confidence: 0.98, category: "spelling"),
        .init(id: "too-low", title: "Word choice", text: "Use too for degree.", original: "to low", replacement: "too low", range: WritingActionTextRange(start: 101, end: 107), confidence: 0.94, category: "grammar"),
        .init(id: "warning-domain", type: "warning", title: "Ambiguity", text: "The phrase receive limit may be domain-specific.")
    ]

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
