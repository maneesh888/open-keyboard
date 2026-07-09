import XCTest
@testable import OpenKeyboardCore

final class NextTextPredictionTests: XCTestCase {
    func testEmptyInputReturnsStarterSuggestions() {
        let predictor = AppleNaturalLanguageNextTextPredictor(corpus: NextTextPredictionCorpus(texts: [
            "Alpha one.",
            "Beta two.",
            "Gamma three."
        ]))

        let predictions = predictor.predictions(for: NextTextPredictionRequest(text: ""))

        XCTAssertEqual(predictions.map(\.text), ["alpha", "beta", "gamma"])
        XCTAssertTrue(predictions.allSatisfy { $0.kind == .nextWord })
    }

    func testTrailingSpaceReturnsNextWordSuggestions() {
        let predictor = AppleNaturalLanguageNextTextPredictor(corpus: NextTextPredictionCorpus(texts: [
            "How are you?",
            "How can I help?",
            "How is everything?"
        ]))

        let predictions = predictor.predictions(for: NextTextPredictionRequest(text: "How "))

        XCTAssertEqual(predictions.map(\.text), ["are", "can", "is"])
        XCTAssertTrue(predictions.allSatisfy { $0.kind == .nextWord })
    }

    func testPartialWordInputReturnsCompletionsFirst() {
        let predictor = AppleNaturalLanguageNextTextPredictor(corpus: NextTextPredictionCorpus(texts: [
            "Hope this helps.",
            "Hope you are well.",
            "Home screen is ready.",
            "How are you?"
        ]))

        let predictions = predictor.predictions(for: NextTextPredictionRequest(text: "Ho"))

        XCTAssertEqual(predictions.first?.text, "hope")
        XCTAssertEqual(predictions.first?.kind, .completion)
        XCTAssertEqual(predictions.count, 3)
        XCTAssertTrue(predictions.allSatisfy { $0.text.hasPrefix("ho") })
    }

    func testMaxSuggestionsIsClampedToThree() {
        let predictor = AppleNaturalLanguageNextTextPredictor(corpus: NextTextPredictionCorpus(texts: [
            "Please alpha.",
            "Please beta.",
            "Please gamma.",
            "Please delta."
        ]))

        let predictions = predictor.predictions(for: NextTextPredictionRequest(text: "Please ", maxSuggestions: 10))

        XCTAssertEqual(predictions.count, 3)
    }

    func testZeroMaxSuggestionsReturnsEmptyPredictions() {
        let predictions = AppleNaturalLanguageNextTextPredictor()
            .predictions(for: NextTextPredictionRequest(text: "How ", maxSuggestions: 0))

        XCTAssertTrue(predictions.isEmpty)
    }

    func testDuplicateAndAlreadyTypedNextWordsAreFiltered() {
        let predictor = AppleNaturalLanguageNextTextPredictor(corpus: NextTextPredictionCorpus(texts: [
            "How how.",
            "How are you?",
            "How are they?"
        ]))

        let predictions = predictor.predictions(for: NextTextPredictionRequest(text: "How "))

        XCTAssertEqual(predictions.first?.text, "are")
        XCTAssertFalse(predictions.contains { $0.text == "how" })
        XCTAssertEqual(predictions.filter { $0.text == "are" }.count, 1)
    }

    func testEarlierWordsCanStillBeValidNextWordSuggestions() {
        let predictor = AppleNaturalLanguageNextTextPredictor(corpus: NextTextPredictionCorpus(texts: [
            "I will see you soon.",
            "I will see you tomorrow."
        ]))

        let predictions = predictor.predictions(for: NextTextPredictionRequest(text: "You know I will see "))

        XCTAssertEqual(predictions.first?.text, "you")
    }

    func testPunctuationCapitalizationApostrophesAndEmojiDoNotBreakTokenization() {
        let predictor = AppleNaturalLanguageNextTextPredictor(corpus: NextTextPredictionCorpus(texts: [
            "We will see you soon.",
            "We will see you tomorrow."
        ]))

        let predictions = predictor.predictions(for: NextTextPredictionRequest(text: "👋 WE'LL see "))

        XCTAssertEqual(predictions.first?.text, "you")
        XCTAssertEqual(predictions.first?.kind, .nextWord)
    }

    func testLongClearlyNonEnglishInputReturnsNoEnglishSuggestions() {
        let predictions = AppleNaturalLanguageNextTextPredictor()
            .predictions(for: NextTextPredictionRequest(text: "Bonjour tout le monde merci beaucoup "))

        XCTAssertTrue(predictions.isEmpty)
    }

    func testInjectedCorpusControlsRanking() {
        let predictor = AppleNaturalLanguageNextTextPredictor(corpus: NextTextPredictionCorpus(texts: [
            "Please approve.",
            "Please approve.",
            "Please review."
        ]))

        let predictions = predictor.predictions(for: NextTextPredictionRequest(text: "Please "))

        XCTAssertEqual(predictions.first?.text, "approve")
        XCTAssertEqual(predictions.first?.score, 152)
    }
}
