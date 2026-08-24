import XCTest
@testable import OpenKeyboardCore

final class ChatCompletionTests: XCTestCase {
    func testPerformWritingActionBuildsAuthorizedChatCompletionRequest() async throws {
        let server = DummyGatewayServer(.chatPlainText("I have an apple."))
        let client = GatewayClient(config: validConfig, httpClient: server)

        let output = try await client.performWritingAction(.fixGrammar, text: "i has a apple", model: "test-model")

        XCTAssertEqual(output, "I have an apple.")
        let request = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://gateway.example/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer test-key")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual(json["operation"] as? String, "fix_grammar")
        XCTAssertEqual(json["input_text"] as? String, "i has a apple")
        XCTAssertNil(json["response_format"])
        XCTAssertNil(json["temperature"])
        XCTAssertEqual(json["max_tokens"] as? Int, 12_000)
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertTrue(messages.first?["content"]?.contains("grammar correction engine") == true)
        XCTAssertEqual(messages.last?["role"], "user")
        XCTAssertEqual(messages.last?["content"], WritingPromptBuilder.prompt(for: .fixGrammar, text: "i has a apple"))
    }

    func testCustomWritingActionKeepsPlainTextContractWithoutResponseFormat() async throws {
        let server = DummyGatewayServer(.chatPlainText("Friendly text."))
        let client = GatewayClient(config: validConfig, httpClient: server)
        let action = WritingAction.custom(
            id: "friendly",
            title: "Make Friendly",
            promptTemplate: "Make this friendly:\n{{text}}"
        )

        let output = try await client.performWritingAction(action, text: "No.", model: "test-model")

        XCTAssertEqual(output, "Friendly text.")
        let request = try XCTUnwrap(server.requests.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertNil(json["response_format"])
        XCTAssertNil(json["temperature"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.last?["content"], "Make this friendly:\nNo.")
    }

    func testRewriteUsesOneValidatedPlainTextReplacementWithoutResponseFormat() async throws {
        let source = "This draft is awkward but contains fact 42."
        let replacement = "This draft reads clearly while retaining fact 42."
        let server = DummyGatewayServer(.chatPlainText(replacement))
        let client = GatewayClient(config: validConfig, httpClient: server)

        let result = try await client.performWritingActionResult(.rewrite, text: source, model: "test-model")

        XCTAssertEqual(result.displayText, replacement)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.replacement, replacement)
        XCTAssertFalse(result.isStructuredResponse)

        let request = try XCTUnwrap(server.requests.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(json["operation"] as? String, "rewrite")
        XCTAssertNil(json["response_format"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.last?["content"], source)
        XCTAssertTrue(messages.first?["content"]?.contains("one complete plain-text replacement") == true)
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

        let result = try await client.performWritingActionResult(.summarize, text: "i has a apple,ths is nt sound god", model: "test-model")

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

        let result = try await client.performWritingActionResult(.summarize, text: DummyGatewayServer.complexSpellFixOriginalText, model: "test-model")

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
                action: .summarize,
                input: "i has a apple,ths is nt sound god",
                content: #"{"operation":"fix_grammar","results":[{"id":"article","type":"correction","title":"Article","text":"Use an before apple","original":"a apple","replacement":"an apple"},{"id":"spelling","type":"correction","title":"Spelling","text":"Fix ths","original":"ths","replacement":"this"},{"id":"grammar","type":"correction","title":"Grammar","text":"Use does not sound good","original":"is nt sound god","replacement":"does not sound good"}],"summary":"Found three issues.","corrected_text":"i has an apple,this does not sound good"}"#,
                expectedDisplayText: "i has an apple,this does not sound good",
                expectedItemTypes: ["correction", "correction", "correction"]
            ),
            Scenario(
                name: "clean text all good",
                action: .summarize,
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
                action: .summarize,
                input: "this sounds bad and confusing",
                content: #"{"operation":"rewrite","results":[{"id":"rewrite-1","type":"suggestion","title":"Clearer rewrite","text":"This could be clearer and easier to read.","replacement":"This could be clearer and easier to read."}],"summary":"Rewritten for clarity."}"#,
                expectedDisplayText: "This could be clearer and easier to read.",
                expectedItemTypes: ["suggestion"]
            ),
            Scenario(
                name: "mixed result types",
                action: .summarize,
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

        let result = try await client.performWritingActionResult(.summarize, text: "i has a apple,ths is nt sound god", model: "test-model")

        XCTAssertEqual(result.operation, "fix_grammar")
        XCTAssertEqual(result.correctedText, "I have an apple; this does not sound good.")
        XCTAssertEqual(result.displayText, "I have an apple; this does not sound good.")
        XCTAssertTrue(result.items.contains { $0.original == "a apple" && $0.replacement == "an apple" })
        XCTAssertTrue(result.items.contains { $0.original == "nt" && $0.replacement == "not" })
        XCTAssertTrue(result.items.contains { $0.original == "god" && $0.replacement == "good" })
    }

    func testStructuredOperationResultToleratesNoncanonicalOptionalMetadata() async throws {
        let content = #"{"operation":"fix_grammar","results":[{"id":1,"type":"correction","title":"Spelling","text":"Fix typo","original":"teh","replacement":"the","range":{"start":"0","end":"3"},"confidence":"0.97"}],"summary":{"unexpected":true},"corrected_text":"the message"}"#
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

        let result = try await client.performWritingActionResult(.summarize, text: "teh message", model: "test-model")

        XCTAssertTrue(result.isStructuredResponse)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].id, "item-1")
        XCTAssertEqual(result.items[0].replacement, "the")
        XCTAssertEqual(result.items[0].range, WritingActionTextRange(start: 0, end: 3))
        XCTAssertEqual(result.items[0].confidence, 0.97)
        XCTAssertNil(result.summary)
        XCTAssertEqual(result.correctedText, "the message")
    }


    func testStructuredOperationResultParsesItemsAliasAndMarkdownFence() async throws {
        let content = """
        ```json
        {"operation":"fix_grammar","items":[{"id":"item-1","type":"correction","title":"Spelling","text":"Fix typo","original":"teh","replacement":"the"}],"corrected_text":"the quick brown fox"}
        ```
        """
        let http = DummyGatewayServer(.chatRawContent(content))
        let client = GatewayClient(config: validConfig, httpClient: http)

        let result = try await client.performWritingActionResult(.summarize, text: "teh quick brown fox", model: "test-model")

        XCTAssertEqual(result.operation, "fix_grammar")
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].replacement, "the")
        XCTAssertEqual(result.displayText, "the quick brown fox")
    }

    func testStructuredOperationResultRejectsInvalidEmptyStructuredResponse() async {
        let content = #"{"operation":"fix_grammar","results":[]}"#
        let http = DummyGatewayServer(.chatRawContent(content))
        let client = GatewayClient(config: validConfig, httpClient: http)

        await XCTAssertThrowsErrorAsync(try await client.performWritingActionResult(.summarize, text: "i has a apple", model: "test-model")) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }
    }

    func testStructuredOperationResultIgnoresMalformedNestedJSONCards() async throws {
        let content = #"{"operation":"rewrite","results":[{"id":"bad","type":"suggestion","title":"Nested payload","text":"{\"corrected_text\":\"I have an apple.\"}"},{"id":"good","type":"suggestion","title":"Rewrite","text":"Use have","original":"has","replacement":"have"}],"corrected_text":"I have an apple."}"#
        let http = DummyGatewayServer(.chatRawContent(content))
        let client = GatewayClient(config: validConfig, httpClient: http)

        let result = try await client.performWritingActionResult(.summarize, text: "i has a apple", model: "test-model")

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.id, "good")
        XCTAssertEqual(result.items.first?.replacement, "have")
        XCTAssertEqual(result.correctedText, "I have an apple.")
    }


    func testParsesCanonicalStructuredResultWithCorrectedTextKeepsAllItems() async throws {
        let content = #"{"operation":"fix_grammar","results":[{"id":"c1","type":"correction","title":"Verb","text":"Use have","original":"has","replacement":"have"},{"id":"c2","type":"correction","title":"Article","text":"Use an","original":"a apple","replacement":"an apple"}],"summary":"Two issues.","corrected_text":"I have an apple."}"#
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

        let result = try await client.performWritingActionResult(.summarize, text: "i has a apple", model: "test-model")

        XCTAssertEqual(result.operation, "fix_grammar")
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items.map(\.replacement), ["have", "an apple"])
        XCTAssertEqual(result.correctedText, "I have an apple.")
    }

    func testParsesCanonicalStructuredResultWithoutCorrectedTextKeepsAllItems() async throws {
        let content = #"{"operation":"fix_grammar","results":[{"id":"c1","type":"correction","title":"Verb","text":"Use have","original":"has","replacement":"have"},{"id":"c2","type":"correction","title":"Article","text":"Use an","original":"a apple","replacement":"an apple"}]}"#
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

        let result = try await client.performWritingActionResult(.summarize, text: "i has a apple", model: "test-model")

        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items.map(\.original), ["has", "a apple"])
        XCTAssertNil(result.correctedText)
        XCTAssertEqual(result.displayText, "have", "Legacy display text may still choose the first replacement, but structured items must remain intact.")
    }

    func testParsesItemsAliasAsResults() async throws {
        let content = #"{"operation":"fix_grammar","items":[{"id":"c1","type":"correction","title":"Spelling","text":"Fix ths","original":"ths","replacement":"this"},{"id":"c2","type":"correction","title":"Missing word","text":"Expand nt","original":"nt","replacement":"not"}]}"#
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

        let result = try await client.performWritingActionResult(.summarize, text: "ths is nt good", model: "test-model")

        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items.map(\.replacement), ["this", "not"])
    }

    func testUnknownResultTypesDoNotCrash() async throws {
        let content = #"{"operation":"fix_grammar","results":[{"id":"w1","type":"warning","title":"Warning","text":"Ambiguous text"},{"id":"s1","type":"summary","title":"Summary","text":"Short summary"},{"id":"e1","type":"explanation","title":"Why","text":"Explanation text"},{"id":"x1","type":"made_up","title":"Unknown","text":"Unknown item"}],"summary":"Handled safely."}"#
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

        let result = try await client.performWritingActionResult(.summarize, text: "Some text", model: "test-model")

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

    func testPerformWritingActionRestoresOriginalBoundaryWhitespace() async throws {
        let source = "  i has a apple  "
        let http = DummyGatewayServer(.chatPlainText("\nI have an apple. \t"))
        let client = GatewayClient(config: validConfig, httpClient: http)

        let output = try await client.performWritingAction(.fixGrammar, text: source, model: "test-model")

        XCTAssertEqual(output, "  I have an apple.  ")
    }

    func testPlainGrammarPreservesExactBoundaryWhitespace() async throws {
        let source = "  i has a apple.  "
        let corrected = "  I have an apple.  "
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatPlainText(corrected)))

        let result = try await client.performWritingActionResult(.fixGrammar, text: source, model: "test-model")
        let actionClient = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatPlainText(corrected)))
        let output = try await actionClient.performWritingAction(.fixGrammar, text: source, model: "test-model")

        XCTAssertEqual(result.correctedText, corrected)
        XCTAssertEqual(result.displayText, corrected)
        XCTAssertEqual(output, corrected)
    }

    func testPlainGrammarRejectsSuspiciousRewriteAndTruncation() async {
        let suspicious = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("This sentence is entirely unrelated."))
        )
        await XCTAssertThrowsErrorAsync(
            try await suspicious.performWritingAction(.fixGrammar, text: "i recieved teh refnd.", model: "test-model")
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let truncated = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatTruncated("I received the"))
        )
        await XCTAssertThrowsErrorAsync(
            try await truncated.performWritingAction(.fixGrammar, text: "i recieved teh refnd.", model: "test-model")
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let commentary = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("i recieved teh refnd. Hope this helps."))
        )
        await XCTAssertThrowsErrorAsync(
            try await commentary.performWritingAction(.fixGrammar, text: "i recieved teh refnd.", model: "test-model")
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let correctedWithOneWordCommentary = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("I received the refund. Sure."))
        )
        await XCTAssertThrowsErrorAsync(
            try await correctedWithOneWordCommentary.performWritingAction(
                .fixGrammar,
                text: "i recieved teh refnd.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let commentaryReplacingTail = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("This sentence needs correction. Sure."))
        )
        await XCTAssertThrowsErrorAsync(
            try await commentaryReplacingTail.performWritingAction(
                .fixGrammar,
                text: "This sentnce need correction today.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        for boundaryCommentary in [
            "This sentence needs correction: Sure.",
            "This sentence needs correction; sure.",
            "This sentence needs correction — sure."
        ] {
            let delimiterCommentary = GatewayClient(
                config: validConfig,
                httpClient: DummyGatewayServer(.chatPlainText(boundaryCommentary))
            )
            await XCTAssertThrowsErrorAsync(
                try await delimiterCommentary.performWritingAction(
                    .fixGrammar,
                    text: "This sentnce need correction today.",
                    model: "test-model"
                )
            ) { error in
                XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
            }
        }

        let existingBoundaryCommentary = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("This sentence needs correction. Sure thing."))
        )
        await XCTAssertThrowsErrorAsync(
            try await existingBoundaryCommentary.performWritingAction(
                .fixGrammar,
                text: "This sentnce need correction. Reply tomorrow.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let whitespaceBoundaryCommentary = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("This sentence needs correction Sure."))
        )
        await XCTAssertThrowsErrorAsync(
            try await whitespaceBoundaryCommentary.performWritingAction(
                .fixGrammar,
                text: "This sentnce need correction today.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let sourceTypoCorrectedToSuffixWord = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("I am sure."))
        )
        do {
            let corrected = try await sourceTypoCorrectedToSuffixWord.performWritingAction(
                .fixGrammar,
                text: "I am shure.",
                model: "test-model"
            )
            XCTAssertEqual(corrected, "I am sure.")
        } catch {
            XCTFail("A source-owned suffix typo should remain correctable: \(error)")
        }

        let whitespacePrefixCommentary = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("Sure thing we send updates."))
        )
        await XCTAssertThrowsErrorAsync(
            try await whitespacePrefixCommentary.performWritingAction(
                .fixGrammar,
                text: "Today we send updates.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let unrelatedTailReplacement = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("This sentence needs correction Certainly."))
        )
        await XCTAssertThrowsErrorAsync(
            try await unrelatedTailReplacement.performWritingAction(
                .fixGrammar,
                text: "This sentnce need correction today.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let nearSpellingTailReplacement = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("This sentence needs correction Totally."))
        )
        await XCTAssertThrowsErrorAsync(
            try await nearSpellingTailReplacement.performWritingAction(
                .fixGrammar,
                text: "This sentnce need correction today.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let pronounAndModalityRewrite = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("I can send updates."))
        )
        await XCTAssertThrowsErrorAsync(
            try await pronounAndModalityRewrite.performWritingAction(
                .fixGrammar,
                text: "You send updates.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let modalityRewrite = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("You may pay today."))
        )
        await XCTAssertThrowsErrorAsync(
            try await modalityRewrite.performWritingAction(
                .fixGrammar,
                text: "You must pay today.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        for (source, response) in [
            ("You must pay today.", "You just pay today."),
            ("We can pay today.", "He can pay today."),
            ("The black bag arrived.", "The block bag arrived."),
            ("The planes changed.", "The plans changed."),
            ("They stared today.", "They started today."),
            ("The trial starts today.", "The trail starts today."),
            ("You pay today.", "You have to pay today."),
            ("We send updates.", "We did send updates.")
        ] {
            let semanticRewrite = GatewayClient(
                config: validConfig,
                httpClient: DummyGatewayServer(.chatPlainText(response))
            )
            await XCTAssertThrowsErrorAsync(
                try await semanticRewrite.performWritingAction(
                    .fixGrammar,
                    text: source,
                    model: "test-model"
                )
            ) { error in
                XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
            }
        }

        let grammarOnlyBoundaryReplacement = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("They are."))
        )
        let correctedGrammar = try? await grammarOnlyBoundaryReplacement.performWritingAction(
            .fixGrammar,
            text: "They is.",
            model: "test-model"
        )
        XCTAssertEqual(correctedGrammar, "They are.")

        let insertedArticle = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("I sent an update."))
        )
        let correctedArticle = try? await insertedArticle.performWritingAction(
            .fixGrammar,
            text: "I sent update.",
            model: "test-model"
        )
        XCTAssertEqual(correctedArticle, "I sent an update.")

        let apostropheCorrection = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("I don't know."))
        )
        let correctedApostrophe = try? await apostropheCorrection.performWritingAction(
            .fixGrammar,
            text: "I dont know.",
            model: "test-model"
        )
        XCTAssertEqual(correctedApostrophe, "I don't know.")

        let contractionCorrection = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("She doesn't receive updates."))
        )
        let correctedContraction = try? await contractionCorrection.performWritingAction(
            .fixGrammar,
            text: "She dont receive updates.",
            model: "test-model"
        )
        XCTAssertEqual(correctedContraction, "She doesn't receive updates.")

        let ordinarySpellingCorrection = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("I wrote an apology, but the grammar needs work."))
        )
        let correctedSpelling = try? await ordinarySpellingCorrection.performWritingAction(
            .fixGrammar,
            text: "I wrote an apoligy, but the grammer needs work.",
            model: "test-model"
        )
        XCTAssertEqual(correctedSpelling, "I wrote an apology, but the grammar needs work.")

        for (source, response) in [
            ("It dose not work.", "It does not work."),
            ("I defiantly agree.", "I definitely agree."),
            ("He are ready.", "He is ready."),
            ("She have notes.", "She has notes.")
        ] {
            let contextualCorrection = GatewayClient(
                config: validConfig,
                httpClient: DummyGatewayServer(.chatPlainText(response))
            )
            let correctedContext = try? await contextualCorrection.performWritingAction(
                .fixGrammar,
                text: source,
                model: "test-model"
            )
            XCTAssertEqual(correctedContext, response)
        }

        let relocatedLineBreak = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("First sentence. Second\nline stays."))
        )
        await XCTAssertThrowsErrorAsync(
            try await relocatedLineBreak.performWritingAction(
                .fixGrammar,
                text: "First sentnce.\nSecond line stays.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let preservedLineBreak = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("First sentence.\nSecond line stays."))
        )
        let correctedMultiline = try? await preservedLineBreak.performWritingAction(
            .fixGrammar,
            text: "First sentnce.\nSecond line stays.",
            model: "test-model"
        )
        XCTAssertEqual(correctedMultiline, "First sentence.\nSecond line stays.")

        let removedEmoji = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("Hello world."))
        )
        await XCTAssertThrowsErrorAsync(
            try await removedEmoji.performWritingAction(
                .fixGrammar,
                text: "Hello 🙂 world.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let replacedEmoji = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("Hello 😈 world."))
        )
        await XCTAssertThrowsErrorAsync(
            try await replacedEmoji.performWritingAction(
                .fixGrammar,
                text: "Hello 🙂 world.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let movedEmoji = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("Hello world 🙂."))
        )
        await XCTAssertThrowsErrorAsync(
            try await movedEmoji.performWritingAction(
                .fixGrammar,
                text: "Hello 🙂 world.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let removedFormatting = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("Important update."))
        )
        await XCTAssertThrowsErrorAsync(
            try await removedFormatting.performWritingAction(
                .fixGrammar,
                text: "*Important* update.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let removedMarkdownLink = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("Important note update."))
        )
        await XCTAssertThrowsErrorAsync(
            try await removedMarkdownLink.performWritingAction(
                .fixGrammar,
                text: "[Important](note) update.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let movedMarkdownWhitespace = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("Please review* this *now."))
        )
        await XCTAssertThrowsErrorAsync(
            try await movedMarkdownWhitespace.performWritingAction(
                .fixGrammar,
                text: "Please review *this* now.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        for (source, response) in [
            ("Review *the note*.", "Review the *note*."),
            ("[the note]", #"["the","note"]"#),
            ("{the note}", #"{"the":"note"}"#),
            ("teh update.", #""the update.""#),
            ("teh update.", "'the update.'"),
            ("teh update.", "“the update.”"),
            ("teh update.", "«the update.»"),
            ("teh update.", "「the update.」"),
            ("teh update.", "the 'update'."),
            ("teh update.", "the “update”."),
            ("- Teh item.", "The item."),
            ("![Alt](image.png)", "[Alt](image.png)")
        ] {
            let structuralRewrite = GatewayClient(
                config: validConfig,
                httpClient: DummyGatewayServer(.chatPlainText(response))
            )
            await XCTAssertThrowsErrorAsync(
                try await structuralRewrite.performWritingAction(
                    .fixGrammar,
                    text: source,
                    model: "test-model"
                )
            ) { error in
                XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
            }
        }

        let preservedJSONStructure = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText(#"["the"]"#))
        )
        let correctedJSON = try? await preservedJSONStructure.performWritingAction(
            .fixGrammar,
            text: #"["teh"]"#,
            model: "test-model"
        )
        XCTAssertEqual(correctedJSON, #"["the"]"#)

        for (source, response) in [
            ("'teh update.'", "'the update.'"),
            ("“teh update.”", "“the update.”"),
            ("「teh update.」", "「the update.」"),
            ("She said 'teh update.'", "She said 'the update.'")
        ] {
            let preservedQuoteStructure = GatewayClient(
                config: validConfig,
                httpClient: DummyGatewayServer(.chatPlainText(response))
            )
            let correctedQuote = try? await preservedQuoteStructure.performWritingAction(
                .fixGrammar,
                text: source,
                model: "test-model"
            )
            XCTAssertEqual(correctedQuote, response)
        }

        let preservedMarkdownLink = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("[Important](note) update."))
        )
        let correctedMarkdownLink = try? await preservedMarkdownLink.performWritingAction(
            .fixGrammar,
            text: "[Important](note) udpate.",
            model: "test-model"
        )
        XCTAssertEqual(correctedMarkdownLink, "[Important](note) update.")

        let preservedMarkdownFence = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("```\nthe update\n```"))
        )
        let correctedMarkdownFence = try? await preservedMarkdownFence.performWritingAction(
            .fixGrammar,
            text: "```\nteh update\n```",
            model: "test-model"
        )
        XCTAssertEqual(correctedMarkdownFence, "```\nthe update\n```")

        let punctuationCorrection = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("Hello, world."))
        )
        let correctedPunctuation = try? await punctuationCorrection.performWritingAction(
            .fixGrammar,
            text: "Hello world",
            model: "test-model"
        )
        XCTAssertEqual(correctedPunctuation, "Hello, world.")

        let shortTailOmission = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("This is a detailed sentence."))
        )
        await XCTAssertThrowsErrorAsync(
            try await shortTailOmission.performWritingAction(
                .fixGrammar,
                text: "This is a detailed sentence about updates.",
                model: "test-model"
            )
        ) { error in
            XCTAssertEqual(error as? GatewayClientError, .invalidResponse)
        }

        let sourceOwnedPrefix = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("Here is the account update."))
        )
        let corrected = try? await sourceOwnedPrefix.performWritingAction(
            .fixGrammar,
            text: "Here is teh account update.",
            model: "test-model"
        )
        XCTAssertEqual(corrected, "Here is the account update.")

        let sourceTypoCorrectedToPrefix = GatewayClient(
            config: validConfig,
            httpClient: DummyGatewayServer(.chatPlainText("Here is the account update."))
        )
        let correctedPrefix = try? await sourceTypoCorrectedToPrefix.performWritingAction(
            .fixGrammar,
            text: "Hear is teh account update.",
            model: "test-model"
        )
        XCTAssertEqual(correctedPrefix, "Here is the account update.")

        for (source, response) in [
            ("I going.", "I am going."),
            ("I did went.", "I went."),
            ("He is works.", "He works."),
            ("I can to go.", "I can go."),
            ("The team walk.", "The team walks."),
            ("The timeline sound wrong.", "The timeline sounds wrong."),
            ("🙂 I going.", "🙂 I am going."),
            ("He said \"hello\" and sent update.", "He said \"hello\" and sent an update."),
            ("The notes is, however, clear.", "The notes are, however, clear.")
        ] {
            let generalGrammar = GatewayClient(
                config: validConfig,
                httpClient: DummyGatewayServer(.chatPlainText(response))
            )
            let generalCorrection = try? await generalGrammar.performWritingAction(
                .fixGrammar,
                text: source,
                model: "test-model"
            )
            XCTAssertEqual(generalCorrection, response)
        }
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
            (#"{"operation":"rewrite","rewritten_text":"This is clearer."}"#, .summarize, "This is clearer."),
            (#"{"operation":"rewrite","correctedText":"I have an apple."}"#, .summarize, "I have an apple."),
            (#"{"operation":"rewrite","result":{"id":"rewrite-1","type":"suggestion","text":"Clearer text.","replacement":"Clearer text."}}"#, .summarize, "Clearer text."),
            (#"{"operation":"rewrite","improved_text":"I have an apple."}"#, .summarize, "I have an apple."),
            (#"{"operation":"rewrite","replacement":"Replacement text."}"#, .summarize, "Replacement text."),
            (#"{"operation":"rewrite","text":"Top-level text."}"#, .summarize, "Top-level text."),
            (#"{"operation":"rewrite","output":"Output text."}"#, .summarize, "Output text.")
        ]

        for (content, action, expectedDisplayText) in scenarios {
            let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

            let result = try await client.performWritingActionResult(action, text: "i has a apple", model: "test-model")

            XCTAssertEqual(result.displayText, expectedDisplayText)
            XCTAssertTrue(result.isStructuredResponse)
        }
    }

    func testStructuredJSONStringPayloadIsParsedInsteadOfReturnedAsRawText() async throws {
        let payload = #"{"operation":"rewrite","results":[{"id":"1","type":"suggestion","title":"Rewrite","text":"Use clearer wording.","original":"bad","replacement":"clear"}],"summary":"One rewrite found."}"#
        let encodedPayload = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(encodedPayload)))

        let result = try await client.performWritingActionResult(.summarize, text: "i has a apple", model: "test-model")

        XCTAssertTrue(result.isStructuredResponse)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.replacement, "clear")
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
        let content = "The app works well today."
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))

        let result = try await client.performWritingActionResult(.fixGrammar, text: "The app works well today.", model: "test-model")

        XCTAssertTrue(result.isNoChangeResult)
        let actionClient = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatRawContent(content)))
        let output = try await actionClient.performWritingAction(.fixGrammar, text: "The app works well today.", model: "test-model")
        XCTAssertEqual(output, content)
    }

    private var validConfig: GatewayConfig {
        DummyGatewayServer.validConfig
    }
}
