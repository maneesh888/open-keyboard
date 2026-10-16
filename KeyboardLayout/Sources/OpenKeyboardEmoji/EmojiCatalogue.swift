import Foundation
import KeyboardLayout

/// OpenKeyboard's local content adapter. The renderer remains catalogue-independent.
public struct EmojiCatalogue: Sendable {
    private struct Entry: Decodable, Sendable {
        let id: String
        let text: String
        let label: String
        let version: Double
        let variants: [Entry]?
    }
    private struct Section: Decodable, Sendable {
        let id: String
        let label: String
        let symbol: String
        let items: [Entry]
    }
    public static let standard = EmojiCatalogue()
    public let sections: [SmileySection]
    private let itemsByID: [String: SmileyItem]
    public var validIDs: Set<String> { Set(itemsByID.keys) }
    public init(maximumVersion: Double = EmojiCatalogue.platformEmojiVersion) {
        let url = Bundle.module.url(forResource: "emoji", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        let content = try! JSONDecoder().decode([Section].self, from: data)
        sections = content.map { section in
            SmileySection(id: section.id, label: section.label, symbol: section.symbol,
                items: section.items.filter { $0.version <= maximumVersion }.map { entry in
                    SmileyItem(id: entry.id, text: entry.text, label: entry.label,
                        variants: (entry.variants ?? []).filter { $0.version <= maximumVersion }.map {
                            SmileyVariant(id: $0.id, text: $0.text, label: $0.label)
                        })
                })
        }
        var index = [String: SmileyItem]()
        for item in sections.flatMap(\.items) {
            index[item.id] = item
            for variant in item.variants {
                index[variant.id] = SmileyItem(id: variant.id, text: variant.text, label: variant.label,
                    variants: [SmileyVariant(id: item.id, text: item.text, label: item.label)] + item.variants)
            }
        }
        itemsByID = index
    }
    public static var platformEmojiVersion: Double {
        #if os(iOS)
        if #available(iOS 18.4, *) { return 16 }
        if #available(iOS 17.4, *) { return 15.1 }
        if #available(iOS 16.4, *) { return 15 }
        return 14
        #elseif os(macOS)
        if #available(macOS 15.4, *) { return 16 }
        if #available(macOS 14.4, *) { return 15.1 }
        if #available(macOS 13.3, *) { return 15 }
        return 14
        #else
        return 14
        #endif
    }
    public func snapshot(recentIDs: [String] = []) -> SmileySnapshot {
        var seen = Set<String>()
        let recents = recentIDs.filter { seen.insert($0).inserted }.compactMap { itemsByID[$0] }
        return SmileySnapshot(sections: [SmileySection(id: "recent", label: "Recently Used", symbol: "clock", items: recents)] + sections)
    }
}

/// Stores only known emoji identifiers, with bounded retention. Never stores search or host text.
public final class EmojiHistoryStore {
    private struct Record: Codable { let id: String; let date: Date }
    private let defaults: UserDefaults
    private let now: () -> Date
    private let validIDs: Set<String>
    private let key = "openkeyboard.emoji.recent.v1"
    public init(defaults: UserDefaults, validIDs: Set<String> = EmojiCatalogue.standard.validIDs,
                now: @escaping () -> Date = Date.init) {
        self.defaults = defaults; self.validIDs = validIDs; self.now = now
    }
    public func recentIDs() -> [String] {
        let records = retainedRecords()
        persist(records)
        return records.map(\.id)
    }
    public func record(_ id: String) {
        guard validIDs.contains(id) else { return }
        let records = [Record(id: id, date: now())] + retainedRecords().filter { $0.id != id }
        persist(Array(records.prefix(40)))
    }
    public func clear() { defaults.removeObject(forKey: key) }
    private func retainedRecords() -> [Record] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        let cutoff = now().addingTimeInterval(-30 * 24 * 60 * 60)
        var seen = Set<String>()
        return Array(records.filter {
            validIDs.contains($0.id) && $0.date >= cutoff && $0.date <= now() && seen.insert($0.id).inserted
        }.prefix(40))
    }
    private func persist(_ records: [Record]) {
        if records.isEmpty { clear() }
        else if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }
}
