//
//  KeyboardView.swift
//  OpenKeyboardExtension
//

import SwiftUI

struct KeyboardView: View {
    @ObservedObject var viewModel: KeyboardViewModel


    var body: some View {
        VStack(spacing: 7) {
            KeyboardAIToolbar(
                state: viewModel.toolbarState,
                isPerformingAIAction: viewModel.isPerformingAIAction,
                actionsEnabled: viewModel.canRunAIAction,
                onStatusIcon: { viewModel.handleToolbarLogoTap() },
                onSparkle: { viewModel.showActionPanel() }
            )

            switch viewModel.panelMode {
            case .keyboard:
                keyGrid
            case .actions:
                AIActionPanel(
                    actionsEnabled: viewModel.canRunAIAction,
                    onAction: { viewModel.performAIAction($0) },
                    onBackToKeyboard: { viewModel.showKeyboardPanel() }
                )
            case .analyzing:
                keyGrid
            case .allGood:
                AllGoodPanel(onBackToKeyboard: { viewModel.showKeyboardPanel() })
            case .analysisFailed:
                AnalysisFailedPanel(
                    message: viewModel.analysisErrorMessage,
                    onRetry: { viewModel.retryAnalysis() },
                    onBackToKeyboard: { viewModel.showKeyboardPanel() }
                )
            case .correctionDetail:
                if let card = viewModel.currentCorrectionCard {
                    CorrectionDetailPanel(
                        card: card,
                        currentPosition: viewModel.suggestionState?.currentCorrectionPosition ?? 1,
                        totalCount: viewModel.suggestionState?.correctionCount ?? 1,
                        canMovePrevious: viewModel.suggestionState?.canMoveToPreviousCorrection ?? false,
                        canMoveNext: viewModel.suggestionState?.canMoveToNextCorrection ?? false,
                        onPrevious: { viewModel.moveToPreviousSuggestion() },
                        onNext: { viewModel.moveToNextSuggestion() },
                        onApply: { viewModel.applyCurrentSuggestion() },
                        onDismiss: { viewModel.dismissCurrentSuggestion() },
                        onBackToKeyboard: { viewModel.showKeyboardPanel() }
                    )
                } else {
                    AllGoodPanel(onBackToKeyboard: { viewModel.showKeyboardPanel() })
                }
            case .correctionComplete:
                CorrectionCompletePanel(onBackToKeyboard: { viewModel.showKeyboardPanel() })
            }

        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .background(keyboardChromeShape.fill(KeyboardColors.keyboardBackground))
        .overlay(
            keyboardChromeShape.stroke(OpenKeyboardTheme.Stroke.control.opacity(0.65), lineWidth: 1)
        )
        .clipShape(keyboardChromeShape)
        .padding(.horizontal, 5)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .onAppear { viewModel.reloadConfig() }
    }

    private var keyboardChromeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }

    private var keyGrid: some View {
        VStack(spacing: 8) {
            keyRow(viewModel.isNumbersEnabled ? ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] : ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"])
                .accessibilityIdentifier("keyboard_row_qwerty")

            keyRow(viewModel.isNumbersEnabled ? ["-", "/", ":", ";", "(", ")", "$", "&", "@"] : ["a", "s", "d", "f", "g", "h", "j", "k", "l"])
                .padding(.horizontal, 18)
                .accessibilityIdentifier("keyboard_row_home")

            HStack(spacing: 6) {
                KeyButton(label: viewModel.isNumbersEnabled ? "#+=" : "⇧", role: .modifier, isAccent: viewModel.isShiftEnabled) {
                    if viewModel.isNumbersEnabled {
                        viewModel.toggleNumbers()
                    } else {
                        viewModel.toggleShift()
                    }
                }
                .frame(width: 52)

                keyRow(viewModel.isNumbersEnabled ? [".", ",", "?", "!", "'", "\"", "_"] : ["z", "x", "c", "v", "b", "n", "m"])

                KeyButton(label: "⌫", role: .modifier) {
                    viewModel.deleteBackward()
                }
                .frame(width: 52)
            }
            .accessibilityIdentifier("keyboard_row_bottom_letters")

            HStack(spacing: 6) {
                KeyButton(label: viewModel.isNumbersEnabled ? "ABC" : "123", role: .modifier) {
                    viewModel.toggleNumbers()
                }
                    .frame(width: 58)
                    .accessibilityIdentifier("keyboard_key_numbers")

                KeyButton(systemImage: "globe", role: .modifier, iconSize: 24, iconColor: OpenKeyboardTheme.Text.primary) {
                    viewModel.switchKeyboard()
                }
                    .frame(width: 54)
                    .accessibilityIdentifier("keyboard_key_next_keyboard")
                    .accessibilityLabel("Next Keyboard")

                KeyButton(label: "space", role: .space) {
                    viewModel.insertSpace()
                }
                .accessibilityIdentifier("keyboard_key_space")

                KeyButton(label: "return", role: .returnKey) {
                    viewModel.insertReturn()
                }
                .frame(width: 92)
                .accessibilityIdentifier("keyboard_key_return")
            }
            .accessibilityIdentifier("keyboard_row_controls")
        }
    }

    private func keyRow(_ keys: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in
                KeyButton(label: viewModel.isShiftEnabled ? key.uppercased() : key, role: .letter) {
                    viewModel.insert(key)
                }
            }
        }
    }
}

private struct KeyboardAIToolbar: View {
    let state: KeyboardToolbarState
    let isPerformingAIAction: Bool
    let actionsEnabled: Bool
    let onStatusIcon: () -> Void
    let onSparkle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            Button(action: onStatusIcon) {
                statusContent
            }
            .buttonStyle(.plain)
            .disabled(!actionsEnabled)
            .accessibilityIdentifier("ai_toolbar_status_action")
            sparkleButton
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(KeyboardColors.toolbarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai_toolbar")
    }

    private var statusIcon: some View {        Button(action: onStatusIcon) {
            Group {
                if state.showsIssueCount {
                    Text("\(state.issueCount)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(OpenKeyboardTheme.Text.inverse)
                        .frame(width: 36, height: 36)
                        .background(OpenKeyboardTheme.Semantic.error)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                } else if state.showsBrandMark {
                    toolbarLogoIcon
                } else {
                    Image(systemName: state.leadingSystemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(OpenKeyboardTheme.Semantic.warning)
                        .frame(width: 36, height: 36)
                        .background(OpenKeyboardTheme.Surface.warningBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!actionsEnabled)
        .accessibilityIdentifier(state.showsIssueCount ? "keyboard_issue_count_badge" : "keyboard_openkeyboard_icon")
        .accessibilityLabel(state.showsIssueCount ? "\(state.issueCount) writing suggestions" : "Open Keyboard analysis")
        .accessibilityHint(state.showsIssueCount ? "Shows writing suggestions" : "Shows analysis progress")
    }

    private var toolbarLogoIcon: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return Image("OpenKeyboardToolbarIcon")
            .resizable()
            .scaledToFill()
            .frame(width: 36, height: 36)
            .clipShape(shape)
            .overlay(
                shape.stroke(OpenKeyboardTheme.Stroke.control.opacity(0.45), lineWidth: 1)
            )
    }

    private var statusContent: some View {
        Group {
            if state.showsIssueCount {
                HStack(spacing: 7) {
                    if let correction = state.compactCorrection {
                        compactSuggestionBlock(
                            hint: correction.label,
                            value: correction.value,
                            valueColor: OpenKeyboardTheme.Semantic.primaryAction,
                            identifier: "keyboard_compact_correction_block"
                        )
                        .layoutPriority(2)
                    }

                    if let prediction = state.compactPrediction {
                        compactSuggestionBlock(
                            hint: "Next word",
                            value: prediction,
                            valueColor: .primary,
                            identifier: "keyboard_prediction_block"
                        )
                        .layoutPriority(1)
                    }

                    Spacer(minLength: 0)
                }
                .accessibilityIdentifier("keyboard_compact_suggestion_strip")
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(actionsEnabled ? OpenKeyboardTheme.Surface.brandPanelBackground : KeyboardColors.panelBackground.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
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
        .background(KeyboardColors.panelBackground.opacity(0.90), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OpenKeyboardTheme.Stroke.control.opacity(0.55), lineWidth: 1)
        )
        .accessibilityIdentifier(identifier)
    }

    private var sparkleButton: some View {
        Button(action: onSparkle) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .foregroundColor(actionsEnabled ? OpenKeyboardTheme.Text.inverse : .secondary)
        .background(actionsEnabled ? OpenKeyboardTheme.Semantic.primaryAction : KeyboardColors.panelBackground.opacity(0.72))
        .clipShape(Circle())
        .disabled(!actionsEnabled)
        .accessibilityIdentifier("ai_sparkle_action")
        .accessibilityLabel("Open Keyboard AI actions")
        .accessibilityHint("Opens the AI actions menu")
    }
}

private struct AIActionPanel: View {
    let actionsEnabled: Bool
    let onAction: (KeyboardAIAction) -> Void
    let onBackToKeyboard: () -> Void

    var body: some View {
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

                Button(action: onBackToKeyboard) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary)
                .background(KeyboardColors.panelBackground.opacity(0.98))
                .overlay(
                    Circle().stroke(OpenKeyboardTheme.Stroke.control, lineWidth: 1)
                )
                .clipShape(Circle())
                .accessibilityIdentifier("back_to_keyboard")
            }

            VStack(spacing: 8) {
                overlayAction(.fixGrammar, title: "Improve", subtitle: "Fix grammar and clarity", systemImage: "sparkles")
                overlayAction(.rewrite, title: "Rephrase", subtitle: "Make the sentence flow better", systemImage: "arrow.triangle.2.circlepath")
                overlayAction(.summarize, title: "Summarize", subtitle: "Shorten the selected thought", systemImage: "text.bubble")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 232, maxHeight: 302, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(KeyboardColors.overlayBackground)
                .shadow(color: OpenKeyboardTheme.Shadow.overlay, radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(OpenKeyboardTheme.Semantic.primaryAction.opacity(0.55), lineWidth: 1.2)
        )
        .padding(.horizontal, 2)
        .accessibilityIdentifier("ai_action_panel")
    }

    private func overlayAction(_ action: KeyboardAIAction, title: String, subtitle: String, systemImage: String) -> some View {
        Button { onAction(action) } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .foregroundColor(action == .fixGrammar ? OpenKeyboardTheme.Text.inverse : OpenKeyboardTheme.Semantic.primaryAction)
                    .background(action == .fixGrammar ? OpenKeyboardTheme.Semantic.primaryAction : OpenKeyboardTheme.Surface.iconBackground)
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
        }
        .foregroundColor(actionsEnabled ? .primary : .secondary)
        .background(KeyboardColors.panelBackground.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(action == .fixGrammar ? OpenKeyboardTheme.Semantic.primaryAction.opacity(0.9) : OpenKeyboardTheme.Stroke.control.opacity(0.75), lineWidth: action == .fixGrammar ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .disabled(!actionsEnabled)
        .accessibilityIdentifier("ai_action_\(action.rawValue)")
    }
}


private struct AnalyzingTextPanel: View {
    let onBackToKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image("OpenKeyboardToolbarIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(OpenKeyboardTheme.Stroke.control.opacity(0.45), lineWidth: 1)
                )

            ProgressView()
                .tint(OpenKeyboardTheme.Semantic.primaryAction)

            Text("Analyzing your text...")
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 226)
        .padding(.horizontal, 18)
        .padding(.vertical, 26)
        .background(KeyboardColors.overlayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("keyboard_analyzing_panel")
    }
}



private struct CorrectionDetailPanel: View {
    let card: KeyboardCorrectionCard
    let currentPosition: Int
    let totalCount: Int
    let canMovePrevious: Bool
    let canMoveNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onApply: () -> Void
    let onDismiss: () -> Void
    let onBackToKeyboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(OpenKeyboardTheme.Text.inverse)
                    .frame(width: 34, height: 34)
                    .background(OpenKeyboardTheme.Semantic.error, in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(card.categoryTitle)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Text(card.explanation)
                        .font(.caption)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .lineLimit(2)
                }

                Spacer()

                Button(action: onBackToKeyboard) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary)
                .accessibilityIdentifier("correction_detail_close")
            }

            HStack(spacing: 8) {
                correctionToken(title: "Replace", value: card.original, tint: OpenKeyboardTheme.Semantic.error, strikethrough: true)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                correctionToken(title: "With", value: card.replacement, tint: OpenKeyboardTheme.Semantic.primaryAction, strikethrough: false)
            }
            .accessibilityIdentifier("correction_detail_diff")

            if totalCount > 1 {
                HStack(spacing: 10) {
                    Button(action: onPrevious) {
                        Image(systemName: "chevron.left")
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMovePrevious)
                    .opacity(canMovePrevious ? 1 : 0.35)
                    .accessibilityIdentifier("correction_previous")

                    Text("\(currentPosition) of \(totalCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("correction_progress")

                    Button(action: onNext) {
                        Image(systemName: "chevron.right")
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMoveNext)
                    .opacity(canMoveNext ? 1 : 0.35)
                    .accessibilityIdentifier("correction_next")
                }
            }

            HStack(spacing: 10) {
                Button(action: onApply) {
                    Text("Apply")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain)
                .foregroundColor(OpenKeyboardTheme.Text.inverse)
                .background(OpenKeyboardTheme.Semantic.primaryAction, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("correction_apply")

                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain)
                .foregroundColor(OpenKeyboardTheme.Semantic.error)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(OpenKeyboardTheme.Semantic.error, lineWidth: 1.2)
                )
                .accessibilityIdentifier("correction_dismiss")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 232, alignment: .topLeading)
        .background(KeyboardColors.overlayBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(OpenKeyboardTheme.Semantic.error.opacity(0.55), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("keyboard_correction_detail_panel")
        .gesture(
            DragGesture(minimumDistance: 28)
                .onEnded { value in
                    if value.translation.width < -32, canMoveNext { onNext() }
                    if value.translation.width > 32, canMovePrevious { onPrevious() }
                }
        )
    }

    private func correctionToken(title: String, value: String, tint: Color, strikethrough: Bool) -> some View {
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
        .background(KeyboardColors.panelBackground.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct AnalysisFailedPanel: View {
    let message: String
    let onRetry: () -> Void
    let onBackToKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(OpenKeyboardTheme.Surface.errorBackground)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(OpenKeyboardTheme.Semantic.error)
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Analysis failed")
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Text(message)
                        .font(.caption)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 9) {
                Button(action: onBackToKeyboard) {
                    Text("Back to Typing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.plain)
                .foregroundColor(OpenKeyboardTheme.Semantic.primaryAction)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(OpenKeyboardTheme.Semantic.primaryAction, lineWidth: 1.4)
                )
                .accessibilityIdentifier("analysis_back_to_typing")

                Button(action: onRetry) {
                    Text("Retry")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.plain)
                .foregroundColor(OpenKeyboardTheme.Text.inverse)
                .background(OpenKeyboardTheme.Semantic.primaryAction, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("analysis_retry")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .center)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(KeyboardColors.overlayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("keyboard_analysis_failed_panel")
    }
}

private struct AllGoodPanel: View {
    let onBackToKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(OpenKeyboardTheme.Brand.blueGreenGradient)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(OpenKeyboardTheme.Text.inverse)
            }
            .frame(width: 64, height: 64)
            .padding(.bottom, 4)

            Text("All Good")
                .font(.title3.weight(.bold))

            Text("No issues found.")
                .font(.subheadline)
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

            Button(action: onBackToKeyboard) {
                Text("Back to Typing")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 42)
            }
            .buttonStyle(.plain)
            .foregroundColor(OpenKeyboardTheme.Semantic.primaryAction)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(OpenKeyboardTheme.Semantic.primaryAction, lineWidth: 1.5)
            )
            .padding(.top, 4)
            .accessibilityIdentifier("back_to_typing")
        }
        .frame(maxWidth: .infinity, minHeight: 226)
        .padding(.horizontal, 18)
        .padding(.vertical, 26)
        .background(KeyboardColors.overlayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("keyboard_all_good_panel")
    }
}

private struct CorrectionCompletePanel: View {
    let onBackToKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(OpenKeyboardTheme.Brand.blueGreenGradient)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(OpenKeyboardTheme.Text.inverse)
            }
            .frame(width: 64, height: 64)
            .padding(.bottom, 4)

            Text("All Good")
                .font(.title3.weight(.bold))

            Text("No issues found.")
                .font(.subheadline)
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

            Button(action: onBackToKeyboard) {
                Text("Back to Typing")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 42)
            }
            .buttonStyle(.plain)
            .foregroundColor(OpenKeyboardTheme.Semantic.primaryAction)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(OpenKeyboardTheme.Semantic.primaryAction, lineWidth: 1.5)
            )
            .padding(.top, 4)
            .accessibilityIdentifier("back_to_keyboard")
        }
        .frame(maxWidth: .infinity, minHeight: 226)
        .padding(.horizontal, 18)
        .padding(.vertical, 26)
        .background(KeyboardColors.overlayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier("keyboard_all_good_panel")
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
    var systemImage: String?
    var role: KeyRole = .letter
    var isAccent = false
    var iconSize: CGFloat = 21
    var iconColor: Color = OpenKeyboardTheme.Text.secondaryStrong
    let action: () -> Void

    init(label: String, role: KeyRole = .letter, isAccent: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = nil
        self.role = role
        self.isAccent = isAccent
        self.action = action
    }

    init(systemImage: String, role: KeyRole = .modifier, isAccent: Bool = false, iconSize: CGFloat = 21, iconColor: Color = OpenKeyboardTheme.Text.secondaryStrong, action: @escaping () -> Void) {
        self.label = ""
        self.systemImage = systemImage
        self.role = role
        self.isAccent = isAccent
        self.iconSize = iconSize
        self.iconColor = iconColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            keyContent
                .frame(maxWidth: .infinity, minHeight: role == .letter ? 52 : 46)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: OpenKeyboardTheme.Shadow.key, radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var keyContent: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(iconFont)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            Text(label)
                .font(font)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var font: Font {
        switch role {
        case .letter: return .system(size: 25, weight: .regular)
        case .space: return .system(size: 16, weight: .regular)
        case .returnKey, .modifier: return .system(size: label.count > 2 ? 16 : 22, weight: .regular)
        }
    }

    private var iconFont: Font {
        .system(size: iconSize, weight: .medium)
    }

    private var cornerRadius: CGFloat {
        role == .letter ? 10 : 12
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
