import XCTest

final class GatewayClientArchitectureTests: XCTestCase {
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
        let transport = NetworkManagerTestTransport(.chat(content: "I have an apple."))
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
        XCTAssertEqual(json["input_text"] as? String, "i has a apple")
        XCTAssertEqual(json["max_tokens"] as? Int, 1600)
        XCTAssertEqual(json["temperature"] as? Double, 0.1)
        XCTAssertEqual(json["stream"] as? Bool, false)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertTrue((messages.first?["content"] as? String)?.contains("Return strict JSON only") == true)
        XCTAssertTrue((messages.last?["content"] as? String)?.contains("Operation: fix_grammar") == true)
        XCTAssertTrue((messages.last?["content"] as? String)?.contains("i has a apple") == true)
    }

    func testFetchModelsMapsAuthServerAndMalformedResponses() async throws {
        try await assertFetchModelsThrows(.unauthorized, response: .status(403))
        try await assertFetchModelsThrows(.serverError("HTTP 500"), response: .status(500))
        try await assertFetchModelsThrows(.noData, response: .rawJSON(#"{"data":123}"#))
    }

    func testCorrectionSmokeMapsServerMalformedTimeoutAndUnusableResponses() async throws {
        try await assertCorrectionSmokeThrows(.serverError("Gateway down"), response: .rawJSON("Gateway down", statusCode: 503))
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .rawJSON(#"{"choices":[]}"#))
        try await assertCorrectionSmokeThrows(.timeout, response: .throwing(URLError(.timedOut)))
        try await assertCorrectionSmokeThrows(.unusableCorrection, response: .chat(content: "This sentence is already fine."))
    }

    func testGatewayDiagnosticsRunsFullGatewayContractAndMeasuresPerformance() async throws {
        let transport = NetworkManagerTestTransport([
            .rawJSON(#"{"status":"ok"}"#),
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"verb","type":"correction","title":"Verb","text":"Use have.","original":"has","replacement":"have"}],"corrected_text":"I have an apple."}"#),
            .chat(content: #"{"corrections":[{"label":"Spelling","original":"teh","replacement":"the"}],"predictions":[{"label":"Suggestion","text":"tomorrow","kind":"nextWord"}]}"#),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"1","type":"correction","title":"Spelling","text":"Use definitely.","original":"definately","replacement":"definitely"},{"id":"2","type":"correction","title":"Spelling","text":"Use receive.","original":"recieve","replacement":"receive"},{"id":"3","type":"correction","title":"Spelling","text":"Use address.","original":"adress","replacement":"address"},{"id":"4","type":"correction","title":"Spelling","text":"Use tomorrow.","original":"tomorow","replacement":"tomorrow"}],"corrected_text":"I definitely receive the address tomorrow, and separate files won't upload because its receive limit is too low."}"#),
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
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"verb","type":"correction","title":"Verb","text":"Use have.","original":"has","replacement":"have"}],"corrected_text":"I have an apple."}"#),
            .chat(content: #"{"corrections":[{"label":"Spelling","original":"teh","replacement":"the"}],"predictions":[]}"#),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"1","type":"correction","title":"Spelling","text":"Use definitely.","original":"definately","replacement":"definitely"},{"id":"2","type":"correction","title":"Spelling","text":"Use receive.","original":"recieve","replacement":"receive"},{"id":"3","type":"correction","title":"Spelling","text":"Use address.","original":"adress","replacement":"address"}],"corrected_text":"I definitely receive the address tomorrow."}"#),
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

    func testGatewayDiagnosticsFailsPlainTextActionBecauseJSONIsRequired() async throws {
        let transport = NetworkManagerTestTransport([
            .rawJSON(#"{"status":"ok"}"#),
            .models(["gpt-oss:120b-cloud"]),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"verb","type":"correction","title":"Verb","text":"Use have.","original":"has","replacement":"have"}],"corrected_text":"I have an apple."}"#),
            .chat(content: #"{"corrections":[{"label":"Spelling","original":"teh","replacement":"the"}],"predictions":[]}"#),
            .chat(content: #"{"operation":"fix_grammar","results":[{"id":"1","type":"correction","title":"Spelling","text":"Use definitely.","original":"definately","replacement":"definitely"},{"id":"2","type":"correction","title":"Spelling","text":"Use receive.","original":"recieve","replacement":"receive"},{"id":"3","type":"correction","title":"Spelling","text":"Use address.","original":"adress","replacement":"address"}],"corrected_text":"I definitely receive the address tomorrow."}"#),
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
        XCTAssertEqual(rewriteCheck.status, .failed)
        XCTAssertEqual(rewriteCheck.message, "rewrite did not return valid app JSON.")
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
            .chat(content: "I have an apple.")
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
            "/v1/chat/completions"
        ])
        let smokeBodies = try transport.requests.suffix(2).map { request -> String in
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            return try XCTUnwrap(json["model"] as? String)
        }
        XCTAssertEqual(smokeBodies, ["apple-foundationmodel", "gpt-oss:120b-cloud"])
    }

    @MainActor
    func testViewModelDoesNotSaveDraftConfigWhenNetworkSmokeFails() async throws {
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
            .chat(content: "This sentence is already fine.")
        ])
        let manager = NetworkManager(transport: transport)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: manager, defaults: defaults)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-api-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.config.gatewayURL, "")
        XCTAssertEqual(viewModel.config.apiKey, "")
        XCTAssertEqual(viewModel.config.selectedModel, "")
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
        XCTAssertFalse(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertNil(secretStore.apiKey)
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
        let manager = NetworkManager(transport: NetworkManagerTestTransport(response))
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
        guard let gatewayURL = environment["OPEN_KEYBOARD_TEST_GATEWAY_URL"], !gatewayURL.isEmpty,
              let apiKey = environment["OPEN_KEYBOARD_TEST_API_KEY"], !apiKey.isEmpty,
              let model = environment["OPEN_KEYBOARD_TEST_MODEL"], !model.isEmpty else {
            throw XCTSkip("Set OPEN_KEYBOARD_TEST_GATEWAY_URL, OPEN_KEYBOARD_TEST_API_KEY, and OPEN_KEYBOARD_TEST_MODEL to run live gateway smoke.")
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
