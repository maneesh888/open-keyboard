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
        VStack(spacing: 8) {
            suggestionBar

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

    private var suggestionBar: some View {
        HStack {
            Image(systemName: viewModel.config.isConfigured ? "checkmark.circle.fill" : "sparkles")
                .foregroundColor(viewModel.config.isConfigured ? .green : .secondary)

            Text(viewModel.config.isConfigured ? "Gateway paired" : "Pair gateway in Open Keyboard app")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemBackground).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(isAccent ? Color.accentColor.opacity(0.35) : Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .layoutPriority(Double(weight))
    }
}
