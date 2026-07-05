//
//  KeyboardView.swift
//  OpenKeyboardExtension
//

import SwiftUI

enum KeyboardPanelLayout {
    static let toolbarHeight: CGFloat = 44
    static let toolbarVerticalPadding: CGFloat = 6
    static let toolbarRenderedHeight: CGFloat = toolbarHeight + (toolbarVerticalPadding * 2)
    static let toolbarSpacing: CGFloat = 10
    static let outerHorizontalPadding: CGFloat = 6
    static let outerTopPadding: CGFloat = 4
    static let outerBottomPadding: CGFloat = 0
    static let letterKeyHeight: CGFloat = 46
    static let controlKeyHeight: CGFloat = 42
    static let keyRowSpacing: CGFloat = 8
    static let keyGridHeight: CGFloat = (letterKeyHeight * 3) + controlKeyHeight + (keyRowSpacing * 3)
    static let preferredKeyboardHeight: CGFloat = outerTopPadding + toolbarRenderedHeight + toolbarSpacing + keyGridHeight + outerBottomPadding
    static let expandedPanelMinHeight: CGFloat = preferredKeyboardHeight
}

struct KeyboardView: View {
    @ObservedObject var viewModel: KeyboardViewModel

    var body: some View {
        let showsToolbar = viewModel.panelMode != .actions && viewModel.panelMode != .rewriteOptions
        let usesTypingKeyboardHeight = isTypingKeyboardVisible

        VStack(spacing: showsToolbar ? KeyboardPanelLayout.toolbarSpacing : 0) {
            if showsToolbar {
                KeyboardAIToolbar(
                    state: viewModel.toolbarState,
                    isPerformingAIAction: viewModel.isPerformingAIAction,
                    actionsEnabled: viewModel.canOpenActionPanel,
                    statusActionEnabled: viewModel.canOpenGrammarCorrection,
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
        .frame(maxWidth: .infinity, maxHeight: usesTypingKeyboardHeight ? nil : .infinity, alignment: .top)
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
        VStack(spacing: KeyboardPanelLayout.keyRowSpacing) {
            keyRow(
                viewModel.isNumbersEnabled ? ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] : ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                keyHeight: KeyboardPanelLayout.letterKeyHeight
            )
            .accessibilityIdentifier("keyboard_row_qwerty")

            keyRow(
                viewModel.isNumbersEnabled ? ["-", "/", ":", ";", "(", ")", "$", "&", "@"] : ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                keyHeight: KeyboardPanelLayout.letterKeyHeight
            )
            .padding(.horizontal, 18)
            .accessibilityIdentifier("keyboard_row_home")

            HStack(spacing: 6) {
                KeyButton(label: viewModel.isNumbersEnabled ? "#+=" : "⇧", role: .modifier, height: KeyboardPanelLayout.letterKeyHeight, isAccent: viewModel.isShiftEnabled) {
                    if viewModel.isNumbersEnabled {
                        viewModel.toggleNumbers()
                    } else {
                        viewModel.toggleShift()
                    }
                }
                .frame(width: 52)

                keyRow(
                    viewModel.isNumbersEnabled ? [".", ",", "?", "!", "'", "\"", "_"] : ["z", "x", "c", "v", "b", "n", "m"],
                    keyHeight: KeyboardPanelLayout.letterKeyHeight
                )

                KeyButton(label: "⌫", role: .modifier, height: KeyboardPanelLayout.letterKeyHeight) {
                    viewModel.deleteBackward()
                }
                .frame(width: 52)
            }
            .accessibilityIdentifier("keyboard_row_bottom_letters")

            HStack(spacing: 6) {
                KeyButton(label: viewModel.isNumbersEnabled ? "ABC" : "123", role: .modifier, height: KeyboardPanelLayout.controlKeyHeight) {
                    viewModel.toggleNumbers()
                }
                .frame(width: 58)
                .accessibilityIdentifier("keyboard_key_numbers")

                KeyButton(label: "space", role: .space, height: KeyboardPanelLayout.controlKeyHeight) {
                    viewModel.insertSpace()
                }
                .accessibilityIdentifier("keyboard_key_space")

                KeyButton(label: "return", role: .returnKey, height: KeyboardPanelLayout.controlKeyHeight) {
                    viewModel.insertReturn()
                }
                .frame(width: 92)
                .accessibilityIdentifier("keyboard_key_return")
            }
            .accessibilityIdentifier("keyboard_row_controls")
        }
        .frame(maxWidth: .infinity)
        .frame(height: KeyboardPanelLayout.keyGridHeight, alignment: .bottom)
    }

    private func keyRow(_ keys: [String], keyHeight: CGFloat) -> some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in
                KeyButton(label: viewModel.isShiftEnabled ? key.uppercased() : key, role: .letter, height: keyHeight) {
                    viewModel.insert(key)
                }
            }
        }
    }

    private var isTypingKeyboardVisible: Bool {
        switch viewModel.panelMode {
        case .keyboard:
            return viewModel.actionError == nil
        case .actions:
            return viewModel.actionPanelState == nil
        case .rewriteOptions:
            return viewModel.rewriteOptionsState == nil
        case .correctionDetail:
            return viewModel.currentCorrectionCard == nil && !viewModel.isGrammarCorrectionLoading
        case .correctionComplete:
            return false
        }
    }
}

private struct KeyboardAIToolbar: View {
    let state: KeyboardToolbarState
    let isPerformingAIAction: Bool
    let actionsEnabled: Bool
    let statusActionEnabled: Bool
    let onStatus: () -> Void
    let onSparkle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            Button(action: performStatusAction) {
                statusContent
            }
            .buttonStyle(.plain)
            .disabled(!statusActionEnabled)
            .accessibilityIdentifier("ai_toolbar_status_action")
            sparkleButton
        }
        .frame(minHeight: KeyboardPanelLayout.toolbarHeight)
        .padding(.horizontal, 8)
        .padding(.vertical, KeyboardPanelLayout.toolbarVerticalPadding)
        .background(KeyboardColors.toolbarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                if state.showsIssueCount {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(OpenKeyboardTheme.Semantic.error)
                    Text("\(state.issueCount)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(OpenKeyboardTheme.Text.inverse)
                } else if state.showsBrandMark && actionsEnabled {
                    OpenKeyboardBrandMark(size: 36, symbolSize: 16)
                } else {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(OpenKeyboardTheme.Surface.warningBackground)
                    Image(systemName: state.leadingSystemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(OpenKeyboardTheme.Semantic.warning)
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!statusActionEnabled)
        .accessibilityIdentifier(state.showsIssueCount ? "keyboard_issue_count_badge" : "keyboard_openkeyboard_icon")
        .accessibilityLabel(state.showsIssueCount ? "\(state.issueCount) writing suggestions" : "Open Keyboard status")
    }

    private var statusContent: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
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
            if isPerformingAIAction {
                ProgressView().scaleEffect(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(actionsEnabled ? OpenKeyboardTheme.Surface.brandPanelBackground : KeyboardColors.panelBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sparkleButton: some View {
        Button(action: onSparkle) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .foregroundColor(actionsEnabled ? OpenKeyboardTheme.Text.inverse : .secondary)
        .background(actionsEnabled ? OpenKeyboardTheme.Semantic.primaryAction : KeyboardColors.panelBackground.opacity(0.72))
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
            if state.isCarouselVisible {
                actionCarousel
                .padding(.bottom, 7)
            }
            Divider()
                .overlay(OpenKeyboardTheme.Stroke.control.opacity(0.5))
            controlRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: KeyboardPanelLayout.expandedPanelMinHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(KeyboardColors.overlayBackground)
                .shadow(color: OpenKeyboardTheme.Shadow.overlay, radius: 16, x: 0, y: 6)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai_action_panel")
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
                Text(selectedOption.text)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(OpenKeyboardTheme.Text.primary)
                    .lineLimit(state.isCarouselVisible ? 4 : 6)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ai_action_result_text")
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
            minHeight: state.isCarouselVisible ? 84 : 132,
            maxHeight: .infinity,
            alignment: state.selectedOption == nil ? .center : .topLeading
        )
        .padding(.top, 10)
        .layoutPriority(1)
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
        .frame(height: 38)
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
            .disabled(state.selectedOption == nil || state.isLoading)
            .opacity(state.selectedOption == nil || state.isLoading ? 0.42 : 1)
            .accessibilityIdentifier("ai_action_apply")
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
        .frame(maxWidth: .infinity, minHeight: KeyboardPanelLayout.expandedPanelMinHeight, maxHeight: .infinity, alignment: .topLeading)
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
    var role: KeyRole = .letter
    let height: CGFloat
    var isAccent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: OpenKeyboardTheme.Shadow.key, radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var font: Font {
        switch role {
        case .letter: return .system(size: 25, weight: .regular)
        case .space: return .system(size: 16, weight: .regular)
        case .returnKey, .modifier: return .system(size: label.count > 2 ? 16 : 22, weight: .regular)
        }
    }

    private var backgroundColor: Color {
        if isAccent { return OpenKeyboardTheme.Semantic.primaryAction.opacity(0.32) }
        switch role {
        case .letter, .space:
            return KeyboardColors.keyBackground
        case .modifier, .returnKey:
            return KeyboardColors.modifierKeyBackground
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
