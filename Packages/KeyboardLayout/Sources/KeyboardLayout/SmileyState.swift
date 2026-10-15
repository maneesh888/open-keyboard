/// Host-owned display content. The package has no catalogue, storage or networking.
public struct SmileyItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let label: String

    public init(id: String, text: String, label: String) {
        self.id = id
        self.text = text
        self.label = label
    }
}

public struct SmileySection: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let items: [SmileyItem]

    public init(id: String, label: String, items: [SmileyItem]) {
        self.id = id
        self.label = label
        self.items = items
    }
}

/// IDs are unique within their container. Invalid/duplicate entries are discarded,
/// keeping the first occurrence, so malformed host data cannot create ambiguous controls.
public struct SmileySnapshot: Equatable, Sendable {
    public let sections: [SmileySection]

    public init(sections: [SmileySection]) {
        var sectionIDs = Set<String>()
        self.sections = sections.compactMap { section in
            guard !section.id.isEmpty, !section.label.isEmpty,
                  sectionIDs.insert(section.id).inserted else { return nil }
            var itemIDs = Set<String>()
            return SmileySection(id: section.id, label: section.label, items: section.items.filter {
                !$0.id.isEmpty && !$0.text.isEmpty && !$0.label.isEmpty && itemIDs.insert($0.id).inserted
            })
        }
    }
}

public enum SmileyAction: Equatable, Sendable {
    case selectCategory(String)
    case activateItem(String)
    case deleteBackward
    case returnToTyping
    case nextSystemKeyboard
}

/// One event per activation. Selection metadata travels with the insertion so a
/// consumer cannot accidentally insert twice while observing an item selection.
public enum SmileyIntent: Equatable, Sendable {
    case insertText(String, sectionID: String, itemID: String)
    case deleteBackward
    case returnToTyping
    case nextSystemKeyboard
}

public struct SmileyState: Equatable, Sendable {
    public private(set) var snapshot: SmileySnapshot
    public private(set) var selectedCategoryID: String?

    public init(snapshot: SmileySnapshot) {
        self.snapshot = snapshot
        selectedCategoryID = snapshot.sections.first?.id
    }

    public var selectedSection: SmileySection? {
        snapshot.sections.first { $0.id == selectedCategoryID }
    }

    public mutating func update(_ snapshot: SmileySnapshot) {
        self.snapshot = snapshot
        if !snapshot.sections.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = snapshot.sections.first?.id
        }
    }

    /// Category navigation is local state only; document edits remain host intents.
    public mutating func send(_ action: SmileyAction) -> SmileyIntent? {
        switch action {
        case .selectCategory(let id):
            if snapshot.sections.contains(where: { $0.id == id }) { selectedCategoryID = id }
            return nil
        case .activateItem(let id):
            guard let section = selectedSection,
                  let item = section.items.first(where: { $0.id == id }) else { return nil }
            return .insertText(item.text, sectionID: section.id, itemID: item.id)
        case .deleteBackward: return .deleteBackward
        case .returnToTyping: return .returnToTyping
        case .nextSystemKeyboard: return .nextSystemKeyboard
        }
    }
}

/// Bounded cells adapt to the allocated width, including compact iPad windows.
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
