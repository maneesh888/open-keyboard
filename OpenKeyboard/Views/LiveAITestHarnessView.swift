#if DEBUG
import SwiftUI

struct LiveAITestHarnessView: View {
    @State private var inputText = ""
    @State private var statusText = "Ready"
    @State private var isLoading = false

    private let environment = ProcessInfo.processInfo.environment
    private let arguments = ProcessInfo.processInfo.arguments

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Live AI Test Harness")
                    .font(.title2.bold())
                    .accessibilityIdentifier("live_ai_title")

                TextEditor(text: $inputText)
                    .font(.body)
                    .frame(minHeight: 180)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("live_ai_text_editor")

                VStack(spacing: 12) {
                    Button {
                        run(action: "fix_grammar")
                    } label: {
                        Label("Fix Grammar", systemImage: "text.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                    .accessibilityIdentifier("live_ai_fix_grammar_button")

                    Button {
                        run(action: "improve")
                    } label: {
                        Label("Improve", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                    .accessibilityIdentifier("live_ai_improve_button")

                    Button {
                        run(action: "summarize")
                    } label: {
                        Label("Summarize", systemImage: "text.alignleft")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                    .accessibilityIdentifier("live_ai_summarize_button")
                }

                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(statusText.lowercased().contains("error") ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("live_ai_status")

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func run(action: String) {
        let original = inputText
        isLoading = true
        statusText = "Loading"

        Task {
            do {
                let output = try await performLiveAction(action: action, text: original)
                await MainActor.run {
                    inputText = output
                    statusText = "Success"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    inputText = original
                    statusText = "Error: \(userMessage(for: error))"
                    isLoading = false
                }
            }
        }
    }

    private func performLiveAction(action: String, text: String) async throws -> String {
        guard let gatewayURLString = environment["OPEN_KEYBOARD_LIVE_GATEWAY_URL"],
              let gatewayURL = URL(string: gatewayURLString),
              let model = environment["OPEN_KEYBOARD_LIVE_MODEL"],
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiveAITestHarnessError.missingConfiguration
        }

        var apiKey = environment["OPEN_KEYBOARD_LIVE_API_KEY"] ?? ""
        if arguments.contains("--live-ai-invalid-key") {
            apiKey = "invalid-open-keyboard-ui-test-key"
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiveAITestHarnessError.missingConfiguration
        }

        var request = URLRequest(url: gatewayURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: model,
            operation: action,
            inputText: String(text.prefix(500)),
            messages: [
                ChatMessage(role: "system", content: Self.structuredOperationSystemPrompt),
                ChatMessage(role: "user", content: prompt(for: action, text: text))
            ],
            maxTokens: 1600,
            temperature: 0.1,
            stream: false
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LiveAITestHarnessError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LiveAITestHarnessError.httpStatus(http.statusCode)
        }

        let completion = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = completion.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw LiveAITestHarnessError.invalidResponse
        }

        let result = try KeyboardActionOperationResult.parse(content, operation: action, fallbackText: text)
        let output = result.displayText
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiveAITestHarnessError.invalidResponse
        }
        return output
    }

    private static let structuredOperationSystemPrompt = """
    You are an iOS keyboard text editing assistant. Return strict JSON only.
    Contract: {"operation":"fix_grammar|summarize|improve","results":[{"id":"...","type":"correction|suggestion|summary|warning|explanation","title":"...","text":"...","original":"...","replacement":"...","range":{"start":0,"end":0},"confidence":0.0,"explanation":"...","category":"..."}],"summary":"...","corrected_text":"..."}
    Use the requested operation and current text only. Unknown item types are allowed. Do not include markdown.
    """

    private func prompt(for action: String, text: String) throws -> String {
        switch action {
        case "fix_grammar":
            return """
            Operation: fix_grammar
            Analyze this text and return structured JSON with a results array of correction items. Include category on each correction when possible. Preserve the original meaning and include corrected_text when you can safely produce the full corrected text.

            Text:
            \(text)
            """
        case "improve":
            return """
            Operation: improve
            Improve this text for clarity, tone, and readability. Preserve the original meaning and return structured JSON with a suggestion item and corrected_text for the full replacement.

            Text:
            \(text)
            """
        case "summarize":
            return """
            Operation: summarize
            Summarize this text concisely. Return structured JSON with a summary item.

            Text:
            \(text)
            """
        default:
            throw LiveAITestHarnessError.unsupportedAction
        }
    }

    private func userMessage(for error: Error) -> String {
        if let harnessError = error as? LiveAITestHarnessError {
            return harnessError.userMessage
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "Gateway request timed out"
        }
        return "Gateway request failed"
    }
}

private enum LiveAITestHarnessError: Error {
    case missingConfiguration
    case unsupportedAction
    case invalidResponse
    case httpStatus(Int)

    var userMessage: String {
        switch self {
        case .missingConfiguration:
            return "Missing live gateway test configuration"
        case .unsupportedAction:
            return "Unsupported live AI action"
        case .invalidResponse:
            return "Invalid gateway response"
        case .httpStatus(let status):
            if status == 401 || status == 403 {
                return "Gateway authorization failed"
            }
            return "Gateway HTTP \(status)"
        }
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let operation: String
    let inputText: String
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

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatMessage
}
#endif
