import SwiftUI

/// Four-row typing keyboard. Width is measured from the containing view, never the screen.
public struct TypingKeyboardView: View {
    public let state: KeyboardTypingState
    public let showsSystemKeyboardSwitch: Bool
    public let returnLabel: String
    public let style: KeyboardStyle
    public let metrics: KeyboardMetrics
    public let onAction: (KeyboardTypingAction) -> Void

    public init(state: KeyboardTypingState, showsSystemKeyboardSwitch: Bool = false,
                returnLabel: String = "return", style: KeyboardStyle = .init(),
                metrics: KeyboardMetrics = .init(), onAction: @escaping (KeyboardTypingAction) -> Void) {
        self.state = state; self.showsSystemKeyboardSwitch = showsSystemKeyboardSwitch
        self.returnLabel = returnLabel; self.style = style; self.metrics = metrics; self.onAction = onAction
    }
    public var body: some View {
        GeometryReader { geometry in
            let positions = KeyboardKeyPositions(availableWidth: geometry.size.width, spacing: metrics.horizontalSpacing)
            let inputMode = state.mode

            VStack(spacing: metrics.keyRowSpacing) {
                keyRow(
                    positions.topRow(
                        keyIDs: inputMode.topRowKeys,
                        keyHeight: metrics.letterKeyHeight
                    )
                )
                .accessibilityIdentifier("keyboard_row_qwerty")

                keyRow(
                    positions.middleRow(
                        keyIDs: inputMode.middleRowKeys,
                        usesInset: inputMode.usesMiddleRowInset,
                        keyHeight: metrics.letterKeyHeight
                    )
                )
                .accessibilityIdentifier("keyboard_row_home")

                let bottomKeyWidth = inputMode == .symbols
                    ? positions.symbolBottomKeyWidth
                    : positions.letterWidth
                let bottomLetterLayout = positions.bottomLetterRow(
                    leadingKeyID: "keyboard_shift",
                    letterKeyIDs: inputMode.bottomRowKeys,
                    trailingKeyID: "keyboard_delete",
                    keyWidth: bottomKeyWidth,
                    keyHeight: metrics.letterKeyHeight
                )
                HStack(spacing: 0) {
                    ForEach(bottomLetterLayout.keys) { target in
                        if target.id == "keyboard_shift" {
                            KeyButton(
                                label: inputMode.leadingBottomKeyLabel,
                                role: .modifier,
                                target: target, style: style, metrics: metrics,
                                isAccent: state.isShiftEnabled
                            ) {
                                if inputMode == .letters {
                                    onAction(.shift)
                                } else {
                                    onAction(.symbols)
                                }
                            }
                        } else if target.id == "keyboard_delete" {
                            KeyButton(label: "⌫", role: .modifier, target: target, style: style, metrics: metrics) {
                                onAction(.deleteBackward)
                            }
                        } else {
                            KeyButton(
                                label: state.isShiftEnabled ? target.id.uppercased() : target.id,
                                role: .letter,
                                target: target, style: style, metrics: metrics
                            ) {
                                onAction(.character(target.id))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("keyboard_row_bottom_letters")

                let controlLayout = positions.controlRow(
                    keyIDs: showsSystemKeyboardSwitch
                        ? ["keyboard_numbers", "keyboard_emoji", "keyboard_next", "keyboard_space", "keyboard_return"]
                        : ["keyboard_numbers", "keyboard_emoji", "keyboard_space", "keyboard_return"],
                    keyHeight: metrics.controlKeyHeight
                )
                HStack(spacing: 0) {
                    ForEach(controlLayout.keys) { target in
                        switch target.id {
                        case "keyboard_numbers":
                            KeyButton(label: inputMode.bottomControlKeyLabel, role: .modifier, target: target, style: style, metrics: metrics) {
                                onAction(.numbers)
                            }
                            .accessibilityIdentifier("keyboard_key_numbers")
                        case "keyboard_emoji":
                            KeyButton(label: "Emoji", systemImage: "face.smiling", role: .modifier, target: target, style: style, metrics: metrics) {
                                onAction(.smileys)
                            }
                            .accessibilityIdentifier("keyboard_key_emoji")
                        case "keyboard_next":
                            KeyButton(label: "Next keyboard", systemImage: "globe", role: .modifier, target: target, style: style, metrics: metrics) {
                                onAction(.nextKeyboard)
                            }
                            .accessibilityIdentifier("keyboard_key_next")
                        case "keyboard_space":
                            KeyButton(label: "space", role: .space, target: target, style: style, metrics: metrics) {
                                onAction(.space)
                            }
                            .accessibilityIdentifier("keyboard_key_space")
                        default:
                            KeyButton(label: returnLabel, role: .returnKey, target: target, style: style, metrics: metrics) {
                                onAction(.return)
                            }
                            .accessibilityIdentifier("keyboard_key_return")
                        }
                    }
                }
                .accessibilityIdentifier("keyboard_row_controls")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, metrics.keyShadowAllowance)
        .frame(height: metrics.keyGridHeight, alignment: .top)
    }

    private func keyRow(_ layout: KeyboardTouchRow) -> some View {
        HStack(spacing: 0) {
            ForEach(layout.keys) { target in
                KeyButton(
                    label: state.isShiftEnabled ? target.id.uppercased() : target.id,
                    role: .letter,
                    target: target, style: style, metrics: metrics
                ) {
                    onAction(.character(target.id))
                }
            }
        }
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
    let target: KeyboardTouchKey
    let style: KeyboardStyle
    let metrics: KeyboardMetrics
    var isAccent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.001))

                Group {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(style.symbolFont)
                            .symbolRenderingMode(.monochrome)
                    } else {
                        Text(label)
                            .font(font)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                .foregroundColor(style.foreground)
                .frame(
                    width: target.visualFrame.width,
                    height: metrics.keyCapHeight
                )
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
                .shadow(color: style.shadow, radius: 0, x: 0, y: 1)
                .offset(x: target.leadingTouchInset)
            }
            .frame(
                width: target.touchFrame.width,
                height: target.touchFrame.height,
                alignment: .topLeading
            )
        }
        .buttonStyle(.plain)
        .frame(
            width: target.touchFrame.width,
            height: target.touchFrame.height,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .accessibilityLabel(label)
    }

    private var font: Font {
        switch role {
        case .letter: return style.letterFont
        case .space: return style.controlFont
        case .returnKey, .modifier: return label.count > 2 ? style.controlFont : style.symbolFont
        }
    }

    private var backgroundColor: Color {
        if isAccent { return style.accent }
        switch role {
        case .letter, .space:
            return style.key
        case .modifier, .returnKey:
            return style.control
        }
    }
}
