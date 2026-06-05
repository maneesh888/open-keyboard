//
//  KeyboardView.swift
//  OpenKeyboardExtension
//

import SwiftUI

struct KeyboardView: View {
    @ObservedObject var viewModel: KeyboardViewModel

    private let rows = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]

    var body: some View {
        VStack(spacing: 7) {
            aiHeaderBar
            aiActionBar

            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key in
                        KeyButton(label: viewModel.isShiftEnabled ? key.uppercased() : key) {
                            viewModel.insert(key)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                KeyButton(label: "⇧", weight: 1.2, isAccent: viewModel.isShiftEnabled) {
                    viewModel.toggleShift()
                }

                KeyButton(label: "🌐", weight: 1.0) {
                    viewModel.switchKeyboard()
                }

                KeyButton(label: "space", weight: 4.5) {
                    viewModel.insertSpace()
                }

                KeyButton(label: "return", weight: 1.8) {
                    viewModel.insertReturn()
                }

                KeyButton(label: "⌫", weight: 1.2) {
                    viewModel.deleteBackward()
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray5))
        .onAppear { viewModel.reloadConfig() }
    }

    private var headerTitle: String {
        if !viewModel.hasFullAccess { return "Full Access required" }
        return viewModel.config.isConfigured ? "Open Keyboard AI" : "Gateway not configured"
    }

    private var aiHeaderBar: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.canRunAIAction ? "sparkles" : "exclamationmark.triangle.fill")
                .foregroundColor(viewModel.canRunAIAction ? .purple : .orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)

                Text(viewModel.aiStatus)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if viewModel.isPerformingAIAction {
                ProgressView()
                    .scaleEffect(0.72)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var aiActionBar: some View {
        HStack(spacing: 6) {
            ForEach(KeyboardAIAction.allCases) { action in
                AIActionButton(action: action, isEnabled: viewModel.canRunAIAction) {
                    viewModel.performAIAction(action)
                }
            }
        }
        .opacity(viewModel.canRunAIAction ? 1 : 0.55)
    }
}

private struct AIActionButton: View {
    let action: KeyboardAIAction
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: action.iconName)
                    .font(.caption2)
                Text(action.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(isEnabled ? .white : .secondary)
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.horizontal, 5)
            .background(isEnabled ? Color.purple : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
        .accessibilityIdentifier("ai_action_\(action.rawValue)")
    }
}

private struct KeyButton: View {
    let label: String
    var weight: CGFloat = 1
    var isAccent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: label.count > 1 ? 14 : 21, weight: .medium))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(isAccent ? Color.accentColor.opacity(0.35) : Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .layoutPriority(Double(weight))
    }
}
