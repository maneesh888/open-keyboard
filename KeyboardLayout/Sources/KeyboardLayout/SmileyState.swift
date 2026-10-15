import Foundation

public struct SmileyVariant: Equatable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let label: String
    public init(id: String, text: String, label: String) {
        self.id = id; self.text = text; self.label = label
    }
}

/// Content and accessible names are supplied by the consumer, never an AI service.
public struct SmileyItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let label: String
    public let variants: [SmileyVariant]
    public init(id: String, text: String, label: String, variants: [SmileyVariant] = []) {
        self.id = id; self.text = text; self.label = label
        var ids = Set([id])
        self.variants = variants.filter {
            !$0.id.isEmpty && !$0.text.isEmpty && !$0.label.isEmpty && ids.insert($0.id).inserted
        }
    }
}

public struct SmileySection: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let symbol: String
    public let items: [SmileyItem]
    public init(id: String, label: String, symbol: String = "face.smiling", items: [SmileyItem]) {
        self.id = id; self.label = label; self.symbol = symbol; self.items = items
    }
}

public struct SmileySnapshot: Equatable, Sendable {
    public let sections: [SmileySection]
    public init(sections: [SmileySection]) {
        var sectionIDs = Set<String>()
        self.sections = sections.compactMap { section in
            guard !section.id.isEmpty, !section.label.isEmpty,
                  sectionIDs.insert(section.id).inserted else { return nil }
            var itemIDs = Set<String>()
            return SmileySection(id: section.id, label: section.label, symbol: section.symbol,
                items: section.items.filter {
                    !$0.id.isEmpty && !$0.text.isEmpty && !$0.label.isEmpty && itemIDs.insert($0.id).inserted
                })
        }
    }
}

public enum SmileyAction: Equatable, Sendable {
    case selectCategory(String), browseCategory(String), activateItem(String)
    case beginSearch, endSearch, setSearchQuery(String)
    case showVariants(String), dismissVariants
    case deleteBackward, returnToTyping, nextSystemKeyboard
}

public enum SmileyIntent: Equatable, Sendable {
    case insertText(String, sectionID: String, itemID: String)
    case deleteBackward, returnToTyping, nextSystemKeyboard
}

public struct SmileyCategoryScrollRequest: Equatable, Sendable {
    public let categoryID: String
    public let revision: UInt
}

public struct SmileyState: Equatable, Sendable {
    public private(set) var snapshot: SmileySnapshot
    public private(set) var selectedCategoryID: String?
    public private(set) var isSearching = false
    public private(set) var searchQuery = ""
    public private(set) var categoryScrollRequest: SmileyCategoryScrollRequest?
    public var categoryScrollRevision: UInt { categoryScrollRequest?.revision ?? 0 }
    public private(set) var variantItemID: String?
    public var variantItem: SmileyItem? { visibleItems.first { $0.id == variantItemID } }

    public init(snapshot: SmileySnapshot) {
        self.snapshot = snapshot
        selectedCategoryID = snapshot.sections.first(where: { !$0.items.isEmpty })?.id ?? snapshot.sections.first?.id
    }
    public var selectedSection: SmileySection? { snapshot.sections.first { $0.id == selectedCategoryID } }
    public var visibleItems: [SmileyItem] {
        guard isSearching, !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return selectedSection?.items ?? []
        }
        let terms = normalized(searchQuery).split(separator: " ")
        var ids = Set<String>()
        return snapshot.sections.flatMap(\.items).filter { item in
            let name = normalized(item.label)
            return ids.insert(item.id).inserted &&
                (item.text == searchQuery || terms.allSatisfy { name.contains($0) })
        }
    }
    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "-", with: " ")
    }
    public mutating func update(_ snapshot: SmileySnapshot) {
        self.snapshot = snapshot
        variantItemID = nil
        if !snapshot.sections.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = snapshot.sections.first(where: { !$0.items.isEmpty })?.id ?? snapshot.sections.first?.id
        }
    }
    public mutating func send(_ action: SmileyAction) -> SmileyIntent? {
        switch action {
        case .showVariants(let id):
            if visibleItems.contains(where: { $0.id == id && !$0.variants.isEmpty }) { variantItemID = id }
        case .dismissVariants: variantItemID = nil
        case .browseCategory(let id):
            guard !isSearching, selectedCategoryID != id,
                  snapshot.sections.contains(where: { $0.id == id }) else { return nil }
            selectedCategoryID = id; variantItemID = nil
        case .selectCategory(let id):
            guard snapshot.sections.contains(where: { $0.id == id }) else { return nil }
            selectedCategoryID = id
            categoryScrollRequest = .init(categoryID: id, revision: categoryScrollRevision &+ 1)
            isSearching = false; searchQuery = ""; variantItemID = nil
        case .beginSearch: isSearching = true; variantItemID = nil
        case .endSearch: isSearching = false; searchQuery = ""; variantItemID = nil
        case .setSearchQuery(let query):
            guard isSearching else { return nil }
            searchQuery = String(query.prefix(100)); variantItemID = nil
        case .activateItem(let id):
            variantItemID = nil
            for item in visibleItems {
                let sectionID = isSearching && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? snapshot.sections.first(where: { $0.items.contains(where: { $0.id == item.id }) })?.id ?? ""
                    : selectedCategoryID ?? ""
                if item.id == id { return .insertText(item.text, sectionID: sectionID, itemID: id) }
                if let variant = item.variants.first(where: { $0.id == id }) {
                    return .insertText(variant.text, sectionID: sectionID, itemID: id)
                }
            }
        case .deleteBackward: return .deleteBackward
        case .returnToTyping: isSearching = false; searchQuery = ""; variantItemID = nil; return .returnToTyping
        case .nextSystemKeyboard: return .nextSystemKeyboard
        }
        return nil
    }
}

public struct SmileyGridMetrics: Equatable, Sendable {
    public let columns: Int
    public let cellWidth: Double
    public let spacing: Double
    public init(availableWidth: Double, minimumCellWidth: Double = 44,
                maximumCellWidth: Double = 64, spacing: Double = 6) {
        let width = availableWidth.isFinite ? max(0, availableWidth) : 0
        let minimum = minimumCellWidth.isFinite ? max(44, minimumCellWidth) : 44
        let maximum = maximumCellWidth.isFinite ? max(minimum, maximumCellWidth) : minimum
        let gap = spacing.isFinite ? max(0, spacing) : 6
        columns = max(1, Int((width + gap) / (minimum + gap)))
        cellWidth = min(maximum, max(0, (width - Double(columns - 1) * gap) / Double(columns)))
        self.spacing = gap
    }
}
