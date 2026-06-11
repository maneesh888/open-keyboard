//
//  KeyboardVisualPreviewView.swift
//  OpenKeyboard
//

import SwiftUI

struct KeyboardPreviewLabView: View {
    @State private var selectedState: KeyboardPreviewLabState = .ready

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard Preview Lab")
                            .font(.largeTitle.weight(.bold))
                        Text("Safe deterministic previews for the future Grammarly-style correction flow. No private typed text or live debug internals are exposed here.")
                            .font(.subheadline)
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    }
                    .padding(.horizontal, 20)

                    Picker("Preview state", selection: $selectedState) {
                        ForEach(KeyboardPreviewLabState.allCases) { state in
                            Text(state.title).tag(state)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .accessibilityIdentifier("keyboard_preview_lab_state_picker")

                    VStack(alignment: .leading, spacing: 10) {
                        Text(selectedState.title)
                            .font(.headline.weight(.semibold))
                        Text(description(for: selectedState))
                            .font(.caption)
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OpenKeyboardTheme.Surface.brandCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(OpenKeyboardTheme.Stroke.subtle, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    KeyboardVisualPreviewView(panel: selectedState.previewPanel)
                        .frame(minHeight: 390)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .padding(.horizontal, 12)
                }
                .padding(.vertical, 18)
            }
        }
        .navigationTitle("Keyboard Preview Lab")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("keyboard_preview_lab")
    }

    private func description(for state: KeyboardPreviewLabState) -> String {
        switch state {
        case .ready:
            return "Ready state: top-left shows the approved OpenKeyboard icon and the right sparkle opens AI actions."
        case .issue:
            return "Detected issue state: top-left changes to a count badge so it is visibly different from zero issues."
        case .correctionCard:
            return "First compact suggestion: one focused replacement token, not the full corrected sentence."
        case .correctionCardNext:
            return "Next compact suggestion after applying the first token; this models recursive issue handling."
        case .correctionOnly:
            return "Correction-only compact state with no prediction lane."
        case .predictionOnly:
            return "Prediction-only compact state with no correction count confusion."
        case .correctionDetail:
            return "Detail panel shown after tapping the issue count/card; this is where apply/dismiss can wire into the replacement planner later."
        case .actions:
            return "Right sparkle assistant panel with Improve, Rephrase, and Summarize actions."
        case .correctionComplete:
            return "Completion panel after suggestions are resolved."
        }
    }
}

struct KeyboardVisualPreviewView: View {
    let panel: KeyboardVisualPreviewPanel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 7) {
                previewToolbar

                switch panel {
                case .keyboard, .issue:
                    keyGrid
                case .correctionCard, .correctionCardNext, .correctionOnly, .predictionOnly:
                    keyGrid
                case .correctionDetail:
                    correctionDetailPanel
                case .actions:
                    actionPanel
                case .correctionComplete:
                    correctionCompletePanel
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(OpenKeyboardTheme.Surface.keyboardBackground)
            .accessibilityIdentifier("keyboard_visual_preview")
        }
        .background(OpenKeyboardTheme.Surface.panelBackground)
        .ignoresSafeArea(.keyboard)
    }

    private struct PreviewToolbarDisplay {
        let title: String
        let subtitle: String
        let issueCount: Int

        var showsIssueCount: Bool { issueCount > 0 }
    }

    private var toolbarState: PreviewToolbarDisplay {
        switch panel {
        case .keyboard, .actions, .correctionComplete:
            return PreviewToolbarDisplay(title: "Open Keyboard AI", subtitle: "Ready", issueCount: 0)
        case .issue:
            return PreviewToolbarDisplay(title: "2 writing suggestions", subtitle: "Spelling and grammar suggestions", issueCount: 2)
        case .correctionCard, .correctionCardNext, .correctionOnly, .correctionDetail:
            return PreviewToolbarDisplay(title: "1 writing suggestion", subtitle: panel == .correctionCardNext ? "Next grammar suggestion" : "Subject-verb agreement", issueCount: 1)
        case .predictionOnly:
            return PreviewToolbarDisplay(title: "Open Keyboard AI", subtitle: "Suggestion", issueCount: 0)
        }
    }


    private var panelState: KeyboardPreviewLabState {
        switch panel {
        case .keyboard: return .ready
        case .issue: return .issue
        case .correctionCard: return .correctionCard
        case .correctionCardNext: return .correctionCardNext
        case .correctionOnly: return .correctionOnly
        case .predictionOnly: return .predictionOnly
        case .correctionDetail: return .correctionDetail
        case .actions: return .actions
        case .correctionComplete: return .correctionComplete
        }
    }

    private var previewToolbar: some View {
        HStack(spacing: 8) {
            previewStatusIcon

            previewToolbarContent
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((panel == .correctionCard || panel == .correctionCardNext || panel == .correctionOnly || panel == .predictionOnly) ? OpenKeyboardTheme.Surface.overlayBackground : OpenKeyboardTheme.Surface.brandPanelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke((panel == .correctionCard || panel == .correctionCardNext || panel == .correctionOnly || panel == .predictionOnly) ? OpenKeyboardTheme.Semantic.error.opacity(0.42) : Color.clear, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Text.inverse)
                .frame(width: 34, height: 34)
                .background(OpenKeyboardTheme.Semantic.primaryAction)
                .clipShape(Circle())
                .accessibilityIdentifier("preview_ai_sparkle_action")
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(OpenKeyboardTheme.Surface.toolbarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("preview_ai_toolbar")
    }

    @ViewBuilder
    private var previewToolbarContent: some View {
        if (panel == .correctionCard || panel == .correctionCardNext || panel == .correctionOnly || panel == .predictionOnly) {
            HStack(spacing: 6) {
                if panel != .predictionOnly {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(panelState.compactSuggestion?.label ?? "Correct grammar:")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                            .lineLimit(1)
                        Text(panelState.compactSuggestion?.replacement ?? "I")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(OpenKeyboardTheme.Semantic.primaryAction)
                            .lineLimit(1)
                    }
                    .layoutPriority(2)
                }

                if let prediction = panelState.compactSuggestion?.prediction {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(panel == .predictionOnly ? "Suggestion" : "Next word")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                            .lineLimit(1)
                        Text(prediction)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(OpenKeyboardTheme.Surface.panelBackground.opacity(0.86), in: Capsule())
                    .overlay(
                        Capsule().stroke(OpenKeyboardTheme.Stroke.control.opacity(0.7), lineWidth: 1)
                    )
                    .accessibilityIdentifier("preview_prediction_chip")
                }

                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
            }
            .accessibilityIdentifier("preview_compact_correction_strip")
        } else {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(toolbarState.title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(toolbarState.subtitle)
                        .font(.caption2)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
        }
    }

    private var previewStatusIcon: some View {
        ZStack {
            if toolbarState.showsIssueCount {
                Circle().fill(OpenKeyboardTheme.Semantic.error)
                Text("\(toolbarState.issueCount)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(OpenKeyboardTheme.Text.inverse)
            } else {
                OpenKeyboardBrandMark(size: 36, symbolSize: 16)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityIdentifier(toolbarState.showsIssueCount ? "preview_issue_count_badge" : "preview_openkeyboard_icon")
    }

    private var keyGrid: some View {
        VStack(spacing: 8) {
            previewKeyRow(["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"])
            previewKeyRow(["a", "s", "d", "f", "g", "h", "j", "k", "l"])
                .padding(.horizontal, 18)

            HStack(spacing: 6) {
                previewKey("⇧", role: .modifier).frame(width: 52)
                previewKeyRow(["z", "x", "c", "v", "b", "n", "m"])
                previewKey("⌫", role: .modifier).frame(width: 52)
            }

            HStack(spacing: 6) {
                previewKey("123", role: .modifier).frame(width: 58)
                previewKey("🌐", role: .modifier).frame(width: 52)
                previewKey("space", role: .space)
                previewKey("return", role: .modifier).frame(width: 92)
            }
        }
        .accessibilityIdentifier("preview_keyboard_grid")
    }

    private var correctionDetailPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Correct grammar")
                    .font(.headline.weight(.bold))
                Spacer()
                Text("1 issue")
                    .font(.caption.weight(.bold))
                    .foregroundColor(OpenKeyboardTheme.Text.inverse)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(OpenKeyboardTheme.Semantic.error, in: Capsule())
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Problem")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                Text("i has a apple")
                    .font(.body.weight(.semibold))
                    .foregroundColor(OpenKeyboardTheme.Semantic.error.opacity(0.9))
                    .strikethrough(color: OpenKeyboardTheme.Semantic.error)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggestion")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                Text("I have an apple.")
                    .font(.title3.weight(.bold))
                    .foregroundColor(OpenKeyboardTheme.Semantic.primaryAction)
            }
            HStack(spacing: 10) {
                detailButton("Apply", filled: true)
                detailButton("Dismiss", filled: false, tint: OpenKeyboardTheme.Semantic.error)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 232, alignment: .topLeading)
        .background(OpenKeyboardTheme.Surface.overlayBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(OpenKeyboardTheme.Semantic.error.opacity(0.55), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("preview_correction_detail_panel")
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(OpenKeyboardTheme.Brand.blueGreenGradient)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(OpenKeyboardTheme.Text.inverse)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Improve your writing")
                        .font(.headline.weight(.semibold))
                    Text("Choose what Open Keyboard should do next.")
                        .font(.caption)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
                    .background(OpenKeyboardTheme.Surface.panelBackground.opacity(0.98))
                    .overlay(Circle().stroke(OpenKeyboardTheme.Stroke.control, lineWidth: 1))
                    .clipShape(Circle())
            }

            VStack(spacing: 8) {
                previewAction("Improve", subtitle: "Fix grammar and clarity", systemImage: "sparkles", isPrimary: true)
                previewAction("Rephrase", subtitle: "Make the sentence flow better", systemImage: "arrow.triangle.2.circlepath", isPrimary: false)
                previewAction("Summarize", subtitle: "Shorten the selected thought", systemImage: "text.bubble", isPrimary: false)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 232, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(OpenKeyboardTheme.Surface.overlayBackground)
                .shadow(color: OpenKeyboardTheme.Shadow.overlay, radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(OpenKeyboardTheme.Semantic.primaryAction.opacity(0.55), lineWidth: 1.2)
        )
        .padding(.horizontal, 2)
        .accessibilityIdentifier("preview_ai_action_panel")
    }

    private var correctionCompletePanel: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(OpenKeyboardTheme.Brand.blueGreenGradient)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(OpenKeyboardTheme.Text.inverse)
            }
            .frame(width: 64, height: 64)
            .padding(.bottom, 4)

            Text("All Done")
                .font(.title3.weight(.bold))

            Text("There are no more suggestions.")
                .font(.subheadline)
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

            Text("Back to Keyboard")
                .font(.headline.weight(.semibold))
                .foregroundColor(OpenKeyboardTheme.Semantic.primaryAction)
                .padding(.horizontal, 18)
                .frame(minHeight: 42)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(OpenKeyboardTheme.Semantic.primaryAction, lineWidth: 1.5)
                )
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 226)
        .padding(.horizontal, 18)
        .padding(.vertical, 26)
        .background(OpenKeyboardTheme.Surface.overlayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("preview_correction_complete_panel")
    }

    private func previewKeyRow(_ keys: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { previewKey($0, role: .letter) }
        }
    }

    private enum PreviewKeyRole {
        case letter
        case modifier
        case space
    }

    private func previewKey(_ label: String, role: PreviewKeyRole) -> some View {
        Text(label)
            .font(previewKeyFont(label, role: role))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, minHeight: role == .letter ? 52 : 46)
            .background(role == .modifier ? OpenKeyboardTheme.Surface.modifierKeyBackground : OpenKeyboardTheme.Surface.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: OpenKeyboardTheme.Shadow.key, radius: 0, x: 0, y: 1)
    }

    private func previewKeyFont(_ label: String, role: PreviewKeyRole) -> Font {
        switch role {
        case .letter: return .system(size: 25, weight: .regular)
        case .space: return .system(size: 16, weight: .regular)
        case .modifier: return .system(size: label.count > 2 ? 16 : 22, weight: .regular)
        }
    }

    private func previewAction(_ title: String, subtitle: String, systemImage: String, isPrimary: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundColor(isPrimary ? OpenKeyboardTheme.Text.inverse : OpenKeyboardTheme.Semantic.primaryAction)
                .background(isPrimary ? OpenKeyboardTheme.Semantic.primaryAction : OpenKeyboardTheme.Surface.iconBackground)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.horizontal, 12)
        .foregroundColor(.primary)
        .background(OpenKeyboardTheme.Surface.panelBackground.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isPrimary ? OpenKeyboardTheme.Semantic.primaryAction.opacity(0.9) : OpenKeyboardTheme.Stroke.control.opacity(0.75), lineWidth: isPrimary ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func detailButton(_ title: String, filled: Bool, tint: Color = OpenKeyboardTheme.Semantic.primaryAction) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(filled ? OpenKeyboardTheme.Text.inverse : tint)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(filled ? tint : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint, lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
