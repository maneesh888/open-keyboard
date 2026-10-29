import XCTest
import KeyboardLayout
@testable import KeyboardEmoji

final class EmojiCatalogueTests: XCTestCase {
    func testCompleteCatalogueHasUniqueLiteralSequencesAndSupportedVersions() {
        let catalogue = EmojiCatalogue(maximumVersion: 16)
        XCTAssertEqual(catalogue.sections.count, 8)
        XCTAssertEqual(catalogue.sections.flatMap(\.items).count, 1906)
        XCTAssertEqual(catalogue.validIDs.count, 3781)
        XCTAssertEqual(catalogue.snapshot().sections.count, 9)
        XCTAssertLessThan(EmojiCatalogue(maximumVersion: 15).validIDs.count, catalogue.validIDs.count)
        for item in catalogue.sections.flatMap(\.items) {
            XCTAssertEqual(item.text.count, 1, item.id)
            for variant in item.variants { XCTAssertEqual(variant.text.count, 1, variant.id) }
        }
        let recent = catalogue.snapshot(recentIDs: ["1f44d-1f3fd", "invalid", "1f44d-1f3fd"]).sections[0]
        XCTAssertEqual(recent.items.map(\.text), ["👍🏽"])
        XCTAssertTrue(recent.items[0].variants.contains { $0.text == "👍" })
    }
    func testHistoryDeduplicatesBoundsExpiresAndRejectsUnknownText() {
        let suite = "emoji-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var date = Date()
        let history = EmojiHistoryStore(defaults: defaults, validIDs: Set((0..<50).map(String.init)), now: { date })
        history.record("private search text")
        XCTAssertEqual(history.recentIDs(), [])
        for id in 0..<50 { history.record(String(id)) }
        XCTAssertEqual(history.recentIDs().count, 40)
        history.record("25")
        XCTAssertEqual(history.recentIDs().first, "25")
        XCTAssertEqual(history.recentIDs().filter { $0 == "25" }.count, 1)
        date = date.addingTimeInterval(31 * 24 * 60 * 60)
        XCTAssertEqual(history.recentIDs(), [])
        XCTAssertNil(defaults.data(forKey: "keyboard.emoji.recent.v1"))
        history.record("1"); history.clear()
        XCTAssertEqual(history.recentIDs(), [])
    }
    func testConsumerSelectedStorageKeysPreserveHistoryAndStayIsolated() {
        let suite = "emoji-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = EmojiHistoryStore(defaults: defaults, validIDs: ["a"], key: "consumer.previous.key")
        first.record("a")
        let reopened = EmojiHistoryStore(defaults: defaults, validIDs: ["a"], key: "consumer.previous.key")
        XCTAssertEqual(reopened.recentIDs(), ["a"])
        let isolated = EmojiHistoryStore(defaults: defaults, validIDs: ["a"])
        XCTAssertEqual(isolated.recentIDs(), [])
        isolated.clear()
        XCTAssertEqual(first.recentIDs(), ["a"])
    }
    func testSearchAndVariantActionsStayLiteralAndCancelRestoresCategory() {
        var state = SmileyState(snapshot: EmojiCatalogue(maximumVersion: 16).snapshot())
        _ = state.send(.selectCategory("food"))
        XCTAssertNil(state.send(.beginSearch))
        XCTAssertNil(state.send(.setSearchQuery("THUMBS UP")))
        XCTAssertTrue(state.visibleItems.contains { $0.text == "👍" })
        XCTAssertNil(state.send(.showVariants("1f44d")), "Holding opens choices without inserting")
        XCTAssertEqual(state.variantItem?.text, "👍")
        XCTAssertEqual(state.send(.activateItem("1f44d-1f3fd")), .insertText("👍🏽", sectionID: "people", itemID: "1f44d-1f3fd"))
        XCTAssertNil(state.variantItem)
        _ = state.send(.showVariants("1f44d"))
        _ = state.send(.dismissVariants)
        XCTAssertNil(state.variantItem)
        _ = state.send(.showVariants("1f44d"))
        _ = state.send(.setSearchQuery("no emoji should match this"))
        XCTAssertNil(state.variantItem)
        XCTAssertEqual(state.visibleItems, [])
        XCTAssertNil(state.send(.activateItem("1f44d")))
        XCTAssertNil(state.send(.endSearch))
        XCTAssertEqual(state.selectedCategoryID, "food")
        XCTAssertEqual(state.searchQuery, "")
    }
}
