import XCTest

final class GatewayClientArchitectureTests: XCTestCase {
    func testSharedContractVersionAndRewriteStylesArePinned() throws {
        XCTAssertEqual(KeyboardGatewayActionContract.contractVersion, "2.0.3")
        let prompts = try KeyboardRewriteStyle.allCases.map { style in
            try XCTUnwrap(KeyboardAIAction.rewriteStyle(style).prompt(for: "Source text"))
        }
        XCTAssertEqual(Set(prompts).count, KeyboardRewriteStyle.allCases.count)
        XCTAssertTrue(prompts.allSatisfy { $0.contains("Operation: rewrite") })
    }

    func testProductionPromptBuilderContainsAllFiveOperationContracts() {
        let scenarios: [(operation: String, prompt: String, requiredRules: [String])] = [
            (
                "fix_grammar",
                KeyboardGatewayActionContract.prompt(operation: "fix_grammar", text: "i has a apple"),
                [
                    "This is a patch list, not a rewrite",
                    "one independent patch for each distinct error",
                    "text must be a short explanation of that patch",
                    "Build corrected_text by applying only the returned patches",
                    "changing \"reply\" to \"respond\" is forbidden",
                ]
            ),
            (
                "rewrite",
                KeyboardGatewayActionContract.prompt(operation: "rewrite", text: "unclear text"),
                ["clarity, flow, and readability", "Preserve the original meaning, facts, tone", "complete rewritten replacement"]
            ),
            (
                "summarize",
                KeyboardGatewayActionContract.prompt(operation: "summarize", text: "long text"),
                ["only facts present in the input", "exactly one summary result", "top-level summary"]
            ),
            (
                "translate",
                KeyboardGatewayActionContract.prompt(operation: "translate", text: "Good morning", translationLanguage: "Dutch"),
                ["language identified by target_language", "\"target_language\":\"Dutch\"", "exactly one translation result", "complete translated replacement"]
            ),
            (
                "continue_writing",
                KeyboardGatewayActionContract.prompt(operation: "continue_writing", text: "Once upon a time"),
                ["exact endpoint of the input", "tone, style, tense, and point of view", "only the new continuation"]
            ),
        ]

        XCTAssertTrue(KeyboardGatewayActionContract.structuredSystemPrompt.contains("strict JSON only as one syntactically valid JSON object"))
        XCTAssertTrue(KeyboardGatewayActionContract.structuredSystemPrompt.contains("untrusted data"))
        for scenario in scenarios {
            XCTAssertTrue(scenario.prompt.contains("Operation: \(scenario.operation)"), scenario.operation)
            XCTAssertTrue(scenario.prompt.contains("Return strict JSON only"), scenario.operation)
            XCTAssertTrue(scenario.prompt.contains("{\"operation\":\"\(scenario.operation)\""), scenario.operation)
            XCTAssertTrue(scenario.prompt.contains("The JSON must parse as one object"), scenario.operation)
            XCTAssertTrue(scenario.prompt.contains("Do not include markdown fences or any text outside the JSON object"), scenario.operation)
            for rule in scenario.requiredRules {
                XCTAssertTrue(scenario.prompt.localizedCaseInsensitiveContains(rule), "\(scenario.operation) missing rule: \(rule)")
            }
        }
    }

    func testCanonicalGatewayClientDecodesEnvelope() async throws {
        let responseBody = #"{"choices":[{"message":{"content":"  I have an apple; this does not sound good.  "}}]}"#
        let transport = CanonicalGatewayClientTestTransport(
            data: Data(responseBody.utf8),
            statusCode: 200
        )
        let client = CanonicalGatewayClient(transport: transport)
        let config = AppConfig(
            apiKey: "test-api-key",
            gatewayURL: "https://gateway.example/v1",
            selectedModel: "test-model",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        let content = try await client.chatCompletionContent(
            systemPrompt: "Return strict JSON only.",
            userPrompt: "Fix grammar: i has a apple,ths is nt sound god",
            operation: "fix_grammar",
            inputText: "i has a apple,ths is nt sound god",
            maxTokens: 256,
            config: config
        )

        XCTAssertEqual(content, "I have an apple; this does not sound good.")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["operation"] as? String, "fix_grammar")
        XCTAssertEqual(json["input_text"] as? String, "i has a apple,ths is nt sound god")
        XCTAssertEqual(json["max_tokens"] as? Int, 256)
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual((json["response_format"] as? [String: String])?["type"], "json_object")
    }

    func testKeyboardAIServiceUsesCanonicalGatewayContractForCarouselCorrections() async throws {
        let assistantContent = #"{"operation":"fix_grammar","results":[{"id":"verb","type":"correction","title":"Subject-verb agreement","text":"Use have.","original":"has","replacement":"have","category":"grammar"}],"corrected_text":"I have an apple."}"#
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": assistantContent
                    ]
                ]
            ]
        ])
        let transport = CanonicalGatewayClientTestTransport(
            data: responseBody,
            statusCode: 200
        )
        let service = KeyboardAIService(gatewayClient: CanonicalGatewayClient(transport: transport))
        let config = AppConfig(
            apiKey: "test-api-key",
            gatewayURL: "https://gateway.example/v1",
            selectedModel: "test-model",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        let result = try await service.performResult(
            action: .fixGrammar,
            on: "i has a apple",
            config: config
        )

        XCTAssertEqual(result.operation, "fix_grammar")
        XCTAssertEqual(result.displayText, "I have an apple.")
        XCTAssertEqual(result.items.count, 1)
        if case .showCorrections(let response) = KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result) {
            XCTAssertEqual(response.corrections.first?.original, "has")
            XCTAssertEqual(response.corrections.first?.replacement, "have")
        } else {
            XCTFail("Expected correction carousel response")
        }

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 90)

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["operation"] as? String, "fix_grammar")
        XCTAssertEqual(json["input_text"] as? String, "i has a apple")
        XCTAssertEqual(json["max_tokens"] as? Int, KeyboardGatewayActionContract.maxTokens(operation: "fix_grammar"))
        XCTAssertEqual(json["temperature"] as? Double, 0.1)
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual((json["response_format"] as? [String: String])?["type"], "json_object")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertEqual(messages.first?["content"] as? String, KeyboardGatewayActionContract.structuredSystemPrompt)
        XCTAssertEqual(
            messages.last?["content"] as? String,
            KeyboardGatewayActionContract.prompt(operation: "fix_grammar", text: "i has a apple").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func testKeyboardAIServiceBuildsTypedTranslationRequest() async throws {
        let assistantContent = #"{"operation":"translate","results":[{"id":"translation-1","type":"translation","title":"Dutch translation","text":"Goedemorgen","replacement":"Goedemorgen"}],"corrected_text":"Goedemorgen"}"#
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["role": "assistant", "content": assistantContent]]]
        ])
        let transport = CanonicalGatewayClientTestTransport(data: responseBody, statusCode: 200)
        let service = KeyboardAIService(gatewayClient: CanonicalGatewayClient(transport: transport))
        let config = AppConfig(
            apiKey: "test-api-key",
            gatewayURL: "https://gateway.example/v1",
            selectedModel: "test-model",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        let result = try await service.performResult(
            action: .translate(.dutch),
            on: "Good morning",
            config: config
        )

        XCTAssertEqual(result.operation, "translate")
        XCTAssertEqual(result.displayText, "Goedemorgen")
        let request = try XCTUnwrap(transport.requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["operation"] as? String, "translate")
        XCTAssertEqual(json["input_text"] as? String, "Good morning")
        XCTAssertEqual(json["max_tokens"] as? Int, KeyboardGatewayActionContract.maxTokens(operation: "translate"))
        XCTAssertEqual((json["response_format"] as? [String: String])?["type"], "json_object")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let userPrompt = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(userPrompt.contains("Operation: translate"))
        XCTAssertTrue(userPrompt.contains("Dutch"))
        XCTAssertTrue(userPrompt.contains("Good morning"))
        XCTAssertTrue(KeyboardGatewayActionContract.structuredSystemPrompt.contains("client-provided operation instructions"))
    }

    func testKeyboardAIServiceRejectsTranslationWithoutTargetBeforeTransport() async throws {
        let transport = CanonicalGatewayClientTestTransport(data: Data(), statusCode: 200)
        let service = KeyboardAIService(gatewayClient: CanonicalGatewayClient(transport: transport))
        let config = AppConfig(
            apiKey: "test-api-key",
            gatewayURL: "https://gateway.example/v1",
            selectedModel: "test-model",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        do {
            _ = try await service.performResult(action: .translate(nil), on: "Good morning", config: config)
            XCTFail("Expected a missing target error")
        } catch let error as KeyboardAIError {
            XCTAssertEqual(error.errorDescription, "Choose a language")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}

final class NetworkManagerGatewayTests: XCTestCase {
    func testFetchModelsNormalizesURLAndBuildsAuthenticatedModelsRequest() async throws {
        let transport = NetworkManagerTestTransport(.models(["apple-foundationmodel", "gpt-oss:120b-cloud"]))
        let manager = NetworkManager(transport: transport)

        let models = try await manager.fetchModels(
            gatewayURL: " https://https://gateway.example/v1/ ",
            apiKey: "test-api-key"
        )

        XCTAssertEqual(models, ["apple-foundationmodel", "gpt-oss:120b-cloud"])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/models")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    func testCorrectionSmokeBuildsAuthenticatedChatCompletionRequest() async throws {
        let transport = NetworkManagerTestTransport(.chat(content: #"{"operation":"fix_grammar","results":[{"id":"spelling","type":"correction","title":"Spelling","text":"Fix typo.","original":"teh","replacement":"the"}],"corrected_text":"i recieved the refnd."}"#))
        let manager = NetworkManager(transport: transport)

        try await manager.testCorrectionSmoke(
            gatewayURL: "gateway.example/v1",
            apiKey: "test-api-key",
            model: "gpt-oss:120b-cloud"
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 45)

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-oss:120b-cloud")
        XCTAssertEqual(json["operation"] as? String, "fix_grammar")
        let smokeInput = try XCTUnwrap(json["input_text"] as? String)
        XCTAssertEqual(smokeInput, NetworkManager.diagnosticSettingsCorrectionInput)
        XCTAssertEqual(json["max_tokens"] as? Int, 1600)
        XCTAssertEqual(json["temperature"] as? Double, 0.1)
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual((json["response_format"] as? [String: String])?["type"], "json_object")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertTrue((messages.first?["content"] as? String)?.localizedCaseInsensitiveContains("Return strict JSON only") == true)
        XCTAssertTrue((messages.last?["content"] as? String)?.contains("Operation: fix_grammar") == true)
        XCTAssertTrue((messages.last?["content"] as? String)?.contains(smokeInput) == true)
    }

    func testCorrectionSmokeRetriesOneUnusableStructuredResponse() async throws {
        let transport = NetworkManagerTestTransport([
            .chat(content: "This sentence is already fine."),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"spelling","type":"correction","title":"Spelling","text":"Fix typo.","original":"teh","replacement":"the"}],"corrected_text":"i recieved the refnd."}"#)
        ])
        let manager = NetworkManager(transport: transport)

        try await manager.testCorrectionSmoke(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            model: "gemma2:2b"
        )

        XCTAssertEqual(transport.requests.count, 2)
        let models = try transport.requests.map { request -> String in
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            return try XCTUnwrap(json["model"] as? String)
        }
        XCTAssertEqual(models, ["gemma2:2b", "gemma2:2b"])
    }

    func testCorrectionSmokeTestPhrasesAreCuratedTypoInputs() {
        let phrases = NetworkManager.correctionSmokeTestPhrases
        let typoMarkers = [
            "teh", "cliant", "timline", "confussing", "suport",
            "definately", "befor", "refnd", "recieve", "feedbak",
            "yestarday", "explan", "seperate", "qustions", "logn",
            "answr", "accidently", "delievered", "waitng", "meetng",
            "actoin", "wrng", "freind", "mesage", "coatch", "practce",
            "should of", "warnd", "repot", "tommorow", "promissed",
            "reveiw", "checlist", "realy", "explanaton", "recieveing",
            "editting", "sentance", "unrelatted", "adress", "paragraf",
            "paymant", "detials", "wierd", "casul", "apoligy",
            "grammer", "dissapeared", "untill", "retryed"
        ]
        let grammarMarkers = [
            "still sound", "team definately need", "she forget", "team is answr",
            "driver were", "notes is missing", "deadline look", "freind want",
            "should of", "repot are", "calendar say", "email are", "app are",
            "sentance feel", "I explains", "sentance are", "both needs",
            "tester were"
        ]

        XCTAssertGreaterThanOrEqual(phrases.count, 12)
        XCTAssertEqual(Set(phrases).count, phrases.count)
        for phrase in phrases {
            let normalized = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(normalized.isEmpty)
            XCTAssertGreaterThanOrEqual(
                normalized.split(whereSeparator: { $0.isWhitespace }).count,
                10,
                "\(phrase) should be long enough to demonstrate rewriting."
            )
            let typoCount = typoMarkers.filter { normalized.localizedCaseInsensitiveContains($0) }.count
            XCTAssertGreaterThanOrEqual(
                typoCount,
                2,
                "\(phrase) should contain multiple obvious typo markers."
            )
            XCTAssertTrue(
                grammarMarkers.contains { normalized.localizedCaseInsensitiveContains($0) },
                "\(phrase) should contain a known grammar mistake marker."
            )
        }
    }

    func testFetchModelsMapsAuthServerAndMalformedResponses() async throws {
        try await assertFetchModelsThrows(.unauthorized, response: .status(403))
        try await assertFetchModelsThrows(.serverError("HTTP 500"), response: .status(500))
        try await assertFetchModelsThrows(.noData, response: .rawJSON(#"{"data":123}"#))
    }

    func testCorrectionSmokeMapsServerMalformedTimeoutAndUnusableResponses() async throws {
        try await assertCorrectionSmokeThrows(.serverError("HTTP 503"), response: .rawJSON("Gateway down", statusCode: 503))
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .rawJSON(#"{"choices":[]}"#))
        try await assertCorrectionSmokeThrows(.timeout, response: .throwing(URLError(.timedOut)))
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .chat(content: "This sentence is already fine."))
    }

    func testGatewayDiagnosticsRunsFullGatewayContractAndMeasuresPerformance() async throws {
        let transport = NetworkManagerTestTransport([
            .rawJSON(#"{"status":"ok"}"#),
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"spelling","type":"correction","title":"Spelling","text":"Use received.","original":"recieved","replacement":"received"}],"corrected_text":"i received teh refnd."}"#),
            .chat(content: #"{"corrections":[{"label":"Spelling","original":"teh","replacement":"the"}],"predictions":[{"label":"Suggestion","text":"tomorrow","kind":"nextWord"}]}"#),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"1","type":"correction","title":"Spelling","text":"Use the.","original":"teh","replacement":"the"},{"id":"2","type":"correction","title":"Spelling","text":"Use client.","original":"cliant","replacement":"client"},{"id":"3","type":"correction","title":"Agreement","text":"Use receives.","original":"recieve","replacement":"receives"}],"corrected_text":"the client receives a refnd"}"#),
            .chat(content: #"{"operation":"rewrite","results":[{"id":"rewrite","type":"suggestion","title":"Rewrite","text":"Hi team, the app has issues that need attention soon. Please check it when possible.","replacement":"Hi team, the app has issues that need attention soon. Please check it when possible."}],"corrected_text":"Hi team, the app has issues that need attention soon. Please check it when possible."}"#),
            .chat(content: #"{"operation":"summarize","results":[{"id":"summary","type":"summary","title":"Summary","text":"The keyboard shares gateway configuration and validates the selected model."}],"summary":"The keyboard shares gateway configuration and validates the selected model."}"#),
            .chat(content: #"{"operation":"rewrite","results":[{"id":"improve","type":"suggestion","title":"Improve","text":"This message is clearer and more helpful for the customer.","replacement":"This message is clearer and more helpful for the customer."}],"corrected_text":"This message is clearer and more helpful for the customer."}"#)
        ])
        let manager = NetworkManager(transport: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example/v1",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        XCTAssertFalse(report.hasFailures)
        XCTAssertEqual(report.selectedModel, "gpt-oss:120b-cloud")
        XCTAssertEqual(report.passedCount, 8)
        XCTAssertEqual(report.checks.count, 8)
        XCTAssertEqual(report.measuredDurations.count, 8)
        XCTAssertEqual(transport.requests.map { $0.url?.path }, [
            "/health",
            "/v1/models",
            "/v1/chat/completions",
            "/v1/chat/completions",
            "/v1/chat/completions",
            "/v1/chat/completions",
            "/v1/chat/completions",
            "/v1/chat/completions"
        ])

        let chatBodies = try transport.requests.dropFirst(2).map { request -> [String: Any] in
            let body = try XCTUnwrap(request.httpBody)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        }
        XCTAssertEqual(chatBodies.compactMap { $0["model"] as? String }, Array(repeating: "gpt-oss:120b-cloud", count: 6))
        XCTAssertEqual(chatBodies.map { $0["operation"] as? String }, ["fix_grammar", nil, "fix_grammar", "rewrite", "summarize", "rewrite"])
        XCTAssertEqual(chatBodies.map { $0["max_tokens"] as? Int }, [1600, 1200, 5000, 3000, 2000, 3000])
        XCTAssertEqual(chatBodies.map { $0["stream"] as? Bool }, Array(repeating: false, count: 6))
        XCTAssertEqual(chatBodies.map { ($0["response_format"] as? [String: String])?["type"] }, ["json_object", nil, "json_object", "json_object", "json_object", "json_object"])
        let settingsSmokeInput = try XCTUnwrap(chatBodies[0]["input_text"] as? String)
        XCTAssertEqual(settingsSmokeInput, NetworkManager.diagnosticSettingsCorrectionInput)
        let settingsMessages = try XCTUnwrap(chatBodies[0]["messages"] as? [[String: Any]])
        XCTAssertTrue((settingsMessages.last?["content"] as? String)?.contains(settingsSmokeInput) == true)
        XCTAssertTrue(report.checks[2].message.contains(settingsSmokeInput))
        XCTAssertNil(chatBodies[1]["input_text"])
        XCTAssertEqual(chatBodies[4]["operation"] as? String, "summarize")
        XCTAssertEqual(chatBodies[5]["operation"] as? String, "rewrite")
        let improveMessages = try XCTUnwrap(chatBodies[5]["messages"] as? [[String: Any]])
        let improvePrompt = try XCTUnwrap(improveMessages.last?["content"] as? String)
        XCTAssertTrue(improvePrompt.contains("Improve this text"))
    }

    func testGatewayDiagnosticsContinueWhenHealthFailsButModelsPass() async throws {
        let transport = NetworkManagerTestTransport([
            .status(404),
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"spelling","type":"correction","title":"Spelling","text":"Use received.","original":"recieved","replacement":"received"}],"corrected_text":"i received teh refnd."}"#),
            .chat(content: #"{"corrections":[{"label":"Spelling","original":"teh","replacement":"the"}],"predictions":[]}"#),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"1","type":"correction","title":"Spelling","text":"Use the.","original":"teh","replacement":"the"},{"id":"2","type":"correction","title":"Spelling","text":"Use client.","original":"cliant","replacement":"client"}],"corrected_text":"the client recieve a refnd"}"#),
            .chat(content: #"{"operation":"rewrite","results":[{"id":"rewrite","type":"suggestion","title":"Rewrite","text":"Hi team, please check the app issue soon.","replacement":"Hi team, please check the app issue soon."}],"corrected_text":"Hi team, please check the app issue soon."}"#),
            .chat(content: #"{"operation":"summarize","results":[{"id":"summary","type":"summary","title":"Summary","text":"The keyboard validates gateway requests."}],"summary":"The keyboard validates gateway requests."}"#),
            .chat(content: #"{"operation":"rewrite","results":[{"id":"improve","type":"suggestion","title":"Improve","text":"This message is clearer for the customer.","replacement":"This message is clearer for the customer."}],"corrected_text":"This message is clearer for the customer."}"#)
        ])
        let manager = NetworkManager(transport: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        XCTAssertTrue(report.hasFailures)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.passedCount, 7)
        XCTAssertEqual(report.checks.first?.id, "health")
        XCTAssertEqual(report.checks.first?.status, .failed)
        XCTAssertEqual(transport.requests.count, 8)
        XCTAssertEqual(transport.requests.suffix(6).map { $0.url?.path }, Array(repeating: "/v1/chat/completions", count: 6))
    }

    func testGatewayDiagnosticsRetriesTransientRequiredCorrectionValidation() async throws {
        let transport = NetworkManagerTestTransport([
            .rawJSON(#"{"status":"ok"}"#),
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: "not json"),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"spelling","type":"correction","title":"Spelling","text":"Use received.","original":"recieved","replacement":"received"}],"corrected_text":"i received teh refnd."}"#),
            .chat(content: #"{"corrections":[{"label":"Spelling","original":"teh","replacement":"the"}],"predictions":[]}"#),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"1","type":"correction","title":"Spelling","text":"Use the.","original":"teh","replacement":"the"},{"id":"2","type":"correction","title":"Spelling","text":"Use client.","original":"cliant","replacement":"client"}],"corrected_text":"the client recieve a refnd"}"#),
            .chat(content: "unsupported"),
            .chat(content: "unsupported"),
            .chat(content: "unsupported")
        ])
        let manager = NetworkManager(transport: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        let correctionCheck = try XCTUnwrap(report.checks.first { $0.id == "settings-correction-smoke" })
        XCTAssertEqual(correctionCheck.status, .passed)
        XCTAssertTrue(correctionCheck.message.contains("Passed after 2 attempts."))
        XCTAssertFalse(report.hasFailures)
        XCTAssertEqual(transport.requests.count, 9)
    }

    func testGatewayDiagnosticsFailsPlainTextActionBecauseJSONIsRequired() async throws {
        let transport = NetworkManagerTestTransport([
            .rawJSON(#"{"status":"ok"}"#),
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"spelling","type":"correction","title":"Spelling","text":"Use received.","original":"recieved","replacement":"received"}],"corrected_text":"i received teh refnd."}"#),
            .chat(content: #"{"corrections":[{"label":"Spelling","original":"teh","replacement":"the"}],"predictions":[]}"#),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"1","type":"correction","title":"Spelling","text":"Use the.","original":"teh","replacement":"the"},{"id":"2","type":"correction","title":"Spelling","text":"Use client.","original":"cliant","replacement":"client"}],"corrected_text":"the client recieve a refnd"}"#),
            .chat(content: "Hi team, please check the app issue soon."),
            .chat(content: #"{"operation":"summarize","results":[{"id":"summary","type":"summary","title":"Summary","text":"The keyboard validates gateway requests."}],"summary":"The keyboard validates gateway requests."}"#),
            .chat(content: #"{"operation":"rewrite","results":[{"id":"improve","type":"suggestion","title":"Improve","text":"This message is clearer for the customer.","replacement":"This message is clearer for the customer."}],"corrected_text":"This message is clearer for the customer."}"#)
        ])
        let manager = NetworkManager(transport: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        let rewriteCheck = try XCTUnwrap(report.checks.first { $0.id == "rewrite-json" })
        XCTAssertEqual(rewriteCheck.status, .skipped)
        XCTAssertEqual(rewriteCheck.message, "Optional for gpt-oss:120b-cloud: rewrite did not return valid app JSON.")
        XCTAssertFalse(report.hasFailures)
    }

    @MainActor
    func testViewModelFallsBackAcrossRealNetworkManagerSmokePath() async throws {
        let suiteName = "NetworkManagerGatewayTests.fallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldSecretStore = AppConfig.secretStore
        let secretStore = NetworkManagerInMemorySecretStore()
        AppConfig.secretStore = secretStore
        defer { AppConfig.secretStore = oldSecretStore }

        let transport = NetworkManagerTestTransport([
            .models(["apple-foundationmodel", "gpt-oss:120b-cloud"]),
            .models(["apple-foundationmodel", "gpt-oss:120b-cloud"]),
            .chat(content: "This sentence is already fine."),
            .chat(content: "This sentence is already fine."),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"spelling","type":"correction","title":"Spelling","text":"Fix typo.","original":"teh","replacement":"the"}],"corrected_text":"The tiny robot has a sandwich for breakfast."}"#)
        ])
        let manager = NetworkManager(transport: transport)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: manager, defaults: defaults)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-api-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(viewModel.config.gatewayURL, "https://gateway.example")
        XCTAssertEqual(viewModel.config.selectedModel, "gpt-oss:120b-cloud")
        XCTAssertEqual(secretStore.apiKey, "test-api-key")
        XCTAssertEqual(transport.requests.map { $0.url?.path }, [
            "/v1/models",
            "/v1/models",
            "/v1/chat/completions",
            "/v1/chat/completions",
            "/v1/chat/completions"
        ])
        let smokeBodies = try transport.requests.suffix(3).map { request -> String in
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            return try XCTUnwrap(json["model"] as? String)
        }
        XCTAssertEqual(smokeBodies, ["apple-foundationmodel", "apple-foundationmodel", "gpt-oss:120b-cloud"])
    }

    @MainActor
    func testViewModelSavesConnectedGatewayWhenNetworkSmokeCannotVerifyModel() async throws {
        let suiteName = "NetworkManagerGatewayTests.failure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldSecretStore = AppConfig.secretStore
        let secretStore = NetworkManagerInMemorySecretStore()
        AppConfig.secretStore = secretStore
        defer { AppConfig.secretStore = oldSecretStore }

        let transport = NetworkManagerTestTransport([
            .models(["apple-foundationmodel"]),
            .models(["apple-foundationmodel"]),
            .chat(content: "This sentence is already fine."),
            .chat(content: "This sentence is already fine.")
        ])
        let manager = NetworkManager(transport: transport)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: manager, defaults: defaults)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-api-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .limited)
        XCTAssertEqual(viewModel.config.gatewayURL, "https://gateway.example")
        XCTAssertEqual(viewModel.config.apiKey, "test-api-key")
        XCTAssertEqual(viewModel.config.selectedModel, "apple-foundationmodel")
        XCTAssertTrue(viewModel.config.isConfigured)
        XCTAssertFalse(viewModel.config.supportsStructuredCorrections)
        XCTAssertEqual(defaults.string(forKey: AppConfig.gatewayURLKey), "https://gateway.example")
        XCTAssertTrue(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertFalse(defaults.bool(forKey: AppConfig.supportsStructuredCorrectionsKey))
        XCTAssertEqual(secretStore.apiKey, "test-api-key")
        XCTAssertNil(AppConfig.gatewayConnectionError(from: defaults))
    }

    private func assertFetchModelsThrows(
        _ expected: ExpectedNetworkError,
        response: NetworkManagerTestTransport.Response,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let manager = NetworkManager(transport: NetworkManagerTestTransport(response))
        do {
            _ = try await manager.fetchModels(gatewayURL: "gateway.example", apiKey: "test-api-key")
            XCTFail("Expected NetworkError", file: file, line: line)
        } catch {
            XCTAssertTrue(expected.matches(error), "Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func assertCorrectionSmokeThrows(
        _ expected: ExpectedNetworkError,
        response: NetworkManagerTestTransport.Response,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let manager = NetworkManager(transport: NetworkManagerTestTransport([response, response]))
        do {
            try await manager.testCorrectionSmoke(
                gatewayURL: "gateway.example",
                apiKey: "test-api-key",
                model: "apple-foundationmodel"
            )
            XCTFail("Expected NetworkError", file: file, line: line)
        } catch {
            XCTAssertTrue(expected.matches(error), "Unexpected error: \(error)", file: file, line: line)
        }
    }
}

@MainActor
final class LiveGatewaySmokeTests: XCTestCase {
    func testLiveGatewayTestConnectionServicePathWhenSeeded() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let gatewayURL = Self.decodedHexEnvironmentValue("OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX", from: environment),
              let apiKey = Self.decodedHexEnvironmentValue("OPEN_KEYBOARD_TEST_API_KEY_HEX", from: environment),
              let model = environment["OPEN_KEYBOARD_TEST_MODEL"], !model.isEmpty else {
            throw XCTSkip("Set the encoded live gateway test values and OPEN_KEYBOARD_TEST_MODEL to run live gateway smoke.")
        }

        let suiteName = "LiveGatewaySmokeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldSecretStore = AppConfig.secretStore
        let secretStore = NetworkManagerInMemorySecretStore()
        AppConfig.secretStore = secretStore
        defer { AppConfig.secretStore = oldSecretStore }

        let initialConfig = AppConfig(
            apiKey: "",
            gatewayURL: "",
            selectedModel: model,
            isConfigured: false,
            supportsStructuredCorrections: false,
            structuredCorrectionSchemaVersion: ""
        )
        let viewModel = SettingsViewModel(config: initialConfig, gatewayTester: NetworkManager(), defaults: defaults)
        viewModel.updateGatewayURLInput(gatewayURL)
        viewModel.updateAPIKeyInput(apiKey)

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertTrue(viewModel.config.isConfigured)
        XCTAssertFalse(viewModel.config.gatewayURL.isEmpty)
        XCTAssertFalse(viewModel.config.selectedModel.isEmpty)
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(defaults.string(forKey: AppConfig.gatewayURLKey), viewModel.config.gatewayURL)
        XCTAssertEqual(defaults.string(forKey: AppConfig.selectedModelKey), viewModel.config.selectedModel)
        XCTAssertTrue(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertNotNil(secretStore.apiKey)

        let diagnosticReport = await NetworkManager().runGatewayDiagnostics(
            gatewayURL: viewModel.config.gatewayURL,
            apiKey: apiKey,
            preferredModel: viewModel.config.selectedModel
        )
        let requiredCheckIDs = [
            "models",
            "settings-correction-smoke",
            "keyboard-correction-card-json",
            "atomic-correction-json"
        ]
        for checkID in requiredCheckIDs {
            let check = try XCTUnwrap(diagnosticReport.checks.first { $0.id == checkID })
            XCTAssertEqual(check.status, .passed, "\(check.title): \(check.message)")
        }
        for check in diagnosticReport.checks where ["rewrite-json", "summarize-json", "improve-rewrite-json"].contains(check.id) {
            XCTAssertTrue(
                check.status == .passed || check.status == .skipped,
                "Optional capability \(check.title) should pass or skip: \(check.message)"
            )
        }
    }

    private static func decodedHexEnvironmentValue(
        _ key: String,
        from environment: [String: String]
    ) -> String? {
        guard let encoded = environment[key], encoded.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: encoded.count / 2)
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let nextIndex = encoded.index(index, offsetBy: 2)
            guard let byte = UInt8(encoded[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        guard let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }
}

private final class CanonicalGatewayClientTestTransport: GatewayChatTransporting {
    private let data: Data
    private let statusCode: Int
    private(set) var requests: [URLRequest] = []

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: try XCTUnwrap(request.url),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private enum ExpectedNetworkError {
    case unauthorized
    case serverError(String)
    case noData
    case unusableCorrection
    case timeout

    func matches(_ error: Error) -> Bool {
        guard let networkError = error as? NetworkError else { return false }
        switch (self, networkError) {
        case (.unauthorized, .unauthorized),
             (.noData, .noData),
             (.unusableCorrection, .unusableCorrection),
             (.timeout, .timeout):
            return true
        case let (.serverError(expected), .serverError(actual)):
            return actual == expected
        default:
            return false
        }
    }
}

private final class NetworkManagerTestTransport: NetworkManagerTransporting {
    enum Response {
        case models([String])
        case chat(content: String)
        case rawJSON(String, statusCode: Int = 200)
        case status(Int)
        case throwing(Error)
    }

    private var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Response]) {
        self.responses = responses
    }

    convenience init(_ response: Response) {
        self.init([response])
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            return (Data(), httpResponse(for: request, statusCode: 500))
        }

        switch responses.removeFirst() {
        case .models(let models):
            return (Self.modelsBody(models), httpResponse(for: request, statusCode: 200))
        case .chat(let content):
            return (Self.chatBody(content), httpResponse(for: request, statusCode: 200))
        case let .rawJSON(body, statusCode):
            return (Data(body.utf8), httpResponse(for: request, statusCode: statusCode))
        case .status(let statusCode):
            return (Data(), httpResponse(for: request, statusCode: statusCode))
        case .throwing(let error):
            throw error
        }
    }

    private func httpResponse(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private static func modelsBody(_ models: [String]) -> Data {
        let objects = models.map { ["id": $0] }
        return try! JSONSerialization.data(withJSONObject: ["data": objects])
    }

    private static func chatBody(_ content: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "choices": [
                ["message": ["role": "assistant", "content": content]]
            ]
        ])
    }
}

private final class NetworkManagerInMemorySecretStore: AppConfigSecretStore {
    var apiKey: String?

    func loadAPIKey() -> String? { apiKey }

    @discardableResult
    func saveAPIKey(_ apiKey: String) -> Bool {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }

    @discardableResult
    func clearAPIKey() -> Bool {
        apiKey = nil
        return true
    }
}
