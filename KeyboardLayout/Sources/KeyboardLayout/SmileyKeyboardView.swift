#if canImport(SwiftUI)
import SwiftUI

public struct SmileyKeyboardStyle {
    public var keyBackground: Color
    public var controlBackground: Color
    public var accent: Color
    public var minimumCellWidth: Double
    public var maximumCellWidth: Double
    public var spacing: Double
    public init(keyBackground: Color = .clear, controlBackground: Color = .secondary.opacity(0.15),
                accent: Color = .primary, minimumCellWidth: Double = 44,
                maximumCellWidth: Double = 64, spacing: Double = 4) {
        self.keyBackground = keyBackground; self.controlBackground = controlBackground; self.accent = accent
        self.minimumCellWidth = minimumCellWidth; self.maximumCellWidth = maximumCellWidth; self.spacing = spacing
    }
}
public struct SmileyKeyboardLabels {
    public var back: String
    public var backAccessibility: String
    public var delete: String
    public var nextKeyboard: String
    public var empty: String
    public var search: String
    public var cancel: String
    public init(back: String = "ABC", backAccessibility: String = "Back to typing", delete: String = "Delete",
                nextKeyboard: String = "Next keyboard", empty: String = "No emoji available",
                search: String = "Search Emoji", cancel: String = "Cancel") {
        self.back = back; self.backAccessibility = backAccessibility; self.delete = delete
        self.nextKeyboard = nextKeyboard; self.empty = empty; self.search = search; self.cancel = cancel
    }
}

/// Horizontal three-row browsing and a bottom category strip. Search input is supplied
/// by the host; a keyboard extension must not summon a nested system keyboard.
public struct SmileyKeyboardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    public let state: SmileyState
    public let showsSystemKeyboardSwitch: Bool
    public let style: SmileyKeyboardStyle
    public let labels: SmileyKeyboardLabels
    public let onAction: (SmileyAction) -> Void
    public init(state: SmileyState, showsSystemKeyboardSwitch: Bool = true,
                style: SmileyKeyboardStyle = .init(), labels: SmileyKeyboardLabels = .init(),
                onAction: @escaping (SmileyAction) -> Void) {
        self.state = state; self.showsSystemKeyboardSwitch = showsSystemKeyboardSwitch
        self.style = style; self.labels = labels; self.onAction = onAction
    }
    public var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button { onAction(.beginSearch) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").font(.system(size: 18))
                        Text(state.searchQuery.isEmpty ? labels.search : state.searchQuery)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        if state.isSearching { Rectangle().frame(width: 1, height: 22).accessibilityHidden(true) }
                    }
                    .font(.callout).foregroundStyle(state.searchQuery.isEmpty ? .secondary : .primary)
                    .padding(.horizontal, 10).frame(minHeight: 36)
                    .background(style.controlBackground, in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel(labels.search)
                .accessibilityValue(state.searchQuery)
                .accessibilityIdentifier("smiley_search")
                if state.isSearching {
                    Button { onAction(.endSearch) } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "xmark").font(.system(size: 20))
                        } else { Text(labels.cancel).font(.callout) }
                    }
                    .accessibilityLabel(labels.cancel).accessibilityHint("Ends emoji search")
                    .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("smiley_search_cancel")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(state.isSearching && !state.searchQuery.isEmpty ? "SEARCH RESULTS" : (state.selectedSection?.label.uppercased() ?? "EMOJI"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geometry in
                let rows = state.isSearching ? 1 : max(1, min(3, Int(geometry.size.height / 46)))
                let items = state.visibleItems
                if let item = state.variantItem {
                    HStack(spacing: 0) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 2) {
                                variantButton(.init(id: item.id, text: item.text, label: item.label))
                                ForEach(item.variants) { variant in variantButton(variant) }
                            }
                        }.scrollIndicators(.hidden)
                        Button { onAction(.dismissVariants) } label: {
                            Image(systemName: "xmark").font(.system(size: 18)).frame(width: 44, height: 44)
                        }.accessibilityLabel("Close skin tones").accessibilityIdentifier("smiley_variants_close")
                    }
                    .padding(4)
                    .background(style.controlBackground, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("smiley_variants")
                } else if items.isEmpty {
                    Text(state.isSearching ? "No emoji found" : (state.selectedCategoryID == "recent" ? "No recently used emoji" : labels.empty))
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { scroll in
                        ScrollView(.horizontal) {
                            LazyHGrid(rows: Array(repeating: GridItem(.fixed(44), spacing: 2), count: rows), spacing: style.spacing) {
                                ForEach(items) { item in
                                    Button { onAction(.activateItem(item.id)) } label: {
                                        Text(item.text).font(.system(size: 32)).lineLimit(1).minimumScaleFactor(0.6)
                                            .frame(width: SmileyGridMetrics(availableWidth: geometry.size.width, minimumCellWidth: style.minimumCellWidth, maximumCellWidth: style.maximumCellWidth, spacing: style.spacing).cellWidth, height: 44)
                                            .background(style.keyBackground)
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel(item.label)
                                    .accessibilityHint(item.variants.isEmpty ? "" : "Touch and hold for skin tones")
                                    .accessibilityIdentifier("smiley_item_" + item.id)
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.45, maximumDistance: 8)
                                            .onEnded { _ in onAction(.showVariants(item.id)) }
                                    )
                                    .accessibilityActions {
                                        if !item.variants.isEmpty {
                                            Button("Skin tones") { onAction(.showVariants(item.id)) }
                                        }
                                    }
                                    .id(item.id)
                                }
                            }.padding(.horizontal, 4)
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: state.selectedCategoryID) { _ in
                            if let id = items.first?.id { scroll.scrollTo(id, anchor: .leading) }
                        }
                        .onChange(of: state.searchQuery) { _ in
                            if let id = items.first?.id { scroll.scrollTo(id, anchor: .leading) }
                        }
                    }
                }
            }
            if !state.isSearching {
                HStack(spacing: 0) {
                    Button(labels.back) { onAction(.returnToTyping) }
                        .font(.system(size: 15, weight: .medium)).frame(width: 44, height: 44)
                        .accessibilityLabel(labels.backAccessibility).accessibilityIdentifier("smiley_back_to_typing")
                    ScrollViewReader { scroll in
                        ScrollView(.horizontal) {
                            HStack(spacing: 0) {
                                ForEach(state.snapshot.sections) { section in
                                    Button { onAction(.selectCategory(section.id)) } label: {
                                        Image(systemName: section.symbol).font(.system(size: 20))
                                            .foregroundStyle(state.selectedCategoryID == section.id ? style.accent : .secondary)
                                            .frame(width: 44, height: 44)
                                            .background {
                                                if state.selectedCategoryID == section.id {
                                                    Circle().fill(style.controlBackground).padding(5)
                                                }
                                            }
                                    }
                                    .accessibilityLabel(section.label)
                                    .accessibilityAddTraits(state.selectedCategoryID == section.id ? .isSelected : [])
                                    .accessibilityIdentifier("smiley_category_" + section.id).id(section.id)
                                }
                            }
                        }.scrollIndicators(.hidden)
                        .onChange(of: state.selectedCategoryID) { id in
                            if let id { scroll.scrollTo(id, anchor: .center) }
                        }
                    }
                    Button { onAction(.deleteBackward) } label: {
                        Image(systemName: "delete.left").font(.system(size: 22)).frame(width: 44, height: 44)
                    }.accessibilityLabel(labels.delete).accessibilityIdentifier("smiley_delete")
                    if showsSystemKeyboardSwitch {
                        Button { onAction(.nextSystemKeyboard) } label: {
                            Image(systemName: "globe").font(.system(size: 21)).frame(width: 44, height: 44)
                        }.accessibilityLabel(labels.nextKeyboard).accessibilityIdentifier("smiley_next_keyboard")
                    }
                }
            }
        }
        .buttonStyle(.plain).foregroundStyle(.primary)
        .accessibilityIdentifier("smiley_keyboard")
    }
    private func variantButton(_ variant: SmileyVariant) -> some View {
        Button { onAction(.activateItem(variant.id)) } label: {
            Text(variant.text).font(.system(size: 32)).frame(width: 44, height: 44)
        }
        .accessibilityLabel(variant.label)
        .accessibilityIdentifier("smiley_variant_" + variant.id)
    }
}
#endif
