#if DEBUG
//
//  KeyboardVisualPreviewView.swift
//  OpenKeyboard
//

import SwiftUI

private enum KeyboardVisualPreviewLayout {
    static let toolbarHeight: CGFloat = 44
    static let toolbarSpacing: CGFloat = 7
    static let outerHorizontalPadding: CGFloat = 6
    static let outerTopPadding: CGFloat = 8
    static let outerBottomPadding: CGFloat = 6
    static let expandedPanelMinHeight: CGFloat = 286
    static let correctionDetailMinHeight: CGFloat = 232
    static let correctionCompleteMinHeight: CGFloat = 226
}

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
                        Text("Safe deterministic previews for the future compact correction flow. No private typed text or live debug internals are exposed here.")
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
            return "Right sparkle Improve mode with generated text, action carousel, rerun, copy, back, and accept controls."
        case .rewriteOptions:
            return "Rephrase result panel with the selected suggestion as the main content and horizontal alternatives available on demand."
        case .correctionComplete:
            return "Completion panel after suggestions are resolved."
        }
    }
}

struct KeyboardVisualPreviewView: View {
    let panel: KeyboardVisualPreviewPanel

    var body: some View {
        let showsToolbar = panel != .actions && panel != .rewriteOptions

        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: showsToolbar ? KeyboardVisualPreviewLayout.toolbarSpacing : 0) {
                if showsToolbar {
                    previewToolbar
                }

                switch panel {
                case .keyboard, .issue:
                    keyGrid
                case .correctionCard, .correctionCardNext, .correctionOnly, .predictionOnly:
                    keyGrid
                case .correctionDetail:
                    correctionDetailPanel
                case .actions:
                    actionPanel
                case .rewriteOptions:
                    rewriteOptionsPanel
                case .correctionComplete:
                    correctionCompletePanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: showsToolbar ? nil : .infinity, alignment: .top)
            .padding(.horizontal, showsToolbar ? KeyboardVisualPreviewLayout.outerHorizontalPadding : 0)
            .padding(.top, showsToolbar ? KeyboardVisualPreviewLayout.outerTopPadding : 0)
            .padding(.bottom, showsToolbar ? KeyboardVisualPreviewLayout.outerBottomPadding : 0)
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
        case .keyboard, .actions, .rewriteOptions, .correctionComplete:
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
        case .rewriteOptions: return .rewriteOptions
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
        .frame(minHeight: KeyboardVisualPreviewLayout.toolbarHeight)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(OpenKeyboardTheme.Surface.toolbarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("preview_ai_toolbar")
    }

    @ViewBuilder
    private var previewToolbarContent: some View {
        if (panel == .correctionCard || panel == .correctionCardNext || panel == .correctionOnly || panel == .predictionOnly) {
            HStack(spacing: 7) {
                if panel != .predictionOnly {
                    compactSuggestionBlock(
                        hint: panelState.compactSuggestion?.label ?? "Correct grammar",
                        value: panelState.compactSuggestion?.replacement ?? "I",
                        valueColor: OpenKeyboardTheme.Semantic.primaryAction,
                        identifier: "preview_compact_correction_block"
                    )
                    .layoutPriority(2)
                }

                if let prediction = panelState.compactSuggestion?.prediction {
                    compactSuggestionBlock(
                        hint: panel == .predictionOnly ? "Suggestion" : "Next word",
                        value: prediction,
                        valueColor: .primary,
                        identifier: "preview_prediction_block"
                    )
                    .layoutPriority(1)
                }

                Spacer(minLength: 0)
            }
            .accessibilityIdentifier("preview_compact_suggestion_strip")
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

    private func compactSuggestionBlock(hint: String, value: String, valueColor: Color, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(hint.replacingOccurrences(of: ":", with: ""))
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(minWidth: 58, alignment: .leading)
        .background(OpenKeyboardTheme.Surface.panelBackground.opacity(0.90), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OpenKeyboardTheme.Stroke.control.opacity(0.55), lineWidth: 1)
        )
        .accessibilityIdentifier(identifier)
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
                previewKey("space", role: .space)
                previewKey("return", role: .modifier).frame(width: 92)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
        .frame(maxWidth: .infinity, minHeight: KeyboardVisualPreviewLayout.correctionDetailMinHeight, alignment: .topLeading)
        .background(OpenKeyboardTheme.Surface.overlayBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(OpenKeyboardTheme.Semantic.error.opacity(0.55), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("preview_correction_detail_panel")
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                OpenKeyboardBrandMark(size: 30, symbolSize: 13)
                Text("Improve grammar and clarity.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(OpenKeyboardTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 0)
            }
            Divider()
                .overlay(OpenKeyboardTheme.Stroke.control.opacity(0.5))
                .padding(.top, 8)

            Text("None of these are bulbs in the universe.")
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(OpenKeyboardTheme.Text.primary)
                .lineLimit(4)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                .padding(.top, 10)
                .accessibilityIdentifier("preview_action_result_text")

            Spacer(minLength: 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    previewAction("Improve", systemImage: "sparkles", selected: true, identifier: "preview_ai_action_improve")
                    previewAction("Rephrase", systemImage: "arrow.triangle.2.circlepath", selected: false, identifier: "preview_ai_action_rewrite")
                    previewAction("Summarize", systemImage: "text.bubble", selected: false, identifier: "preview_ai_action_summarize")
                }
                .padding(.horizontal, 1)
            }
            .frame(height: 38)
            .padding(.bottom, 7)
            .accessibilityIdentifier("preview_ai_action_carousel")

            Divider()
                .overlay(OpenKeyboardTheme.Stroke.control.opacity(0.5))

            previewImproveControls(applyIdentifier: "preview_ai_action_apply", backIdentifier: "preview_back_to_keyboard")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: KeyboardVisualPreviewLayout.expandedPanelMinHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(OpenKeyboardTheme.Surface.overlayBackground)
                .shadow(color: OpenKeyboardTheme.Shadow.overlay, radius: 16, x: 0, y: 6)
        )
        .accessibilityIdentifier("preview_ai_action_panel")
    }

    private var rewriteOptionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                OpenKeyboardBrandMark(size: 30, symbolSize: 13)
                Text("Rephrase text.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(OpenKeyboardTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 0)
            }
            Divider()
                .overlay(OpenKeyboardTheme.Stroke.control.opacity(0.5))
                .padding(.top, 8)

            Text("None of these are bulbs in the universe.")
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(OpenKeyboardTheme.Text.primary)
                .lineLimit(4)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                .padding(.top, 10)
                .accessibilityIdentifier("preview_rewrite_result_text")

            Spacer(minLength: 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    previewRewriteOption("Clearer", text: "None of these are bulbs in the universe.", selected: true, identifier: "preview_rewrite_option_0")
                    previewRewriteOption("Natural", text: "There are no bulbs anywhere in the universe.", selected: false, identifier: "preview_rewrite_option_1")
                    previewRewriteOption("Concise", text: "No bulbs exist in the universe.", selected: false, identifier: "preview_rewrite_option_2")
                }
                .padding(.horizontal, 1)
            }
            .frame(height: 38)
            .padding(.bottom, 7)
            .accessibilityIdentifier("preview_rewrite_options_carousel")

            Divider()
                .overlay(OpenKeyboardTheme.Stroke.control.opacity(0.5))

            previewImproveControls(applyIdentifier: "preview_rewrite_apply", backIdentifier: "preview_rewrite_back")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: KeyboardVisualPreviewLayout.expandedPanelMinHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(OpenKeyboardTheme.Surface.overlayBackground)
                .shadow(color: OpenKeyboardTheme.Shadow.overlay, radius: 16, x: 0, y: 6)
        )
        .accessibilityIdentifier("preview_rewrite_options_panel")
    }

    private func previewRewriteOption(_ title: String, text: String, selected: Bool, identifier: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selected ? OpenKeyboardTheme.Semantic.primaryAction : OpenKeyboardTheme.Text.secondaryStrong)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Text.primary)
                .lineLimit(1)

            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .frame(width: 184, height: 32, alignment: .leading)
        .background(OpenKeyboardTheme.Surface.overlayBackground.opacity(selected ? 0.98 : 0.72), in: Capsule())
        .overlay(
            Capsule()
                .stroke(selected ? OpenKeyboardTheme.Semantic.primaryAction.opacity(0.95) : OpenKeyboardTheme.Stroke.control.opacity(0.9), lineWidth: selected ? 1.5 : 1)
        )
        .accessibilityIdentifier(identifier)
        .accessibilityValue(selected ? "Selected" : "")
    }

    private var correctionCompletePanel: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(OpenKeyboardTheme.Brand.blueGreenGradient)
                Image(systemName: "checkmark")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundColor(OpenKeyboardTheme.Text.inverse)
            }
            .frame(width: 58, height: 58)
            .padding(.bottom, 2)

            Text("All Done")
                .font(.headline.weight(.bold))

            Text("There are no more suggestions.")
                .font(.subheadline)
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

            Text("Back to Keyboard")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(OpenKeyboardTheme.Semantic.primaryAction)
                .padding(.horizontal, 18)
                .frame(minHeight: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(OpenKeyboardTheme.Semantic.primaryAction, lineWidth: 1.5)
                )
                .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: KeyboardVisualPreviewLayout.correctionCompleteMinHeight)
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

    private func previewAction(_ title: String, systemImage: String, selected: Bool, identifier: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18, height: 18)
                .foregroundColor(selected ? OpenKeyboardTheme.Semantic.primaryAction : OpenKeyboardTheme.Text.secondaryStrong)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .frame(height: 32, alignment: .center)
        .background(OpenKeyboardTheme.Surface.overlayBackground.opacity(selected ? 0.98 : 0.72), in: Capsule())
        .overlay(
            Capsule()
                .stroke(selected ? OpenKeyboardTheme.Semantic.primaryAction.opacity(0.95) : OpenKeyboardTheme.Stroke.control.opacity(0.9), lineWidth: selected ? 1.5 : 1)
        )
        .accessibilityIdentifier(identifier)
        .accessibilityValue(selected ? "Selected" : "")
    }

    private func previewImproveControls(applyIdentifier: String, backIdentifier: String) -> some View {
        HStack(spacing: 8) {
            previewCircleControl(systemImage: "keyboard", foreground: OpenKeyboardTheme.Text.primary, background: OpenKeyboardTheme.Surface.overlayBackground.opacity(0.7))
                .overlay(Circle().stroke(OpenKeyboardTheme.Stroke.control.opacity(0.9), lineWidth: 1.2))
                .accessibilityIdentifier(backIdentifier)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                previewGroupedControl(systemImage: "arrow.clockwise", foreground: OpenKeyboardTheme.Text.primary)
                    .accessibilityIdentifier("preview_ai_rerun")
                previewGroupedControl(systemImage: "sparkles", foreground: OpenKeyboardTheme.Semantic.primaryAction)
                    .accessibilityIdentifier("preview_ai_toggle_carousel")
                previewGroupedControl(systemImage: "doc.on.doc", foreground: OpenKeyboardTheme.Text.primary)
                    .accessibilityIdentifier("preview_ai_copy")
            }
            .frame(height: 36)
            .background(OpenKeyboardTheme.Surface.overlayBackground.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(OpenKeyboardTheme.Stroke.control.opacity(0.9), lineWidth: 1.1))

            Spacer(minLength: 0)

            previewCircleControl(systemImage: "checkmark", foreground: OpenKeyboardTheme.Text.inverse, background: OpenKeyboardTheme.Semantic.primaryAction)
                .accessibilityIdentifier(applyIdentifier)
        }
        .padding(.top, 7)
    }

    private func previewCircleControl(systemImage: String, foreground: Color, background: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(foreground)
            .frame(width: 36, height: 36)
            .background(background, in: Circle())
    }

    private func previewGroupedControl(systemImage: String, foreground: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(foreground)
            .frame(width: 40, height: 36)
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
#endif
