//
//  PlaygroundView.swift
//  OpenKeyboard
//
//  Product-facing screen where users can try Open Keyboard in a real text field.
//

import SwiftUI

struct PlaygroundView: View {
    @State private var text = Self.initialText
    @State private var gatewayProofStatus = "Checking gateway…"
    @State private var isCheckingGateway = false
    @State private var regressionResult: PlaygroundAnalysisResult?

    private static var isWritingAssistantProofMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--playground-writing-assistant-proof")
    }

    private static var isGatewayProofMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--playground-gateway-proof")
    }

    private static var isRegressionProofMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--playground-all-good-regression-proof")
    }

    private static var initialText: String {
        if isWritingAssistantProofMode { return "Yesterday I has a apple before the meeting, and ths message still sound wrong when I send it to the client." }
        if isGatewayProofMode || isRegressionProofMode { return "Yesterday I has a apple before the meeting, and ths message still sound wrong when I send it to the client." }
        return "Yesterday I has a apple before the meeting, and ths message still sound wrong when I send it to the client."
    }

    private var proofCard: KeyboardCorrectionCard {
        KeyboardCorrectionCard(correction: KeyboardCorrectionSuggestion(
            label: "Subject-verb agreement",
            original: "has",
            replacement: "have",
            explanation: "Use “have” because the subject is plural.",
            category: "grammar"
        ))
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Type here with Open Keyboard selected to try your AI writing actions in a real text field.")
                        .font(.subheadline)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .fixedSize(horizontal: false, vertical: true)

                    if Self.isGatewayProofMode {
                        PlaygroundGatewayProofCard(
                            status: gatewayProofStatus,
                            isChecking: isCheckingGateway,
                            onRetry: { Task { await runGatewayProofCheck() } }
                        )
                        .accessibilityIdentifier("playground_gateway_proof_card")
                    }

                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 150)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .background(OpenKeyboardTheme.Surface.panelBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Try typing: Can you make this sound friendlier?")
                                    .font(.body)
                                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                                    .padding(.horizontal, 17)
                                    .padding(.vertical, 20)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(OpenKeyboardTheme.Stroke.subtle, lineWidth: 1)
                        )
                        .accessibilityIdentifier("playground_text_input")

                    if let regressionResult {
                        PlaygroundAnalysisResultView(result: regressionResult)
                            .accessibilityIdentifier("playground_analysis_result")
                    }

                    if Self.isWritingAssistantProofMode {
                        PlaygroundCorrectionProofCard(card: proofCard)
                            .accessibilityIdentifier("playground_writing_assistant_correction_card")
                    }

                    Text("Tip: if the standard keyboard appears, switch keyboards from the globe key and choose Open Keyboard.")
                        .font(.footnote)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
        }
        .navigationTitle("Playground")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if Self.isGatewayProofMode {
                await runGatewayProofCheck()
            }
            if Self.isRegressionProofMode {
                runRegressionProofCheck()
            }
        }
    }

    @MainActor
    private func runRegressionProofCheck() {
        let content = """
        {
          "issue_count": 4,
          "overall_status": "issues_found",
          "corrected_text": "I have an apple; this does not sound right.",
          "corrections": [
            {"id":"subject-verb","category":"grammar","label":"Subject-verb agreement","original":"i has","replacement":"I have","explanation":"Use “I have” for first-person agreement."},
            {"id":"article","category":"grammar","label":"Article","original":"a apple","replacement":"an apple","explanation":"Use “an” before a vowel sound."},
            {"id":"spelling-this","category":"spelling","label":"Spelling","original":"ths","replacement":"this","explanation":"Correct the misspelling."},
            {"id":"spelling-not","category":"spelling","label":"Spelling","original":"nt","replacement":"not","explanation":"Expand the missing vowel."}
          ],
          "summary":"Four issues found."
        }
        """
        do {
            let response = try KeyboardSuggestionParser.parseAssistantContent(content)
            let cards = response.corrections.map(KeyboardCorrectionCard.init(correction:))
            regressionResult = cards.isEmpty ? .failure("Analysis failed. No usable suggestions were returned for broken input.") : .suggestions(cards)
        } catch {
            regressionResult = .failure("Analysis failed. The model output was unusable for this broken input.")
        }
    }

    @MainActor
    private func runGatewayProofCheck() async {
        guard !isCheckingGateway else { return }
        isCheckingGateway = true
        defer { isCheckingGateway = false }

        let config = AppConfig.load()
        let gatewayURL = config.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gatewayURL.isEmpty, !apiKey.isEmpty, !model.isEmpty else {
            gatewayProofStatus = "Analysis failed. Gateway is not configured. Reconnect your gateway in the app."
            return
        }

        do {
            try await NetworkManager.shared.testCorrectionSmoke(
                gatewayURL: gatewayURL,
                apiKey: apiKey,
                model: model
            )
            gatewayProofStatus = "Gateway correction succeeded for the current Playground text."
        } catch {
            let message = NetworkManager.userFacingSmokeErrorMessage(for: error, model: model)
            gatewayProofStatus = "Analysis failed. \(message)"
        }
    }
}

private struct KeyboardCorrectionCard: Equatable, Identifiable {
    let id: String
    let categoryTitle: String
    let original: String
    let replacement: String
    let explanation: String

    init(correction: KeyboardCorrectionSuggestion) {
        id = correction.id
        categoryTitle = correction.category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? correction.category!.capitalized
            : correction.label
        original = correction.original
        replacement = correction.replacement
        explanation = correction.explanation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? correction.explanation!
            : correction.label
    }
}

private enum PlaygroundAnalysisResult: Equatable {
    case suggestions([KeyboardCorrectionCard])
    case failure(String)
    case allGood
}

private struct PlaygroundAnalysisResultView: View {
    let result: PlaygroundAnalysisResult

    var body: some View {
        switch result {
        case .suggestions(let cards):
            VStack(alignment: .leading, spacing: 12) {
                Text("Writing suggestions")
                    .font(.headline.weight(.bold))
                    .accessibilityIdentifier("playground_suggestions_title")
                PlaygroundCorrectionCarousel(cards: cards)
                Text("Local regression proof uses the shared structured parser contract for this exact sample.")
                    .font(.caption)
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
            }
            .accessibilityIdentifier("playground_suggestions_card")
        case .failure(let message):
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(OpenKeyboardTheme.Semantic.error)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OpenKeyboardTheme.Surface.errorBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier("playground_analysis_failure")
        case .allGood:
            VStack(alignment: .leading, spacing: 4) {
                Text("All Good")
                    .font(.headline.weight(.bold))
                Text("No issues found.")
                    .font(.subheadline)
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OpenKeyboardTheme.Surface.successBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier("playground_all_good_card")
        }
    }
}


private struct PlaygroundCorrectionCarousel: View {
    let cards: [KeyboardCorrectionCard]
    @State private var currentIndex = 0

    private var clampedIndex: Int {
        min(max(currentIndex, 0), max(cards.count - 1, 0))
    }

    var body: some View {
        if let card = cards[safe: clampedIndex] {
            VStack(spacing: 10) {
                PlaygroundCorrectionProofCard(card: card)
                    .id(clampedIndex)
                    .accessibilityIdentifier("playground_correction_card_\(clampedIndex + 1)")

                if cards.count > 1 {
                    HStack(spacing: 10) {
                        Button(action: movePrevious) {
                            Image(systemName: "chevron.left")
                                .frame(width: 34, height: 30)
                        }
                        .buttonStyle(.plain)
                        .disabled(clampedIndex == 0)
                        .opacity(clampedIndex == 0 ? 0.35 : 1)
                        .accessibilityIdentifier("playground_correction_previous")

                        Text("\(clampedIndex + 1) of \(cards.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("playground_correction_progress")

                        Button(action: moveNext) {
                            Image(systemName: "chevron.right")
                                .frame(width: 34, height: 30)
                        }
                        .buttonStyle(.plain)
                        .disabled(clampedIndex + 1 >= cards.count)
                        .opacity(clampedIndex + 1 >= cards.count ? 0.35 : 1)
                        .accessibilityIdentifier("playground_correction_next")
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 28)
                    .onEnded { value in
                        if value.translation.width < -32 { moveNext() }
                        if value.translation.width > 32 { movePrevious() }
                    }
            )
        }
    }

    private func movePrevious() {
        guard clampedIndex > 0 else { return }
        currentIndex = clampedIndex - 1
    }

    private func moveNext() {
        guard clampedIndex + 1 < cards.count else { return }
        currentIndex = clampedIndex + 1
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct PlaygroundGatewayProofCard: View {
    let status: String
    let isChecking: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: isChecking ? "clock.arrow.circlepath" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isChecking ? OpenKeyboardTheme.Semantic.primaryAction : OpenKeyboardTheme.Semantic.error)
                    .frame(width: 34, height: 34)
                    .background(OpenKeyboardTheme.Surface.panelBackground, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Live gateway check")
                        .font(.headline.weight(.bold))
                    Text(status)
                        .font(.subheadline)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("playground_gateway_status")
                }
            }

            Button(action: onRetry) {
                Text(isChecking ? "Checking…" : "Retry Gateway Check")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.plain)
            .foregroundColor(OpenKeyboardTheme.Text.inverse)
            .background(OpenKeyboardTheme.Semantic.primaryAction, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(isChecking)
            .accessibilityIdentifier("playground_gateway_retry")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenKeyboardTheme.Surface.overlayBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(OpenKeyboardTheme.Semantic.warning.opacity(0.55), lineWidth: 1.2)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct PlaygroundCorrectionProofCard: View {
    let card: KeyboardCorrectionCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(OpenKeyboardTheme.Text.inverse)
                    .frame(width: 34, height: 34)
                    .background(OpenKeyboardTheme.Semantic.error, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.categoryTitle)
                        .font(.headline.weight(.bold))
                    Text(card.explanation)
                        .font(.caption)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                token(title: "Replace", value: card.original, tint: OpenKeyboardTheme.Semantic.error, strikethrough: true)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                token(title: "With", value: card.replacement, tint: OpenKeyboardTheme.Semantic.primaryAction, strikethrough: false)
            }

            HStack(spacing: 10) {
                Button("Apply") {}
                    .font(.headline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(OpenKeyboardTheme.Text.inverse)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(OpenKeyboardTheme.Semantic.primaryAction, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("playground_correction_apply")

                Button("Dismiss") {}
                    .font(.headline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(OpenKeyboardTheme.Semantic.error)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(OpenKeyboardTheme.Semantic.error, lineWidth: 1.2)
                    )
                    .accessibilityIdentifier("playground_correction_dismiss")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenKeyboardTheme.Surface.overlayBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(OpenKeyboardTheme.Semantic.error.opacity(0.55), lineWidth: 1.2)
        )
    }

    private func token(title: String, value: String, tint: Color, strikethrough: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                .textCase(.uppercase)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(tint)
                .lineLimit(1)
                .strikethrough(strikethrough, color: tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenKeyboardTheme.Surface.panelBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PlaygroundView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PlaygroundView()
        }
    }
}
