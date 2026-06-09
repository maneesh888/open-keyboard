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
            case .correctionComplete:
                CorrectionCompletePanel(onBackToKeyboard: { viewModel.showKeyboardPanel() })
            }

        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(KeyboardColors.keyboardBackground)
        .onAppear { viewModel.reloadConfig() }
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

                KeyButton(label: "🌐", role: .modifier) {
                    viewModel.switchKeyboard()
                }
                    .frame(width: 52)
                    .accessibilityIdentifier("keyboard_key_next_keyboard")

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
    let onSparkle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            statusContent
            sparkleButton
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(KeyboardColors.toolbarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("ai_toolbar")
    }

    private var statusIcon: some View {
        ZStack {
            Circle().fill(actionsEnabled ? Color.green.opacity(0.16) : Color.orange.opacity(0.18))
            Image(systemName: state.leadingSystemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(actionsEnabled ? .green : .orange)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    private var statusContent: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(state.subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
        .background(KeyboardColors.panelBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sparkleButton: some View {
        Button(action: onSparkle) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
        }
        .foregroundColor(actionsEnabled ? .white : .secondary)
        .background(actionsEnabled ? Color.accentColor : KeyboardColors.panelBackground.opacity(0.72))
        .clipShape(Circle())
        .disabled(!actionsEnabled)
        .accessibilityIdentifier("ai_sparkle_action")
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
                    Circle().fill(Color.accentColor.opacity(0.14))
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Improve your writing")
                        .font(.headline.weight(.semibold))
                    Text("Choose what Open Keyboard should do next.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                    Circle().stroke(Color.secondary.opacity(0.24), lineWidth: 1)
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
        .frame(maxWidth: .infinity, minHeight: 232, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(KeyboardColors.overlayBackground)
                .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
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
                    .foregroundColor(action == .fixGrammar ? .white : .accentColor)
                    .background(action == .fixGrammar ? Color.accentColor : Color.accentColor.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 12)
        }
        .foregroundColor(actionsEnabled ? .primary : .secondary)
        .background(KeyboardColors.panelBackground.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(action == .fixGrammar ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.18), lineWidth: action == .fixGrammar ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .disabled(!actionsEnabled)
        .accessibilityIdentifier("ai_action_\(action.rawValue)")
    }
}

private struct CorrectionCompletePanel: View {
    let onBackToKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(.accentColor)
                .padding(.bottom, 4)

            Text("All Done")
                .font(.title3.weight(.bold))

            Text("There are no more suggestions.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: onBackToKeyboard) {
                Text("Back to Keyboard")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 42)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 1.5)
            )
            .padding(.top, 4)
            .accessibilityIdentifier("back_to_keyboard")
        }
        .frame(maxWidth: .infinity, minHeight: 226)
        .padding(.horizontal, 18)
        .padding(.vertical, 26)
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
    var isAccent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, minHeight: role == .letter ? 52 : 46)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 1)
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
        if isAccent { return Color.accentColor.opacity(0.32) }
        switch role {
        case .letter, .space:
            return KeyboardColors.keyBackground
        case .modifier, .returnKey:
            return KeyboardColors.modifierKeyBackground
        }
    }
}

private enum KeyboardColors {
    static let keyboardBackground = Color(.systemGray5)
    static let toolbarBackground = Color(.systemGray4).opacity(0.72)
    static let panelBackground = Color(.systemBackground)
    static let overlayBackground = Color(.secondarySystemBackground).opacity(0.96)
    static let keyBackground = Color(.systemBackground)
    static let modifierKeyBackground = Color(.systemGray3)
}
