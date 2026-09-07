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

        let rendering = KeyboardGatewayActionContract.rendering(operation: action, text: text)
        let profile = try OpenKeyboardGatewayProfile(
            gatewayURL: gatewayURLString,
            apiKey: apiKey
        )
        let request = try OpenKeyboardAIRequest.writing(
            rendering: rendering,
            modelID: model,
            timeoutInterval: 90
        )
        let response = try await OpenKeyboardRequestDeadline.value(timeoutInterval: 90) {
            try await UniversalAIConnectorAdapter.shared.respond(to: request, profile: profile)
        }

        let result: KeyboardActionOperationResult
        if action == "fix_grammar" {
            result = try KeyboardActionOperationResult.plainTextGrammarResponse(
                response,
                original: text
            )
        } else {
            result = try KeyboardActionOperationResult.plainTextResponse(
                response,
                rendering: rendering,
                title: action == "summarize" ? "Summarize" : "Improve",
                source: text
            )
        }
        let output = result.displayText
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiveAITestHarnessError.invalidResponse
        }
        return output
    }

    private func userMessage(for error: Error) -> String {
        if let harnessError = error as? LiveAITestHarnessError {
            return harnessError.userMessage
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "Gateway request timed out"
        }
        if let connectorError = error as? OpenKeyboardAIConnectorError {
            switch connectorError {
            case .unauthorized, .forbidden:
                return "Gateway authorization failed"
            case .timeout:
                return "Gateway request timed out"
            case .serverStatus(let status):
                return "Gateway HTTP \(status)"
            default:
                return "Gateway request failed"
            }
        }
        return "Gateway request failed"
    }
}

private enum LiveAITestHarnessError: Error {
    case missingConfiguration
    case invalidResponse

    var userMessage: String {
        switch self {
        case .missingConfiguration:
            return "Missing live gateway test configuration"
        case .invalidResponse:
            return "Invalid gateway response"
        }
    }
}
#endif
