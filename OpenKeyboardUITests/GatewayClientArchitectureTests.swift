import XCTest
import UniversalAiConnector

private let validFastGrammarDiagnosticResponse = "The gateway connection is ready."
private let validRewriteDiagnosticResponse = "Hi team, the app has issues that we need to fix soon, so please check it."
private let validDutchDiagnosticResponse = "De gatewayverbinding is klaar voor schrijfacties."

final class GatewayClientArchitectureTests: XCTestCase {
    func testLiveImproveHarnessUsesConnectorImprovePlainTextPath() throws {
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
        XCTAssertTrue(source.contains("KeyboardActionOperationResult.plainTextResponse"))
        XCTAssertTrue(source.contains("rendering: rendering"))
        XCTAssertTrue(source.contains("OpenKeyboardAIRequest.writing"))
        XCTAssertTrue(source.contains("UniversalAIConnectorAdapter.shared.respond"))
        XCTAssertFalse(source.contains("URLSession.shared"))
        XCTAssertFalse(source.contains("KeyboardActionOperationResult.parse"))
    }

    func testSharedContractVersionAndRewriteStylesArePinned() throws {
        XCTAssertEqual(KeyboardGatewayActionContract.contractVersion, "5.0.0")
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

    func testConnectorRequestPreservesExactContractMessagesAndGenerationSettings() throws {
        let source = "  i has a apple,ths is nt sound god  "
        let rendering = KeyboardGatewayActionContract.rendering(
            operation: "fix_grammar",
            text: source
        )

        let request = try OpenKeyboardAIRequest.writing(
            rendering: rendering,
            modelID: "test-model",
            timeoutInterval: 17
        )

        XCTAssertEqual(request.modelID, "test-model")
        XCTAssertEqual(request.messages.map(\.role), [.system, .user])
        XCTAssertEqual(request.messages.map(\.content), rendering.messages.map(\.content))
        XCTAssertEqual(request.maxOutputTokens, rendering.maxTokens)
        XCTAssertEqual(request.temperature, rendering.temperature)
        XCTAssertNil(request.topP)
        XCTAssertTrue(request.stopSequences.isEmpty)
        XCTAssertEqual(request.timeoutInterval, 17)
    }

    func testConnectorBaseURLAddsExactlyOneV1SuffixWithoutChangingStoredURL() throws {
        let cases: [(input: String, stored: String, connector: String)] = [
            ("gateway.example", "https://gateway.example", "https://gateway.example/v1"),
            ("https://gateway.example/v1/", "https://gateway.example", "https://gateway.example/v1"),
            ("https://gateway.example/V1/v1", "https://gateway.example/V1/v1", "https://gateway.example/v1"),
            ("https://gateway.example/custom/", "https://gateway.example/custom", "https://gateway.example/custom/v1")
        ]

        for item in cases {
            let profile = try OpenKeyboardGatewayProfile(
                gatewayURL: item.input,
                apiKey: "test-api-key"
            )
            XCTAssertEqual(profile.gatewayURL, item.stored, item.input)
            XCTAssertEqual(profile.connectorBaseURL, item.connector, item.input)
            XCTAssertEqual(OpenKeyboardGatewayProfile.providerID, "openai-compatible")
        }
    }

    func testProviderProfilesPreserveProviderSpecificBaseURLsAndRequestTargets() throws {
        let cases: [(
            provider: OpenKeyboardAIProvider,
            input: String,
            stored: String,
            connector: String
        )] = [
            (.openAI, "https://api.openai.com/v1/", "https://api.openai.com/v1", "https://api.openai.com/v1"),
            (.anthropic, "https://api.anthropic.com/v1/", "https://api.anthropic.com/v1", "https://api.anthropic.com/v1"),
            (.openRouter, "https://openrouter.ai/api/v1/", "https://openrouter.ai/api/v1", "https://openrouter.ai/api/v1"),
            (.openAICompatible, "https://gateway.example/v1/", "https://gateway.example", "https://gateway.example/v1")
        ]
        let request = try OpenKeyboardAIRequest(
            modelID: "exact-model",
            messages: [OpenKeyboardAIMessage(role: .user, content: "Source text")],
            maxOutputTokens: 64,
            temperature: nil
        )

        for item in cases {
            let profile = try OpenKeyboardGatewayProfile(
                provider: item.provider,
                baseURL: item.input,
                apiKey: "test-key"
            )
            XCTAssertEqual(profile.provider, item.provider)
            XCTAssertEqual(profile.baseURL, item.stored)
            XCTAssertEqual(profile.connectorBaseURL, item.connector)
            XCTAssertEqual(profile.providerID, item.provider.rawValue)
            XCTAssertEqual(
                UniversalAIConnectorAdapter.connectorRequest(
                    from: request,
                    providerID: profile.providerID
                ).target.providerId.rawValue,
                item.provider.rawValue
            )
        }
    }

    func testConnectorWritingRequestRejectsStructuredResponseMetadata() throws {
        let rendering = SemanticPromptRendering(
            contractVersion: SemanticPromptContract.version,
            schemaVersion: SemanticPromptContract.schemaVersion,
            packID: "writing-actions",
            operationID: "legacy",
            wireOperationID: "legacy",
            messages: [
                SemanticPromptMessage(role: "system", content: "System"),
                SemanticPromptMessage(role: "user", content: "User")
            ],
            responseFormatType: "json_object",
            maxTokens: 128,
            temperature: nil,
            plainTextValidationPolicy: nil
        )

        XCTAssertThrowsError(try OpenKeyboardAIRequest.writing(
            rendering: rendering,
            modelID: "test-model"
        )) { error in
            XCTAssertEqual(error as? OpenKeyboardAIConnectorError, .invalidResponse)
        }
    }

    func testUniversalConnectorRequestUsesExactProviderTargetMessagesAndGeneration() throws {
        let localRequest = try OpenKeyboardAIRequest(
            modelID: "exact-model",
            messages: [
                OpenKeyboardAIMessage(role: .system, content: "System instruction"),
                OpenKeyboardAIMessage(role: .user, content: "Source text")
            ],
            maxOutputTokens: 321,
            temperature: 0.25,
            topP: 0.75,
            stopSequences: ["END"],
            timeoutInterval: 7
        )

        let connectorRequest = UniversalAIConnectorAdapter.connectorRequest(from: localRequest)

        XCTAssertEqual(connectorRequest.target.providerId.rawValue, "openai-compatible")
        XCTAssertEqual(connectorRequest.target.modelId.rawValue, "exact-model")
        XCTAssertEqual(connectorRequest.input.map(\.role.rawValue), ["system", "user"])
        XCTAssertEqual(connectorRequest.input.map(\.content), ["System instruction", "Source text"])
        XCTAssertEqual(connectorRequest.responseFormat, .plainText)
        XCTAssertEqual(connectorRequest.generation.maxOutputTokens, 321)
        XCTAssertEqual(connectorRequest.generation.temperature, 0.25)
        XCTAssertEqual(connectorRequest.generation.topP, 0.75)
        XCTAssertEqual(connectorRequest.generation.stopSequences, ["END"])
    }

    func testUniversalConnectorAdaptsSamplingToProviderCompatibility() throws {
        let localRequest = try OpenKeyboardAIRequest(
            modelID: "exact-model",
            messages: [
                OpenKeyboardAIMessage(role: .system, content: "System instruction"),
                OpenKeyboardAIMessage(role: .user, content: "Source text")
            ],
            maxOutputTokens: 321,
            temperature: 0.25,
            topP: 0.75,
            stopSequences: [],
            timeoutInterval: 7
        )

        for provider in [OpenKeyboardAIProvider.openAI, .anthropic] {
            let connectorRequest = UniversalAIConnectorAdapter.connectorRequest(
                from: localRequest,
                providerID: provider.rawValue
            )

            XCTAssertNil(connectorRequest.generation.temperature, provider.rawValue)
            XCTAssertNil(connectorRequest.generation.topP, provider.rawValue)
            XCTAssertEqual(connectorRequest.generation.maxOutputTokens, 321, provider.rawValue)
        }

        for provider in [OpenKeyboardAIProvider.openRouter, .openAICompatible] {
            let connectorRequest = UniversalAIConnectorAdapter.connectorRequest(
                from: localRequest,
                providerID: provider.rawValue
            )

            XCTAssertEqual(connectorRequest.generation.temperature, 0.25, provider.rawValue)
            XCTAssertEqual(connectorRequest.generation.topP, 0.75, provider.rawValue)
            XCTAssertEqual(connectorRequest.generation.maxOutputTokens, 321, provider.rawValue)
        }
    }

    func testUniversalConnectorPlainTextResponseIsStrictAndPreservesContent() throws {
        let target = UniversalAiTarget(
            providerId: UniversalAiProviderId(rawValue: "openai-compatible"),
            modelId: UniversalAiModelId(rawValue: "exact-model")
        )
        let response = UniversalAiResponse(
            contractVersion: UniversalAiRequest.currentContractVersion,
            id: UniversalAiResponseId(rawValue: "response-1"),
            target: target,
            outputs: [
                UniversalAiOutput(
                    id: UniversalAiOutputId(rawValue: "output-1"),
                    index: 0,
                    kind: .text,
                    text: "  Preserved output.  "
                )
            ],
            completionReason: .stop
        )

        XCTAssertEqual(
            try UniversalAIConnectorAdapter.plainText(from: response, expectedTarget: target),
            "  Preserved output.  "
        )

        let truncated = UniversalAiResponse(
            contractVersion: UniversalAiRequest.currentContractVersion,
            id: UniversalAiResponseId(rawValue: "response-2"),
            target: target,
            outputs: response.outputs,
            completionReason: .maxOutputTokens
        )
        XCTAssertThrowsError(
            try UniversalAIConnectorAdapter.plainText(from: truncated, expectedTarget: target)
        ) { error in
            XCTAssertEqual(error as? OpenKeyboardAIConnectorError, .truncatedResponse)
        }

        let filtered = UniversalAiResponse(
            contractVersion: UniversalAiRequest.currentContractVersion,
            id: UniversalAiResponseId(rawValue: "response-3"),
            target: target,
            outputs: response.outputs,
            completionReason: .contentFilter
        )
        XCTAssertThrowsError(
            try UniversalAIConnectorAdapter.plainText(from: filtered, expectedTarget: target)
        ) { error in
            XCTAssertEqual(error as? OpenKeyboardAIConnectorError, .invalidResponse)
        }
    }

    func testUniversalConnectorMapsStablePublicErrorCategoriesAndCodes() throws {
        let cases: [(UniversalAiConnectorError, OpenKeyboardAIConnectorError)] = [
            (try connectorError(category: .authentication, code: "provider_authentication_failed"), .unauthorized),
            (try connectorError(category: .authorization, code: "provider_permission_denied"), .forbidden),
            (try connectorError(category: .notFound, code: "provider_resource_not_found"), .modelUnavailable),
            (try connectorError(category: .rateLimit, code: "provider_rate_limited"), .rateLimited),
            (try connectorError(category: .transport, code: "request_timeout"), .timeout),
            (try connectorError(category: .protocol, code: "malformed_provider_response"), .invalidResponse),
            (try connectorError(category: .provider, code: "provider_output_limit_reached"), .truncatedResponse),
            (try connectorError(category: .provider, code: "provider_unavailable"), .serverStatus(503))
        ]

        for (error, expected) in cases {
            XCTAssertEqual(
                UniversalAIConnectorAdapter.mappedError(error) as? OpenKeyboardAIConnectorError,
                expected,
                error.code.rawValue
            )
        }
    }

    func testUniversalConnectorReusesRuntimeAndClosesItOnProfileChangeAndExplicitClose() async throws {
        let recorder = ConnectorRuntimeFactoryRecorder()
        let adapter = UniversalAIConnectorAdapter(factory: recorder.makeRuntime)
        let firstProfile = try OpenKeyboardGatewayProfile(
            gatewayURL: "https://gateway.example",
            apiKey: "first-key"
        )
        let changedProfile = try OpenKeyboardGatewayProfile(
            gatewayURL: "https://gateway.example",
            apiKey: "second-key"
        )
        let changedURLProfile = try OpenKeyboardGatewayProfile(
            gatewayURL: "https://other-gateway.example",
            apiKey: "second-key"
        )
        let changedProviderProfile = try OpenKeyboardGatewayProfile(
            provider: .openAI,
            baseURL: "https://other-gateway.example/v1",
            apiKey: "second-key"
        )

        let firstModels = try await adapter.listModels(profile: firstProfile)
        let repeatedModels = try await adapter.listModels(profile: firstProfile)
        XCTAssertEqual(firstModels, ["exact-model"])
        XCTAssertEqual(repeatedModels, ["exact-model"])
        XCTAssertEqual(recorder.runtimes.count, 1)
        XCTAssertEqual(recorder.runtimes[0].closeCount, 0)

        let changedModels = try await adapter.listModels(profile: changedProfile)
        XCTAssertEqual(changedModels, ["exact-model"])
        XCTAssertEqual(recorder.runtimes.count, 2)
        XCTAssertEqual(recorder.runtimes[0].closeCount, 1)
        XCTAssertEqual(recorder.runtimes[1].closeCount, 0)

        let changedURLModels = try await adapter.listModels(profile: changedURLProfile)
        XCTAssertEqual(changedURLModels, ["exact-model"])
        XCTAssertEqual(recorder.runtimes.count, 3)
        XCTAssertEqual(recorder.runtimes[1].closeCount, 1)
        XCTAssertEqual(recorder.runtimes[2].closeCount, 0)

        let changedProviderModels = try await adapter.listModels(profile: changedProviderProfile)
        XCTAssertEqual(changedProviderModels, ["exact-model"])
        XCTAssertEqual(recorder.runtimes.count, 4)
        XCTAssertEqual(recorder.runtimes[2].closeCount, 1)
        XCTAssertEqual(recorder.runtimes[3].closeCount, 0)

        adapter.close()
        adapter.close()
        XCTAssertEqual(recorder.runtimes[3].closeCount, 1)
    }

    func testUniversalConnectorClosesRuntimeOnAdapterTeardown() async throws {
        let recorder = ConnectorRuntimeFactoryRecorder()
        var adapter: UniversalAIConnectorAdapter? = UniversalAIConnectorAdapter(
            factory: recorder.makeRuntime
        )
        let profile = try OpenKeyboardGatewayProfile(
            gatewayURL: "https://gateway.example",
            apiKey: "test-key"
        )

        _ = try await adapter?.listModels(profile: profile)
        XCTAssertEqual(recorder.runtimes.count, 1)
        XCTAssertEqual(recorder.runtimes[0].closeCount, 0)

        adapter = nil

        XCTAssertEqual(recorder.runtimes[0].closeCount, 1)
    }

    func testUniversalConnectorRejectsUnsupportedDiscoveryWithoutGenerationFallback() async throws {
        let runtime = try ConnectorRuntimeTestDouble(
            listResult: .unsupported(
                providerId: UniversalAiProviderId(rawValue: "openai-compatible")
            )
        )
        let adapter = UniversalAIConnectorAdapter(factory: { _ in runtime })
        let profile = try OpenKeyboardGatewayProfile(
            gatewayURL: "https://gateway.example",
            apiKey: "test-key"
        )

        do {
            _ = try await adapter.listModels(profile: profile)
            XCTFail("Expected unsupported model discovery")
        } catch let error as OpenKeyboardAIConnectorError {
            XCTAssertEqual(error, .unsupportedModelDiscovery)
        }
        XCTAssertEqual(runtime.listCount, 1)
        XCTAssertEqual(runtime.responseCount, 0)
    }

    func testUniversalConnectorCloseCancelsAnActiveResponse() async throws {
        let started = expectation(description: "response started")
        let runtime = ConnectorSuspendingRuntimeTestDouble {
            started.fulfill()
        }
        let adapter = UniversalAIConnectorAdapter(factory: { _ in runtime })
        let profile = try OpenKeyboardGatewayProfile(
            gatewayURL: "https://gateway.example",
            apiKey: "test-key"
        )
        let request = try OpenKeyboardAIRequest(
            modelID: "exact-model",
            messages: [OpenKeyboardAIMessage(role: .user, content: "Source text")],
            maxOutputTokens: 128,
            temperature: nil
        )
        let responseTask = Task {
            try await adapter.respond(to: request, profile: profile)
        }

        await fulfillment(of: [started], timeout: 1)
        adapter.close()

        do {
            _ = try await responseTask.value
            XCTFail("Expected close to cancel the active connector response")
        } catch is CancellationError {
            // Expected native cancellation.
        }
        XCTAssertEqual(runtime.closeCount, 1)
    }

    func testKeyboardAIServiceUsesConnectorContractForCarouselCorrections() async throws {
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
        let transport = ConnectorResponseTestDouble(
            data: responseBody,
            statusCode: 200
        )
        let service = KeyboardAIService(connector: transport)
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
        XCTAssertEqual(request.timeoutInterval, GatewayRequestTimeouts.keyboardAction)
        XCTAssertEqual(request.modelID, "test-model")
        XCTAssertEqual(request.maxOutputTokens, KeyboardGatewayActionContract.maxTokens(operation: "fix_grammar"))
        XCTAssertNil(request.temperature)
        XCTAssertEqual(request.messages.map(\.role), [.system, .user])
        XCTAssertEqual(
            request.messages.first?.content,
            KeyboardGatewayActionContract.rendering(operation: "fix_grammar", text: "i has a apple").messages[0].content
        )
        XCTAssertEqual(
            request.messages.last?.content,
            "i has a apple"
        )
        XCTAssertEqual(transport.profiles.first?.gatewayURL, "https://gateway.example")
        XCTAssertEqual(transport.profiles.first?.connectorBaseURL, "https://gateway.example/v1")
    }

    func testKeyboardAIServiceKeepsTwoConcurrentGrammarChunksOnOneConnectorProfile() async throws {
        let source = """
        The first paragraph is intentionally long enough to exercise the bounded grammar chunk path while preserving its original text and punctuation exactly for deterministic verification.

        The second paragraph provides another complete section so two connector operations can overlap without changing the source or relying on network behavior during this test.

        The final paragraph verifies that later work starts only after one of the first two requests finishes and that reassembly still follows the original chunk order.
        """
        let expectedChunks = GrammarTextChunker.chunks(in: source)
        XCTAssertGreaterThan(expectedChunks.count, 2)
        let connector = ConcurrentGrammarConnectorTestDouble()
        let service = KeyboardAIService(connector: connector)

        let result = try await service.performResult(
            action: .fixGrammar,
            on: source,
            config: configuredGateway
        )

        XCTAssertTrue(result.isNoChangeResult)
        XCTAssertEqual(result.displayText, source)
        XCTAssertEqual(
            connector.requests.count,
            expectedChunks.count * 2,
            "A completely unchanged first grammar pass is retried once with the same connector profile."
        )
        XCTAssertEqual(connector.maximumActiveResponses, 2)
        XCTAssertTrue(connector.requests.allSatisfy { $0.modelID == "test-model" })
        XCTAssertTrue(connector.profiles.allSatisfy {
            $0.connectorBaseURL == "https://gateway.example/v1"
        })
        XCTAssertEqual(
            Set(connector.requests.compactMap { $0.messages.last?.content }),
            Set(expectedChunks.map(\.text))
        )
    }

    func testKeyboardAIServiceKeepsBoundedContextualCorrectionInIndividualReviewFlow() async throws {
        let source = "We should of warnd the users that the repot are slower when the server is busy."
        let corrected = "We should have warnd the users that the report is slower when the server is busy."
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": corrected
                    ]
                ]
            ]
        ])
        let connector = ConnectorResponseTestDouble(data: responseBody, statusCode: 200)
        let service = KeyboardAIService(connector: connector)

        let result = try await service.performResult(
            action: .fixGrammar,
            on: source,
            config: configuredGateway
        )

        XCTAssertEqual(result.displayText, corrected)
        XCTAssertEqual(result.grammarPresentation, .correctionCards)
        guard case .showCorrections(let response) = KeyboardActionResultHandler.outcome(
            operation: "fix_grammar",
            result: result,
            sourceText: source
        ) else {
            return XCTFail("Expected individual grammar correction cards")
        }
        XCTAssertEqual(response.corrections.map(\.original), ["of", "repot", "are"])
        XCTAssertEqual(response.corrections.map(\.replacement), ["have", "report", "is"])
    }

    func testKeyboardAIServicePresentsSafeStructuralGrammarResponseAsWholeVersionProposal() async throws {
        let source = "First sentnce needs correction.\nSecond line stays here."
        let proposed = "A different opening sentence appears.\nSecond line stays here."
        let chunks = GrammarTextChunker.chunks(in: source)
        var contentsByInput = Dictionary(uniqueKeysWithValues: chunks.map { ($0.text, $0.text) })
        contentsByInput[chunks[0].text] = "A different opening sentence appears.\n"
        let connector = InputMappedConnectorResponseTestDouble(contentsByInput: contentsByInput)
        let service = KeyboardAIService(connector: connector)

        let result = try await service.performResult(
            action: .fixGrammar,
            on: source,
            config: configuredGateway
        )

        XCTAssertEqual(result.displayText, proposed)
        XCTAssertEqual(result.grammarPresentation, .wholeVersionProposal)
        XCTAssertEqual(
            KeyboardActionResultHandler.outcome(
                operation: "fix_grammar",
                result: result,
                sourceText: source
            ),
            .showGrammarWholeVersionProposal(proposed)
        )
    }

    func testKeyboardAIServiceChecksAndReassemblesEverySentence() async throws {
        let source = "The first sentence are wrong. The second sentence have an error. The final sentence is clean."
        let corrected = "The first sentence is wrong. The second sentence has an error. The final sentence is clean."
        let chunks = GrammarTextChunker.chunks(in: source)
        XCTAssertEqual(chunks.count, 3)
        let correctedChunks = GrammarTextChunker.chunks(in: corrected)
        let contentsByInput = Dictionary(uniqueKeysWithValues: zip(chunks, correctedChunks).map { pair in
            (pair.0.text, pair.1.text)
        })
        let connector = InputMappedConnectorResponseTestDouble(contentsByInput: contentsByInput)
        let service = KeyboardAIService(connector: connector)

        let result = try await service.performResult(
            action: .fixGrammar,
            on: source,
            config: configuredGateway
        )

        XCTAssertEqual(result.displayText, corrected)
        let requestedInputs = await connector.requestedInputs
        XCTAssertEqual(Set(requestedInputs), Set(chunks.map(\.text)))
        XCTAssertEqual(requestedInputs.count, chunks.count)
    }

    func testKeyboardAIServiceAggregatesMixedChunkDriftIntoOneWholeVersionProposal() async throws {
        let source = """
        This opening sentence continues
        with a deliberate line break and enough detail to form the first request. Another sentence remains unchanged.

        The second paragraph contains enough ordinary words to keep the overall document above the chunking threshold. It should stay exactly as supplied.

        The final paragraph also remains unchanged while making this fixture substantial enough to exercise concurrent chunk aggregation safely.
        """
        let chunks = GrammarTextChunker.chunks(in: source)
        XCTAssertGreaterThan(chunks.count, 1)
        let structuralChunk = try XCTUnwrap(chunks.first { $0.text.contains("deliberate line break") })
        let structurallyChanged = "The launch plan is complete and the customer can review it tomorrow. "
        var contentsByInput = Dictionary(uniqueKeysWithValues: chunks.map { ($0.text, $0.text) })
        contentsByInput[structuralChunk.text] = structurallyChanged
        let connector = InputMappedConnectorResponseTestDouble(contentsByInput: contentsByInput)
        let service = KeyboardAIService(connector: connector)

        let result = try await service.performResult(
            action: .fixGrammar,
            on: source,
            config: configuredGateway
        )
        let expected = chunks.map { contentsByInput[$0.text] ?? $0.text }.joined()

        XCTAssertEqual(result.displayText, expected)
        XCTAssertEqual(result.grammarPresentation, .wholeVersionProposal)
        XCTAssertEqual(
            KeyboardActionResultHandler.outcome(
                operation: "fix_grammar",
                result: result,
                sourceText: source
            ),
            .showGrammarWholeVersionProposal(expected)
        )
        let requestCount = await connector.requestedInputs.count
        XCTAssertEqual(requestCount, chunks.count)
    }

    func testKeyboardAIServiceSendsOneConnectorPlainTextRequestForImproveRephraseAndStyle() async throws {
        let source = "Please send the project update tomorrow at 10."
        let scenarios: [(KeyboardAIAction, String, String)] = [
            (.improve, "improve", "Please send the polished project update tomorrow at 10."),
            (.rewrite, "rewrite", "Tomorrow at 10, please send the project update."),
            (.rewriteStyle(.professional), "rewrite_professional", "Please provide the project update tomorrow at 10.")
        ]
        var renderingsByOperation: [String: SemanticPromptRendering] = [:]

        for (action, contractOperation, replacement) in scenarios {
            let transport = SequencedConnectorResponseTestDouble(contents: [replacement])
            let service = KeyboardAIService(connector: transport)

            let result = try await service.performResult(action: action, on: source, config: configuredGateway)

            XCTAssertEqual(transport.requests.count, 1, action.rawValue)
            XCTAssertEqual(result.items.count, 1, action.rawValue)
            XCTAssertEqual(result.displayText, replacement, action.rawValue)
            let request = try XCTUnwrap(transport.requests.first)
            let rendering = KeyboardGatewayActionContract.rendering(operation: contractOperation, text: source)
            XCTAssertEqual(request.messages.last?.content, source, action.rawValue)
            XCTAssertEqual(request.messages.first?.content, rendering.messages.first?.content, action.rawValue)
            XCTAssertEqual(request.messages.map(\.role), [.system, .user], action.rawValue)
            XCTAssertEqual(request.maxOutputTokens, rendering.maxTokens, action.rawValue)
            XCTAssertEqual(request.temperature, rendering.temperature, action.rawValue)
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
        let assistantContent = "Goedemorgen"
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["role": "assistant", "content": assistantContent]]]
        ])
        let transport = ConnectorResponseTestDouble(data: responseBody, statusCode: 200)
        let service = KeyboardAIService(connector: transport)
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
        XCTAssertEqual(result.items.map(\.type), ["translation"])
        let request = try XCTUnwrap(transport.requests.first)
        let rendering = KeyboardGatewayActionContract.rendering(
            operation: "translate",
            text: "Good morning",
            translationLanguage: "Dutch"
        )
        XCTAssertEqual(request.maxOutputTokens, KeyboardGatewayActionContract.maxTokens(operation: "translate"))
        XCTAssertEqual(request.messages.map { $0.role.rawValue }, rendering.messages.map(\.role))
        XCTAssertEqual(request.messages.map(\.content), rendering.messages.map(\.content))
    }

    func testKeyboardAIServiceRejectsTranslationWithoutTargetBeforeTransport() async throws {
        let transport = ConnectorResponseTestDouble(data: Data(), statusCode: 200)
        let service = KeyboardAIService(connector: transport)
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
        let transport = SequencedConnectorResponseTestDouble(contents: [
            "Good morning, I hope you are well and enjoying a wonderful day.",
            "صباح الخير، أتمنى أن تكون بخير وأن تستمتع بيوم رائع."
        ])
        let service = KeyboardAIService(connector: transport)

        let result = try await service.performResult(
            action: .translate(.arabic),
            on: "Good morning, I hope you are well and enjoying a wonderful day.",
            config: configuredGateway
        )

        XCTAssertEqual(result.displayText, "صباح الخير، أتمنى أن تكون بخير وأن تستمتع بيوم رائع.")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testKeyboardAIServiceRetriesInvalidTranslationOnceThenReturnsTargetedFailure() async throws {
        let wrongLanguage = "Good morning, I hope you are well and enjoying a wonderful day."
        let transport = SequencedConnectorResponseTestDouble(contents: [wrongLanguage, wrongLanguage])
        let service = KeyboardAIService(connector: transport)

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
        let transport = SequencedConnectorResponseTestDouble(contents: [
            #"{"malformed"#,
            #"{"still-malformed"#
        ])
        let service = KeyboardAIService(connector: transport)

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

    func testKeyboardAIServiceRetriesLegacyJSONTranslationEnvelopeThenReturnsTargetedWarning() async throws {
        let warning = #"{"operation":"translate","results":[{"id":"translation-warning","type":"warning","title":"Translation warning","text":"No","replacement":"No"}]}"#
        let transport = SequencedConnectorResponseTestDouble(contents: [warning, warning])
        let service = KeyboardAIService(connector: transport)

        do {
            _ = try await service.performResult(
                action: .translate(.englishAmerican),
                on: "Nee",
                config: configuredGateway
            )
            XCTFail("Expected the legacy JSON envelope to produce a translation-scoped warning")
        } catch let error as KeyboardAIError {
            XCTAssertEqual(error, .unreliableTranslation(.englishAmerican))
            XCTAssertEqual(error.actionErrorKind, .translationCapability)
        }

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testKeyboardAIServiceRetriesGenericTranslationCapabilityFailureThenScopesWarning() async throws {
        let transport = SequencedConnectorResponseTestDouble(contents: ["", ""])
        let service = KeyboardAIService(connector: transport)

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
        let transport = SequencedConnectorResponseTestDouble(contents: [
            "Yes",
            "نعم"
        ])
        let service = KeyboardAIService(connector: transport)

        let result = try await service.performResult(
            action: .translate(.arabic),
            on: "Yes",
            config: configuredGateway
        )

        XCTAssertEqual(result.displayText, "نعم")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testKeyboardAIServiceRetriesShortSameScriptTranslationOnceThenReturnsTargetedFailure() async throws {
        let wrongLanguage = "Bonjour"
        let transport = SequencedConnectorResponseTestDouble(contents: [wrongLanguage, wrongLanguage])
        let service = KeyboardAIService(connector: transport)

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
        let transport = SequencedConnectorResponseTestDouble(contents: [content])
        let service = KeyboardAIService(connector: transport)

        let result = try await service.performResult(
            action: .rewrite,
            on: "Rewrite this text.",
            config: configuredGateway
        )

        XCTAssertEqual(result.displayText, "مرحبا mixed script output")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testKeyboardAIServiceMapsStableConnectorErrorCategories() {
        XCTAssertEqual(
            KeyboardAIService.keyboardError(from: OpenKeyboardAIConnectorError.truncatedResponse),
            .modelCapability
        )
        XCTAssertEqual(
            KeyboardAIService.keyboardError(from: OpenKeyboardAIConnectorError.modelUnavailable),
            .modelUnavailable
        )
        XCTAssertEqual(KeyboardAIService.keyboardError(from: OpenKeyboardAIConnectorError.unauthorized), .unauthorized)
        XCTAssertEqual(KeyboardAIService.keyboardError(from: OpenKeyboardAIConnectorError.forbidden), .unauthorized)
        XCTAssertEqual(KeyboardAIService.keyboardError(from: OpenKeyboardAIConnectorError.timeout), .timeout)
        XCTAssertEqual(KeyboardAIService.keyboardError(from: URLError(.timedOut)), .timeout)
        XCTAssertEqual(KeyboardAIService.keyboardError(from: OpenKeyboardAIConnectorError.transport), .transport)
        XCTAssertEqual(KeyboardAIService.keyboardError(from: OpenKeyboardAIConnectorError.invalidResponse), .invalidResponse)
        XCTAssertEqual(KeyboardAIService.keyboardError(from: OpenKeyboardAIConnectorError.rateLimited), .server("Gateway HTTP 429"))
        XCTAssertEqual(KeyboardAIService.keyboardError(from: OpenKeyboardAIConnectorError.serverStatus(503)), .server("Gateway HTTP 503"))
    }

    func testKeyboardAIServiceEnforcesWallClockTimeout() async throws {
        let assistantContent = "A clearer sentence."
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["role": "assistant", "content": assistantContent]]]
        ])
        let transport = ConnectorResponseTestDouble(
            data: responseBody,
            statusCode: 200,
            delayNanoseconds: 1_000_000_000,
            ignoresCancellation: true
        )
        let service = KeyboardAIService(
            connector: transport,
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
        let transport = ConnectorResponseTestDouble(
            data: Data(#"{"choices":[{"message":{"content":"{}"}}]}"#.utf8),
            statusCode: 200,
            delayNanoseconds: 250_000_000
        )
        let service = KeyboardAIService(
            connector: transport,
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

    func testKeyboardAIServiceRejectsLegacyJSONGrammarEnvelopeAsRetryableInvalidResponse() async throws {
        do {
            _ = try await keyboardService(
                content: #"{"operation":"fix_grammar","results":[],"corrected_text":"I have an apple."}"#
            ).performResult(
                action: .fixGrammar,
                on: "i has a apple",
                config: configuredGateway
            )
            XCTFail("Expected invalid grammar response")
        } catch let error as KeyboardAIError {
            XCTAssertEqual(error, .invalidResponse)
            XCTAssertEqual(error.actionErrorKind, .invalidResponse)
            XCTAssertEqual(error.errorDescription, "Couldn't generate a usable suggestion. Try again.")
        }
    }

    func testKeyboardAIServiceMapsEmptyMalformedAndClearlyTruncatedGrammarToRetryableInvalidResponse() async throws {
        let longSource = String(
            repeating: "The detailed account update contains important information for every reviewer ",
            count: 6
        ) + "."
        let cases = [
            ("   ", "A grammar source."),
            ("```\nA corrected grammar source.\n```", "A grammar source."),
            ("A completely different short rewrite.", longSource)
        ]

        for (content, source) in cases {
            do {
                _ = try await keyboardService(content: content).performResult(
                    action: .fixGrammar,
                    on: source,
                    config: configuredGateway
                )
                XCTFail("Expected invalid grammar response")
            } catch let error as KeyboardAIError {
                XCTAssertEqual(error, .invalidResponse)
                XCTAssertEqual(error.actionErrorKind, .invalidResponse)
                XCTAssertEqual(error.errorDescription, "Couldn't generate a usable suggestion. Try again.")
            } catch {
                XCTFail("Expected an invalid-response classification")
            }
        }
    }

    func testKeyboardAIServiceRejectsLegacyJSONRewriteEnvelopeAsModelCapabilityFailure() async throws {
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
        XCTAssertEqual(
            KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result, sourceText: "The app works well."),
            .noChanges
        )
    }

    func testKeyboardAIServiceRetriesOneCompletelyUnchangedGrammarPass() async throws {
        let source = "Our support team definately needs the corrected refund note."
        let corrected = "Our support team definitely needs the corrected refund note."
        let connector = SequencedConnectorResponseTestDouble(contents: [source, corrected])
        let service = KeyboardAIService(connector: connector)

        let result = try await service.performResult(
            action: .fixGrammar,
            on: source,
            config: configuredGateway
        )

        XCTAssertEqual(result.displayText, corrected)
        XCTAssertEqual(connector.requests.count, 2)
        let requestInputs = connector.requests.compactMap { $0.messages.last?.content }
        XCTAssertEqual(requestInputs, [source, source])
    }

    func testKeyboardAIServiceKeepsValidUnchangedGrammarWhenRetryIsUnusable() async throws {
        let source = "The grammar and tone both need work."
        let connector = SequencedConnectorResponseTestDouble(
            contents: [source, "Certainly: \(source)"]
        )
        let service = KeyboardAIService(connector: connector)

        let result = try await service.performResult(
            action: .fixGrammar,
            on: source,
            config: configuredGateway
        )

        XCTAssertTrue(result.isNoChangeResult)
        XCTAssertEqual(result.displayText, source)
        XCTAssertEqual(connector.requests.count, 2)
        XCTAssertEqual(connector.requests.compactMap { $0.messages.last?.content }, [source, source])
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
        return KeyboardAIService(
            connector: ConnectorResponseTestDouble(data: responseBody, statusCode: 200)
        )
    }

    private func connectorError(
        category: UniversalAiErrorCategory,
        code: String
    ) throws -> UniversalAiConnectorError {
        try UniversalAiConnectorError(
            category: category,
            code: UniversalAiErrorCode(rawValue: code),
            message: "Stable connector failure."
        )
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
    func testFetchModelsNormalizesProfileForConnectorDiscovery() async throws {
        let transport = NetworkManagerTestConnector(.models(["apple-foundationmodel", "gpt-oss:120b-cloud"]))
        let manager = NetworkManager(connector: transport)

        let models = try await manager.fetchModels(
            gatewayURL: " https://https://gateway.example/v1/ ",
            apiKey: "test-api-key"
        )

        XCTAssertEqual(models, ["apple-foundationmodel", "gpt-oss:120b-cloud"])
        let call = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(call.path, "/v1/models")
        XCTAssertEqual(call.profile.gatewayURL, "https://gateway.example")
        XCTAssertEqual(call.profile.connectorBaseURL, "https://gateway.example/v1")
        XCTAssertEqual(call.profile.apiKey, "test-api-key")
        XCTAssertNil(call.request)
    }

    func testCorrectionSmokeBuildsExactConnectorRequest() async throws {
        let transport = NetworkManagerTestConnector(.chat(content: validFastGrammarDiagnosticResponse))
        let manager = NetworkManager(connector: transport)

        try await manager.testCorrectionSmoke(
            gatewayURL: "gateway.example/v1",
            apiKey: "test-api-key",
            model: "gpt-oss:120b-cloud"
        )

        let call = try XCTUnwrap(transport.requests.first)
        let request = try XCTUnwrap(call.request)
        XCTAssertEqual(call.path, "/v1/chat/completions")
        XCTAssertEqual(call.profile.gatewayURL, "https://gateway.example")
        XCTAssertEqual(call.profile.connectorBaseURL, "https://gateway.example/v1")
        XCTAssertEqual(call.profile.apiKey, "test-api-key")
        XCTAssertEqual(request.timeoutInterval, GatewayRequestTimeouts.modelCheckAttempt)
        XCTAssertEqual(request.modelID, "gpt-oss:120b-cloud")
        let smokeInput = NetworkManager.diagnosticSettingsCorrectionInput
        XCTAssertEqual(smokeInput, NetworkManager.diagnosticSettingsCorrectionInput)
        XCTAssertEqual(request.maxOutputTokens, 12_000)
        XCTAssertNil(request.temperature)
        XCTAssertNil(request.topP)
        XCTAssertTrue(request.stopSequences.isEmpty)
        let rendering = KeyboardGatewayActionContract.rendering(
            operation: "fix_grammar",
            text: smokeInput
        )
        XCTAssertEqual(request.messages.map { $0.role.rawValue }, rendering.messages.map(\.role))
        XCTAssertEqual(request.messages.map(\.content), rendering.messages.map(\.content))
    }

    func testCorrectionSmokeUsesOneAttemptAndPreservesUnusableFailure() async throws {
        let transport = NetworkManagerTestConnector([
            .chat(content: NetworkManager.diagnosticSettingsCorrectionInput),
            .chat(content: validFastGrammarDiagnosticResponse)
        ])
        let manager = NetworkManager(connector: transport)

        do {
            try await manager.testCorrectionSmoke(
                gatewayURL: "gateway.example",
                apiKey: "test-api-key",
                model: "gemma2:2b"
            )
            XCTFail("Expected the first unusable response to fail without retrying")
        } catch {
            XCTAssertTrue(
                ExpectedNetworkError.unusableCorrection.matches(error),
                "Unexpected first-attempt failure: \(error)"
            )
        }

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertTrue(transport.requests.allSatisfy {
            $0.request?.timeoutInterval == GatewayRequestTimeouts.modelCheckAttempt
        })
        let models = try transport.requests.map { call -> String in
            try XCTUnwrap(call.request?.modelID)
        }
        XCTAssertEqual(models, ["gemma2:2b"])
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
        try await assertCorrectionSmokeThrows(
            .unusableCorrection,
            response: .chat(content: NetworkManager.diagnosticSettingsCorrectionInput)
        )
        try await assertCorrectionSmokeThrows(.cancelled, response: .throwing(CancellationError()))
        try await assertCorrectionSmokeThrows(.cancelled, response: .throwing(URLError(.cancelled)))
    }

    func testGatewayDiagnosticsRunsContractOwnedGrammarRewriteAndTranslationPaths() async throws {
        let transport = NetworkManagerTestConnector([
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: validFastGrammarDiagnosticResponse),
            .chat(content: validRewriteDiagnosticResponse),
            .chat(content: validDutchDiagnosticResponse)
        ])
        let manager = NetworkManager(connector: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example/v1",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        XCTAssertFalse(report.hasFailures)
        XCTAssertEqual(report.selectedModel, "gpt-oss:120b-cloud")
        XCTAssertEqual(report.passedCount, 4)
        XCTAssertEqual(report.checks.count, 4)
        XCTAssertEqual(report.measuredDurations.count, 4)
        XCTAssertEqual(transport.requests.map(\.path), [
            "/v1/models",
            "/v1/chat/completions",
            "/v1/chat/completions",
            "/v1/chat/completions"
        ])

        let chatRequest = try XCTUnwrap(transport.requests[1].request)
        XCTAssertEqual(chatRequest.modelID, "gpt-oss:120b-cloud")
        XCTAssertEqual(chatRequest.maxOutputTokens, 12_000)
        XCTAssertNil(chatRequest.temperature)
        XCTAssertNil(chatRequest.topP)
        XCTAssertTrue(chatRequest.stopSequences.isEmpty)
        let settingsSmokeInput = NetworkManager.diagnosticSettingsCorrectionInput
        XCTAssertEqual(settingsSmokeInput, NetworkManager.diagnosticSettingsCorrectionInput)
        XCTAssertTrue(chatRequest.messages.last?.content.contains(settingsSmokeInput) == true)
        XCTAssertEqual(report.checks[1].id, "settings-correction-smoke")
        XCTAssertEqual(report.checks[1].title, "Fast plain-text grammar")
        XCTAssertEqual(report.checks[2].id, "settings-rewrite-improve")
        XCTAssertEqual(report.checks[2].title, "Rewrite and Improve")
        XCTAssertEqual(report.checks[3].id, "settings-translation-dutch")
        XCTAssertEqual(report.checks[3].title, "Translation to Dutch")

        let completionRequests = try transport.requests.dropFirst().map { call in
            try XCTUnwrap(call.request)
        }
        XCTAssertEqual(
            completionRequests.map { $0.messages.last?.content },
            [
                NetworkManager.diagnosticSettingsCorrectionInput,
                Self.presetUserMessage(id: NetworkManager.rewriteDiagnosticPresetID),
                Self.presetUserMessage(id: NetworkManager.translationDiagnosticPresetID)
            ]
        )
        XCTAssertTrue(completionRequests.allSatisfy { !$0.messages.isEmpty })
    }

    func testGatewayDiagnosticsDoesNotSubstituteForUnavailablePreferredModel() async throws {
        let transport = NetworkManagerTestConnector([
            .models(["another-model"]),
            .chat(content: validFastGrammarDiagnosticResponse),
            .chat(content: validRewriteDiagnosticResponse),
            .chat(content: validDutchDiagnosticResponse)
        ])
        let manager = NetworkManager(connector: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gemma2:2b"
        )

        XCTAssertEqual(report.selectedModel, "gemma2:2b")
        XCTAssertFalse(report.hasFailures)
        XCTAssertEqual(report.checks.count, 4)
        XCTAssertEqual(transport.requests.map(\.path), [
            "/v1/models",
            "/v1/chat/completions",
            "/v1/chat/completions",
            "/v1/chat/completions"
        ])
        for call in transport.requests.dropFirst() {
            XCTAssertEqual(call.request?.modelID, "gemma2:2b")
        }
    }

    func testGatewayDiagnosticsPreservesExactPreferredModelCasing() async throws {
        let transport = NetworkManagerTestConnector([
            .models(["GEMMA2:2B"]),
            .chat(content: validFastGrammarDiagnosticResponse),
            .chat(content: validRewriteDiagnosticResponse),
            .chat(content: validDutchDiagnosticResponse)
        ])

        let report = await NetworkManager(connector: transport).runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gemma2:2b"
        )

        XCTAssertEqual(report.selectedModel, "gemma2:2b")
        XCTAssertFalse(report.hasFailures)
        for call in transport.requests.dropFirst() {
            XCTAssertEqual(call.request?.modelID, "gemma2:2b")
        }
    }

    func testGatewayDiagnosticsReportsEveryCapabilityFailureWhenModelsFail() async throws {
        let transport = NetworkManagerTestConnector([
            .status(503),
            .status(503),
            .status(503),
            .status(503)
        ])
        let manager = NetworkManager(connector: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        XCTAssertTrue(report.hasFailures)
        XCTAssertEqual(report.failedCount, 4)
        XCTAssertEqual(report.skippedCount, 0)
        XCTAssertEqual(report.checks.first?.id, "models")
        XCTAssertEqual(report.checks.first?.status, .failed)
        XCTAssertEqual(report.checks.map(\.id), [
            "models",
            "settings-correction-smoke",
            "settings-rewrite-improve",
            "settings-translation-dutch"
        ])
        XCTAssertTrue(report.checks.dropFirst().allSatisfy { $0.status == .failed })
        XCTAssertEqual(transport.requests.count, 4)
    }

    func testGatewayDiagnosticsUsesOneAttemptPerCapabilityAndContinuesAfterFailure() async throws {
        let transport = NetworkManagerTestConnector([
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: NetworkManager.diagnosticSettingsCorrectionInput),
            .chat(content: validRewriteDiagnosticResponse),
            .chat(content: validDutchDiagnosticResponse)
        ])
        let manager = NetworkManager(connector: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        let correctionCheck = try XCTUnwrap(report.checks.first { $0.id == "settings-correction-smoke" })
        XCTAssertEqual(correctionCheck.status, .failed)
        XCTAssertEqual(report.checks.first { $0.id == "settings-rewrite-improve" }?.status, .passed)
        XCTAssertEqual(report.checks.first { $0.id == "settings-translation-dutch" }?.status, .passed)
        XCTAssertTrue(report.hasFailures)
        XCTAssertEqual(transport.requests.count, 4)
    }

    func testGatewayDiagnosticsReportsPlainTextRewriteFailureWithoutBlockingTranslation() async throws {
        let rewritePreset = try XCTUnwrap(
            SemanticPromptContract.gatewayPromptPreset(id: NetworkManager.rewriteDiagnosticPresetID)
        )
        let transport = NetworkManagerTestConnector([
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: validFastGrammarDiagnosticResponse),
            .chat(content: rewritePreset.input),
            .chat(content: validDutchDiagnosticResponse)
        ])

        let report = await NetworkManager(connector: transport).runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        XCTAssertEqual(report.checks.first { $0.id == "settings-correction-smoke" }?.status, .passed)
        let rewrite = try XCTUnwrap(report.checks.first { $0.id == "settings-rewrite-improve" })
        XCTAssertEqual(rewrite.status, .failed)
        XCTAssertEqual(
            rewrite.message,
            NetworkError.unusableCapability("Rewrite and Improve").localizedDescription
        )
        XCTAssertEqual(report.checks.first { $0.id == "settings-translation-dutch" }?.status, .passed)
        XCTAssertEqual(transport.requests.count, 4, "Each completion capability must run exactly once.")
    }

    func testGatewayDiagnosticsStopsAfterCancellationWithoutStartingLaterCapabilities() async throws {
        let transport = NetworkManagerTestConnector([
            .models(["gpt-oss:120b-cloud"]),
            .throwing(CancellationError()),
            .chat(content: validRewriteDiagnosticResponse),
            .chat(content: validDutchDiagnosticResponse)
        ])

        let report = await NetworkManager(connector: transport).runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        XCTAssertEqual(report.checks.first { $0.id == "settings-correction-smoke" }?.status, .failed)
        XCTAssertNil(report.checks.first { $0.id == "settings-rewrite-improve" })
        XCTAssertNil(report.checks.first { $0.id == "settings-translation-dutch" })
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testGatewayDiagnosticsSanitizesSensitiveFailureAndContinues() async throws {
        let transport = NetworkManagerTestConnector([
            .models(["gpt-oss:120b-cloud"]),
            .throwing(SensitiveDiagnosticTransportError()),
            .chat(content: validRewriteDiagnosticResponse),
            .chat(content: validDutchDiagnosticResponse)
        ])

        let report = await NetworkManager(connector: transport).runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        let grammar = try XCTUnwrap(report.checks.first { $0.id == "settings-correction-smoke" })
        XCTAssertEqual(grammar.status, .failed)
        XCTAssertFalse(grammar.message.localizedCaseInsensitiveContains("authorization"))
        XCTAssertFalse(grammar.message.localizedCaseInsensitiveContains("bearer"))
        XCTAssertFalse(grammar.message.contains("sensitive-diagnostic-value"))
        XCTAssertEqual(
            NetworkManager.diagnosticMessage(for: SensitiveDiagnosticTransportError()),
            "Gateway returned an invalid response."
        )
        XCTAssertEqual(report.checks.first { $0.id == "settings-rewrite-improve" }?.status, .passed)
        XCTAssertEqual(report.checks.first { $0.id == "settings-translation-dutch" }?.status, .passed)
        XCTAssertEqual(transport.requests.count, 4)
    }

    func testGatewayDiagnosticsRejectsSchemaValidNonDutchTranslation() async throws {
        let frenchResponse = "La connexion de la passerelle est prête pour les actions d'écriture."
        let transport = NetworkManagerTestConnector([
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: validFastGrammarDiagnosticResponse),
            .chat(content: validRewriteDiagnosticResponse),
            .chat(content: frenchResponse)
        ])
        let report = await NetworkManager(connector: transport).runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        XCTAssertEqual(report.checks.first { $0.id == "settings-correction-smoke" }?.status, .passed)
        XCTAssertEqual(report.checks.first { $0.id == "settings-rewrite-improve" }?.status, .passed)
        let translation = try XCTUnwrap(report.checks.first { $0.id == "settings-translation-dutch" })
        XCTAssertEqual(translation.status, .failed)
        XCTAssertEqual(translation.message, NetworkError.unusableCapability("Dutch translation").localizedDescription)
        XCTAssertEqual(transport.requests.count, 4)
    }

    func testGatewayDiagnosticsFailsWhenPlainTextGrammarIsUnusable() async throws {
        let transport = NetworkManagerTestConnector([
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: NetworkManager.diagnosticSettingsCorrectionInput),
            .chat(content: validRewriteDiagnosticResponse),
            .chat(content: validDutchDiagnosticResponse)
        ])
        let manager = NetworkManager(connector: transport)

        let report = await manager.runGatewayDiagnostics(
            gatewayURL: "gateway.example",
            apiKey: "test-api-key",
            preferredModel: "gpt-oss:120b-cloud"
        )

        let grammarCheck = try XCTUnwrap(report.checks.first { $0.id == "settings-correction-smoke" })
        XCTAssertEqual(grammarCheck.status, .failed)
        XCTAssertEqual(grammarCheck.message, NetworkError.unusableCorrection.localizedDescription)
        XCTAssertTrue(report.hasFailures)
        XCTAssertEqual(report.passedCount, 3)
        XCTAssertEqual(transport.requests.count, 4)
    }

    @MainActor
    func testViewModelRequiresExplicitModelAndDoesNotPublishWhenGrammarCannotVerify() async throws {
        let suiteName = "NetworkManagerGatewayTests.fallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldSecureStore = AppConfig.secureStore
        let secureStore = NetworkManagerInMemorySecureStore()
        AppConfig.secureStore = secureStore
        defer { AppConfig.secureStore = oldSecureStore }

        let transport = NetworkManagerTestConnector([
            .models(["apple-foundationmodel", "gpt-oss:120b-cloud"]),
            .models(["apple-foundationmodel", "gpt-oss:120b-cloud"]),
            .chat(content: NetworkManager.diagnosticSettingsCorrectionInput)
        ])
        let manager = NetworkManager(connector: transport)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: manager, defaults: defaults)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-api-key")

        await viewModel.testConnection()
        XCTAssertTrue(viewModel.modelSelectionRequired)
        XCTAssertTrue(transport.requests.allSatisfy { $0.path == "/v1/models" })
        viewModel.updateSelectedModelInput("apple-foundationmodel")
        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertEqual(viewModel.config.selectedModel, "")
        XCTAssertNil(secureStore.apiKey)
        XCTAssertEqual(transport.requests.map(\.path), [
            "/v1/models",
            "/v1/models",
            "/v1/chat/completions"
        ])
        let smokeRequest = try XCTUnwrap(transport.requests.last?.request)
        XCTAssertEqual(smokeRequest.modelID, "apple-foundationmodel")
    }

    @MainActor
    func testViewModelPreservesEmptyPersistedProfileWhenNetworkSmokeCannotVerifyModel() async throws {
        let suiteName = "NetworkManagerGatewayTests.failure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldSecureStore = AppConfig.secureStore
        let secureStore = NetworkManagerInMemorySecureStore()
        AppConfig.secureStore = secureStore
        defer { AppConfig.secureStore = oldSecureStore }

        let transport = NetworkManagerTestConnector([
            .models(["apple-foundationmodel"]),
            .chat(content: NetworkManager.diagnosticSettingsCorrectionInput)
        ])
        let manager = NetworkManager(connector: transport)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: manager, defaults: defaults)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-api-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.config.gatewayURL, "")
        XCTAssertEqual(viewModel.config.apiKey, "")
        XCTAssertEqual(viewModel.config.selectedModel, "")
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertFalse(viewModel.config.supportsStructuredCorrections)
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
        XCTAssertFalse(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertFalse(defaults.bool(forKey: AppConfig.supportsStructuredCorrectionsKey))
        XCTAssertNil(secureStore.apiKey)
        XCTAssertNotNil(AppConfig.gatewayConnectionError(from: defaults))
        XCTAssertEqual(transport.requests.map(\.path), [
            "/v1/models",
            "/v1/chat/completions"
        ])
        let smokeRequest = try XCTUnwrap(transport.requests.last?.request)
        XCTAssertEqual(smokeRequest.modelID, "apple-foundationmodel")
    }

    private func assertFetchModelsThrows(
        _ expected: ExpectedNetworkError,
        response: NetworkManagerTestConnector.Response,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let manager = NetworkManager(connector: NetworkManagerTestConnector(response))
        do {
            _ = try await manager.fetchModels(gatewayURL: "gateway.example", apiKey: "test-api-key")
            XCTFail("Expected NetworkError", file: file, line: line)
        } catch {
            XCTAssertTrue(expected.matches(error), "Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func assertCorrectionSmokeThrows(
        _ expected: ExpectedNetworkError,
        response: NetworkManagerTestConnector.Response,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let transport = NetworkManagerTestConnector(response)
        let manager = NetworkManager(connector: transport)
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
        XCTAssertEqual(transport.requests.count, 1, "Correction smoke must make exactly one response attempt.", file: file, line: line)
    }

    private static func presetUserMessage(id: String) -> String? {
        SemanticPromptContract.gatewayPromptPreset(id: id)?.rendering.messages.last?.content
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
        let providerValue = environment["OPEN_KEYBOARD_TEST_PROVIDER"],
        providerValue == OpenKeyboardAIProvider.openAICompatible.rawValue,
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
        XCTAssertTrue(config.selectedModel == model, "The exact live model was not preserved in memory.")
        let diagnosticReport = await NetworkManager().runGatewayDiagnostics(
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            preferredModel: model
        )
        try attachLiveGatewayDiagnosticEvidence(diagnosticReport, role: role)
        let transportCheck = try XCTUnwrap(diagnosticReport.checks.first { $0.id == "models" })
        XCTAssertEqual(transportCheck.status, .passed, "The live model-discovery diagnostic did not pass.")
        print("LIVE_GATEWAY_DIAGNOSTIC role=\(role) capability=transport status=\(transportCheck.status.rawValue.lowercased())")
        for checkID in ["settings-correction-smoke", "settings-rewrite-improve", "settings-translation-dutch"] {
            let check = try XCTUnwrap(diagnosticReport.checks.first { $0.id == checkID })
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(check.durationMilliseconds), 0)
            XCTAssertFalse(check.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            print("LIVE_GATEWAY_DIAGNOSTIC role=\(role) capability=\(checkID) status=\(check.status.rawValue.lowercased())")
        }
        let grammarCheck = try XCTUnwrap(
            diagnosticReport.checks.first { $0.id == "settings-correction-smoke" }
        )
        let rewriteCheck = try XCTUnwrap(
            diagnosticReport.checks.first { $0.id == "settings-rewrite-improve" }
        )
        XCTAssertEqual(grammarCheck.status, .passed, "The live grammar diagnostic did not pass.")
        XCTAssertEqual(rewriteCheck.status, .passed, "The live rewrite diagnostic did not pass.")
        let service = KeyboardAIService(requestTimeoutInterval: 90)

        var grammarFollowUpSource: String?
        for fixture in Self.grammarFixtures {
            let result: KeyboardActionOperationResult
            do {
                result = try await service.performResult(
                    action: .fixGrammar,
                    on: fixture.text,
                    config: config
                )
            } catch let error as KeyboardAIError {
                XCTFail("The \(fixture.id) grammar case failed with canonical classification \(error.actionErrorKind).")
                return
            } catch {
                XCTFail("The \(fixture.id) grammar case failed without a canonical keyboard classification.")
                return
            }
            XCTAssertEqual(result.operation, "fix_grammar")
            XCTAssertFalse(result.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(Self.looksLikeJSONContainer(result.displayText))
            XCTAssertTrue(
                result.displayText != fixture.text,
                "The definite errors in \(fixture.id) were not corrected."
            )
            XCTAssertNotNil(result.grammarPresentation)
            if fixture.id == "short" {
                grammarFollowUpSource = result.correctedText
            }
            print("LIVE_GRAMMAR_VARIANT role=\(role) case=\(fixture.id) status=passed")
        }

        let summary: KeyboardActionOperationResult
        do {
            summary = try await service.performResult(
                action: .summarize,
                on: Self.summaryFixture,
                config: config
            )
        } catch let error as KeyboardAIError {
            XCTFail("The summary contract failed with canonical classification \(error.actionErrorKind).")
            return
        }
        XCTAssertEqual(summary.operation, "summarize")
        XCTAssertEqual(summary.items.count, 1)
        XCTAssertTrue(summary.displayText.localizedCaseInsensitiveContains("Friday"))
        XCTAssertFalse(Self.looksLikeJSONContainer(summary.displayText))

        let continuationRendering = KeyboardGatewayActionContract.rendering(
            operation: "continue_writing",
            text: Self.continuationFixture
        )
        let continuationOutput: String
        do {
            let profile = try OpenKeyboardGatewayProfile(
                gatewayURL: config.gatewayURL,
                apiKey: config.apiKey
            )
            let request = try OpenKeyboardAIRequest.writing(
                rendering: continuationRendering,
                modelID: config.selectedModel,
                timeoutInterval: 90
            )
            continuationOutput = try await OpenKeyboardRequestDeadline.value(timeoutInterval: 90) {
                try await UniversalAIConnectorAdapter.shared.respond(to: request, profile: profile)
            }
        } catch {
            XCTFail("The continuation contract failed through the universal AI connector.")
            return
        }
        let continuation = try SemanticPromptContract.validatePlainTextResponse(
            continuationOutput,
            rendering: continuationRendering,
            source: Self.continuationFixture
        )
        XCTAssertFalse(continuation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(continuation.contains(Self.continuationFixture))
        XCTAssertFalse(Self.looksLikeJSONContainer(continuation))
        print("LIVE_PLAIN_TEXT_WRITING role=\(role) summarize=passed continue_writing=passed")

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
                XCTAssertFalse(result.items.isEmpty)
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
            XCTAssertFalse(result.items.isEmpty)
            assertUsableLongMalayalamTranslation(
                result.displayText,
                source: Self.longCapabilityFixture
            )
        default:
            XCTFail("Unsupported targeted live-model role.")
            return
        }
        let followUpSource = try XCTUnwrap(
            grammarFollowUpSource,
            "The initial grammar pass must produce corrected text for the live follow-up."
        )
        let followUp: KeyboardActionOperationResult
        do {
            followUp = try await service.performResult(
                action: .fixGrammar,
                on: followUpSource,
                config: config
            )
        } catch let error as KeyboardAIError {
            XCTFail("The grammar follow-up failed with canonical classification \(error.actionErrorKind).")
            return
        } catch {
            XCTFail("The grammar follow-up failed without a canonical keyboard classification.")
            return
        }
        XCTAssertEqual(followUp.operation, "fix_grammar")
        XCTAssertFalse(followUp.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(Self.looksLikeJSONContainer(followUp.displayText))
        XCTAssertNotNil(followUp.grammarPresentation)
        print("LIVE_GRAMMAR_FOLLOW_UP role=\(role) status=passed")

        if role == "low" && !lowBoundaryEstablished {
            throw XCTSkip("The fixed low-profile translation succeeded; capability boundary remains diagnostic only.")
        }
    }

    private static let grammarFixtures: [(id: String, text: String)] = [
        (
            "short",
            "Our support team definately needs the corrected refund note."
        ),
        (
            "medium",
            "Yesterday the support team recieve the account report, but the totals was incorrect and the final notes still needs a careful reveiw before the client meeting tomorrow."
        ),
        (
            "long",
            """
            our support team recieve the first report yesterday, but the account totals was incorrect and several important notes still needs review before the client meeting.

            The project manager ask everyone to check their assigned section, confirm that each reference are current, and record any question that remain unresolved. The clean scheduling sentence should remain unchanged.

            Before the final copy is sent, the team need to compare the updated figures, correct the repeated adress error, and make sure every reviewer have signed the checklist.
            """
        )
    ]
    private static let summaryFixture = "The release moved to Friday. The team will run every full check on Thursday."
    private static let continuationFixture = "The rain stopped just as Maya opened the door, and"
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

        XCTAssertTrue(
            evidence.translatedText != source,
            "The translation must differ from the source text.",
            file: file,
            line: line
        )
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

    private static func looksLikeJSONContainer(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }

    private func attachLiveGatewayDiagnosticEvidence(
        _ report: GatewayDiagnosticReport,
        role: String
    ) throws {
        let capabilities: [(id: String, evidenceName: String)] = [
            ("models", "transport"),
            ("settings-correction-smoke", "grammar"),
            ("settings-rewrite-improve", "rewrite"),
            ("settings-translation-dutch", "translation")
        ]
        let lines = try capabilities.map { capability in
            let check = try XCTUnwrap(report.checks.first { $0.id == capability.id })
            return "LIVE_GATEWAY_DIAGNOSTIC role=\(role) capability=\(capability.evidenceName) status=\(check.status.rawValue.lowercased())"
        }
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "live-gateway-diagnostics-\(role)"
        attachment.lifetime = .keepAlways
        add(attachment)
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
              let model = environment["OPEN_KEYBOARD_TEST_MODEL"], !model.isEmpty,
              let providerValue = environment["OPEN_KEYBOARD_TEST_PROVIDER"],
              let provider = OpenKeyboardAIProvider(rawValue: providerValue) else {
            throw XCTSkip("Set the encoded live gateway test values and OPEN_KEYBOARD_TEST_MODEL to run live gateway smoke.")
        }

        let suiteName = "LiveGatewaySmokeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldSecureStore = AppConfig.secureStore
        let secureStore = NetworkManagerInMemorySecureStore()
        AppConfig.secureStore = secureStore
        defer { AppConfig.secureStore = oldSecureStore }

        let initialConfig = AppConfig(
            apiKey: "",
            gatewayURL: "",
            selectedModel: model,
            isConfigured: false,
            grammarCorrectionVerified: false,
            grammarCorrectionContractVersion: "",
            provider: provider
        )
        let viewModel = SettingsViewModel(config: initialConfig, gatewayTester: NetworkManager(), defaults: defaults)
        viewModel.updateGatewayURLInput(gatewayURL)
        viewModel.updateAPIKeyInput(apiKey)

        await viewModel.loadModels()
        if viewModel.shouldShowManualModelEntry {
            viewModel.updateSelectedModelInput(model)
        } else {
            guard viewModel.availableModels.contains(model) else {
                XCTFail("The exact seeded model is not available for this provider profile.")
                return
            }
            viewModel.updateSelectedModelInput(model)
        }

        await viewModel.testConnection()
        XCTAssertFalse(
            viewModel.modelSelectionRequired,
            "The single live Test Connection attempt unexpectedly required another model selection."
        )
        guard !viewModel.modelSelectionRequired else { return }

        XCTAssertEqual(
            viewModel.connectionStatus,
            .success,
            "Test Connection did not verify plain-text grammar."
        )
        guard viewModel.connectionStatus == .success else { return }
        let expectedBaseURL = try NetworkManager.normalizedProviderBaseURLString(
            gatewayURL,
            provider: provider
        )
        XCTAssertTrue(viewModel.config.isConfigured)
        XCTAssertTrue(
            viewModel.config.baseURL == expectedBaseURL,
            "The validated provider base URL was not saved exactly after normalization."
        )
        XCTAssertTrue(
            viewModel.config.selectedModel == model,
            "The live proof must exercise the exact seeded model without catalog fallback."
        )
        XCTAssertEqual(viewModel.config.provider, provider)
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.selectedModelKey))
        XCTAssertFalse(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertTrue(defaults.bool(forKey: AppConfig.gatewayProfileConfiguredHintKey))
        XCTAssertFalse((defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey) ?? "").isEmpty)
        XCTAssertNotNil(secureStore.apiKey)
        XCTAssertTrue(
            AppConfig.load(from: defaults) == viewModel.config,
            "The saved secure profile did not match the validated in-memory profile."
        )
        XCTAssertTrue(viewModel.config.grammarCorrectionVerified)

        print("OpenKeyboard live Test Connection transport: passed; grammar save validation: passed.")

        let diagnosticReport = await NetworkManager().runGatewayDiagnostics(
            profile: try OpenKeyboardGatewayProfile(
                provider: provider,
                baseURL: viewModel.config.baseURL,
                apiKey: apiKey
            ),
            preferredModel: viewModel.config.selectedModel
        )
        XCTAssertTrue(
            diagnosticReport.selectedModel == model,
            "Diagnostics did not preserve the exact validated model."
        )
        let requiredCheckIDs = [
            "models",
            "settings-correction-smoke",
            "settings-rewrite-improve",
            "settings-translation-dutch"
        ]
        for checkID in requiredCheckIDs {
            let check = try XCTUnwrap(diagnosticReport.checks.first { $0.id == checkID })
            if checkID == "models" {
                XCTAssertTrue(
                    check.status == .passed || check.status == .skipped,
                    "The model-discovery diagnostic produced an unexpected status."
                )
            } else {
                XCTAssertEqual(
                    check.status,
                    .passed,
                    "The required exact-model capability diagnostic did not pass."
                )
            }
            print("OpenKeyboard live diagnostic \(check.title): \(check.status.rawValue.lowercased()).")
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

private final class ConnectorRuntimeFactoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRuntimes: [ConnectorRuntimeTestDouble] = []

    var runtimes: [ConnectorRuntimeTestDouble] {
        lock.withLock { storedRuntimes }
    }

    func makeRuntime(_ profile: OpenKeyboardGatewayProfile) throws -> UniversalAIConnectorRuntime {
        let runtime = try ConnectorRuntimeTestDouble(providerID: profile.providerID)
        lock.withLock {
            storedRuntimes.append(runtime)
        }
        return runtime
    }
}

private final class ConnectorRuntimeTestDouble: UniversalAIConnectorRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private let listResult: UniversalAiModelListResult
    private var storedListCount = 0
    private var storedResponseCount = 0
    private var storedCloseCount = 0

    var listCount: Int { lock.withLock { storedListCount } }
    var responseCount: Int { lock.withLock { storedResponseCount } }
    var closeCount: Int { lock.withLock { storedCloseCount } }

    init(
        providerID: String = OpenKeyboardGatewayProfile.providerID,
        listResult: UniversalAiModelListResult? = nil
    ) throws {
        if let listResult {
            self.listResult = listResult
        } else {
            let providerId = UniversalAiProviderId(rawValue: providerID)
            self.listResult = .supported(
                providerId: providerId,
                models: [
                    try UniversalAiModelDescriptor(
                        target: UniversalAiTarget(
                            providerId: providerId,
                            modelId: UniversalAiModelId(rawValue: "exact-model")
                        )
                    )
                ]
            )
        }
    }

    func listModels(
        providerId: UniversalAiProviderId
    ) async throws -> UniversalAiModelListResult {
        lock.withLock {
            storedListCount += 1
        }
        return listResult
    }

    func respond(to request: UniversalAiRequest) async throws -> UniversalAiResponse {
        lock.withLock {
            storedResponseCount += 1
        }
        throw OpenKeyboardAIConnectorError.invalidResponse
    }

    func close() {
        lock.withLock {
            storedCloseCount += 1
        }
    }
}

private final class ConnectorSuspendingRuntimeTestDouble: UniversalAIConnectorRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private let onStart: @Sendable () -> Void
    private var continuation: CheckedContinuation<UniversalAiResponse, Error>?
    private var storedCloseCount = 0

    var closeCount: Int { lock.withLock { storedCloseCount } }

    init(onStart: @escaping @Sendable () -> Void) {
        self.onStart = onStart
    }

    func listModels(
        providerId: UniversalAiProviderId
    ) async throws -> UniversalAiModelListResult {
        .unsupported(providerId: providerId)
    }

    func respond(to request: UniversalAiRequest) async throws -> UniversalAiResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
            }
            onStart()
        }
    }

    func close() {
        let continuation = lock.withLock { () -> CheckedContinuation<UniversalAiResponse, Error>? in
            storedCloseCount += 1
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(throwing: CancellationError())
    }
}

private final class ConcurrentGrammarConnectorTestDouble: OpenKeyboardAIConnectorServing, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [OpenKeyboardAIRequest] = []
    private var storedProfiles: [OpenKeyboardGatewayProfile] = []
    private var activeResponses = 0
    private var storedMaximumActiveResponses = 0

    var requests: [OpenKeyboardAIRequest] { lock.withLock { storedRequests } }
    var profiles: [OpenKeyboardGatewayProfile] { lock.withLock { storedProfiles } }
    var maximumActiveResponses: Int { lock.withLock { storedMaximumActiveResponses } }

    func listModels(profile: OpenKeyboardGatewayProfile) async throws -> [String] {
        throw OpenKeyboardAIConnectorError.unsupportedModelDiscovery
    }

    func respond(
        to request: OpenKeyboardAIRequest,
        profile: OpenKeyboardGatewayProfile
    ) async throws -> String {
        lock.withLock {
            storedRequests.append(request)
            storedProfiles.append(profile)
            activeResponses += 1
            storedMaximumActiveResponses = max(storedMaximumActiveResponses, activeResponses)
        }
        defer {
            lock.withLock {
                activeResponses -= 1
            }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        guard let source = request.messages.last?.content else {
            throw OpenKeyboardAIConnectorError.missingInput
        }
        return source
    }

    func close() {}
}

private final class ConnectorResponseTestDouble: OpenKeyboardAIConnectorServing, @unchecked Sendable {
    private let data: Data
    private let statusCode: Int
    private let delayNanoseconds: UInt64
    private let ignoresCancellation: Bool
    private let lock = NSLock()
    private var storedRequests: [OpenKeyboardAIRequest] = []
    private var storedProfiles: [OpenKeyboardGatewayProfile] = []

    var requests: [OpenKeyboardAIRequest] {
        lock.withLock { storedRequests }
    }

    var profiles: [OpenKeyboardGatewayProfile] {
        lock.withLock { storedProfiles }
    }

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

    func listModels(profile: OpenKeyboardGatewayProfile) async throws -> [String] {
        throw OpenKeyboardAIConnectorError.unsupportedModelDiscovery
    }

    func respond(
        to request: OpenKeyboardAIRequest,
        profile: OpenKeyboardGatewayProfile
    ) async throws -> String {
        lock.withLock {
            storedRequests.append(request)
            storedProfiles.append(profile)
        }
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
        guard (200..<300).contains(statusCode) else {
            throw Self.error(for: statusCode)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenKeyboardAIConnectorError.invalidResponse
        }
        return content
    }

    func close() {}

    private static func error(for statusCode: Int) -> OpenKeyboardAIConnectorError {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .modelUnavailable
        case 429: return .rateLimited
        default: return .serverStatus(statusCode)
        }
    }
}

private final class SequencedConnectorResponseTestDouble: OpenKeyboardAIConnectorServing, @unchecked Sendable {
    private let lock = NSLock()
    private var contents: [String]
    private var storedRequests: [OpenKeyboardAIRequest] = []

    var requests: [OpenKeyboardAIRequest] {
        lock.withLock { storedRequests }
    }

    init(contents: [String]) {
        self.contents = contents
    }

    func listModels(profile: OpenKeyboardGatewayProfile) async throws -> [String] {
        throw OpenKeyboardAIConnectorError.unsupportedModelDiscovery
    }

    func respond(
        to request: OpenKeyboardAIRequest,
        profile: OpenKeyboardGatewayProfile
    ) async throws -> String {
        try lock.withLock {
            storedRequests.append(request)
            guard !contents.isEmpty else {
                throw OpenKeyboardAIConnectorError.invalidResponse
            }
            return contents.removeFirst()
        }
    }

    func close() {}
}

private actor InputMappedConnectorResponseTestDouble: OpenKeyboardAIConnectorServing {
    private let contentsByInput: [String: String]
    private(set) var requestedInputs: [String] = []

    init(contentsByInput: [String: String]) {
        self.contentsByInput = contentsByInput
    }

    func listModels(profile: OpenKeyboardGatewayProfile) async throws -> [String] {
        throw OpenKeyboardAIConnectorError.unsupportedModelDiscovery
    }

    func respond(
        to request: OpenKeyboardAIRequest,
        profile: OpenKeyboardGatewayProfile
    ) async throws -> String {
        guard let input = request.messages.last?.content,
              let content = contentsByInput[input] else {
            throw OpenKeyboardAIConnectorError.invalidResponse
        }
        requestedInputs.append(input)
        return content
    }

    nonisolated func close() {}
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

private struct SensitiveDiagnosticTransportError: LocalizedError {
    var errorDescription: String? {
        #"Authorization: Bearer sensitive-diagnostic-value {"error":"private"}"#
    }
}

private final class NetworkManagerTestConnector: OpenKeyboardAIConnectorServing, @unchecked Sendable {
    enum Response {
        case models([String])
        case chat(content: String)
        case rawJSON(String, statusCode: Int = 200)
        case status(Int)
        case throwing(Error)
    }

    struct Call {
        enum Kind {
            case listModels
            case respond
        }

        let kind: Kind
        let profile: OpenKeyboardGatewayProfile
        let request: OpenKeyboardAIRequest?

        var path: String {
            switch kind {
            case .listModels: return "/v1/models"
            case .respond: return "/v1/chat/completions"
            }
        }
    }

    private let lock = NSLock()
    private var responses: [Response]
    private var storedRequests: [Call] = []

    var requests: [Call] {
        lock.withLock { storedRequests }
    }

    init(_ responses: [Response]) {
        self.responses = responses
    }

    convenience init(_ response: Response) {
        self.init([response])
    }

    func listModels(profile: OpenKeyboardGatewayProfile) async throws -> [String] {
        let response = nextResponse(
            recording: Call(kind: .listModels, profile: profile, request: nil)
        )
        switch response {
        case .models(let models):
            return models
        case let .rawJSON(body, statusCode):
            guard (200..<300).contains(statusCode) else {
                throw Self.error(for: statusCode)
            }
            guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
                  let data = object["data"] as? [[String: Any]] else {
                throw OpenKeyboardAIConnectorError.invalidResponse
            }
            return data.compactMap { $0["id"] as? String }
        case .status(let statusCode):
            throw Self.error(for: statusCode)
        case .throwing(let error):
            throw error
        case .chat:
            throw OpenKeyboardAIConnectorError.invalidResponse
        }
    }

    func respond(
        to request: OpenKeyboardAIRequest,
        profile: OpenKeyboardGatewayProfile
    ) async throws -> String {
        let response = nextResponse(
            recording: Call(kind: .respond, profile: profile, request: request)
        )
        switch response {
        case .chat(let content):
            return content
        case let .rawJSON(body, statusCode):
            guard (200..<300).contains(statusCode) else {
                throw Self.error(for: statusCode)
            }
            guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
                  let choices = object["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw OpenKeyboardAIConnectorError.invalidResponse
            }
            return content
        case .status(let statusCode):
            throw Self.error(for: statusCode)
        case .throwing(let error):
            throw error
        case .models:
            throw OpenKeyboardAIConnectorError.invalidResponse
        }
    }

    func close() {}

    private func nextResponse(recording call: Call) -> Response {
        lock.withLock {
            storedRequests.append(call)
            guard !responses.isEmpty else {
                return .status(500)
            }
            return responses.removeFirst()
        }
    }

    private static func error(for statusCode: Int) -> OpenKeyboardAIConnectorError {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .modelUnavailable
        case 429: return .rateLimited
        default: return .serverStatus(statusCode)
        }
    }
}

private final class NetworkManagerInMemorySecureStore: AppConfigSecureStore {
    private var profileData: Data?
    private var legacyAPIKey: String?
    private var referencedAPIKeys: [String: String] = [:]
    private var clearIntent: AppConfigSecureClearIntent?
    var apiKey: String? { Self.apiKey(from: profileData) ?? legacyAPIKey }

    func loadProfile() -> Data? { profileData }

    @discardableResult
    func saveProfile(_ profile: Data) -> Bool {
        profileData = profile
        return true
    }

    @discardableResult
    func clearProfile() -> Bool {
        profileData = nil
        return true
    }

    func loadClearIntentResult() -> AppConfigSecureStoreClearIntentReadResult {
        clearIntent.map(AppConfigSecureStoreClearIntentReadResult.found) ?? .notFound
    }

    func saveClearIntent(_ intent: AppConfigSecureClearIntent) -> Bool {
        clearIntent = intent
        return true
    }

    func clearClearIntent() -> Bool {
        clearIntent = nil
        return true
    }

    func loadLegacyAPIKey() -> String? { legacyAPIKey }
    func loadLegacyAPIKey(reference: String) -> String? { referencedAPIKeys[reference] }
    func loadLegacyAPIKeyResult() -> AppConfigSecureStoreStringReadResult {
        legacyAPIKey.map(AppConfigSecureStoreStringReadResult.found) ?? .notFound
    }
    func loadLegacyAPIKeyResult(reference: String) -> AppConfigSecureStoreStringReadResult {
        referencedAPIKeys[reference].map(AppConfigSecureStoreStringReadResult.found) ?? .notFound
    }

    @discardableResult
    func saveLegacyAPIKey(_ apiKey: String) -> Bool {
        legacyAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }

    @discardableResult
    func clearLegacyAPIKey() -> Bool {
        legacyAPIKey = nil
        return true
    }

    @discardableResult
    func clearLegacyAPIKey(reference: String) -> Bool {
        referencedAPIKeys.removeValue(forKey: reference)
        return true
    }

    private static func apiKey(from data: Data?) -> String? {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["apiKey"] as? String
    }
}
