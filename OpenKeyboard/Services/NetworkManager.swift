//
//  NetworkManager.swift
//  OpenKeyboard
//
//  Network service for gateway communication
//

import Foundation

protocol NetworkManagerTransporting: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: NetworkManagerTransporting {}

enum NetworkError: Error {
    case invalidURL
    case noData
    case unauthorized
    case serverError(String)
    case networkError(Error)
    case modelUnavailable
    case unusableCorrection
    case timeout

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid gateway URL"
        case .noData:
            return "No response from server"
        case .unauthorized:
            return "Invalid API key"
        case .serverError(let message):
            return "Server error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .modelUnavailable:
            return "The selected model is not available for this key."
        case .unusableCorrection:
            return "Gateway connected, but the selected model did not return a usable correction."
        case .timeout:
            return "Gateway connected, but the selected model timed out during the test."
        }
    }
}

enum GatewayDiagnosticStatus: String, Equatable {
    case passed = "Passed"
    case failed = "Failed"
    case skipped = "Skipped"
}

struct GatewayDiagnosticCheck: Identifiable, Equatable {
    let id: String
    let title: String
    let endpoint: String
    let status: GatewayDiagnosticStatus
    let durationMilliseconds: Int?
    let message: String

    var durationDisplay: String {
        guard let durationMilliseconds else { return "-" }
        return "\(durationMilliseconds) ms"
    }
}

struct GatewayDiagnosticReport: Equatable {
    let selectedModel: String
    let checks: [GatewayDiagnosticCheck]

    var hasFailures: Bool {
        checks.contains { $0.status == .failed }
    }

    var passedCount: Int {
        checks.filter { $0.status == .passed }.count
    }

    var failedCount: Int {
        checks.filter { $0.status == .failed }.count
    }

    var skippedCount: Int {
        checks.filter { $0.status == .skipped }.count
    }

    var measuredDurations: [Int] {
        checks.compactMap(\.durationMilliseconds)
    }

    var averageDurationMilliseconds: Int? {
        let durations = measuredDurations
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / durations.count
    }

    var maxDurationMilliseconds: Int? {
        measuredDurations.max()
    }

    var summary: String {
        var parts = ["\(passedCount)/\(checks.count) passed"]
        if failedCount > 0 { parts.append("\(failedCount) failed") }
        if skippedCount > 0 { parts.append("\(skippedCount) skipped") }
        if let averageDurationMilliseconds, let maxDurationMilliseconds {
            parts.append("avg \(averageDurationMilliseconds) ms")
            parts.append("max \(maxDurationMilliseconds) ms")
        }
        return parts.joined(separator: " · ")
    }
}

private enum GatewayDiagnosticValidationError: LocalizedError {
    case invalidJSON(String)
    case invalidOperation(expected: String, actual: String)
    case noUsableOutput(String)
    case unchangedOutput(String)
    case notEnoughCorrectionDetail

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let label):
            return "\(label) did not return valid app JSON."
        case .invalidOperation(let expected, let actual):
            return "Expected \(expected), got \(actual)."
        case .noUsableOutput(let label):
            return "\(label) returned no usable output."
        case .unchangedOutput(let label):
            return "\(label) returned unchanged text."
        case .notEnoughCorrectionDetail:
            return "Complex grammar response did not include enough correction detail."
        }
    }
}

class NetworkManager {
    static let shared = NetworkManager()

    private let transport: NetworkManagerTransporting

    init(transport: NetworkManagerTransporting = URLSession.shared) {
        self.transport = transport
    }

    /// Test connection to gateway with given API key. Uses the authenticated
    /// models endpoint so gateways that do not expose unauthenticated /health
    /// can still validate correctly.
    func testConnection(gatewayURL: String, apiKey: String) async throws -> Bool {
        !((try await fetchModels(gatewayURL: gatewayURL, apiKey: apiKey)).isEmpty)
    }

    /// Run a correction smoke through the same structured chat completions contract
    /// used by the keyboard action path.
    func testCorrectionSmoke(gatewayURL: String, apiKey: String, model: String) async throws {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw NetworkError.modelUnavailable }
        let smokeInput = "i has a apple"
        let content = try await chatCompletionContent(
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            model: trimmedModel,
            operation: "fix_grammar",
            inputText: smokeInput,
            systemPrompt: Self.structuredCorrectionSmokeSystemPrompt,
            userPrompt: Self.structuredCorrectionSmokeUserPrompt(for: smokeInput),
            maxTokens: 1600,
            timeoutInterval: 45
        )
        guard Self.isUsableCorrectionSmokeResponse(content) else {
            throw NetworkError.unusableCorrection
        }
    }

    func runGatewayDiagnostics(gatewayURL: String, apiKey: String, preferredModel: String) async -> GatewayDiagnosticReport {
        let trimmedPreferredModel = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        var models: [String] = []
        var checks: [GatewayDiagnosticCheck] = []

        checks.append(await diagnosticCheck(
            id: "health",
            title: "Health",
            endpoint: "GET /health"
        ) {
            try await checkHealth(gatewayURL: gatewayURL, apiKey: apiKey)
            return "Gateway health is ok."
        })

        checks.append(await diagnosticCheck(
            id: "models",
            title: "Models",
            endpoint: "GET /v1/models"
        ) {
            models = try await fetchModels(gatewayURL: gatewayURL, apiKey: apiKey)
            guard !models.isEmpty else { throw NetworkError.modelUnavailable }
            return "Loaded \(models.count) model\(models.count == 1 ? "" : "s")."
        })

        let modelsCheckPassed = checks.last?.status == .passed
        let candidates = AppConfig.gatewayModelCandidates(from: models, currentModel: trimmedPreferredModel)
        let selectedModel = candidates.first ?? trimmedPreferredModel
        guard !selectedModel.isEmpty, modelsCheckPassed else {
            checks.append(contentsOf: Self.skippedDiagnosticChecks(reason: "Skipped because no model was available."))
            return GatewayDiagnosticReport(selectedModel: selectedModel, checks: checks)
        }

        let settingsSmokeInput = "i has a apple"
        checks.append(await chatDiagnosticCheck(
            id: "settings-correction-smoke",
            title: "Settings correction",
            operation: "fix_grammar",
            inputText: settingsSmokeInput,
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: Self.structuredCorrectionSmokeSystemPrompt,
            userPrompt: Self.structuredCorrectionSmokeUserPrompt(for: settingsSmokeInput),
            maxTokens: 1600
        ) { content in
            let result = try Self.validateStructuredActionContent(content, operation: "fix_grammar", fallbackText: settingsSmokeInput, requireChangedOutput: true)
            guard Self.isUsableCorrectionSmokeResponse("\(content)\n\(result.displayText)") else {
                throw NetworkError.unusableCorrection
            }
            return "Correction smoke returned usable structured JSON."
        })

        let suggestionInput = "i definately recieve teh adress tomorow"
        checks.append(await chatDiagnosticCheck(
            id: "keyboard-suggestion-json",
            title: "Suggestion JSON",
            operation: nil,
            inputText: nil,
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: "You are an iOS keyboard writing assistant. Return strict JSON only.",
            userPrompt: Self.suggestionPrompt(for: suggestionInput),
            maxTokens: 1_200
        ) { content in
            let parsed = try KeyboardSuggestionParser.parseAssistantContent(content)
            let itemCount = parsed.corrections.count + parsed.predictions.count + (parsed.correctedText == nil ? 0 : 1)
            guard itemCount > 0 else { throw GatewayDiagnosticValidationError.noUsableOutput("Suggestion JSON") }
            return "Parsed \(itemCount) suggestion item\(itemCount == 1 ? "" : "s")."
        })

        let complexGrammarInput = "i definately recieve teh adress tomorow, and seperate files wont upload because its recieve limit is to low."
        checks.append(await chatDiagnosticCheck(
            id: "complex-grammar-json",
            title: "Complex grammar JSON",
            operation: "fix_grammar",
            inputText: complexGrammarInput,
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: Self.structuredCorrectionSmokeSystemPrompt,
            userPrompt: Self.structuredCorrectionSmokeUserPrompt(for: complexGrammarInput),
            maxTokens: 5_000
        ) { content in
            let result = try Self.validateStructuredActionContent(content, operation: "fix_grammar", fallbackText: complexGrammarInput, requireChangedOutput: true)
            let correctionCount = result.items.filter { $0.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "correction" }.count
            let expectedTerms = ["definitely", "receive", "address", "tomorrow", "separate", "won't", "too"]
            let displayText = result.displayText.lowercased()
            let hitCount = expectedTerms.filter { displayText.contains($0) || content.lowercased().contains($0) }.count
            guard correctionCount >= 3 || hitCount >= 3 else { throw GatewayDiagnosticValidationError.notEnoughCorrectionDetail }
            return "Parsed \(correctionCount) correction item\(correctionCount == 1 ? "" : "s")."
        })

        let rewriteInput = "hey team the app has issues and we need fix soon please check it"
        checks.append(await chatDiagnosticCheck(
            id: "rewrite-json",
            title: "Rewrite JSON",
            operation: "rewrite",
            inputText: rewriteInput,
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: Self.structuredCorrectionSmokeSystemPrompt,
            userPrompt: Self.rewritePrompt(for: rewriteInput),
            maxTokens: 3_000
        ) { content in
            let result = try Self.validateStructuredActionContent(content, operation: "rewrite", fallbackText: rewriteInput, requireChangedOutput: true)
            return "Parsed rewrite output, \(result.displayText.count) characters."
        })

        let summaryInput = "The keyboard extension now reads the same App Group gateway configuration as the host app. When the user tests the gateway in settings, the app loads models, stores the selected model, and runs a structured correction smoke request so the keyboard can rely on the same endpoint."
        checks.append(await chatDiagnosticCheck(
            id: "summarize-json",
            title: "Summarize JSON",
            operation: "summarize",
            inputText: summaryInput,
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: Self.structuredCorrectionSmokeSystemPrompt,
            userPrompt: Self.summarizePrompt(for: summaryInput),
            maxTokens: 2_000
        ) { content in
            let result = try Self.validateStructuredActionContent(content, operation: "summarize", fallbackText: summaryInput, requireChangedOutput: false)
            return "Parsed summary output, \(result.displayText.count) characters."
        })

        let improveInput = "this message is confusing and it should sound better for the customer"
        checks.append(await chatDiagnosticCheck(
            id: "improve-rewrite-json",
            title: "Improve via Rewrite JSON",
            operation: "rewrite",
            inputText: String(improveInput.prefix(500)),
            model: selectedModel,
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            systemPrompt: Self.structuredCorrectionSmokeSystemPrompt,
            userPrompt: Self.improvePrompt(for: improveInput),
            maxTokens: 3_000
        ) { content in
            let result = try Self.validateStructuredActionContent(content, operation: "rewrite", fallbackText: improveInput, requireChangedOutput: true)
            return "Parsed improve rewrite output, \(result.displayText.count) characters."
        })

        return GatewayDiagnosticReport(selectedModel: selectedModel, checks: checks)
    }

    static func isUsableCorrectionSmokeResponse(_ value: String) -> Bool {
        let normalized = value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !normalized.isEmpty else { return false }
        return normalized.contains("i have an apple") ||
            normalized.contains("i have a apple") ||
            normalized.contains("i had an apple") ||
            (normalized.contains("have") && normalized.contains("apple"))
    }

    private static let structuredCorrectionSmokeSystemPrompt = """
    You are an iOS keyboard text editing assistant. Return strict JSON only.
    Contract: {"operation":"fix_grammar|summarize|rewrite","results":[{"id":"...","type":"correction|suggestion|summary|warning|explanation","title":"...","text":"...","original":"...","replacement":"...","range":{"start":0,"end":0},"confidence":0.0,"explanation":"...","category":"..."}],"summary":"...","corrected_text":"..."}
    Use the requested operation and current text only. Unknown item types are allowed. Do not include markdown.
    """

    private static func structuredCorrectionSmokeUserPrompt(for text: String) -> String {
        """
        Operation: fix_grammar
        Analyze this text and return structured JSON with a results array of correction items. Include category on each correction when possible. Preserve the original meaning and include corrected_text when you can safely produce the full corrected text.

        Text:
        \(text)
        """
    }

    private static func rewritePrompt(for text: String) -> String {
        """
        Operation: rewrite
        Rewrite this text in a clear, friendly tone. Return structured JSON with a rewrite/suggestion item and corrected_text for the full replacement.

        Text:
        \(text)
        """
    }

    private static func summarizePrompt(for text: String) -> String {
        """
        Operation: summarize
        Summarize this text concisely. Return structured JSON with a summary item.

        Text:
        \(text)
        """
    }

    private static func improvePrompt(for text: String) -> String {
        """
        Operation: rewrite
        Improve this text for clarity, tone, and readability. Preserve the original meaning and return structured JSON with a rewrite/suggestion item and corrected_text for the full replacement.

        Text:
        \(text)
        """
    }

    private static func suggestionPrompt(for boundedContext: String) -> String {
        """
        Analyze this bounded keyboard context and return strict JSON only. Do not include markdown or explanations outside JSON.
        Return corrections and predictions separately using this schema:
        {"corrections":[{"label":"Correct capitalization","original":"i","replacement":"I","explanation":"Capitalize the pronoun I.","category":"capitalization"}],"predictions":[{"label":"Suggestion","text":"apple","kind":"nextWord"}]}
        Corrections modify existing text. Predictions are optional next-word/phrase/synonym suggestions. Keep replacements and prediction text short for a compact keyboard bar.
        Context:
        \(String(boundedContext.prefix(500)))
        """
    }

    static func normalizedGatewayBaseURLString(_ value: String) throws -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NetworkError.invalidURL }
        while trimmed.localizedCaseInsensitiveContains("https://https://") {
            trimmed = trimmed.replacingOccurrences(of: "https://https://", with: "https://", options: .caseInsensitive)
        }
        while trimmed.localizedCaseInsensitiveContains("http://http://") {
            trimmed = trimmed.replacingOccurrences(of: "http://http://", with: "http://", options: .caseInsensitive)
        }
        if trimmed.hasPrefix("http:/"), !trimmed.hasPrefix("http://") {
            trimmed = "http://" + trimmed.dropFirst("http:/".count)
        }
        if trimmed.hasPrefix("https:/"), !trimmed.hasPrefix("https://") {
            trimmed = "https://" + trimmed.dropFirst("https:/".count)
        }
        if !trimmed.localizedCaseInsensitiveContains("://") {
            trimmed = "https://" + trimmed
        }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = components.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkError.invalidURL
        }
        components.scheme = scheme
        components.path = components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        if components.path == "/v1" { components.path = "" }
        components.query = nil
        components.fragment = nil
        guard let normalized = components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), !normalized.isEmpty else {
            throw NetworkError.invalidURL
        }
        return normalized
    }

    static func endpointURL(gatewayURL: String, path: String) throws -> URL {
        let base = try normalizedGatewayBaseURLString(gatewayURL)
        let cleanedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/\(cleanedPath)") else { throw NetworkError.invalidURL }
        return url
    }

    static func userFacingSmokeErrorMessage(for error: Error, model: String) -> String {
        let raw = (error as? NetworkError)?.localizedDescription ?? error.localizedDescription
        let lower = raw.lowercased()
        let lowerModel = model.lowercased()
        if let networkError = error as? NetworkError {
            switch networkError {
            case .unauthorized:
                return "API key was rejected by the gateway. Reconnect your gateway in the app."
            case .timeout:
                return "Gateway connected, but the selected model timed out during the test."
            case .modelUnavailable:
                return "The selected model is not available for this key."
            case .unusableCorrection:
                return "Gateway connected, but the selected model did not return a usable correction."
            default:
                break
            }
        }
        if lowerModel.contains("apple-foundationmodel") || lower.contains("foundationmodels") || lower.contains("generationerror") {
            return "Gateway connected, but Apple Foundation model did not respond. Try another key/model."
        }
        if lower.contains("http 500") || lower.contains("server error") {
            return "Gateway connected, but the selected model failed to generate a response."
        }
        if lower.contains("invalid url") || lower.contains("network") || lower.contains("could not connect") {
            return "Could not reach gateway. Check the URL and network."
        }
        return "Gateway connected, but the selected model failed to generate a response."
    }

    /// Fetch available models from gateway
    func fetchModels(gatewayURL: String, apiKey: String) async throws -> [String] {
        let url = try Self.endpointURL(gatewayURL: gatewayURL, path: "v1/models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await transport.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.noData
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw NetworkError.unauthorized
            }

            if httpResponse.statusCode != 200 {
                throw NetworkError.serverError("HTTP \(httpResponse.statusCode)")
            }

            guard let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
                throw NetworkError.noData
            }

            return decoded.data.map(\.id)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.networkError(error)
        }
    }

    private func checkHealth(gatewayURL: String, apiKey: String) async throws {
        let url = try Self.endpointURL(gatewayURL: gatewayURL, path: "health")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await transport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw NetworkError.noData }
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 { throw NetworkError.unauthorized }
            guard httpResponse.statusCode == 200 else { throw NetworkError.serverError("HTTP \(httpResponse.statusCode)") }
            guard !data.isEmpty else { return }
            guard let decoded = try? JSONDecoder().decode(HealthResponse.self, from: data),
                  decoded.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ok" else {
                throw NetworkError.noData
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.networkError(error)
        }
    }

    private func chatCompletionContent(
        gatewayURL: String,
        apiKey: String,
        model: String,
        operation: String?,
        inputText: String?,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        timeoutInterval: TimeInterval
    ) async throws -> String {
        let url = try Self.endpointURL(gatewayURL: gatewayURL, path: "v1/chat/completions")
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw NetworkError.modelUnavailable }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval
        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: trimmedModel,
            operation: operation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            inputText: inputText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
            ],
            maxTokens: maxTokens,
            temperature: 0.1,
            stream: false
        ))

        do {
            let (data, response) = try await transport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw NetworkError.noData }
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 { throw NetworkError.unauthorized }
            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                throw NetworkError.serverError(body)
            }
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !content.isEmpty else { throw NetworkError.unusableCorrection }
            return content
        } catch let error as NetworkError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw NetworkError.timeout
        } catch DecodingError.dataCorrupted, DecodingError.keyNotFound, DecodingError.typeMismatch, DecodingError.valueNotFound {
            throw NetworkError.unusableCorrection
        } catch {
            throw NetworkError.networkError(error)
        }
    }

    private func diagnosticCheck(
        id: String,
        title: String,
        endpoint: String,
        operation: () async throws -> String
    ) async -> GatewayDiagnosticCheck {
        let started = Date()
        do {
            let message = try await operation()
            return GatewayDiagnosticCheck(
                id: id,
                title: title,
                endpoint: endpoint,
                status: .passed,
                durationMilliseconds: Self.durationMilliseconds(since: started),
                message: message
            )
        } catch {
            return GatewayDiagnosticCheck(
                id: id,
                title: title,
                endpoint: endpoint,
                status: .failed,
                durationMilliseconds: Self.durationMilliseconds(since: started),
                message: Self.diagnosticMessage(for: error)
            )
        }
    }

    private func chatDiagnosticCheck(
        id: String,
        title: String,
        operation: String?,
        inputText: String?,
        model: String,
        gatewayURL: String,
        apiKey: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        validation: (String) throws -> String
    ) async -> GatewayDiagnosticCheck {
        await diagnosticCheck(id: id, title: title, endpoint: "POST /v1/chat/completions") {
            let content = try await chatCompletionContent(
                gatewayURL: gatewayURL,
                apiKey: apiKey,
                model: model,
                operation: operation,
                inputText: inputText,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: maxTokens,
                timeoutInterval: 90
            )
            return try validation(content)
        }
    }

    private static func validateStructuredActionContent(_ content: String, operation: String, fallbackText: String, requireChangedOutput: Bool) throws -> KeyboardActionOperationResult {
        let result: KeyboardActionOperationResult
        do {
            result = try KeyboardActionOperationResult.parse(content, operation: operation, fallbackText: fallbackText)
        } catch {
            throw GatewayDiagnosticValidationError.invalidJSON(operation)
        }
        if result.operation.trimmingCharacters(in: .whitespacesAndNewlines) != operation {
            throw GatewayDiagnosticValidationError.invalidOperation(expected: operation, actual: result.operation)
        }
        guard result.isStructuredResponse else { throw GatewayDiagnosticValidationError.invalidJSON(operation) }
        let output = result.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw GatewayDiagnosticValidationError.noUsableOutput(operation) }
        if requireChangedOutput && output.caseInsensitiveCompare(fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
            throw GatewayDiagnosticValidationError.unchangedOutput(operation)
        }
        return result
    }

    private static func skippedDiagnosticChecks(reason: String) -> [GatewayDiagnosticCheck] {
        [
            ("settings-correction-smoke", "Settings correction"),
            ("keyboard-suggestion-json", "Suggestion JSON"),
            ("complex-grammar-json", "Complex grammar JSON"),
            ("rewrite-json", "Rewrite JSON"),
            ("summarize-json", "Summarize JSON"),
            ("improve-rewrite-json", "Improve via Rewrite JSON")
        ].map { id, title in
            GatewayDiagnosticCheck(
                id: id,
                title: title,
                endpoint: "POST /v1/chat/completions",
                status: .skipped,
                durationMilliseconds: nil,
                message: reason
            )
        }
    }

    private static func durationMilliseconds(since started: Date) -> Int {
        max(0, Int((Date().timeIntervalSince(started) * 1000).rounded()))
    }

    private static func diagnosticMessage(for error: Error) -> String {
        let raw: String
        if let networkError = error as? NetworkError {
            raw = networkError.localizedDescription
        } else if error is KeyboardSuggestionParserError {
            raw = "Suggestion JSON did not return valid app JSON."
        } else if let localized = error as? LocalizedError, let description = localized.errorDescription {
            raw = description
        } else {
            raw = error.localizedDescription
        }
        return KeyboardActionErrorState.sanitized(raw)
    }
}


private struct ChatCompletionRequest: Encodable {
    let model: String
    let operation: String?
    let inputText: String?
    let messages: [ChatMessage]
    let maxTokens: Int
    let temperature: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case operation
        case inputText = "input_text"
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case stream
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct ModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
}

private struct HealthResponse: Decodable {
    let status: String
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}
