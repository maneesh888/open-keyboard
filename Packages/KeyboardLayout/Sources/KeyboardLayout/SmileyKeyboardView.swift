#if canImport(SwiftUI)
import SwiftUI

public struct SmileyKeyboardStyle {
    public var keyBackground: Color
    public var controlBackground: Color
    public var accent: Color
    public var minimumCellWidth: Double
    public var maximumCellWidth: Double
    public var spacing: Double

    public init(keyBackground: Color = .secondary.opacity(0.12),
                controlBackground: Color = .secondary.opacity(0.2), accent: Color = .accentColor,
                minimumCellWidth: Double = 44, maximumCellWidth: Double = 64, spacing: Double = 6) {
        self.keyBackground = keyBackground
        self.controlBackground = controlBackground
        self.accent = accent
        self.minimumCellWidth = minimumCellWidth
        self.maximumCellWidth = maximumCellWidth
        self.spacing = spacing
    }
}

/// All UI strings can be localized by the consumer, including accessibility-only labels.
public struct SmileyKeyboardLabels {
    public var back: String
    public var backAccessibility: String
    public var delete: String
    public var nextKeyboard: String
    public var empty: String

    public init(back: String = "Back", backAccessibility: String = "Back to typing",
                delete: String = "Delete", nextKeyboard: String = "Next keyboard",
                empty: String = "No emoji available") {
        self.back = back
        self.backAccessibility = backAccessibility
        self.delete = delete
        self.nextKeyboard = nextKeyboard
        self.empty = empty
    }
}

/// Controlled rendering: the consumer retains SmileyState across view/width changes.
/// No UIKit controller, document proxy, catalogue, persistence or AI dependency.
public struct SmileyKeyboardView: View {
    public let state: SmileyState
    public let showsSystemKeyboardSwitch: Bool
    public let style: SmileyKeyboardStyle
    public let labels: SmileyKeyboardLabels
    public let onAction: (SmileyAction) -> Void
    @AccessibilityFocusState private var focusedCategory: String?

    public init(state: SmileyState, showsSystemKeyboardSwitch: Bool = true,
                style: SmileyKeyboardStyle = .init(), labels: SmileyKeyboardLabels = .init(),
                onAction: @escaping (SmileyAction) -> Void) {
        self.state = state
        self.showsSystemKeyboardSwitch = showsSystemKeyboardSwitch
        self.style = style
        self.labels = labels
        self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: 4) {
            if !state.snapshot.sections.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(state.snapshot.sections) { section in
                            Button {
                                onAction(.selectCategory(section.id))
                            } label: {
                                Text(section.label)
                                    .font(.callout)
                                    .padding(.horizontal, 12)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .background(style.controlBackground, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        if state.selectedCategoryID == section.id {
                                            RoundedRectangle(cornerRadius: 8).stroke(style.accent, lineWidth: 2)
                                        }
                                    }
                            }
                            .accessibilityAddTraits(state.selectedCategoryID == section.id ? .isSelected : [])
                            .accessibilityIdentifier("smiley_category_" + section.id)
                            .accessibilityFocused($focusedCategory, equals: section.id)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: false, vertical: true)
            }

            GeometryReader { geometry in
                let metrics = SmileyGridMetrics(
                    availableWidth: geometry.size.width,
                    minimumCellWidth: style.minimumCellWidth,
                    maximumCellWidth: style.maximumCellWidth,
                    spacing: style.spacing
                )
                if let section = state.selectedSection, !section.items.isEmpty {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(metrics.cellWidth), spacing: metrics.spacing),
                                                  count: metrics.columns), spacing: metrics.spacing) {
                            ForEach(section.items) { item in
                                Button {
                                    onAction(.activateItem(item.id))
                                } label: {
                                    Text(item.text)
                                        .font(.system(size: 28))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .frame(width: metrics.cellWidth, height: 44)
                                        .background(style.keyBackground, in: RoundedRectangle(cornerRadius: 8))
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel(item.label)
                                .accessibilityIdentifier("smiley_item_" + section.id + "_" + item.id)
                            }
                        }
                    }
                    .id(section.id)
                } else {
                    ScrollView {
                        Text(labels.empty).font(.callout).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(labels.back) { onAction(.returnToTyping) }
                    .accessibilityLabel(labels.backAccessibility)
                    .accessibilityIdentifier("smiley_back_to_typing")
                Spacer(minLength: 0)
                Button { onAction(.deleteBackward) } label: { Image(systemName: "delete.left") }
                    .accessibilityLabel(labels.delete)
                    .accessibilityIdentifier("smiley_delete")
                if showsSystemKeyboardSwitch {
                    Button { onAction(.nextSystemKeyboard) } label: { Image(systemName: "globe") }
                        .accessibilityLabel(labels.nextKeyboard)
                        .accessibilityIdentifier("smiley_next_keyboard")
                }
            }
            .buttonStyle(SmileyControlStyle(background: style.controlBackground))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .onChange(of: state.selectedCategoryID) { id in
            // Recover assistive focus after a host removes the selected category.
            if let focusedCategory, !state.snapshot.sections.contains(where: { $0.id == focusedCategory }) {
                self.focusedCategory = id
            }
        }
        .accessibilityIdentifier("smiley_keyboard")
    }
}

private struct SmileyControlStyle: ButtonStyle {
    let background: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(background.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}
#endif
