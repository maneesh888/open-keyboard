//
//  KeyboardVisualPreviewView.swift
//  OpenKeyboard
//

import SwiftUI

enum KeyboardVisualPreviewPanel: String {
    case keyboard
    case actions
    case correctionComplete
}

struct KeyboardVisualPreviewView: View {
    let panel: KeyboardVisualPreviewPanel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 7) {
                previewToolbar

                switch panel {
                case .keyboard:
                    keyGrid
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

    private var previewToolbar: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(OpenKeyboardTheme.Surface.successBackground)
                Image(systemName: "keyboard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(OpenKeyboardTheme.Semantic.success)
            }
            .frame(width: 34, height: 34)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Open Keyboard AI")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("Ready")
                        .font(.caption2)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(OpenKeyboardTheme.Surface.panelBackground.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Text.inverse)
                .frame(width: 34, height: 34)
                .background(OpenKeyboardTheme.Semantic.primaryAction)
                .clipShape(Circle())
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(OpenKeyboardTheme.Surface.toolbarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("preview_ai_toolbar")
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

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(OpenKeyboardTheme.Surface.iconBackground)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(OpenKeyboardTheme.Semantic.primaryAction)
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
                    .overlay(
                        Circle().stroke(OpenKeyboardTheme.Stroke.control, lineWidth: 1)
                    )
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
                .stroke(OpenKeyboardTheme.Stroke.panel, lineWidth: 1)
        )
        .padding(.horizontal, 2)
        .accessibilityIdentifier("preview_ai_action_panel")
    }

    private var correctionCompletePanel: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Semantic.success)
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
}
