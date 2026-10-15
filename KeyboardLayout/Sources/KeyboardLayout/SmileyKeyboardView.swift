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
    @State private var isBrowserReady = false
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
                let cellWidth = SmileyGridMetrics(availableWidth: geometry.size.width - 8,
                    minimumCellWidth: style.minimumCellWidth, maximumCellWidth: style.maximumCellWidth,
                    spacing: style.spacing).cellWidth
                if state.isSearching {
                    searchGrid(cellWidth: cellWidth)
                } else if state.snapshot.sections.isEmpty {
                    Text(labels.empty).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    categoryBrowser(width: geometry.size.width, rows: rows, cellWidth: cellWidth)
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
        .overlayPreferenceValue(SmileyVariantAnchor.self) { anchor in
            if let anchor, let item = state.variantItem {
                GeometryReader { geometry in
                    let source = geometry[anchor]
                    let width = min(geometry.size.width - 8, CGFloat(item.variants.count + 1) * 44 + 12)
                    let left = max(4, min(source.midX - width / 2, geometry.size.width - width - 4))
                    let top = max(2, source.minY - 64)
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { onAction(.dismissVariants) }
                            .accessibilityLabel("Close skin tones")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { onAction(.dismissVariants) }
                            .accessibilityIdentifier("smiley_variants_close")
                        VStack(spacing: 0) {
                            ScrollView(.horizontal) {
                                HStack(spacing: 0) {
                                    variantButton(.init(id: item.id, text: item.text, label: item.label))
                                    ForEach(item.variants) { variant in variantButton(variant) }
                                }.padding(6)
                            }
                            .scrollIndicators(.hidden)
                            .frame(width: width, height: 56)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.12), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
                            SmileyPopupPointer()
                                .fill(.regularMaterial)
                                .frame(width: 16, height: 8)
                                .offset(x: max(14, min(source.midX - left, width - 14)) - width / 2)
                        }
                        .frame(width: width)
                        .offset(x: left, y: top)
                        .accessibilityIdentifier("smiley_variants")
                    }
                }
            }
        }
        .buttonStyle(.plain).foregroundStyle(.primary)
        .accessibilityIdentifier("smiley_keyboard")
    }
    @ViewBuilder
    private func searchGrid(cellWidth: Double) -> some View {
        if state.visibleItems.isEmpty {
            Text("No emoji found").font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    LazyHGrid(rows: [GridItem(.fixed(44))], spacing: style.spacing) {
                        ForEach(state.visibleItems) { item in
                            emojiCell(item, categoryID: nil, width: cellWidth).id(item.id)
                        }
                    }.padding(.horizontal, 4)
                }
                .scrollIndicators(.hidden)
                .onChange(of: state.searchQuery) { _ in
                    if let id = state.visibleItems.first?.id { scroll.scrollTo(id, anchor: .leading) }
                }
            }
        }
    }

    private func categoryBrowser(width: CGFloat, rows: Int, cellWidth: Double) -> some View {
        ScrollViewReader { scroll in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(state.snapshot.sections) { section in
                        let columns = max(1, (section.items.count + rows - 1) / rows)
                        let sectionWidth = max(width, CGFloat(columns) * cellWidth + CGFloat(columns - 1) * style.spacing + 8)
                        VStack(alignment: .leading, spacing: 0) {
                            if section.items.isEmpty {
                                Text(section.id == "recent" ? "No recently used emoji" : labels.empty)
                                    .font(.callout).foregroundStyle(.secondary)
                                    .frame(width: sectionWidth, height: CGFloat(rows * 46))
                            } else {
                                LazyHGrid(rows: Array(repeating: GridItem(.fixed(44), spacing: 2), count: rows), spacing: style.spacing) {
                                    ForEach(section.items) { item in
                                        emojiCell(item, categoryID: section.id, width: cellWidth)
                                    }
                                }
                                .padding(.horizontal, 4)
                                .frame(width: sectionWidth, alignment: .leading)
                            }
                        }
                        .id(section.id)
                        .background(GeometryReader { sectionGeometry in
                            Color.clear.preference(key: SmileyCategoryFrames.self,
                                value: [section.id: sectionGeometry.frame(in: .named("smiley_catalogue"))])
                        })
                    }
                }
            }
            .coordinateSpace(name: "smiley_catalogue")
            .scrollIndicators(.hidden)
            .onAppear {
                isBrowserReady = true
                if let id = state.selectedCategoryID {
                    DispatchQueue.main.async { scroll.scrollTo(id, anchor: .leading) }
                }
            }
            .onDisappear { isBrowserReady = false }
            .onChange(of: state.categoryScrollRequest) { request in
                // Swipe observations never change this request, so they cannot
                // cause a feedback jump to the beginning of a category.
                if let request {
                    DispatchQueue.main.async { scroll.scrollTo(request.categoryID, anchor: .leading) }
                }
            }
            .onPreferenceChange(SmileyCategoryFrames.self) { frames in
                guard isBrowserReady else { return }
                let visible = state.snapshot.sections.max { lhs, rhs in
                    visibleWidth(frames[lhs.id], viewport: width) < visibleWidth(frames[rhs.id], viewport: width)
                }
                if let visible, visibleWidth(frames[visible.id], viewport: width) > 0,
                   visible.id != state.selectedCategoryID {
                    onAction(.browseCategory(visible.id))
                }
            }
        }
    }

    private func visibleWidth(_ frame: CGRect?, viewport: CGFloat) -> CGFloat {
        guard let frame else { return 0 }
        return max(0, min(viewport, frame.maxX) - max(0, frame.minX))
    }

    private func emojiCell(_ item: SmileyItem, categoryID: String?, width: Double) -> some View {
        let isHeld = state.variantItemID == item.id && (categoryID == nil || state.selectedCategoryID == categoryID)
        return Text(item.text).font(.system(size: 32)).lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: width, height: 44)
            .background(isHeld ? style.controlBackground : style.keyBackground, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            // A successful hold consumes the touch, so releasing cannot insert the base emoji.
            .gesture(LongPressGesture(minimumDuration: 0.45, maximumDistance: 8)
                .exclusively(before: TapGesture())
                .onEnded { value in
                    if let categoryID { onAction(.browseCategory(categoryID)) }
                    switch value {
                    case .first: onAction(.showVariants(item.id))
                    case .second: onAction(.activateItem(item.id))
                    }
                })
            .accessibilityLabel(item.label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if let categoryID { onAction(.browseCategory(categoryID)) }
                onAction(.activateItem(item.id))
            }
            .accessibilityHint(item.variants.isEmpty ? "" : "Touch and hold for skin tones")
            .accessibilityIdentifier("smiley_item_" + item.id)
            .accessibilityActions {
                if !item.variants.isEmpty {
                    Button("Skin tones") {
                        if let categoryID { onAction(.browseCategory(categoryID)) }
                        onAction(.showVariants(item.id))
                    }
                }
            }
            .anchorPreference(key: SmileyVariantAnchor.self, value: .bounds) { isHeld ? $0 : nil }
    }

    private func variantButton(_ variant: SmileyVariant) -> some View {
        Button { onAction(.activateItem(variant.id)) } label: {
            Text(variant.text).font(.system(size: 32)).frame(width: 44, height: 44)
        }
        .accessibilityLabel(variant.label)
        .accessibilityIdentifier("smiley_variant_" + variant.id)
    }
}
private struct SmileyCategoryFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct SmileyVariantAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

private struct SmileyPopupPointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
#endif
