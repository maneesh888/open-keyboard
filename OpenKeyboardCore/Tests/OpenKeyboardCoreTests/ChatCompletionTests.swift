import XCTest
@testable import OpenKeyboardCore

final class ChatCompletionTests: XCTestCase {
    func testPerformWritingActionBuildsAuthorizedChatCompletionRequest() async throws {
        let server = DummyGatewayServer(.chatPlainText("Corrected text."))
        let client = GatewayClient(config: validConfig, httpClient: server)

        let output = try await client.performWritingAction(.fixGrammar, text: "i has a apple", model: "test-model")

        XCTAssertEqual(output, "Corrected text.")
        let request = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://gateway.example/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer test-key")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertNil(json["operation"])
        XCTAssertNil(json["input_text"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertTrue(messages.first?["content"]?.contains("results") == true)
        XCTAssertEqual(messages.last?["role"], "user")
        XCTAssertTrue(messages.last?["content"]?.contains("i has a apple") == true)
    }

    func testPerformWritingActionResultParsesMultipleStructuredItems() async throws {
        let server = DummyGatewayServer(.chatStructuredCorrection(
            correctedText: "i has an apple, this is not sound good",
            items: [
                .init(id: "grammar-1", title: "Article", text: "Use an before apple", original: "a apple", replacement: "an apple", range: WritingActionTextRange(start: 6, end: 13), confidence: 0.94, explanation: "Apple starts with a vowel sound."),
                .init(id: "spelling-1", title: "Spelling", text: "Fix typo", original: "ths", replacement: "this", confidence: 0.9)
            ],
            summary: "Found two issues."
        ))
        let client = GatewayClient(config: validConfig, httpClient: server)

        let result = try await client.performWritingActionResult(.fixGrammar, text: "i has a apple,ths is nt sound god", model: "test-model")

        XCTAssertEqual(result.operation, "fix_grammar")
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].type, "correction")
        XCTAssertEqual(result.items[0].replacement, "an apple")
        XCTAssertEqual(result.items[0].range, WritingActionTextRange(start: 6, end: 13))
        XCTAssertEqual(result.items[1].original, "ths")
        XCTAssertEqual(result.correctedText, "i has an apple, this is not sound good")
    }

    func testMockGatewayComplexSpellFixResponseParsesThroughClient() async throws {
        let server = DummyGatewayServer(.chatComplexSpellFix)
        let client = GatewayClient(config: validConfig, httpClient: server)

        let result = try await client.performWritingActionResult(.fixGrammar, text: DummyGatewayServer.complexSpellFixOriginalText, model: "test-model")

        XCTAssertEqual(server.requestedURLs, ["https://gateway.example/v1/chat/completions"])
        XCTAssertEqual(result.operation, "fix_grammar")
        XCTAssertTrue(result.isStructuredResponse)
        XCTAssertEqual(result.items.count, 12)
        XCTAssertEqual(result.items.filter { $0.type == "correction" }.map(\.replacement), DummyGatewayServer.complexSpellFixReplacements)
        XCTAssertEqual(result.items.last?.type, "warning")
        XCTAssertEqual(result.items[9].range, WritingActionTextRange(start: 84, end: 91))
        XCTAssertEqual(result.correctedText, DummyGatewayServer.complexSpellFixCorrectedText)
        XCTAssertEqual(result.displayText, DummyGatewayServer.complexSpellFixCorrectedText)
    }


    func testStructuredOperationResultScenarios() async throws {
        struct Scenario {
            let name: String
            let action: WritingAction
            let input: String
            let content: String
            let expectedDisplayText: String
            let expectedItemTypes: [String]
        }

        let scenarios = [
            Scenario(
                name: "multi-error grammar",
                action: .fixGrammar,
                input: "i has a apple,ths is nt sound god",
                content: #"{"operation":"fix_grammar","results":[{"id":"article","type":"correction","title":"Article","text":"Use an before apple","original":"a apple","replacement":"an apple"},{"id":"spelling","type":"correction","title":"Spelling","text":"Fix ths","original":"ths","replacement":"this"},{"id":"grammar","type":"correction","title":"Grammar","text":"Use does not sound good","original":"is nt sound god","replacement":"does not sound good"}],"summary":"Found three issues.","corrected_text":"i has an apple,this does not sound good"}"#,
                expectedDisplayText: "i has an apple,this does not sound good",
                expectedItemTypes: ["correction", "correction", "correction"]
            ),
            Scenario(
                name: "clean text all good",
                action: .fixGrammar,
                input: "The app works well today.",
                content: #"{"operation":"fix_grammar","results":[],"summary":"No issues found."}"#,
                expectedDisplayText: "No issues found.",
                expectedItemTypes: []
            ),
            Scenario(
                name: "summary operation",
                action: .summarize,
                input: "The keyboard supports private AI. It can fix grammar and summarize text.",
                content: #"{"operation":"summarize","results":[{"id":"summary-1","type":"summary","title":"Summary","text":"The keyboard offers private AI writing help."}],"summary":"The keyboard offers private AI writing help."}"#,
                expectedDisplayText: "The keyboard offers private AI writing help.",
                expectedItemTypes: ["summary"]
            ),
            Scenario(
                name: "rewrite operation",
                action: .rewrite,
                input: "this sounds bad and confusing",
                content: #"{"operation":"rewrite","results":[{"id":"rewrite-1","type":"suggestion","title":"Clearer rewrite","text":"This could be clearer and easier to read.","replacement":"This could be clearer and easier to read."}],"summary":"Rewritten for clarity."}"#,
                expectedDisplayText: "This could be clearer and easier to read.",
                expectedItemTypes: ["suggestion"]
            ),
            Scenario(
                name: "mixed result types",
                action: .fixGrammar,
                input: "i has a apple, maybe send it",
                content: #"{"operation":"fix_grammar","results":[{"id":"c1","type":"correction","title":"Grammar","text":"Use have","original":"has","replacement":"have","extra":"ignored"},{"id":"s1","type":"suggestion","title":"Tone","text":"Consider adding context."},{"id":"w1","type":"warning","title":"Ambiguous pronoun","text":"It is unclear what it refers to."},{"id":"e1","type":"explanation","title":"Why","text":"The verb should match the subject."}],"corrected_text":"i have a apple, maybe send it"}"#,
                expectedDisplayText: "i have a apple, maybe send it",
                expectedItemTypes: ["correction", "suggestion", "warning", "explanation"]
            ),
        ]

        for scenario in scenarios {
            let server = DummyGatewayServer(.chatRawContent(scenario.content))
            let client = GatewayClient(config: validConfig, httpClient: server)

            let result = try await client.performWritingActionResult(scenario.action, text: scenario.input, model: "test-model")

            XCTAssertEqual(result.displayText, scenario.expectedDisplayText, scenario.name)
            XCTAssertEqual(result.items.map(\.type), scenario.expectedItemTypes, scenario.name)
        }
    }

    func testStructuredOperationResultParsesGatewayCanonicalGrammarContract() async throws {
        let content = #"{"operation":"fix_grammar","results":[{"id":"detected-capitalization-i","type":"correction","title":"Capitalization","text":"Capitalize the pronoun \"I\".","original":"i","replacement":"I","range":{"start":0,"end":1},"confidence":0.98},{"id":"detected-article-an-apple","type":"correction","title":"Article","text":"Use \"an\" before \"apple\".","original":"a apple","replacement":"an apple","range":{"start":6,"end":13},"confidence":0.96},{"id":"detected-missing-not","type":"correction","title":"Missing word","text":"Expand \"nt\" to \"not\".","original":"nt","replacement":"not","confidence":0.82},{"id":"detected-word-choice-good","type":"correction","title":"Word choice","text":"Use \"good\" instead of \"god\".","original":"god","replacement":"good","confidence":0.9}],"corrected_text":"I have an apple; this does not sound good."}"#
        let http = DummyGatewayServer(.chatRawContent(content))
        let client = GatewayClient(config: validConfig, httpClient: http)

        let result = try await client.performWritingActionResult(.fixGrammar, text: "i has a apple,ths is nt sound god", model: "test-model")

        XCTAssertEqual(result.operation, "fix_grammar")
        XCTAssertEqual(result.correctedText, "I have an apple; this does not sound good.")
        XCTAssertEqual(result.displayText, "I have an apple; this does not sound good.")
        XCTAssertTrue(result.items.contains { $0.original == "a apple" && $0.replacement == "an apple" })
        XCTAssertTrue(result.items.contains { $0.original == "nt" && $0.replacement == "not" })
        XCTAssertTrue(result.items.contains { $0.original == "god" && $0.replacement == "good" })
    }


    func testStructuredOperationResultParsesItemsAliasAndMarkdownFence() async throws {
        let content = """
        ```json
        {"operation":"fix_grammar","items":[{"id":"item-1","type":"correction","title":"Spelling","text":"Fix typo","original":"teh","replacement":"the"}],"corrected_text":"the quick brown fox"}
        ```
        """
        let http = DummyGatewayServer(.chatRawContent(content))
        let client = GatewayClient(config: validConfig, httpClient: http)

        let result = try await client.performWritingActionResult(.fixGrammar, text: "teh quick brown fox", model: "test-model")

        XCTAssertEqual(result.operation, "fix_grammar")
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].replacement, "the")
        XCTAssertEqual(result.displayText, "the quick brown fox")
    }

    func testStructuredOperationResultRejectsInvalidEmptyStructuredResponse() async {
        let content = #"{"operation":"fix_grammar","results":[]}"#
        let http = DummyGatewayServer(.chatRawContent(content))
        let client = GatewayClient(config: validConfig, httpClient: http)

        await XCTAssertThrowsErrorAsync(try await client.performWritingActionResult(.fixGrammar, text: "i has a apple", model: "test-model")) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }
    }

    func testStructuredOperationResultIgnoresMalformedNestedJSONCards() async throws {
        let content = #"{"operation":"fix_grammar","results":[{"id":"bad","type":"correction","title":"Nested payload","text":"{\"corrected_text\":\"I have an apple.\"}"},{"id":"good","type":"correction","title":"Grammar","text":"Use have","original":"has","replacement":"have"}],"corrected_text":"I have an apple."}"#
        let http = DummyGatewayServer(.chatRawContent(content))
        let client = GatewayClient(config: validConfig, httpClient: http)

        let result = try await client.performWritingActionResult(.fixGrammar, text: "i has a apple", model: "test-model")

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.id, "good")
        XCTAssertEqual(result.items.first?.replacement, "have")
        XCTAssertEqual(result.correctedText, "I have an apple.")
    }


    func testParsesCanonicalStructuredResultWithCorrectedTextKeepsAllItems() async throws {
        let content = #"{"operation":"fix_grammar","results":[{"id":"c1","type":"correction","title":"Verb","text":"Use have","original":"has","replacement":"have"},{"id":"c2","type":"correction","title":"Article","text":"Use an","original":"a apple","replacement":"an apple"}],"summary":"Two issues.","corrected_text":"I have an apple."}"#
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

        let result = try await client.performWritingActionResult(.fixGrammar, text: "i has a apple", model: "test-model")

        XCTAssertEqual(result.operation, "fix_grammar")
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items.map(\.replacement), ["have", "an apple"])
        XCTAssertEqual(result.correctedText, "I have an apple.")
    }

    func testParsesCanonicalStructuredResultWithoutCorrectedTextKeepsAllItems() async throws {
        let content = #"{"operation":"fix_grammar","results":[{"id":"c1","type":"correction","title":"Verb","text":"Use have","original":"has","replacement":"have"},{"id":"c2","type":"correction","title":"Article","text":"Use an","original":"a apple","replacement":"an apple"}]}"#
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

        let result = try await client.performWritingActionResult(.fixGrammar, text: "i has a apple", model: "test-model")

        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items.map(\.original), ["has", "a apple"])
        XCTAssertNil(result.correctedText)
        XCTAssertEqual(result.displayText, "have", "Legacy display text may still choose the first replacement, but structured items must remain intact.")
    }

    func testParsesItemsAliasAsResults() async throws {
        let content = #"{"operation":"fix_grammar","items":[{"id":"c1","type":"correction","title":"Spelling","text":"Fix ths","original":"ths","replacement":"this"},{"id":"c2","type":"correction","title":"Missing word","text":"Expand nt","original":"nt","replacement":"not"}]}"#
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

        let result = try await client.performWritingActionResult(.fixGrammar, text: "ths is nt good", model: "test-model")

        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items.map(\.replacement), ["this", "not"])
    }

    func testUnknownResultTypesDoNotCrash() async throws {
        let content = #"{"operation":"fix_grammar","results":[{"id":"w1","type":"warning","title":"Warning","text":"Ambiguous text"},{"id":"s1","type":"summary","title":"Summary","text":"Short summary"},{"id":"e1","type":"explanation","title":"Why","text":"Explanation text"},{"id":"x1","type":"made_up","title":"Unknown","text":"Unknown item"}],"summary":"Handled safely."}"#
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

        let result = try await client.performWritingActionResult(.fixGrammar, text: "Some text", model: "test-model")

        XCTAssertEqual(result.items.map(\.type), ["warning", "summary", "explanation", "made_up"])
        XCTAssertEqual(result.summary, "Handled safely.")
    }

    func testLegacyPlainTextStillWorks() async throws {
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatPlainText("I have an apple.")))

        let output = try await client.performWritingAction(.fixGrammar, text: "i has a apple", model: "test-model")

        XCTAssertEqual(output, "I have an apple.")
    }

    func testPerformWritingActionKeepsLegacyCorrectedTextCompatible() async throws {
        let http = DummyGatewayServer(.chatPlainText("I have an apple."))
        let client = GatewayClient(config: validConfig, httpClient: http)

        let output = try await client.performWritingAction(.fixGrammar, text: "i has a apple", model: "test-model")

        XCTAssertEqual(output, "I have an apple.")
    }

    func testPerformWritingActionTrimsCompletionContent() async throws {
        let http = DummyGatewayServer(.chatPlainText("  Corrected text.\n"))
        let client = GatewayClient(config: validConfig, httpClient: http)

        let output = try await client.performWritingAction(.fixGrammar, text: "bad", model: "test-model")

        XCTAssertEqual(output, "Corrected text.")
    }

    func testPerformWritingActionEmptyChoicesMapsToInvalidResponse() async {
        let server = DummyGatewayServer(.chatEmptyChoices)
        let client = GatewayClient(config: validConfig, httpClient: server)

        await XCTAssertThrowsErrorAsync(try await client.performWritingAction(.summarize, text: "Hello", model: "test-model")) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }
    }


    func testStructuredOperationResultParsesCommonDisplayAliases() async throws {
        let scenarios: [(String, WritingAction, String)] = [
            (#"{"operation":"rewrite","rewritten_text":"This is clearer."}"#, .rewrite, "This is clearer."),
            (#"{"operation":"fix_grammar","correctedText":"I have an apple."}"#, .fixGrammar, "I have an apple."),
            (#"{"operation":"rewrite","result":{"id":"rewrite-1","type":"suggestion","text":"Clearer text.","replacement":"Clearer text."}}"#, .rewrite, "Clearer text."),
            (#"{"operation":"fix_grammar","improved_text":"I have an apple."}"#, .fixGrammar, "I have an apple."),
            (#"{"operation":"rewrite","replacement":"Replacement text."}"#, .rewrite, "Replacement text."),
            (#"{"operation":"rewrite","text":"Top-level text."}"#, .rewrite, "Top-level text."),
            (#"{"operation":"rewrite","output":"Output text."}"#, .rewrite, "Output text.")
        ]

        for (content, action, expectedDisplayText) in scenarios {
            let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

            let result = try await client.performWritingActionResult(action, text: "i has a apple", model: "test-model")

            XCTAssertEqual(result.displayText, expectedDisplayText)
            XCTAssertTrue(result.isStructuredResponse)
        }
    }

    func testStructuredJSONStringPayloadIsParsedInsteadOfReturnedAsRawText() async throws {
        let payload = #"{"operation":"fix_grammar","results":[{"id":"1","type":"correction","title":"Subject-verb agreement","text":"Use have.","original":"has","replacement":"have"}],"summary":"One issue found."}"#
        let encodedPayload = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(encodedPayload)))

        let result = try await client.performWritingActionResult(.fixGrammar, text: "i has a apple", model: "test-model")

        XCTAssertTrue(result.isStructuredResponse)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.replacement, "have")
        XCTAssertFalse(result.displayText.contains("\"operation\""), "Raw JSON string must not become display text")
    }

    func testMalformedJSONLikeWritingActionResponseIsInvalidNotLegacyReplacement() async {
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(#"{"operation":"fix_grammar","results":["#)))

        await XCTAssertThrowsErrorAsync(try await client.performWritingAction(.fixGrammar, text: "i has a apple", model: "test-model")) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }
    }

    func testPerformWritingActionDoesNotReplaceTextWithStructuredNoIssueSummary() async {
        let content = #"{"operation":"fix_grammar","results":[],"summary":"No issues found."}"#
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

        await XCTAssertThrowsErrorAsync(try await client.performWritingAction(.fixGrammar, text: "The app works well.", model: "test-model")) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }
    }

    func testPerformWritingActionDoesNotReplaceCleanTextWithSameCorrectedText() async throws {
        let content = #"{"operation":"fix_grammar","results":[],"corrected_text":"The app works well today."}"#
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

        let result = try await client.performWritingActionResult(.fixGrammar, text: "The app works well today.", model: "test-model")

        XCTAssertTrue(result.isStructuredGrammarNoChange)
        let actionClient = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))
        await XCTAssertThrowsErrorAsync(try await actionClient.performWritingAction(.fixGrammar, text: "The app works well today.", model: "test-model")) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }
    }

    private var validConfig: GatewayConfig {
        DummyGatewayServer.validConfig
    }
}
