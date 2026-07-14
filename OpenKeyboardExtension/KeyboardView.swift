//
//  KeyboardView.swift
//  OpenKeyboardExtension
//

import SwiftUI

struct KeyboardView: View {
    @ObservedObject var viewModel: KeyboardViewModel
    let onNextKeyboard: () -> Void

    var body: some View {
        let showsToolbar = viewModel.panelMode != .actions && viewModel.panelMode != .rewriteOptions
        let viewportHeight = KeyboardPanelLayout.keyboardHeight(
            for: viewModel.panelMode,
            actionPanelState: viewModel.actionPanelState
        )
        let contentHeight = showsToolbar
            ? viewportHeight - KeyboardPanelLayout.outerTopPadding - KeyboardPanelLayout.outerBottomPadding
            : viewportHeight

        VStack(spacing: showsToolbar ? KeyboardPanelLayout.toolbarSpacing : 0) {
            if showsToolbar {
                KeyboardAIToolbar(
                    state: viewModel.toolbarState,
                    typingPredictions: viewModel.typingPredictions,
                    isPerformingAIAction: viewModel.isPerformingAIAction,
                    actionsEnabled: viewModel.canOpenActionPanel,
                    statusActionEnabled: viewModel.canOpenGrammarCorrection,
                    onPrediction: { viewModel.applyTypingPrediction(id: $0) },
                    onStatus: { viewModel.openGrammarCorrection() },
                    onSparkle: { viewModel.showActionPanel() }
                )
                .frame(height: KeyboardPanelLayout.toolbarRenderedHeight)
                .layoutPriority(1)
            }

            switch viewModel.panelMode {
            case .keyboard:
                if let error = viewModel.actionError {
                    KeyboardActionErrorPanel(
                        error: error,
                        onBackToTyping: { viewModel.retryAfterActionError() },
                        onCopyDetails: { viewModel.copyActionErrorDetails() },
                        onDismiss: { viewModel.clearActionError() }
                    )
                } else {
                    keyGrid
                }
            case .actions:
                if let state = viewModel.actionPanelState {
                    AIActionPanel(
                        state: state,
                        actionsEnabled: viewModel.canRunAIAction,
                        onSelect: { viewModel.selectActionPanelAction($0) },
                        onRegenerate: { viewModel.rerunSelectedActionPanelAction() },
                        onToggleCarousel: { viewModel.toggleActionPanelCarousel() },
                        onCopy: { viewModel.copySelectedActionPanelSuggestion() },
                        onApply: { viewModel.applySelectedActionPanelAction() },
                        onBackToKeyboard: { viewModel.showKeyboardPanel() }
                    )
                } else {
                    keyGrid
                }
            case .rewriteOptions:
                if let state = viewModel.rewriteOptionsState {
                    RewriteOptionsPanel(
                        state: state,
                        onSelect: { viewModel.selectRewriteOption($0) },
                        onRegenerate: { viewModel.rerunRewriteOptionsAction() },
                        onToggleCarousel: { viewModel.toggleRewriteOptionsCarousel() },
                        onCopy: { viewModel.copySelectedRewriteOption() },
                        onApply: { viewModel.applySelectedRewriteOption() },
                        onBack: { viewModel.dismissRewriteOptions() }
                    )
                } else {
                    keyGrid
                }
            case .correctionDetail:
                if let card = viewModel.currentCorrectionCard {
                    CorrectionDetailPanel(
                        card: card,
                        progressText: viewModel.suggestionState?.correctionProgressText,
                        canMovePrevious: viewModel.suggestionState?.canMoveToPreviousCorrection ?? false,
                        canMoveNext: viewModel.suggestionState?.canMoveToNextCorrection ?? false,
                        onPrevious: { viewModel.moveToPreviousSuggestion() },
                        onNext: { viewModel.moveToNextSuggestion() },
                        onApply: { viewModel.applyCurrentCorrection() },
                        onDismiss: { viewModel.dismissCurrentCorrection() },
                        onBackToKeyboard: { viewModel.showKeyboardPanel() }
                    )
                } else if viewModel.isGrammarCorrectionLoading {
                    GrammarCorrectionLoadingPanel(
                        status: viewModel.aiStatus,
                        onBackToKeyboard: { viewModel.showKeyboardPanel() }
                    )
                } else {
                    keyGrid
                }
            case .correctionComplete:
                CorrectionCompletePanel(
                    state: viewModel.completionPanelState,
                    onBackToKeyboard: { viewModel.showKeyboardPanel() }
                )
            }

        }
        .frame(maxWidth: .infinity, minHeight: contentHeight, maxHeight: contentHeight, alignment: .top)
        .padding(.horizontal, showsToolbar ? KeyboardPanelLayout.outerHorizontalPadding : 0)
        .padding(.top, showsToolbar ? KeyboardPanelLayout.outerTopPadding : 0)
        .padding(.bottom, showsToolbar ? KeyboardPanelLayout.outerBottomPadding : 0)
        .background(KeyboardColors.keyboardBackground)
        .onAppear {
            viewModel.reloadConfig()
            viewModel.refreshSeededSuggestionStateForUITests()
            viewModel.startAutomaticAnalysis()
        }
    }

    private var keyGrid: some View {
        GeometryReader { proxy in
            let metrics = KeyboardPanelLayout.keyGridMetrics(for: proxy.size.width)

            VStack(spacing: KeyboardPanelLayout.keyRowSpacing) {
                fixedKeyRow(
                    viewModel.isNumbersEnabled ? ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] : ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                    keyWidth: metrics.letterWidth,
                    keyHeight: KeyboardPanelLayout.letterKeyHeight
                )
                .accessibilityIdentifier("keyboard_row_qwerty")

                fixedKeyRow(
                    viewModel.isNumbersEnabled ? ["-", "/", ":", ";", "(", ")", "$", "&", "@"] : ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                    keyWidth: metrics.letterWidth,
                    keyHeight: KeyboardPanelLayout.letterKeyHeight
                )
                .padding(.horizontal, metrics.homeRowInset)
                .accessibilityIdentifier("keyboard_row_home")

                HStack(spacing: 0) {
                    KeyButton(
                        label: viewModel.isNumbersEnabled ? "#+=" : "⇧",
                        systemImage: viewModel.isNumbersEnabled ? nil : "shift.fill",
                        role: .modifier,
                        height: KeyboardPanelLayout.letterKeyHeight,
                        isAccent: viewModel.isShiftEnabled
                    ) {
                        if viewModel.isNumbersEnabled {
                            viewModel.toggleNumbers()
                        } else {
                            viewModel.toggleShift()
                        }
                    }
                    .frame(width: metrics.modifierWidth)

                    Spacer(minLength: metrics.bottomLetterSideGap)
                        .frame(width: metrics.bottomLetterSideGap)

                    fixedKeyRow(
                        viewModel.isNumbersEnabled ? [".", ",", "?", "!", "'", "\"", "_"] : ["z", "x", "c", "v", "b", "n", "m"],
                        keyWidth: metrics.letterWidth,
                        keyHeight: KeyboardPanelLayout.letterKeyHeight
                    )

                    Spacer(minLength: metrics.bottomLetterSideGap)
                        .frame(width: metrics.bottomLetterSideGap)

                    KeyButton(label: "⌫", systemImage: "delete.left", role: .modifier, height: KeyboardPanelLayout.letterKeyHeight) {
                        viewModel.deleteBackward()
                    }
                    .frame(width: metrics.modifierWidth)
                }
                .accessibilityIdentifier("keyboard_row_bottom_letters")

                HStack(spacing: KeyboardPanelLayout.keyHorizontalSpacing) {
                    KeyButton(label: viewModel.isNumbersEnabled ? "ABC" : "123", role: .modifier, height: KeyboardPanelLayout.controlKeyHeight) {
                        viewModel.toggleNumbers()
                    }
                    .frame(width: metrics.bottomControlWidth)
                    .accessibilityIdentifier("keyboard_key_numbers")

                    KeyButton(label: "Emoji", systemImage: "face.smiling", role: .modifier, height: KeyboardPanelLayout.controlKeyHeight) {
                        onNextKeyboard()
                    }
                    .frame(width: metrics.bottomControlWidth)
                    .accessibilityIdentifier("keyboard_key_emoji")

                    KeyButton(label: "space", displayLabel: "", role: .space, height: KeyboardPanelLayout.controlKeyHeight) {
                        viewModel.insertSpace()
                    }
                    .frame(width: metrics.spaceWidth)
                    .accessibilityIdentifier("keyboard_key_space")

                    KeyButton(label: "return", systemImage: "return", role: .returnKey, height: KeyboardPanelLayout.controlKeyHeight) {
                        viewModel.insertReturn()
                    }
                    .frame(width: metrics.returnWidth)
                    .accessibilityIdentifier("keyboard_key_return")
                }
                .accessibilityIdentifier("keyboard_row_controls")
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(.bottom, KeyboardPanelLayout.keyShadowAllowance)
        .frame(height: KeyboardPanelLayout.keyGridHeight, alignment: .top)
    }

    private func fixedKeyRow(_ keys: [String], keyWidth: CGFloat, keyHeight: CGFloat) -> some View {
        HStack(spacing: KeyboardPanelLayout.keyHorizontalSpacing) {
            ForEach(keys, id: \.self) { key in
                KeyButton(label: key, displayLabel: keyDisplayLabel(for: key), role: .letter, height: keyHeight) {
                    viewModel.insert(key)
                }
                .frame(width: keyWidth)
            }
        }
    }

    private func keyDisplayLabel(for key: String) -> String {
        guard key.count == 1, key.rangeOfCharacter(from: .letters) != nil else { return key }
        return key.uppercased()
    }
}

private struct KeyboardAIToolbar: View {
    let state: KeyboardToolbarState
    let typingPredictions: [KeyboardPredictionSuggestion]
    let isPerformingAIAction: Bool
    let actionsEnabled: Bool
    let statusActionEnabled: Bool
    let onPrediction: (String) -> Void
    let onStatus: () -> Void
    let onSparkle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            if typingPredictions.isEmpty {
                Button(action: performStatusAction) {
                    statusContent
                }
                .buttonStyle(.plain)
                .disabled(!statusActionEnabled)
                .accessibilityIdentifier("ai_toolbar_status_action")
            } else {
                predictionStrip
            }
            sparkleButton
        }
        .frame(height: KeyboardPanelLayout.toolbarHeight)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai_toolbar")
    }

    private func performStatusAction() {
        guard statusActionEnabled else { return }
        onStatus()
    }

    private var statusIcon: some View {
        Button(action: performStatusAction) {
            ZStack {
                if isPerformingAIAction {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(KeyboardColors.panelBackground.opacity(0.78))
                    ProgressView()
                        .scaleEffect(0.72)
                        .tint(OpenKeyboardTheme.Semantic.primaryAction)
                } else if state.showsIssueCount {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(OpenKeyboardTheme.Semantic.error)
                    Text("\(state.issueCount)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(OpenKeyboardTheme.Text.inverse)
                } else if state.showsBrandMark && actionsEnabled {
                    OpenKeyboardBrandMark(size: KeyboardPanelLayout.toolbarControlSize, symbolSize: 15)
                } else {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(OpenKeyboardTheme.Surface.warningBackground)
                    Image(systemName: state.leadingSystemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(OpenKeyboardTheme.Semantic.warning)
                }
            }
            .frame(width: KeyboardPanelLayout.toolbarControlSize, height: KeyboardPanelLayout.toolbarControlSize)
        }
        .buttonStyle(.plain)
        .disabled(!statusActionEnabled)
        .accessibilityIdentifier(state.showsIssueCount ? "keyboard_issue_count_badge" : "keyboard_openkeyboard_icon")
        .accessibilityLabel(state.showsIssueCount ? "\(state.issueCount) writing suggestions" : "Open Keyboard status")
    }

    private var predictionStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(typingPredictions.prefix(3).enumerated()), id: \.element.id) { index, prediction in
                Button {
                    onPrediction(prediction.id)
                } label: {
                    Text(prediction.text)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(OpenKeyboardTheme.Text.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: KeyboardPanelLayout.toolbarControlSize)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("typing_prediction_chip_\(index)")
                .accessibilityLabel("Typing suggestion \(prediction.text)")

                if index < min(typingPredictions.count, 3) - 1 {
                    Rectangle()
                        .fill(OpenKeyboardTheme.Stroke.control.opacity(0.72))
                        .frame(width: 1, height: KeyboardPanelLayout.toolbarControlSize * 0.72)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: KeyboardPanelLayout.toolbarControlSize)
        .accessibilityIdentifier("typing_prediction_strip")
    }

    private var statusContent: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(state.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(OpenKeyboardTheme.Text.primary)
                    .lineLimit(1)
                Text(state.subtitle)
                    .font(.caption2)
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: KeyboardPanelLayout.toolbarControlSize)
        .padding(.horizontal, 6)
    }

    private var sparkleButton: some View {
        Button(action: onSparkle) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: KeyboardPanelLayout.toolbarControlSize, height: KeyboardPanelLayout.toolbarControlSize)
        }
        .foregroundColor(actionsEnabled ? OpenKeyboardTheme.Semantic.primaryAction : .secondary)
        .background(KeyboardColors.keyBackground)
        .clipShape(Circle())
        .disabled(!actionsEnabled)
        .accessibilityIdentifier("ai_sparkle_action")
    }
}

private struct AIActionPanel: View {
    let state: KeyboardActionPanelState
    let actionsEnabled: Bool
    let onSelect: (KeyboardAIAction) -> Void
    let onRegenerate: () -> Void
    let onToggleCarousel: () -> Void
    let onCopy: () -> Void
    let onApply: () -> Void
    let onBackToKeyboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .overlay(OpenKeyboardTheme.Stroke.control.opacity(0.5))
                .padding(.top, 8)
            suggestionBlock
            Spacer(minLength: 0)
            if state.isCarouselVisible {
                actionCarousel
                .padding(.bottom, carouselBottomPadding)
                .layoutPriority(1)
            }
            Divider()
                .overlay(OpenKeyboardTheme.Stroke.control.opacity(0.5))
            controlRow
                .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(
            maxWidth: .infinity,
            minHeight: panelHeight,
            maxHeight: panelHeight,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(KeyboardColors.overlayBackground)
                .shadow(color: OpenKeyboardTheme.Shadow.overlay, radius: 16, x: 0, y: 6)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai_action_panel")
    }

    private var usesScrollableImproveResult: Bool {
        state.usesScrollableImproveResult
    }

    private var usesExpandedImprovePanel: Bool {
        state.usesExpandedImprovePanel
    }

    private var panelHeight: CGFloat {
        usesExpandedImprovePanel ? KeyboardPanelLayout.improvePanelHeight : KeyboardPanelLayout.expandedPanelHeight
    }

    private var suggestionHeight: CGFloat {
        if usesExpandedImprovePanel {
            return 200
        }
        return state.isCarouselVisible ? 72 : 132
    }

    private var carouselHeight: CGFloat {
        usesExpandedImprovePanel ? 32 : 38
    }

    private var carouselBottomPadding: CGFloat {
        usesExpandedImprovePanel ? 4 : 7
    }

    private var controlButtonSize: CGFloat {
        usesExpandedImprovePanel ? 34 : 36
    }

    private var groupedButtonWidth: CGFloat {
        usesExpandedImprovePanel ? 38 : 40
    }

    private var controlRowTopPadding: CGFloat {
        usesExpandedImprovePanel ? 4 : 7
    }

    private var actionResultFontSize: CGFloat {
        usesExpandedImprovePanel ? 15 : 19
    }

    private var header: some View {
        HStack(spacing: 10) {
            OpenKeyboardBrandMark(size: 30, symbolSize: 13)

            Text(state.selectedAction.actionPanelTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)
        }
    }

    private var suggestionBlock: some View {
        Group {
            if state.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.88)
                    Text("\(state.selectedAction.title)…")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(OpenKeyboardTheme.Text.primary)
                        .lineLimit(2)
                        .accessibilityIdentifier("ai_action_loading_text")
                }
            } else if let selectedOption = state.selectedOption {
                actionResultText(selectedOption.text)
            } else {
                Text("No suggestion yet")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    .lineLimit(2)
                    .accessibilityIdentifier("ai_action_empty_text")
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: suggestionHeight,
            maxHeight: suggestionHeight,
            alignment: state.selectedOption == nil ? .center : .topLeading
        )
        .padding(.top, 10)
        .clipped()
    }

    @ViewBuilder
    private func actionResultText(_ text: String) -> some View {
        if usesScrollableImproveResult {
            ScrollView(.vertical, showsIndicators: true) {
                actionResultLabel(text, lineLimit: nil)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        } else {
            actionResultLabel(text, lineLimit: state.isCarouselVisible ? 4 : 6)
        }
    }

    private func actionResultLabel(_ text: String, lineLimit: Int?) -> some View {
        Text(text)
            .font(.system(size: actionResultFontSize, weight: .regular))
            .foregroundColor(OpenKeyboardTheme.Text.primary)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.72)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("ai_action_result_text")
    }

    private var actionCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(KeyboardActionPanelState.availableActions) { action in
                    actionCard(action)
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: carouselHeight)
        .accessibilityIdentifier("ai_action_carousel")
    }

    private func actionCard(_ action: KeyboardAIAction) -> some View {
        let isSelected = action == state.selectedAction
        return Button {
            onSelect(action)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: action.actionPanelSystemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .foregroundColor(isSelected ? OpenKeyboardTheme.Semantic.primaryAction : OpenKeyboardTheme.Text.secondaryStrong)

                Text(action.actionPanelDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OpenKeyboardTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .frame(height: 32, alignment: .center)
            .background(KeyboardColors.overlayBackground.opacity(isSelected ? 0.98 : 0.72), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? OpenKeyboardTheme.Semantic.primaryAction.opacity(0.95) : OpenKeyboardTheme.Stroke.control.opacity(0.9), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!actionsEnabled || state.isLoading)
        .accessibilityIdentifier("ai_action_\(action.rawValue)")
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            panelCircleButton(
                systemImage: "keyboard",
                foreground: OpenKeyboardTheme.Text.primary,
                background: KeyboardColors.overlayBackground.opacity(0.7),
                action: onBackToKeyboard
            )
            .overlay(Circle().stroke(OpenKeyboardTheme.Stroke.control.opacity(0.9), lineWidth: 1.2))
            .accessibilityIdentifier("back_to_keyboard")

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                panelGroupedButton(
                    systemImage: "arrow.clockwise",
                    foreground: OpenKeyboardTheme.Text.primary,
                    action: onRegenerate
                )
                .disabled(!actionsEnabled || state.isLoading)
                .accessibilityIdentifier("ai_action_rerun")

                panelGroupedButton(
                    systemImage: "sparkles",
                    foreground: OpenKeyboardTheme.Semantic.primaryAction,
                    action: onToggleCarousel
                )
                .accessibilityIdentifier("ai_action_toggle_carousel")

                panelGroupedButton(
                    systemImage: "doc.on.doc",
                    foreground: OpenKeyboardTheme.Text.primary,
                    action: onCopy
                )
                .disabled(state.selectedOption == nil || state.isLoading)
                .accessibilityIdentifier("ai_action_copy")
            }
            .frame(height: controlButtonSize)
            .background(KeyboardColors.overlayBackground.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(OpenKeyboardTheme.Stroke.control.opacity(0.9), lineWidth: 1.1))

            Spacer(minLength: 0)

            panelCircleButton(
                systemImage: "checkmark",
                foreground: OpenKeyboardTheme.Text.inverse,
                background: OpenKeyboardTheme.Semantic.primaryAction,
                action: onApply
            )
            .disabled(state.selectedOption == nil || state.isLoading)
            .opacity(state.selectedOption == nil || state.isLoading ? 0.42 : 1)
            .accessibilityIdentifier("ai_action_apply")
        }
        .padding(.top, controlRowTopPadding)
    }

    private func panelCircleButton(
        systemImage: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: controlButtonSize, height: controlButtonSize)
        }
        .buttonStyle(.plain)
        .foregroundColor(foreground)
        .background(background, in: Circle())
    }

    private func panelGroupedButton(systemImage: String, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: groupedButtonWidth, height: controlButtonSize)
        }
        .buttonStyle(.plain)
        .foregroundColor(foreground)
    }
}

private extension KeyboardAIAction {
    var actionPanelTitle: String {
        switch self {
        case .improve: return "Improve grammar and clarity."
        case .fixGrammar: return "Fix grammar."
        case .rewrite: return "Rephrase text."
        case .summarize: return "Summarize text."
        }
    }

    var actionPanelSubtitle: String {
        switch self {
        case .improve: return "Choose an action for the text below."
        case .fixGrammar: return "Find grammar and spelling fixes."
        case .rewrite: return "Generate alternatives before replacing."
        case .summarize: return "Shorten the source text."
        }
    }

    var actionPanelDisplayName: String {
        switch self {
        case .improve: return "Improve"
        case .fixGrammar: return "Fix"
        case .rewrite: return "Rephrase"
        case .summarize: return "Summarize"
        }
    }

    var actionPanelShortHint: String {
        switch self {
        case .improve: return "Clearer"
        case .fixGrammar: return "Correct"
        case .rewrite: return "Alternatives"
        case .summarize: return "Shorten"
        }
    }

    var actionPanelSystemImage: String {
        switch self {
        case .improve: return "sparkles"
        case .fixGrammar: return "checkmark.seal.fill"
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .summarize: return "text.bubble"
        }
    }
}

private struct RewriteOptionsPanel: View {
    let state: KeyboardRewriteOptionsState
    let onSelect: (String) -> Void
    let onRegenerate: () -> Void
    let onToggleCarousel: () -> Void
    let onCopy: () -> Void
    let onApply: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .overlay(OpenKeyboardTheme.Stroke.control.opacity(0.5))
                .padding(.top, 8)
            suggestionBlock
            if state.isCarouselVisible {
                optionsCarousel
                    .padding(.bottom, 7)
            }
            Divider()
                .overlay(OpenKeyboardTheme.Stroke.control.opacity(0.5))
            controlRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(
            maxWidth: .infinity,
            minHeight: KeyboardPanelLayout.expandedPanelHeight,
            maxHeight: KeyboardPanelLayout.expandedPanelHeight,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(KeyboardColors.overlayBackground)
                .shadow(color: OpenKeyboardTheme.Shadow.overlay, radius: 16, x: 0, y: 6)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai_rewrite_panel")
    }

    private var header: some View {
        HStack(spacing: 10) {
            OpenKeyboardBrandMark(size: 30, symbolSize: 13)

            Text(state.intent == .improve ? "Improve grammar and clarity." : "Rephrase text.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Text.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)
        }
    }

    private var suggestionBlock: some View {
        Group {
            if let selectedOption = state.selectedOption {
                Text(selectedOption.text)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(OpenKeyboardTheme.Text.primary)
                    .lineLimit(state.isCarouselVisible ? 4 : 6)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ai_rewrite_result_text")
            } else {
                Text("No rewrite available")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    .lineLimit(2)
                    .accessibilityIdentifier("ai_rewrite_empty_text")
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: state.isCarouselVisible ? 84 : 132,
            maxHeight: .infinity,
            alignment: state.selectedOption == nil ? .center : .topLeading
        )
        .padding(.top, 10)
        .layoutPriority(1)
    }

    private var sourceBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.intent.sourceLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                .lineLimit(1)
            Text(state.sourceText)
                .font(.caption.weight(.semibold))
                .foregroundColor(OpenKeyboardTheme.Text.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ai_rewrite_source_text")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(OpenKeyboardTheme.Surface.panelBackground.opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OpenKeyboardTheme.Stroke.control.opacity(0.65), lineWidth: 1)
        )
    }

    private var optionsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(state.options.enumerated()), id: \.element.id) { index, option in
                    optionCard(option, index: index)
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: 38)
        .accessibilityIdentifier("ai_rewrite_options_carousel")
    }

    private func optionCard(_ option: KeyboardRewriteOption, index: Int) -> some View {
        let isSelected = option.id == state.selectedOptionID
        return Button {
            onSelect(option.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? OpenKeyboardTheme.Semantic.primaryAction : OpenKeyboardTheme.Text.secondaryStrong)

                Text(option.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OpenKeyboardTheme.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(option.text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 12)
            .frame(width: 184, height: 32, alignment: .leading)
            .background(KeyboardColors.overlayBackground.opacity(isSelected ? 0.98 : 0.72), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? OpenKeyboardTheme.Semantic.primaryAction.opacity(0.95) : OpenKeyboardTheme.Stroke.control.opacity(0.9), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ai_rewrite_option_\(index)")
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            panelCircleButton(
                systemImage: "keyboard",
                foreground: OpenKeyboardTheme.Text.primary,
                background: KeyboardColors.overlayBackground.opacity(0.7),
                action: onBack
            )
            .overlay(Circle().stroke(OpenKeyboardTheme.Stroke.control.opacity(0.9), lineWidth: 1.2))
            .accessibilityIdentifier("ai_rewrite_back")

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                panelGroupedButton(systemImage: "arrow.clockwise", foreground: OpenKeyboardTheme.Text.primary, action: onRegenerate)
                    .accessibilityIdentifier("ai_rewrite_rerun")
                panelGroupedButton(systemImage: "sparkles", foreground: OpenKeyboardTheme.Semantic.primaryAction, action: onToggleCarousel)
                    .accessibilityIdentifier("ai_rewrite_toggle_carousel")
                panelGroupedButton(systemImage: "doc.on.doc", foreground: OpenKeyboardTheme.Text.primary, action: onCopy)
                    .disabled(state.selectedOption == nil)
                    .accessibilityIdentifier("ai_rewrite_copy")
            }
            .frame(height: 36)
            .background(KeyboardColors.overlayBackground.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(OpenKeyboardTheme.Stroke.control.opacity(0.9), lineWidth: 1.1))

            Spacer(minLength: 0)

            panelCircleButton(
                systemImage: "checkmark",
                foreground: OpenKeyboardTheme.Text.inverse,
                background: OpenKeyboardTheme.Semantic.primaryAction,
                action: onApply
            )
            .disabled(state.selectedOption == nil)
            .opacity(state.selectedOption == nil ? 0.42 : 1)
            .accessibilityIdentifier("ai_rewrite_apply")
        }
        .padding(.top, 7)
    }

    private func panelCircleButton(
        systemImage: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundColor(foreground)
        .background(background, in: Circle())
    }

    private func panelGroupedButton(systemImage: String, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundColor(foreground)
    }
}

private struct KeyboardActionErrorPanel: View {
    let error: KeyboardActionErrorState
    let onBackToTyping: () -> Void
    let onCopyDetails: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(OpenKeyboardTheme.Semantic.warning)
                    .frame(width: 38, height: 38)
                    .background(OpenKeyboardTheme.Surface.warningBackground, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(error.title)
                        .font(.headline.weight(.semibold))
                    Text(error.message)
                        .font(.caption)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .lineLimit(3)
                        .accessibilityIdentifier("ai_error_message")
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button(action: onBackToTyping) {
                    Text("Back to Typing")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain)
                .foregroundColor(OpenKeyboardTheme.Text.inverse)
                .background(OpenKeyboardTheme.Semantic.primaryAction)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("ai_error_back_to_typing")

                Button(action: onCopyDetails) {
                    Text("Copy Details")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain)
                .foregroundColor(OpenKeyboardTheme.Semantic.error)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(OpenKeyboardTheme.Semantic.error, lineWidth: 1.2)
                )
                .accessibilityIdentifier("ai_error_copy_details")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .layoutPriority(0)
        .background(KeyboardColors.overlayBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(OpenKeyboardTheme.Semantic.warning.opacity(0.6), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai_error_panel")
    }
}

private struct GrammarCorrectionLoadingPanel: View {
    let status: String
    let onBackToKeyboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.9)
                    .frame(width: 38, height: 38)
                    .background(KeyboardColors.panelBackground.opacity(0.92), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.isEmpty ? "Checking grammar…" : status)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(OpenKeyboardTheme.Text.primary)
                        .lineLimit(1)
                        .accessibilityIdentifier("ai_correction_loading_text")
                    Text("Reviewing current text")
                        .font(.caption)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onBackToKeyboard) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundColor(OpenKeyboardTheme.Text.primary)
                .background(KeyboardColors.panelBackground.opacity(0.92), in: Circle())
                .accessibilityIdentifier("back_to_keyboard")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .layoutPriority(0)
        .background(KeyboardColors.overlayBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(OpenKeyboardTheme.Semantic.primaryAction.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai_correction_loading_panel")
    }
}

private struct CorrectionDetailPanel: View {
    let card: KeyboardCorrectionCard
    let progressText: String?
    let canMovePrevious: Bool
    let canMoveNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onApply: () -> Void
    let onDismiss: () -> Void
    let onBackToKeyboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(OpenKeyboardTheme.Text.inverse)
                    .frame(width: 24, height: 24)
                    .background(OpenKeyboardTheme.Semantic.error)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(card.categoryTitle)
                        .font(.caption.weight(.bold))
                        .foregroundColor(OpenKeyboardTheme.Text.primary)
                        .lineLimit(1)
                    if let progressText {
                        Text(progressText)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                            .accessibilityIdentifier("keyboard_correction_progress")
                            .accessibilityLabel("Correction \(progressText)")
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Button(action: onPrevious) {
                        Image(systemName: "chevron.left")
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMovePrevious)
                    .foregroundColor(canMovePrevious ? OpenKeyboardTheme.Semantic.primaryAction : OpenKeyboardTheme.Text.secondary)
                    .accessibilityIdentifier("keyboard_correction_previous")

                    Button(action: onNext) {
                        Image(systemName: "chevron.right")
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMoveNext)
                    .foregroundColor(canMoveNext ? OpenKeyboardTheme.Semantic.primaryAction : OpenKeyboardTheme.Text.secondary)
                    .accessibilityIdentifier("keyboard_correction_next")
                }
                .font(.caption.weight(.bold))

                Button(action: onBackToKeyboard) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundColor(OpenKeyboardTheme.Text.primary)
                .background(KeyboardColors.panelBackground.opacity(0.92))
                .clipShape(Circle())
                .accessibilityIdentifier("back_to_keyboard")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(card.original)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(OpenKeyboardTheme.Semantic.error)
                        .strikethrough(true, color: OpenKeyboardTheme.Semantic.error)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("ai_correction_original")

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

                    Text(card.replacement)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(OpenKeyboardTheme.Semantic.success)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("ai_correction_replacement")
                }

                Text(card.explanation)
                    .font(.caption)
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ai_correction_explanation")
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 34)
                }
                .buttonStyle(.plain)
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                .accessibilityIdentifier("ai_correction_dismiss")

                Spacer()

                Button(action: onApply) {
                    Text("Accept")
                        .font(.caption.weight(.bold))
                        .foregroundColor(OpenKeyboardTheme.Text.inverse)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 34)
                        .background(OpenKeyboardTheme.Semantic.success)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai_correction_apply")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(0)
        .background(KeyboardColors.overlayBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(OpenKeyboardTheme.Semantic.primaryAction.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    if value.translation.width < -36, canMoveNext {
                        onNext()
                    } else if value.translation.width > 36, canMovePrevious {
                        onPrevious()
                    }
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityValue(progressText ?? "1 of 1")
        .accessibilityIdentifier("ai_correction_panel")
        .accessibilityAction(named: "Next correction") {
            if canMoveNext { onNext() }
        }
        .accessibilityAction(named: "Previous correction") {
            if canMovePrevious { onPrevious() }
        }
    }
}

private struct CorrectionCompletePanel: View {
    let state: KeyboardCompletionPanelState
    let onBackToKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 27, weight: .bold))
                .foregroundColor(OpenKeyboardTheme.Text.inverse)
                .padding(15)
                .background(
                    Circle().fill(OpenKeyboardTheme.Brand.blueGreenGradient)
                )
            .padding(.bottom, 2)

            Text(state.title)
                .font(.headline.weight(.bold))

            Text(state.message)
                .font(.subheadline)
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

            Button(action: onBackToKeyboard) {
                Text("Back to Keyboard")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundColor(OpenKeyboardTheme.Semantic.primaryAction)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(OpenKeyboardTheme.Semantic.primaryAction, lineWidth: 1.5)
            )
            .padding(.top, 2)
            .accessibilityIdentifier("back_to_keyboard")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .layoutPriority(0)
        .background(KeyboardColors.overlayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("correction_complete_panel")
    }
}

private enum KeyRole {
    case letter
    case modifier
    case space
    case returnKey
}

private struct KeyButton: View {
    let label: String
    var displayLabel: String?
    var systemImage: String?
    var role: KeyRole = .letter
    let height: CGFloat
    var isAccent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(iconFont)
                        .symbolRenderingMode(.monochrome)
                } else {
                    Text(displayLabel ?? label)
                        .font(font)
                }
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: OpenKeyboardTheme.Shadow.key, radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var font: Font {
        switch role {
        case .letter: return .system(size: 24, weight: .regular)
        case .space: return .system(size: 16, weight: .regular)
        case .returnKey, .modifier: return .system(size: label.count > 2 ? 16 : 22, weight: .regular)
        }
    }

    private var iconFont: Font {
        switch role {
        case .letter: return .system(size: 24, weight: .regular)
        case .space: return .system(size: 17, weight: .regular)
        case .returnKey: return .system(size: 25, weight: .regular)
        case .modifier: return .system(size: 22, weight: .regular)
        }
    }

    private var backgroundColor: Color {
        if isAccent { return OpenKeyboardTheme.Semantic.primaryAction.opacity(0.32) }
        switch role {
        case .letter, .modifier, .space, .returnKey:
            return KeyboardColors.keyBackground
        }
    }
}

private enum KeyboardColors {
    static let keyboardBackground = OpenKeyboardTheme.Surface.keyboardBackground
    static let toolbarBackground = OpenKeyboardTheme.Surface.toolbarBackground
    static let panelBackground = OpenKeyboardTheme.Surface.panelBackground
    static let overlayBackground = OpenKeyboardTheme.Surface.overlayBackground
    static let keyBackground = OpenKeyboardTheme.Surface.keyBackground
    static let modifierKeyBackground = OpenKeyboardTheme.Surface.modifierKeyBackground
}
