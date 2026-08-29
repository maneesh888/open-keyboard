import XCTest

final class GatewayClientArchitectureTests: XCTestCase {
    func testLiveImproveHarnessUsesCanonicalImprovePlainTextPath() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let harnessURL = repositoryRoot
            .appendingPathComponent("OpenKeyboard")
            .appendingPathComponent("Views")
            .appendingPathComponent("LiveAITestHarnessView.swift")
        let source = try String(contentsOf: harnessURL, encoding: .utf8)

        XCTAssertTrue(source.contains(#"run(action: "improve")"#))
        XCTAssertFalse(source.contains(#"run(action: "rewrite")"#))
        XCTAssertTrue(source.contains(#"else if action == "improve""#))
        XCTAssertTrue(source.contains("KeyboardActionOperationResult.plainTextReplacement"))
        XCTAssertTrue(source.contains("contractOperationID: action"))
        XCTAssertTrue(source.contains("wireOperation: rendering.wireOperationID ?? action"))
    }

    func testSharedContractVersionAndRewriteStylesArePinned() throws {
        XCTAssertEqual(KeyboardGatewayActionContract.contractVersion, "4.0.1")
        let renderings = try KeyboardRewriteStyle.allCases.map { style in
            try XCTUnwrap(KeyboardAIAction.rewriteStyle(style).rendering(for: "Source text"))
        }
        XCTAssertEqual(
            Set(renderings.compactMap { $0.messages.first?.content }).count,
            KeyboardRewriteStyle.allCases.count
        )
        XCTAssertTrue(renderings.allSatisfy { $0.messages.last?.content == "Source text" })
        XCTAssertTrue(renderings.allSatisfy { $0.wireOperationID == "rewrite" })
        XCTAssertTrue(renderings.allSatisfy { $0.responseFormatType == nil })
    }

    func testProductionPromptBuilderUsesExactSharedContractRenderings() throws {
        let scenarios: [(operation: String, input: String, parameters: [String: String])] = [
            ("fix_grammar", "i has a apple", [:]),
            ("rewrite", "unclear text", [:]),
            ("improve", "rough draft", [:]),
            ("summarize", "long text", [:]),
            ("translate", "Good morning", ["target_language": "Dutch"]),
            ("continue_writing", "Once upon a time", [:]),
        ]

        XCTAssertEqual(
            KeyboardGatewayActionContract.structuredSystemPrompt,
            SemanticPromptContract.writingSystemInstruction
        )
        for scenario in scenarios {
            let translationLanguage = scenario.parameters["target_language"]
            let rendering = KeyboardGatewayActionContract.rendering(
                operation: scenario.operation,
                text: scenario.input,
                translationLanguage: translationLanguage
            )
            let canonical = try SemanticPromptContract.renderWriting(
                operationID: scenario.operation,
                input: scenario.input,
                parameters: scenario.parameters
            )

            XCTAssertEqual(rendering, canonical, scenario.operation)
            XCTAssertEqual(
                KeyboardGatewayActionContract.prompt(
                    operation: scenario.operation,
                    text: scenario.input,
                    translationLanguage: translationLanguage
                ),
                canonical.messages.last?.content,
                scenario.operation
            )
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
            systemPrompt: KeyboardGatewayActionContract.rendering(operation: "fix_grammar", text: "  i has a apple,ths is nt sound god  ").messages[0].content,
            userPrompt: "  i has a apple,ths is nt sound god  ",
            operation: "fix_grammar",
            inputText: "  i has a apple,ths is nt sound god  ",
            maxTokens: 256,
            config: config,
            temperature: nil,
            expectsStructuredResponse: false
        )

        XCTAssertEqual(content, "  I have an apple; this does not sound good.  ")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["operation"] as? String, "fix_grammar")
        XCTAssertEqual(json["input_text"] as? String, "  i has a apple,ths is nt sound god  ")
        XCTAssertEqual(json["max_tokens"] as? Int, 256)
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertNil(json["response_format"])
        XCTAssertNil(json["temperature"])
    }

    func testCanonicalGatewayClientMapsStructuredUnavailableModelErrors() async throws {
        let unavailableBodies = [
            #"{"error":{"message":"The model `missing-model` does not exist or is not available for this key.","type":"invalid_request_error","code":"model_not_found"}}"#,
            #"{"detail":"unknown model: missing-model"}"#
        ]
        for body in unavailableBodies {
            let client = CanonicalGatewayClient(transport: CanonicalGatewayClientTestTransport(
                data: Data(body.utf8),
                statusCode: 404
            ))
            do {
                _ = try await client.chatCompletionContent(
                    systemPrompt: "Correct grammar.",
                    userPrompt: "i has text",
                    operation: "fix_grammar",
                    inputText: "i has text",
                    maxTokens: 256,
                    config: configuredGateway,
                    temperature: nil,
                    expectsStructuredResponse: false
                )
                XCTFail("Expected unavailable-model response to retain its typed category")
            } catch let error as CanonicalGatewayClientError {
                XCTAssertEqual(error, .modelUnavailable)
            }
        }

        let genericClient = CanonicalGatewayClient(transport: CanonicalGatewayClientTestTransport(
            data: Data(#"{"error":{"message":"Route not found"}}"#.utf8),
            statusCode: 404
        ))
        do {
            _ = try await genericClient.chatCompletionContent(
                systemPrompt: "Correct grammar.",
                userPrompt: "i has text",
                operation: "fix_grammar",
                inputText: "i has text",
                maxTokens: 256,
                config: configuredGateway,
                temperature: nil,
                expectsStructuredResponse: false
            )
            XCTFail("Expected generic HTTP failure")
        } catch let error as CanonicalGatewayClientError {
            XCTAssertEqual(error, .serverStatus(404))
        }
    }

    func testKeyboardAIServiceUsesCanonicalGatewayContractForCarouselCorrections() async throws {
        let assistantContent = "I have an apple."
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
        XCTAssertTrue(result.items.isEmpty)
        if case .showCorrections(let response) = KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result, sourceText: "i has a apple") {
            XCTAssertEqual(response.correctedText, "I have an apple.")
            XCTAssertGreaterThanOrEqual(response.corrections.count, 3)
        } else {
            XCTFail("Expected correction carousel response")
        }

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-api-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, GatewayRequestTimeouts.keyboardAction)

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "test-model")
        XCTAssertEqual(json["operation"] as? String, "fix_grammar")
        XCTAssertEqual(json["input_text"] as? String, "i has a apple")
        XCTAssertEqual(json["max_tokens"] as? Int, KeyboardGatewayActionContract.maxTokens(operation: "fix_grammar"))
        XCTAssertNil(json["temperature"])
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertNil(json["response_format"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertEqual(messages.first?["content"] as? String, KeyboardGatewayActionContract.rendering(operation: "fix_grammar", text: "i has a apple").messages[0].content)
        XCTAssertEqual(
            messages.last?["content"] as? String,
            "i has a apple"
        )
    }

    func testKeyboardAIServiceSendsOneCanonicalPlainTextRequestForImproveRephraseAndStyle() async throws {
        let source = "Please send the project update tomorrow at 10."
        let scenarios: [(KeyboardAIAction, String, String)] = [
            (.improve, "improve", "Please send the polished project update tomorrow at 10."),
            (.rewrite, "rewrite", "Tomorrow at 10, please send the project update."),
            (.rewriteStyle(.professional), "rewrite_professional", "Please provide the project update tomorrow at 10.")
        ]
        var renderingsByOperation: [String: SemanticPromptRendering] = [:]

        for (action, contractOperation, replacement) in scenarios {
            let transport = SequencedCanonicalGatewayClientTestTransport(contents: [replacement])
            let service = KeyboardAIService(gatewayClient: CanonicalGatewayClient(transport: transport))

            let result = try await service.performResult(action: action, on: source, config: configuredGateway)

            XCTAssertEqual(transport.requests.count, 1, action.rawValue)
            XCTAssertEqual(result.items.count, 1, action.rawValue)
            XCTAssertEqual(result.displayText, replacement, action.rawValue)
            let request = try XCTUnwrap(transport.requests.first)
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["operation"] as? String, "rewrite", action.rawValue)
            XCTAssertEqual(json["input_text"] as? String, source, action.rawValue)
            XCTAssertNil(json["response_format"], action.rawValue)
            let rendering = KeyboardGatewayActionContract.rendering(operation: contractOperation, text: source)
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            XCTAssertEqual(messages.last?["content"], source, action.rawValue)
            XCTAssertEqual(messages.first?["content"], rendering.messages.first?.content, action.rawValue)
            XCTAssertEqual(rendering.operationID, contractOperation, action.rawValue)
            XCTAssertEqual(rendering.wireOperationID, "rewrite", action.rawValue)
            XCTAssertNotNil(rendering.plainTextValidationPolicy, action.rawValue)
            renderingsByOperation[contractOperation] = rendering
        }

        XCTAssertEqual(Set(renderingsByOperation.keys), ["improve", "rewrite", "rewrite_professional"])
        XCTAssertEqual(
            Set(renderingsByOperation.values.compactMap { $0.messages.first?.content }).count,
            renderingsByOperation.count
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
        let rendering = KeyboardGatewayActionContract.rendering(
            operation: "translate",
            text: "Good morning",
            translationLanguage: "Dutch"
        )
        XCTAssertEqual(messages.map { $0["role"] as? String }, rendering.messages.map(\.role))
        XCTAssertEqual(messages.map { $0["content"] as? String }, rendering.messages.map(\.content))
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

    func testTranslationValidatorAcceptsExpectedTargetScriptAndLanguage() {
        let validator = KeyboardTranslationOutputValidator()

        XCTAssertNil(validator.validationFailure(
            for: "صباح الخير، أتمنى أن تكون بخير وأن تستمتع بيوم رائع.",
            target: .arabic
        ))
        XCTAssertNil(validator.validationFailure(
            for: "Goedemorgen, ik hoop dat het goed met je gaat en dat je een fijne dag hebt.",
            target: .dutch
        ))
        XCTAssertNil(validator.validationFailure(
            for: "يمكنك استخدام OpenAI للمساعدة في كتابة هذه الرسالة بوضوح.",
            target: .arabic
        ))
        XCTAssertNil(validator.validationFailure(for: "Ja", target: .dutch))
    }

    func testTranslationValidatorRejectsPredominantlyWrongTargetLanguage() {
        let validator = KeyboardTranslationOutputValidator()

        XCTAssertEqual(
            validator.validationFailure(
                for: "Good morning, I hope you are well and enjoying a wonderful day.",
                target: .arabic
            ),
            .predominantlyWrongLanguage
        )
        XCTAssertEqual(
            validator.validationFailure(
                for: "Good morning, I hope you are well and enjoying a wonderful day.",
                target: .dutch
            ),
            .predominantlyWrongLanguage
        )
        XCTAssertEqual(
            validator.validationFailure(for: "Yes", target: .arabic),
            .predominantlyWrongLanguage
        )
        XCTAssertEqual(
            validator.validationFailure(for: "Bonjour", target: .dutch),
            .predominantlyWrongLanguage
        )
    }

    func testTranslationValidatorRejectsSuspiciousMixedScripts() {
        let validator = KeyboardTranslationOutputValidator()

        XCTAssertEqual(
            validator.validationFailure(
                for: "مرحبا بك في هذا الاختبار mixed text output",
                target: .arabic
            ),
            .suspiciousMixedScripts
        )
    }

    func testLongMalayalamLiveOracleRejectsTrivialFragmentsAndAcceptsSubstantialText() {
        let source = Array(repeating: "source", count: 79).joined(separator: " ")
        let trivial = LongMalayalamTranslationEvidence(translation: "മ", source: source)
        let substantial = LongMalayalamTranslationEvidence(
            translation: String(repeating: "മലയാളം പരിഭാഷ ", count: 30),
            source: source
        )

        XCTAssertFalse(trivial.isUsable)
        XCTAssertTrue(substantial.isUsable)
    }

    func testKeyboardAIServiceRetriesInvalidTranslationOnceThenAcceptsValidOutput() async throws {
        let transport = SequencedCanonicalGatewayClientTestTransport(contents: [
            #"{"operation":"translate","results":[{"id":"translation-1","type":"translation","title":"Arabic translation","text":"Good morning, I hope you are well and enjoying a wonderful day.","replacement":"Good morning, I hope you are well and enjoying a wonderful day."}]}"#,
            #"{"operation":"translate","results":[{"id":"translation-1","type":"translation","title":"Arabic translation","text":"صباح الخير، أتمنى أن تكون بخير وأن تستمتع بيوم رائع.","replacement":"صباح الخير، أتمنى أن تكون بخير وأن تستمتع بيوم رائع."}]}"#
        ])
        let service = KeyboardAIService(gatewayClient: CanonicalGatewayClient(transport: transport))

        let result = try await service.performResult(
            action: .translate(.arabic),
            on: "Good morning, I hope you are well and enjoying a wonderful day.",
            config: configuredGateway
        )

        XCTAssertEqual(result.displayText, "صباح الخير، أتمنى أن تكون بخير وأن تستمتع بيوم رائع.")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testKeyboardAIServiceRetriesInvalidTranslationOnceThenReturnsTargetedFailure() async throws {
        let wrongLanguage = #"{"operation":"translate","results":[{"id":"translation-1","type":"translation","title":"Arabic translation","text":"Good morning, I hope you are well and enjoying a wonderful day.","replacement":"Good morning, I hope you are well and enjoying a wonderful day."}]}"#
        let transport = SequencedCanonicalGatewayClientTestTransport(contents: [wrongLanguage, wrongLanguage])
        let service = KeyboardAIService(gatewayClient: CanonicalGatewayClient(transport: transport))

        do {
            _ = try await service.performResult(
                action: .translate(.arabic),
                on: "Good morning, I hope you are well and enjoying a wonderful day.",
                config: configuredGateway
            )
            XCTFail("Expected a target-specific translation capability failure")
        } catch let error as KeyboardAIError {
            XCTAssertEqual(error, .unreliableTranslation(.arabic))
            XCTAssertEqual(error.actionErrorKind, .translationCapability)
            XCTAssertEqual(
                error.errorDescription,
                "This model may not reliably translate to Arabic. Try again or choose another model."
            )
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testKeyboardAIServiceRetriesMalformedTranslationThenReturnsTargetedWarning() async throws {
        let transport = SequencedCanonicalGatewayClientTestTransport(contents: [
            #"{"malformed"#,
            #"{"still-malformed"#
        ])
        let service = KeyboardAIService(gatewayClient: CanonicalGatewayClient(transport: transport))

        do {
            _ = try await service.performResult(
                action: .translate(.arabic),
                on: "Good morning, I hope you are well.",
                config: configuredGateway
            )
            XCTFail("Expected malformed translation output to become a targeted warning")
        } catch let error as KeyboardAIError {
            XCTAssertEqual(error, .unreliableTranslation(.arabic))
            XCTAssertEqual(error.actionErrorKind, .translationCapability)
        }

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testKeyboardAIServiceRetriesStructuredTranslationWarningThenReturnsTargetedWarning() async throws {
        let warning = #"{"operation":"translate","results":[{"id":"translation-warning","type":"warning","title":"Translation warning","text":"No","replacement":"No"}]}"#
        let transport = SequencedCanonicalGatewayClientTestTransport(contents: [warning, warning])
        let service = KeyboardAIService(gatewayClient: CanonicalGatewayClient(transport: transport))

        do {
            _ = try await service.performResult(
                action: .translate(.englishAmerican),
                on: "Nee",
                config: configuredGateway
            )
            XCTFail("Expected a structured warning to remain a translation-scoped warning")
        } catch let error as KeyboardAIError {
            XCTAssertEqual(error, .unreliableTranslation(.englishAmerican))
            XCTAssertEqual(error.actionErrorKind, .translationCapability)
        }

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testKeyboardAIServiceRetriesGenericTranslationCapabilityFailureThenScopesWarning() async throws {
        let transport = SequencedCanonicalGatewayClientTestTransport(contents: ["", ""])
        let service = KeyboardAIService(gatewayClient: CanonicalGatewayClient(transport: transport))

        do {
            _ = try await service.performResult(
                action: .translate(.englishAmerican),
                on: "Nee",
                config: configuredGateway
            )
            XCTFail("Expected a generic model failure to become a translation-scoped warning")
        } catch let error as KeyboardAIError {
            XCTAssertEqual(error, .unreliableTranslation(.englishAmerican))
            XCTAssertEqual(error.actionErrorKind, .translationCapability)
        }

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testKeyboardAIServiceRetriesShortWrongScriptTranslationThenAcceptsValidOutput() async throws {
        let transport = SequencedCanonicalGatewayClientTestTransport(contents: [
            #"{"operation":"translate","results":[{"id":"translation-1","type":"translation","title":"Arabic translation","text":"Yes","replacement":"Yes"}]}"#,
            #"{"operation":"translate","results":[{"id":"translation-1","type":"translation","title":"Arabic translation","text":"نعم","replacement":"نعم"}]}"#
        ])
        let service = KeyboardAIService(gatewayClient: CanonicalGatewayClient(transport: transport))

        let result = try await service.performResult(
            action: .translate(.arabic),
            on: "Yes",
            config: configuredGateway
        )

        XCTAssertEqual(result.displayText, "نعم")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testKeyboardAIServiceRetriesShortSameScriptTranslationOnceThenReturnsTargetedFailure() async throws {
        let wrongLanguage = #"{"operation":"translate","results":[{"id":"translation-1","type":"translation","title":"Dutch translation","text":"Bonjour","replacement":"Bonjour"}]}"#
        let transport = SequencedCanonicalGatewayClientTestTransport(contents: [wrongLanguage, wrongLanguage])
        let service = KeyboardAIService(gatewayClient: CanonicalGatewayClient(transport: transport))

        do {
            _ = try await service.performResult(
                action: .translate(.dutch),
                on: "Hello",
                config: configuredGateway
            )
            XCTFail("Expected a target-specific translation capability failure")
        } catch let error as KeyboardAIError {
            XCTAssertEqual(error, .unreliableTranslation(.dutch))
            XCTAssertEqual(error.actionErrorKind, .translationCapability)
            XCTAssertEqual(
                error.errorDescription,
                "This model may not reliably translate to Dutch. Try again or choose another model."
            )
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testKeyboardAIServiceDoesNotValidateOrRetryOtherAIActions() async throws {
        let content = "مرحبا mixed script output"
        let transport = SequencedCanonicalGatewayClientTestTransport(contents: [content])
        let service = KeyboardAIService(gatewayClient: CanonicalGatewayClient(transport: transport))

        let result = try await service.performResult(
            action: .rewrite,
            on: "Rewrite this text.",
            config: configuredGateway
        )

        XCTAssertEqual(result.displayText, "مرحبا mixed script output")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testKeyboardAIServicePreservesCanonicalGatewayErrorCategories() {
        XCTAssertEqual(
            KeyboardAIService.keyboardError(from: CanonicalGatewayClientError.unusableCorrection),
            .modelCapability
        )
        XCTAssertEqual(
            KeyboardAIService.keyboardError(from: CanonicalGatewayClientError.modelUnavailable),
            .modelUnavailable
        )
        XCTAssertEqual(KeyboardAIService.keyboardError(from: CanonicalGatewayClientError.unauthorized), .unauthorized)
        XCTAssertEqual(KeyboardAIService.keyboardError(from: CanonicalGatewayClientError.timeout), .timeout)
        XCTAssertEqual(KeyboardAIService.keyboardError(from: URLError(.timedOut)), .timeout)
        XCTAssertEqual(KeyboardAIService.keyboardError(from: CanonicalGatewayClientError.transport), .transport)
        XCTAssertEqual(KeyboardAIService.keyboardError(from: CanonicalGatewayClientError.invalidResponse), .invalidResponse)
    }

    func testKeyboardAIServiceEnforcesWallClockTimeout() async throws {
        let assistantContent = "A clearer sentence."
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["role": "assistant", "content": assistantContent]]]
        ])
        let transport = CanonicalGatewayClientTestTransport(
            data: responseBody,
            statusCode: 200,
            delayNanoseconds: 1_000_000_000,
            ignoresCancellation: true
        )
        let service = KeyboardAIService(
            gatewayClient: CanonicalGatewayClient(transport: transport),
            requestTimeoutInterval: 0.02
        )
        let started = Date()

        do {
            _ = try await service.performResult(
                action: .rewrite,
                on: "Make this clearer.",
                config: configuredGateway
            )
            XCTFail("Expected the request deadline to win")
        } catch let error as KeyboardAIError {
            XCTAssertEqual(error, .timeout)
        }

        XCTAssertLessThan(Date().timeIntervalSince(started), 0.30)
        XCTAssertEqual(transport.requests.first?.timeoutInterval, 0.02)
    }

    func testKeyboardAIServiceEnforcesWallClockTimeoutForAutomaticSuggestions() async throws {
        let transport = CanonicalGatewayClientTestTransport(
            data: Data(#"{"choices":[{"message":{"content":"{}"}}]}"#.utf8),
            statusCode: 200,
            delayNanoseconds: 250_000_000
        )
        let service = KeyboardAIService(
            gatewayClient: CanonicalGatewayClient(transport: transport),
            requestTimeoutInterval: 0.02
        )

        do {
            _ = try await service.analyzeSuggestions(
                for: "i has a apple",
                config: configuredGateway
            )
            XCTFail("Expected the automatic suggestion deadline to win")
        } catch let error as KeyboardAIError {
            XCTAssertEqual(error, .timeout)
        }

        XCTAssertEqual(transport.requests.first?.timeoutInterval, 0.02)
    }

    func testKeyboardAIServiceClassifiesMalformedStructuredJSONAsModelCapabilityFailure() async throws {
        try await assertModelCapabilityFailure(content: #"{"#, action: .fixGrammar, sourceText: "i has a apple")
    }

    func testKeyboardAIServiceClassifiesEmptyPlainTextRewriteOutputAsModelCapabilityFailure() async throws {
        try await assertModelCapabilityFailure(
            content: #"{"operation":"rewrite","results":[]}"#,
            action: .rewrite,
            sourceText: "Please make this clearer."
        )
    }

    func testKeyboardAIServiceClassifiesEmptyAssistantContentAsModelCapabilityFailure() async throws {
        try await assertModelCapabilityFailure(
            content: "   ",
            action: .rewrite,
            sourceText: "Please make this clearer."
        )
    }

    func testKeyboardAIServiceAcceptsValidNoChangeGrammarPlainText() async throws {
        let result = try await keyboardService(content: "The app works well.")
            .performResult(action: .fixGrammar, on: "The app works well.", config: configuredGateway)

        XCTAssertTrue(result.isNoChangeResult)
        XCTAssertFalse(result.isStructuredResponse)
        XCTAssertEqual(
            KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result, sourceText: "The app works well."),
            .noChanges
        )
    }

    private func assertModelCapabilityFailure(
        content: String,
        action: KeyboardAIAction,
        sourceText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            _ = try await keyboardService(content: content).performResult(
                action: action,
                on: sourceText,
                config: configuredGateway
            )
            XCTFail("Expected model capability failure", file: file, line: line)
        } catch let error as KeyboardAIError {
            XCTAssertEqual(error, .modelCapability, file: file, line: line)
        }
    }

    private func keyboardService(content: String) throws -> KeyboardAIService {
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["role": "assistant", "content": content]]]
        ])
        return KeyboardAIService(gatewayClient: CanonicalGatewayClient(
            transport: CanonicalGatewayClientTestTransport(data: responseBody, statusCode: 200)
        ))
    }

    private var configuredGateway: AppConfig {
        AppConfig(
            apiKey: "test-api-key",
            gatewayURL: "https://gateway.example/v1",
            selectedModel: "test-model",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
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
        let transport = NetworkManagerTestTransport(.chat(content: "I received the refund. "))
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
        XCTAssertEqual(request.timeoutInterval, GatewayRequestTimeouts.modelCheckAttempt)

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-oss:120b-cloud")
        XCTAssertEqual(json["operation"] as? String, "fix_grammar")
        let smokeInput = try XCTUnwrap(json["input_text"] as? String)
        XCTAssertEqual(smokeInput, NetworkManager.diagnosticSettingsCorrectionInput)
        XCTAssertEqual(json["max_tokens"] as? Int, 12_000)
        XCTAssertNil(json["temperature"])
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertNil(json["response_format"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let rendering = KeyboardGatewayActionContract.rendering(
            operation: "fix_grammar",
            text: smokeInput
        )
        XCTAssertEqual(messages.map { $0["role"] as? String }, rendering.messages.map(\.role))
        XCTAssertEqual(messages.map { $0["content"] as? String }, rendering.messages.map(\.content))
    }

    func testCorrectionSmokeRetriesOneUnusablePlainTextResponse() async throws {
        let transport = NetworkManagerTestTransport([
            .chat(content: "This sentence is already fine."),
            .chat(content: "I received the refund.")
        ])
        let manager = NetworkManager(transport: transport)

        try await manager.testCorrectionSmoke(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            model: "gemma2:2b"
        )

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertTrue(transport.requests.allSatisfy {
            $0.timeoutInterval == GatewayRequestTimeouts.modelCheckAttempt
        })
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
        try await assertFetchModelsThrows(.cancelled, response: .throwing(CancellationError()))
        try await assertFetchModelsThrows(.cancelled, response: .throwing(URLError(.cancelled)))
        try await assertFetchModelsThrows(.timeout, response: .throwing(URLError(.timedOut)))
    }

    func testCorrectionSmokeMapsServerMalformedTimeoutAndUnusableResponses() async throws {
        try await assertCorrectionSmokeThrows(.serverError("HTTP 503"), response: .rawJSON("Gateway down", statusCode: 503))
        try await assertCorrectionSmokeThrows(
            .modelUnavailable,
            response: .rawJSON(#"{"error":{"message":"model not found","code":"model_not_found"}}"#, statusCode: 404)
        )
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .rawJSON(#"{"choices":[]}"#))
        try await assertCorrectionSmokeThrows(.timeout, response: .throwing(URLError(.timedOut)))
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .chat(content: "This sentence is already fine."))
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .chat(content: "i recieved teh refnd. Hope this helps."))
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .chat(content: "I received the refund. Sure."))
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .chat(content: "I received. Sure."))
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .chat(content: "I received the: Sure."))
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .chat(content: "'i received the refund.'"))
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .chat(content: "“i received the refund.”"))
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .chat(content: "「i received the refund.」"))
        try await assertCorrectionSmokeThrows(.cancelled, response: .throwing(CancellationError()))
        try await assertCorrectionSmokeThrows(.cancelled, response: .throwing(URLError(.cancelled)))
    }

    func testGatewayDiagnosticsRunsKeyboardPlainTextGrammarPathAndMeasuresPerformance() async throws {
        let transport = NetworkManagerTestTransport([
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: "I received the refund.")
        ])
        let manager = NetworkManager(transport: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example/v1",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        XCTAssertFalse(report.hasFailures)
        XCTAssertEqual(report.selectedModel, "gpt-oss:120b-cloud")
        XCTAssertEqual(report.passedCount, 2)
        XCTAssertEqual(report.checks.count, 2)
        XCTAssertEqual(report.measuredDurations.count, 2)
        XCTAssertEqual(transport.requests.map { $0.url?.path }, [
            "/v1/models",
            "/v1/chat/completions"
        ])

        let chatBodyData = try XCTUnwrap(transport.requests.last?.httpBody)
        let chatBody = try XCTUnwrap(JSONSerialization.jsonObject(with: chatBodyData) as? [String: Any])
        XCTAssertEqual(chatBody["model"] as? String, "gpt-oss:120b-cloud")
        XCTAssertEqual(chatBody["operation"] as? String, "fix_grammar")
        XCTAssertEqual(chatBody["max_tokens"] as? Int, 12_000)
        XCTAssertEqual(chatBody["stream"] as? Bool, false)
        XCTAssertNil(chatBody["response_format"])
        let settingsSmokeInput = try XCTUnwrap(chatBody["input_text"] as? String)
        XCTAssertEqual(settingsSmokeInput, NetworkManager.diagnosticSettingsCorrectionInput)
        let settingsMessages = try XCTUnwrap(chatBody["messages"] as? [[String: Any]])
        XCTAssertTrue((settingsMessages.last?["content"] as? String)?.contains(settingsSmokeInput) == true)
        XCTAssertEqual(report.checks[1].id, "settings-correction-smoke")
        XCTAssertEqual(report.checks[1].title, "Plain-text grammar")
        XCTAssertTrue(report.checks[1].message.contains("derived local edits"))
    }

    func testGatewayDiagnosticsDoesNotSubstituteForUnavailablePreferredModel() async throws {
        let transport = NetworkManagerTestTransport([
            .models(["another-model"])
        ])
        let manager = NetworkManager(transport: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gemma2:2b"
        )

        XCTAssertEqual(report.selectedModel, "gemma2:2b")
        let grammarCheck = try XCTUnwrap(report.checks.first { $0.id == "settings-correction-smoke" })
        XCTAssertEqual(grammarCheck.status, .failed)
        XCTAssertEqual(grammarCheck.message, NetworkError.modelUnavailable.localizedDescription)
        XCTAssertEqual(transport.requests.map { $0.url?.path }, ["/v1/models"])
    }

    func testGatewayDiagnosticsSkipsGrammarWhenModelsFail() async throws {
        let transport = NetworkManagerTestTransport([
            .status(503)
        ])
        let manager = NetworkManager(transport: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        XCTAssertTrue(report.hasFailures)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertEqual(report.checks.first?.id, "models")
        XCTAssertEqual(report.checks.first?.status, .failed)
        XCTAssertEqual(report.checks.last?.id, "settings-correction-smoke")
        XCTAssertEqual(report.checks.last?.status, .skipped)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testGatewayDiagnosticsRetriesTransientRequiredCorrectionValidation() async throws {
        let transport = NetworkManagerTestTransport([
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: "not json"),
            .chat(content: "I received the refund.")
        ])
        let manager = NetworkManager(transport: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        let correctionCheck = try XCTUnwrap(report.checks.first { $0.id == "settings-correction-smoke" })
        XCTAssertEqual(correctionCheck.status, .passed)
        XCTAssertTrue(correctionCheck.message.contains("derived local edits"))
        XCTAssertFalse(report.hasFailures)
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testGatewayDiagnosticsFailsWhenPlainTextGrammarIsUnusable() async throws {
        let transport = NetworkManagerTestTransport([
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: NetworkManager.diagnosticSettingsCorrectionInput),
            .chat(content: NetworkManager.diagnosticSettingsCorrectionInput)
        ])
        let manager = NetworkManager(transport: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        let grammarCheck = try XCTUnwrap(report.checks.first { $0.id == "settings-correction-smoke" })
        XCTAssertEqual(grammarCheck.status, .failed)
        XCTAssertEqual(grammarCheck.message, NetworkError.unusableCorrection.localizedDescription)
        XCTAssertTrue(report.hasFailures)
        XCTAssertEqual(transport.requests.count, 3)
    }

    @MainActor
    func testViewModelKeepsExactDiscoveredModelWhenSmokeCannotVerifyIt() async throws {
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
            .chat(content: "This sentence is already fine.")
        ])
        let manager = NetworkManager(transport: transport)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: manager, defaults: defaults)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-api-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .limited)
        XCTAssertEqual(viewModel.config.gatewayURL, "https://gateway.example")
        XCTAssertEqual(viewModel.config.selectedModel, "apple-foundationmodel")
        XCTAssertEqual(secretStore.apiKey, "test-api-key")
        XCTAssertEqual(transport.requests.map { $0.url?.path }, [
            "/v1/models",
            "/v1/models",
            "/v1/chat/completions",
            "/v1/chat/completions"
        ])
        let smokeBodies = try transport.requests.suffix(2).map { request -> String in
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            return try XCTUnwrap(json["model"] as? String)
        }
        XCTAssertEqual(smokeBodies, ["apple-foundationmodel", "apple-foundationmodel"])
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
final class LiveModelDifferentialTests: XCTestCase {
    func testConfiguredProfileDifferentialContract() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let gatewayURL = Self.decodedHexEnvironmentValue(
            "OPEN_KEYBOARD_TEST_GATEWAY_URL_HEX",
            from: environment
        ),
        let apiKey = Self.decodedHexEnvironmentValue(
            "OPEN_KEYBOARD_TEST_API_KEY_HEX",
            from: environment
        ),
        let model = environment["OPEN_KEYBOARD_TEST_MODEL"],
        let role = environment["OPEN_KEYBOARD_LIVE_DIFFERENTIAL_ROLE"],
        !model.isEmpty else {
            throw XCTSkip("The targeted live-model profile environment is not configured.")
        }
        guard role == "low" || role == "high" else {
            XCTFail("The targeted live-model role must be low or high.")
            return
        }

        let models = try await NetworkManager().fetchModels(gatewayURL: gatewayURL, apiKey: apiKey)
        guard models.contains(model) else {
            XCTFail("The exact selected model must exist in the authenticated catalog.")
            return
        }

        let config = AppConfig(
            apiKey: apiKey,
            gatewayURL: gatewayURL,
            selectedModel: model,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertEqual(config.selectedModel, model)
        let service = KeyboardAIService(requestTimeoutInterval: 90)

        let baselineStartedAt = Date()
        let baseline: KeyboardActionOperationResult
        do {
            baseline = try await service.performResult(
                action: .fixGrammar,
                on: Self.baselineFixture,
                config: config
            )
        } catch let error as KeyboardAIError {
            XCTFail("The short baseline failed with canonical classification \(error.actionErrorKind).")
            return
        } catch {
            XCTFail("The short baseline failed without a canonical keyboard classification.")
            return
        }
        let baselineLatency = Date().timeIntervalSince(baselineStartedAt)
        XCTAssertEqual(baseline.operation, "fix_grammar")
        XCTAssertFalse(baseline.isStructuredResponse)
        XCTAssertFalse(baseline.displayText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(baseline.containsWarningItem)

        let boundaryStartedAt = Date()
        var lowBoundaryEstablished = true
        switch role {
        case "low":
            do {
                let result = try await service.performResult(
                    action: .translate(.malayalam),
                    on: Self.longCapabilityFixture,
                    config: config
                )
                XCTAssertEqual(result.operation, "translate")
                XCTAssertTrue(result.isStructuredResponse)
                XCTAssertFalse(result.items.isEmpty)
                XCTAssertFalse(result.containsWarningItem)
                lowBoundaryEstablished = false
            } catch let error as KeyboardAIError {
                XCTAssertEqual(error, .unreliableTranslation(.malayalam))
                XCTAssertEqual(error.actionErrorKind, .translationCapability)
            }
        case "high":
            let result: KeyboardActionOperationResult
            do {
                result = try await service.performResult(
                    action: .translate(.malayalam),
                    on: Self.longCapabilityFixture,
                    config: config
                )
            } catch let error as KeyboardAIError {
                XCTFail("The high-profile boundary request failed with canonical classification \(error.actionErrorKind).")
                return
            } catch {
                XCTFail("The high-profile boundary request failed without a canonical keyboard classification.")
                return
            }
            XCTAssertEqual(result.operation, "translate")
            XCTAssertTrue(result.isStructuredResponse)
            XCTAssertFalse(result.items.isEmpty)
            XCTAssertFalse(result.containsWarningItem)
            assertUsableLongMalayalamTranslation(
                result.displayText,
                source: Self.longCapabilityFixture
            )
        default:
            XCTFail("Unsupported targeted live-model role.")
            return
        }
        let boundaryLatency = Date().timeIntervalSince(boundaryStartedAt)

        let followUpStartedAt = Date()
        let followUp: KeyboardActionOperationResult
        do {
            followUp = try await service.performResult(
                action: .translate(.malayalam),
                on: Self.followUpFixture,
                config: config
            )
        } catch let error as KeyboardAIError {
            XCTFail("The short follow-up failed with canonical classification \(error.actionErrorKind).")
            return
        } catch {
            XCTFail("The short follow-up failed without a canonical keyboard classification.")
            return
        }
        let followUpLatency = Date().timeIntervalSince(followUpStartedAt)
        XCTAssertEqual(followUp.operation, "translate")
        XCTAssertTrue(followUp.isStructuredResponse)
        XCTAssertFalse(followUp.items.isEmpty)
        XCTAssertFalse(followUp.displayText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(followUp.containsWarningItem)
        XCTAssertTrue(
            followUp.displayText.unicodeScalars.contains {
                (0x0D00...0x0D7F).contains($0.value)
            },
            "The short follow-up must contain usable Malayalam text."
        )

        print(String(
            format: "LIVE_MODEL_DIFFERENTIAL_LATENCY role=%@ baseline=%.3f boundary=%.3f follow_up=%.3f",
            role,
            baselineLatency,
            boundaryLatency,
            followUpLatency
        ))
        if role == "low" && !lowBoundaryEstablished {
            throw XCTSkip("The fixed low-profile translation succeeded; capability boundary remains diagnostic only.")
        }
    }

    private static let baselineFixture = "Our support team definately needs the corrected refund note."
    private static let followUpFixture = "Good morning, I hope you are well."
    private static let longCapabilityFixture = """
    Each morning the community garden opens before the streets become busy. Volunteers check the paths, water young plants, and place clean tools beside the storage shed. They leave simple notes about work that is finished and tasks that still need attention, so the next group can continue without repeating anything.

    During the afternoon, families visit the garden to learn how vegetables grow. Children compare leaves, watch insects move between flowers, and help collect dry seeds for the next season.
    """

    private func assertUsableLongMalayalamTranslation(
        _ translation: String,
        source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let evidence = LongMalayalamTranslationEvidence(translation: translation, source: source)

        XCTAssertNotEqual(evidence.translatedText, source, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            evidence.translatedWordCount,
            evidence.minimumTranslatedWordCount,
            "The high-profile result is too short to be a usable translation of the long fixture.",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            evidence.malayalamLetterCount,
            evidence.minimumMalayalamLetterCount,
            "The high-profile result contains too little Malayalam text for the long fixture.",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            evidence.targetScriptRatio,
            0.60,
            "The high-profile long translation is not predominantly Malayalam.",
            file: file,
            line: line
        )
    }

    private static func decodedHexEnvironmentValue(
        _ key: String,
        from environment: [String: String]
    ) -> String? {
        guard let encoded = environment[key],
              !encoded.isEmpty,
              encoded.count.isMultiple(of: 2),
              encoded.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(encoded.count / 2)
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let next = encoded.index(index, offsetBy: 2)
            guard let byte = UInt8(encoded[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}

private struct LongMalayalamTranslationEvidence {
    let translatedText: String
    let sourceWordCount: Int
    let translatedWordCount: Int
    let malayalamLetterCount: Int
    let targetScriptRatio: Double

    init(translation: String, source: String) {
        translatedText = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        sourceWordCount = source.split(whereSeparator: { $0.isWhitespace }).count
        translatedWordCount = translatedText.split(whereSeparator: { $0.isWhitespace }).count
        let letterScalars = translatedText.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        malayalamLetterCount = letterScalars.filter { (0x0D00...0x0D7F).contains($0.value) }.count
        targetScriptRatio = letterScalars.isEmpty
            ? 0
            : Double(malayalamLetterCount) / Double(letterScalars.count)
    }

    var minimumTranslatedWordCount: Int { max(20, sourceWordCount / 3) }
    var minimumMalayalamLetterCount: Int { max(40, sourceWordCount / 2) }
    var isUsable: Bool {
        translatedWordCount >= minimumTranslatedWordCount &&
            malayalamLetterCount >= minimumMalayalamLetterCount &&
            targetScriptRatio >= 0.60
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
            grammarCorrectionVerified: false,
            grammarCorrectionContractVersion: ""
        )
        let viewModel = SettingsViewModel(config: initialConfig, gatewayTester: NetworkManager(), defaults: defaults)
        viewModel.updateGatewayURLInput(gatewayURL)
        viewModel.updateAPIKeyInput(apiKey)

        await viewModel.testConnection()

        let connectionFailure = viewModel.errorMessage ?? "No user-facing error was recorded."
        XCTAssertEqual(
            viewModel.connectionStatus,
            .success,
            "Test Connection did not verify plain-text grammar: \(connectionFailure)"
        )
        guard viewModel.connectionStatus == .success else { return }
        XCTAssertTrue(viewModel.config.isConfigured)
        XCTAssertFalse(viewModel.config.gatewayURL.isEmpty)
        XCTAssertEqual(
            viewModel.config.selectedModel,
            model,
            "The live proof must exercise the exact seeded model without catalog fallback."
        )
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(defaults.string(forKey: AppConfig.gatewayURLKey), viewModel.config.gatewayURL)
        XCTAssertEqual(defaults.string(forKey: AppConfig.selectedModelKey), viewModel.config.selectedModel)
        XCTAssertTrue(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertNotNil(secretStore.apiKey)
        XCTAssertTrue(viewModel.config.grammarCorrectionVerified)

        print("OpenKeyboard live Test Connection status: connected; plain-text grammar verified.")

        let diagnosticReport = await NetworkManager().runGatewayDiagnostics(
            gatewayURL: viewModel.config.gatewayURL,
            apiKey: apiKey,
            preferredModel: viewModel.config.selectedModel
        )
        let requiredCheckIDs = [
            "models",
            "settings-correction-smoke"
        ]
        for checkID in requiredCheckIDs {
            let check = try XCTUnwrap(diagnosticReport.checks.first { $0.id == checkID })
            XCTAssertEqual(check.status, .passed, "\(check.title): \(check.message)")
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
    private let delayNanoseconds: UInt64
    private let ignoresCancellation: Bool
    private(set) var requests: [URLRequest] = []

    init(
        data: Data,
        statusCode: Int,
        delayNanoseconds: UInt64 = 0,
        ignoresCancellation: Bool = false
    ) {
        self.data = data
        self.statusCode = statusCode
        self.delayNanoseconds = delayNanoseconds
        self.ignoresCancellation = ignoresCancellation
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if delayNanoseconds > 0 {
            if ignoresCancellation {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(
                        deadline: .now() + .nanoseconds(Int(delayNanoseconds))
                    ) {
                        continuation.resume()
                    }
                }
            } else {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }
        let response = HTTPURLResponse(
            url: try XCTUnwrap(request.url),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private final class SequencedCanonicalGatewayClientTestTransport: GatewayChatTransporting {
    private var responseBodies: [Data]
    private(set) var requests: [URLRequest] = []

    init(contents: [String]) {
        responseBodies = contents.map { content in
            try! JSONSerialization.data(withJSONObject: [
                "choices": [["message": ["role": "assistant", "content": content]]]
            ])
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !responseBodies.isEmpty else {
            throw CanonicalGatewayClientError.invalidResponse
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseBodies.removeFirst(), response)
    }
}

private enum ExpectedNetworkError {
    case unauthorized
    case serverError(String)
    case noData
    case modelUnavailable
    case unusableCorrection
    case timeout
    case cancelled

    func matches(_ error: Error) -> Bool {
        guard let networkError = error as? NetworkError else { return false }
        switch (self, networkError) {
        case (.unauthorized, .unauthorized),
             (.noData, .noData),
             (.modelUnavailable, .modelUnavailable),
             (.unusableCorrection, .unusableCorrection),
             (.timeout, .timeout),
             (.cancelled, .cancelled):
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
