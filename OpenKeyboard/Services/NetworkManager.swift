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

    /// Run a low-cost correction smoke through the actual chat completions path.
    func testCorrectionSmoke(gatewayURL: String, apiKey: String, model: String) async throws {
        let url = try Self.endpointURL(gatewayURL: gatewayURL, path: "v1/chat/completions")
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw NetworkError.modelUnavailable }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: trimmedModel,
            messages: [
                ChatMessage(role: "system", content: "You are a keyboard grammar checker. Return only one corrected sentence. Do not explain."),
                ChatMessage(role: "user", content: "Correct this sentence and return the full corrected sentence only: i has a apple")
            ],
            maxTokens: 80,
            temperature: 0,
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
            let content = decoded.choices.first?.message.content ?? ""
            guard Self.isUsableCorrectionSmokeResponse(content) else { throw NetworkError.unusableCorrection }
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

    static func isUsableCorrectionSmokeResponse(_ value: String) -> Bool {
        let normalized = value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !normalized.isEmpty else { return false }
        return normalized.contains("i have an apple") ||
            normalized.contains("i have a apple") ||
            normalized.contains("i had an apple") ||
            (normalized.contains("have") && normalized.contains("apple"))
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
}


private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int
    let temperature: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case stream
    }
}

private struct ModelsResponse: Decodable {
    let data: [Model]

    struct Model: Decodable {
        let id: String
    }
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
