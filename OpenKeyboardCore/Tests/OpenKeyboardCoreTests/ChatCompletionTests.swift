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
        let rendering = try XCTUnwrap(
            WritingPromptBuilder.rendering(for: .fixGrammar, text: "i has a apple")
        )
        XCTAssertEqual(messages.map { $0["role"] }, rendering.messages.map(\.role))
        XCTAssertEqual(messages.map { $0["content"] }, rendering.messages.map(\.content))
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
        XCTAssertEqual(result.items.map(\.replacement), [replacement])
        XCTAssertEqual(result.items.map(\.type), ["suggestion"])
        XCTAssertNil(result.summary)
        XCTAssertEqual(result.correctedText, replacement)
        let request = try XCTUnwrap(server.requests.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(json["operation"] as? String, "rewrite")
        XCTAssertEqual(json["input_text"] as? String, source)
        XCTAssertNil(json["response_format"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.last?["content"], source)
        let rendering = try XCTUnwrap(WritingPromptBuilder.rendering(for: .rewrite, text: source))
        XCTAssertEqual(rendering.operationID, "rewrite_core")
        XCTAssertEqual(rendering.wireOperationID, "rewrite")
        XCTAssertNotNil(rendering.plainTextValidationPolicy)
        XCTAssertEqual(messages.first?["content"], rendering.messages.first?.content)
    }

    func testBuiltInWritingActionsMapValidatedPlainTextToOperationSpecificResults() async throws {
        struct Scenario {
            let name: String
            let action: WritingAction
            let input: String
            let content: String
            let expectedOperation: String
            let expectedType: String
            let expectedSummary: String?
            let expectedCorrectedText: String?
        }

        let scenarios = [
            Scenario(
                name: "summary",
                action: .summarize,
                input: "OpenKeyboard keeps prompts in a shared contract and validates model output before showing it to the user.",
                content: "OpenKeyboard centrally defines prompts and validates model output.",
                expectedOperation: "summarize",
                expectedType: "summary",
                expectedSummary: "OpenKeyboard centrally defines prompts and validates model output.",
                expectedCorrectedText: nil
            ),
            Scenario(
                name: "rewrite",
                action: .rewrite,
                input: "This draft is difficult to read.",
                content: "This draft is easier to read.",
                expectedOperation: "rewrite",
                expectedType: "suggestion",
                expectedSummary: nil,
                expectedCorrectedText: "This draft is easier to read."
            ),
            Scenario(
                name: "translation",
                action: .translate(language: "Dutch"),
                input: "Good morning",
                content: "Goedemorgen",
                expectedOperation: "translate",
                expectedType: "translation",
                expectedSummary: nil,
                expectedCorrectedText: "Goedemorgen"
            ),
            Scenario(
                name: "continuation",
                action: .continueWriting,
                input: "The team approved the proposal",
                content: " and scheduled implementation for Monday.",
                expectedOperation: "continue_writing",
                expectedType: "suggestion",
                expectedSummary: nil,
                expectedCorrectedText: " and scheduled implementation for Monday."
            ),
        ]

        for scenario in scenarios {
            let server = DummyGatewayServer(.chatRawContent(scenario.content))
            let client = GatewayClient(config: validConfig, httpClient: server)

            let result = try await client.performWritingActionResult(scenario.action, text: scenario.input, model: "test-model")

            XCTAssertEqual(result.operation, scenario.expectedOperation, scenario.name)
            XCTAssertEqual(result.items.map(\.type), [scenario.expectedType], scenario.name)
            XCTAssertEqual(result.items.map(\.text), [scenario.content], scenario.name)
            XCTAssertEqual(result.summary, scenario.expectedSummary, scenario.name)
            XCTAssertEqual(result.correctedText, scenario.expectedCorrectedText, scenario.name)
            XCTAssertEqual(result.displayText, scenario.content, scenario.name)

            let request = try XCTUnwrap(server.requests.first, scenario.name)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any],
                scenario.name
            )
            XCTAssertNil(json["response_format"], scenario.name)
        }
    }

    func testDeprecatedWritingEnvelopeIsRejectedAsPlainTextForEveryBuiltInMode() async {
        let payloads = [
            #"{"operation":"rewrite","results":[{"id":"rewrite-1","type":"suggestion","text":"Clearer text.","replacement":"Clearer text."}],"corrected_text":"Clearer text."}"#,
            #"{"operation":"rewrite","results":["#
        ]
        let scenarios: [(WritingAction, String)] = [
            (.fixGrammar, "this need work"),
            (.rewrite, "This is difficult to read."),
            (.summarize, "This source contains enough detail to summarize into a shorter response."),
            (.translate(language: "Dutch"), "Good morning"),
            (.continueWriting, "The team approved the proposal")
        ]

        for payload in payloads {
            for (action, source) in scenarios {
                let client = GatewayClient(
                    config: validConfig,
                    httpClient: DummyGatewayServer(.chatRawContent(payload))
                )

                await XCTAssertThrowsErrorAsync(
                    try await client.performWritingActionResult(action, text: source, model: "test-model")
                ) { error in
                    XCTAssertEqual(error as? GatewayClientError, .invalidResponse, action.operationName)
                }
            }
        }
    }

    func testPlainTextGrammarResponseWorks() async throws {
        let client = GatewayClient(config: validConfig, httpClient: DummyGatewayServer(.chatPlainText("I have an apple.")))

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
