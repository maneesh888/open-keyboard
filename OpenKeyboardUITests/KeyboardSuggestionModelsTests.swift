import XCTest
import UIKit

final class KeyboardSuggestionModelsTests: XCTestCase {


    func testBrokenPlaygroundRegressionCannotBecomeAllGoodFromDynamicNoIssues() {
        let json = """
        {"issue_count":0,"overall_status":"no_issues","corrected_text":"i has a apple,ths is nt sound sound","corrections":[],"summary":"No issues found."}
        """

        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "i has a apple,ths is nt sound sound")) { error in
            XCTAssertEqual(error as? KeyboardSuggestionParserError, .uselessOutput)
        }
    }

    func testBrokenPlaygroundRegressionParsesActionableSuggestions() throws {
        let json = """
        {
          "issue_count": 4,
          "overall_status": "issues_found",
          "corrected_text": "I have an apple; this does not sound right.",
          "corrections": [
            {"id":"subject-verb","category":"grammar","label":"Subject-verb agreement","original":"i has","replacement":"I have","explanation":"Use “I have” for first-person agreement."},
            {"id":"article","category":"grammar","label":"Article","original":"a apple","replacement":"an apple","explanation":"Use “an” before a vowel sound."},
            {"id":"spelling-this","category":"spelling","label":"Spelling","original":"ths","replacement":"this","explanation":"Correct the misspelling."},
            {"id":"spelling-not","category":"spelling","label":"Spelling","original":"nt","replacement":"not","explanation":"Expand the missing vowel."}
          ],
          "summary":"Four issues found."
        }
        """

        let response = try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "i has a apple,ths is nt sound sound")

        XCTAssertGreaterThanOrEqual(response.corrections.count, 1)
        XCTAssertTrue(response.corrections.contains { $0.original == "i has" && $0.replacement == "I have" })
        XCTAssertTrue(response.corrections.contains { $0.original == "a apple" && $0.replacement == "an apple" })
        XCTAssertTrue(response.corrections.contains { $0.original == "ths" && $0.replacement == "this" })
    }


    func testMapsStructuredCorrectionItemsToSuggestionResponse() throws {
        let json = """
        {"operation":"fix_grammar","results":[
          {"id":"verb","type":"correction","title":"Subject-verb agreement","text":"Use have","original":"has","replacement":"have","explanation":"Use have for agreement."},
          {"id":"article","type":"correction","title":"Article","text":"Use an","original":"a apple","replacement":"an apple","explanation":"Use an before apple."},
          {"id":"spelling","type":"correction","title":"Spelling","text":"Fix ths","original":"ths","replacement":"this","explanation":"Correct the typo."}
        ]}
        """

        let response = try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "i has a apple and ths")

        XCTAssertEqual(response.corrections.count, 3)
        XCTAssertEqual(response.corrections.map(\.original), ["has", "a apple", "ths"])
        XCTAssertEqual(response.corrections.map(\.replacement), ["have", "an apple", "this"])
        XCTAssertEqual(response.corrections.first?.label, "Subject-verb agreement")
        XCTAssertEqual(response.corrections.first?.category, "correction")
    }

    func testStructuredResultWithoutCorrectedTextStillCreatesCorrections() throws {
        let json = """
        {"operation":"fix_grammar","results":[{"id":"article","type":"correction","title":"Article","text":"Use an","original":"a apple","replacement":"an apple"}]}
        """

        let response = try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "i has a apple")

        XCTAssertEqual(response.corrections.count, 1)
        XCTAssertEqual(response.corrections.first?.replacement, "an apple")
        XCTAssertNil(response.correctedText)
    }

    func testStructuredResultWithCorrectedTextDoesNotDropCorrections() throws {
        let json = """
        {"operation":"fix_grammar","results":[{"id":"article","type":"correction","title":"Article","text":"Use an","original":"a apple","replacement":"an apple"}],"corrected_text":"I have an apple."}
        """

        let response = try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "i has a apple")

        XCTAssertEqual(response.corrections.count, 1)
        XCTAssertEqual(response.corrections.first?.replacement, "an apple")
        XCTAssertEqual(response.correctedText, "I have an apple.")
    }

    func testNonCorrectionItemsAreHandledSafely() throws {
        let json = """
        {"operation":"fix_grammar","results":[
          {"id":"summary","type":"summary","title":"Summary","text":"One issue found."},
          {"id":"warning","type":"warning","title":"Warning","text":"Ambiguous phrasing."},
          {"id":"unknown","type":"custom_type","title":"Unknown","text":"Unknown item."}
        ],"summary":"Handled safely."}
        """

        let response = try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "The text is ambiguous")

        XCTAssertTrue(response.corrections.isEmpty)
        XCTAssertTrue(response.predictions.isEmpty)
        XCTAssertNil(response.correctedText)
    }

    func testParsesDynamicIssueCountSchemaAndDropsPredictions() throws {
        let json = """
        {
          "issue_count": 3,
          "overall_status": "issues_found",
          "corrected_text": "I have an apple, this does not sound good.",
          "corrections": [
            {"id":"c1","category":"grammar","label":"Subject-verb agreement","original":"i has","replacement":"I have","start":0,"end":5,"explanation":"Use I have for first person agreement.","confidence":0.95},
            {"id":"c2","category":"spelling","label":"Spelling","original":"ths","replacement":"this","start":14,"end":17,"explanation":"Correct the misspelling.","confidence":0.98},
            {"id":"c3","category":"spelling","label":"Spelling","original":"god","replacement":"good","start":30,"end":33,"explanation":"Correct the misspelling.","confidence":0.93}
          ],
          "summary":"Three writing issues found."
        }
        """

        let response = try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "i has a apple,ths is nt sound god")

        XCTAssertEqual(response.corrections.count, 3)
        XCTAssertTrue(response.predictions.isEmpty, "Dynamic contract must not render legacy prediction lane")
        XCTAssertEqual(response.corrections.map(\.id), ["c1", "c2", "c3"])
        XCTAssertEqual(response.corrections.map(\.original), ["i has", "ths", "god"])
        XCTAssertEqual(response.corrections.map(\.replacement), ["I have", "this", "good"])
    }

    func testDynamicNoIssuesSchemaProducesEmptyState() throws {
        let json = """
        {"issue_count":0,"overall_status":"no_issues","corrected_text":"The app works well today.","corrections":[],"summary":"No issues found."}
        """

        let response = try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "The app works well today.")

        XCTAssertTrue(response.corrections.isEmpty)
        XCTAssertTrue(response.predictions.isEmpty)
    }

    func testDynamicIssuesFoundWithoutUsableCorrectionThrows() {
        let json = """
        {"issue_count":2,"overall_status":"issues_found","corrected_text":"I have an apple.","corrections":[],"summary":"Issues found."}
        """

        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "i has a apple")) { error in
            XCTAssertEqual(error as? KeyboardSuggestionParserError, .uselessOutput)
        }
    }

    func testParsesCorrectionsAndPredictions() throws {
        let json = """
        {"corrections":[{"label":"Correct capitalization","original":" i ","replacement":" I ","explanation":"Capitalize I.","category":"capitalization"}],"predictions":[{"label":"Suggestion","text":" apple ","kind":"nextWord"}]}
        """
        let response = try KeyboardSuggestionParser.parseAssistantContent(json)
        XCTAssertEqual(response.corrections.first?.label, "Correct capitalization")
        XCTAssertEqual(response.corrections.first?.original, "i")
        XCTAssertEqual(response.corrections.first?.replacement, "I")
        XCTAssertEqual(response.corrections.first?.category, "capitalization")
        XCTAssertEqual(response.predictions.first?.label, "Suggestion")
        XCTAssertEqual(response.predictions.first?.text, "apple")
    }

    func testParsesCorrectionOnlyPredictionOnlyAndEmptyResponses() throws {
        XCTAssertEqual(try KeyboardSuggestionParser.parseAssistantContent("{\"corrections\":[{\"original\":\"has\",\"replacement\":\"have\"}],\"predictions\":[]}").corrections.count, 1)
        XCTAssertEqual(try KeyboardSuggestionParser.parseAssistantContent("{\"corrections\":[],\"predictions\":[{\"text\":\"apple\"}]}").predictions.count, 1)
        let empty = try KeyboardSuggestionParser.parseAssistantContent("{\"corrections\":[],\"predictions\":[]}")
        XCTAssertTrue(empty.corrections.isEmpty)
        XCTAssertTrue(empty.predictions.isEmpty)
    }

    func testDropsInvalidItemsAndStripsMarkdownFences() throws {
        let fenced = """
        ```json
        {"corrections":[{"label":"Bad","original":"","replacement":"X"},{"label":"Correct article","original":"a","replacement":"an"}],"predictions":[{"text":""},{"text":"apple"}]}
        ```
        """
        let response = try KeyboardSuggestionParser.parseAssistantContent(fenced)
        XCTAssertEqual(response.corrections.map(\.replacement), ["an"])
        XCTAssertEqual(response.predictions.map(\.text), ["apple"])
    }

    func testCapsLongCompactValuesAndInvalidJSONThrows() throws {
        let long = String(repeating: "x", count: 80)
        let response = try KeyboardSuggestionParser.parseAssistantContent("{\"corrections\":[{\"original\":\"a\",\"replacement\":\"\(long)\"}],\"predictions\":[{\"text\":\"\(long)\"}]}")
        XCTAssertEqual(response.corrections.first?.replacement.count, 32)
        XCTAssertEqual(response.predictions.first?.text.count, 32)
        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent("not json"))
    }

    func testReducerAdvancesMultipleCorrectionsAndKeepsPredictionLane() {
        let response = KeyboardSuggestionResponse(
            corrections: [
                KeyboardCorrectionSuggestion(label: "Correct capitalization", original: "i", replacement: "I", category: "capitalization"),
                KeyboardCorrectionSuggestion(label: "Correct verb", original: "has", replacement: "have", category: "subjectVerb"),
                KeyboardCorrectionSuggestion(label: "Correct article", original: "a", replacement: "an", category: "article")
            ],
            predictions: [KeyboardPredictionSuggestion(label: "Suggestion", text: "apple", kind: "nextWord")]
        )
        var state = KeyboardSuggestionState(response: response)
        XCTAssertEqual(state.currentCorrection?.replacement, "I")
        XCTAssertEqual(state.currentPrediction?.text, "apple")
        XCTAssertEqual(state.remainingCorrectionCount, 3)
        state.applyCurrentCorrection()
        XCTAssertEqual(state.currentCorrection?.replacement, "have")
        XCTAssertEqual(state.remainingCorrectionCount, 2)
        state.applyCurrentCorrection()
        XCTAssertEqual(state.currentCorrection?.replacement, "an")
        XCTAssertEqual(state.remainingCorrectionCount, 1)
        state.applyCurrentCorrection()
        XCTAssertNil(state.currentCorrection)
        XCTAssertEqual(state.remainingCorrectionCount, 0)
        XCTAssertFalse(state.isComplete, "Prediction lane may remain after corrections finish")
    }


    func testCorrectionCarouselNavigationRespectsBounds() {
        var state = KeyboardSuggestionState(response: Self.multiCorrectionResponse())

        XCTAssertEqual(state.currentCorrectionPosition, 1)
        XCTAssertEqual(state.correctionCount, 3)
        XCTAssertFalse(state.canMoveToPreviousCorrection)
        XCTAssertTrue(state.canMoveToNextCorrection)
        XCTAssertTrue(state.showsCorrectionProgress)

        state.moveToPreviousCorrection()
        XCTAssertEqual(state.currentCorrection?.id, "subject-verb")

        state.moveToNextCorrection()
        XCTAssertEqual(state.currentCorrectionPosition, 2)
        XCTAssertEqual(state.currentCorrection?.id, "article")
        XCTAssertTrue(state.canMoveToPreviousCorrection)
        XCTAssertTrue(state.canMoveToNextCorrection)

        state.moveToNextCorrection()
        XCTAssertEqual(state.currentCorrectionPosition, 3)
        XCTAssertEqual(state.currentCorrection?.id, "spelling-this")
        XCTAssertTrue(state.canMoveToPreviousCorrection)
        XCTAssertFalse(state.canMoveToNextCorrection)

        state.moveToNextCorrection()
        XCTAssertEqual(state.currentCorrection?.id, "spelling-this")
    }

    func testAcceptCurrentCorrectionRemovesOnlyVisibleCardAndClampsIndex() {
        var state = KeyboardSuggestionState(response: Self.multiCorrectionResponse())
        state.moveToNextCorrection()

        state.applyCurrentCorrection()

        XCTAssertEqual(state.correctionCount, 2)
        XCTAssertEqual(state.currentCorrectionPosition, 2)
        XCTAssertEqual(state.currentCorrection?.id, "spelling-this")
        XCTAssertEqual(state.corrections.map(\.id), ["subject-verb", "spelling-this"])
    }

    func testDismissCurrentCorrectionRemovesOnlyVisibleLastCard() {
        var state = KeyboardSuggestionState(response: Self.multiCorrectionResponse())
        state.moveToNextCorrection()
        state.moveToNextCorrection()

        state.dismissCurrentCorrection()

        XCTAssertEqual(state.correctionCount, 2)
        XCTAssertEqual(state.currentCorrectionPosition, 2)
        XCTAssertEqual(state.currentCorrection?.id, "article")
        XCTAssertEqual(state.corrections.map(\.id), ["subject-verb", "article"])
    }

    func testSingleCorrectionDoesNotShowCarouselProgress() {
        let state = KeyboardSuggestionState(response: KeyboardSuggestionResponse(
            corrections: [KeyboardCorrectionSuggestion(id: "only", label: "Spelling", original: "ths", replacement: "this")],
            predictions: []
        ))

        XCTAssertEqual(state.currentCorrectionPosition, 1)
        XCTAssertEqual(state.correctionCount, 1)
        XCTAssertFalse(state.showsCorrectionProgress)
        XCTAssertFalse(state.canMoveToPreviousCorrection)
        XCTAssertFalse(state.canMoveToNextCorrection)
    }

    func testOperationResultMapsStructuredCorrectionItemsToSuggestionResponse() throws {
        let result = try KeyboardActionOperationResult.parse(Self.canonicalGrammarJSON(correctedText: nil), operation: "fix_grammar", fallbackText: "i has a apple ths")

        let response = result.suggestionResponse()

        XCTAssertEqual(response.corrections.count, 3)
        XCTAssertEqual(response.corrections.map(\.original), ["has", "a apple", "ths"])
        XCTAssertEqual(response.corrections.map(\.replacement), ["have", "an apple", "this"])
        XCTAssertEqual(response.corrections.map(\.label), ["Subject-verb agreement", "Article", "Spelling"])
        XCTAssertEqual(response.corrections.map(\.category), ["grammar", "correction", "spelling"])
        XCTAssertEqual(response.corrections[1].explanation, "Use an before a vowel sound.")
    }

    func testOperationResultWithoutCorrectedTextStillCreatesCorrections() throws {
        let result = try KeyboardActionOperationResult.parse(Self.canonicalGrammarJSON(correctedText: nil), operation: "fix_grammar", fallbackText: "i has a apple ths")

        let outcome = KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result)

        guard case .showCorrections(let response) = outcome else {
            return XCTFail("Expected correction state, got \(outcome)")
        }
        let state = KeyboardSuggestionState(response: response, sourceContext: "i has a apple ths")
        XCTAssertNil(response.correctedText)
        XCTAssertEqual(state.correctionCount, 3)
        XCTAssertEqual(state.currentCorrection?.replacement, "have")
    }

    func testOperationResultWithCorrectedTextDoesNotDropCorrections() throws {
        let result = try KeyboardActionOperationResult.parse(Self.canonicalGrammarJSON(correctedText: "I have an apple this"), operation: "fix_grammar", fallbackText: "i has a apple ths")

        let response = result.suggestionResponse()
        let outcome = KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result)

        XCTAssertEqual(response.correctedText, "I have an apple this")
        XCTAssertEqual(response.corrections.count, 3)
        guard case .showCorrections(let routedResponse) = outcome else {
            return XCTFail("Expected correction cards even when corrected_text exists")
        }
        XCTAssertEqual(routedResponse.correctedText, "I have an apple this")
        XCTAssertEqual(routedResponse.corrections.count, 3)
    }

    func testOperationResultNonCorrectionItemsAreHandledSafely() throws {
        let json = """
        {"operation":"fix_grammar","results":[
          {"id":"summary-1","type":"summary","title":"Summary","text":"One issue found."},
          {"id":"warning-1","type":"warning","title":"Warning","text":"Ambiguous pronoun."},
          {"id":"explanation-1","type":"explanation","title":"Why","text":"The verb should match the subject."},
          {"id":"unknown-1","type":"custom_notice","title":"Custom","text":"Custom metadata."}
        ],"summary":"Review complete."}
        """

        let result = try KeyboardActionOperationResult.parse(json, operation: "fix_grammar", fallbackText: "i has a apple")
        let response = result.suggestionResponse()

        XCTAssertEqual(result.items.map(\.type), ["summary", "warning", "explanation", "custom_notice"])
        XCTAssertTrue(response.corrections.isEmpty, "Non-correction items are preserved on the typed result but ignored by the correction-card mapper.")
    }

    private static func multiCorrectionResponse() -> KeyboardSuggestionResponse {
        KeyboardSuggestionResponse(
            corrections: [
                KeyboardCorrectionSuggestion(id: "subject-verb", label: "Subject-verb agreement", original: "i has", replacement: "I have", category: "grammar"),
                KeyboardCorrectionSuggestion(id: "article", label: "Article", original: "a apple", replacement: "an apple", category: "grammar"),
                KeyboardCorrectionSuggestion(id: "spelling-this", label: "Spelling", original: "ths", replacement: "this", category: "spelling")
            ],
            predictions: []
        )
    }

    private static func canonicalGrammarJSON(correctedText: String?) -> String {
        let correctedTextField = correctedText.map { #", "corrected_text": "\#($0)""# } ?? ""
        return #"{"operation":"fix_grammar","results":[{"id":"subject-verb","type":"correction","title":"Subject-verb agreement","text":"Use have.","original":"has","replacement":"have","category":"grammar","explanation":"Use have for first-person agreement."},{"id":"article","type":"correction","title":"Article","text":"Use an.","original":"a apple","replacement":"an apple","explanation":"Use an before a vowel sound."},{"id":"spelling-this","type":"correction","title":"Spelling","text":"Fix typo.","original":"ths","replacement":"this","category":"spelling","explanation":"Correct the misspelling."}], "summary":"Three issues found."\#(correctedTextField)}"#
    }

    func testSuppressesPredictionDuplicatingLastInputWord() {
        let response = KeyboardSuggestionResponse(
            corrections: [KeyboardCorrectionSuggestion(label: "Correct article", original: "a", replacement: "an")],
            predictions: [KeyboardPredictionSuggestion(label: "Suggestion", text: "apple", kind: "nextWord")]
        )

        let state = KeyboardSuggestionState(response: response, sourceContext: "i has a apple")

        XCTAssertEqual(state.currentCorrection?.replacement, "an")
        XCTAssertNil(state.compactPredictionText)
    }

    func testKeepsNonDuplicativePredictionForOpenEndedInput() {
        let response = KeyboardSuggestionResponse(
            corrections: [],
            predictions: [KeyboardPredictionSuggestion(label: "Suggestion", text: "apple", kind: "nextWord")]
        )

        let state = KeyboardSuggestionState(response: response, sourceContext: "I want to eat")

        XCTAssertEqual(state.compactPredictionText, "apple")
    }

    func testSuppressesPredictionCaseInsensitivelyAndWithPunctuation() {
        XCTAssertTrue(KeyboardSuggestionState.isRedundantPrediction("Apple", sourceContext: "apple"))
        XCTAssertTrue(KeyboardSuggestionState.isRedundantPrediction(" apple! ", sourceContext: "I bought an apple."))
        XCTAssertFalse(KeyboardSuggestionState.isRedundantPrediction("apple pie", sourceContext: "I bought an apple"))
    }

    func testCorrectionOnlyPredictionOnlyAndNoSuggestionsStates() {
        let correctionOnly = KeyboardSuggestionState(response: KeyboardSuggestionResponse(corrections: [KeyboardCorrectionSuggestion(label: "Correct", original: "i", replacement: "I")], predictions: []))
        XCTAssertEqual(correctionOnly.compactCorrectionReplacement, "I")
        XCTAssertNil(correctionOnly.compactPredictionText)

        let predictionOnly = KeyboardSuggestionState(response: KeyboardSuggestionResponse(corrections: [], predictions: [KeyboardPredictionSuggestion(label: "Suggestion", text: "apple")]))
        XCTAssertNil(predictionOnly.compactCorrectionReplacement)
        XCTAssertEqual(predictionOnly.compactPredictionText, "apple")

        XCTAssertTrue(KeyboardSuggestionState(response: KeyboardSuggestionResponse(corrections: [], predictions: [])).isComplete)
    }


    func testPlainTextCorrectionFallbackForAppleGrammarCase() throws {
        let response = try KeyboardSuggestionParser.parseAssistantContent("I have an apple.", sourceContext: "i has a apple")

        XCTAssertEqual(response.corrections.first?.replacement, "I have an apple.")
        XCTAssertEqual(response.corrections.first?.label, "Correct grammar")
        XCTAssertTrue(response.predictions.isEmpty)
    }

    func testPlainTextCorrectionFallbackForWorkingGoodCase() throws {
        let response = try KeyboardSuggestionParser.parseAssistantContent("This is not working well.", sourceContext: "this are not working good")

        XCTAssertEqual(response.corrections.first?.replacement, "This is not working well.")
        XCTAssertTrue(response.predictions.isEmpty)
    }

    func testRejectsOneTokenOrGenericOutputsForClearlyBrokenInput() {
        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent("I", sourceContext: "i has a apple"))
        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent("OK", sourceContext: "i has a apple"))
        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent("i has a apple", sourceContext: "i has a apple"))
    }

    func testStructuredCorrectionStillAcceptedForMeaningfulCases() throws {
        let json = """
        {"corrections":[{"label":"Correct grammar","original":"this are not working good","replacement":"This is not working well."}],"predictions":[]}
        """
        let response = try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "this are not working good")

        XCTAssertEqual(response.corrections.first?.replacement, "This is not working well.")
        XCTAssertTrue(response.predictions.isEmpty)
    }


    func testRejectsOnlyCapitalizedIncompleteFragments() {
        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent("I tried with", sourceContext: "i tried with"))
        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent("I tried with.", sourceContext: "i tried with"))
    }

    func testAcceptsMeaningfulCompletionForIncompleteFragment() throws {
        let response = try KeyboardSuggestionParser.parseAssistantContent("I tried with the new keyboard.", sourceContext: "i tried with")

        XCTAssertEqual(response.corrections.first?.replacement, "I tried with the new keyboard.")
    }


    func testNoClearCorrectionSentinelMapsToEmptyState() throws {
        let response = try KeyboardSuggestionParser.parseAssistantContent("NO_CLEAR_CORRECTION", sourceContext: "i tried with")

        XCTAssertTrue(response.corrections.isEmpty)
        XCTAssertTrue(response.predictions.isEmpty)
    }

    func testStructuredSameFragmentIncompleteCorrectionThrowsWhenNoUsefulSuggestionRemains() {
        let json = """
        {"corrections":[{"label":"Correct grammar","original":"i tried with","replacement":"I tried with."}],"predictions":[]}
        """

        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "i tried with"))
    }


    func testRejectsPlainTextCorrectionWithResidualGrammarError() {
        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent("This are not working well.", sourceContext: "this are not working good"))
    }

    func testStructuredCorrectionWithResidualGrammarErrorThrowsWhenNoUsefulCorrectionRemains() {
        let json = """
        {"corrections":[{"label":"Correct grammar","original":"this are not working good","replacement":"This are not working well."}],"predictions":[]}
        """

        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "this are not working good"))
    }


    func testEmptyContentForIncompleteFragmentMapsToNoClearState() throws {
        let response = try KeyboardSuggestionParser.parseAssistantContent("", sourceContext: "i tried with")

        XCTAssertTrue(response.corrections.isEmpty)
        XCTAssertTrue(response.predictions.isEmpty)
    }

    func testClearGrammarInputCannotBecomeAllGoodAfterFilteringBadCorrection() {
        let json = """
        {"corrections":[{"label":"Correct grammar","original":"this are not working good","replacement":"This are not working well."}],"predictions":[]}
        """

        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "this are not working good"))
    }


    func testClearGrammarInputRequiresCorrectionNotPredictionOnlyAfterFiltering() {
        let json = """
        {"corrections":[{"label":"Correct grammar","original":"this are not working good","replacement":"This are not working well."}],"predictions":[{"label":"Suggestion","text":"well"}]}
        """

        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "this are not working good"))
    }


    func testClearGrammarInputWithBadCorrectionAndPredictionThrowsAfterFiltering() {
        let json = """
        {"corrections":[{"label":"Correct grammar","original":"this are not working good","replacement":"This are not working well."}],"predictions":[{"label":"Suggestion","text":"well"}]}
        """

        XCTAssertThrowsError(try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "this are not working good")) { error in
            XCTAssertEqual(error as? KeyboardSuggestionParserError, .uselessOutput)
        }
    }


    func testParsesGrammarlyStyleCorrectionMetadata() throws {
        let json = """
        {"corrections":[{"label":"Subject-verb agreement","original":"has","replacement":"have","explanation":"Use have because the subject is plural.","category":"grammar"}],"predictions":[]}
        """
        let response = try KeyboardSuggestionParser.parseAssistantContent(json, sourceContext: "There has been no apples")
        let card = KeyboardSuggestionState(response: response, sourceContext: "There has been no apples").currentCorrectionCard

        XCTAssertEqual(card?.categoryTitle, "Subject-verb agreement")
        XCTAssertEqual(card?.original, "has")
        XCTAssertEqual(card?.replacement, "have")
        XCTAssertEqual(card?.explanation, "Use have because the subject is plural.")
    }

    func testInfersSubjectVerbExplanationWhenMissing() {
        let correction = KeyboardCorrectionSuggestion(label: "Grammar", original: "has", replacement: "have", explanation: nil, category: "subjectVerb")
        let card = KeyboardCorrectionCard(correction: correction)

        XCTAssertEqual(card.categoryTitle, "Subject-verb agreement")
        XCTAssertEqual(card.explanation, "Use “have” because the subject is plural.")
    }

    func testDismissCurrentCorrectionAdvancesWithoutAllGoodWhenPredictionRemains() {
        let response = KeyboardSuggestionResponse(
            corrections: [KeyboardCorrectionSuggestion(label: "Subject-verb agreement", original: "has", replacement: "have")],
            predictions: [KeyboardPredictionSuggestion(label: "Suggestion", text: "today")]
        )
        var state = KeyboardSuggestionState(response: response, sourceContext: "There has been no apples")
        state.dismissCurrentCorrection()

        XCTAssertNil(state.currentCorrection)
        XCTAssertEqual(state.compactPredictionText, "today")
        XCTAssertFalse(state.isComplete)
    }



    @MainActor
    func testToolbarLogoTapStartsAnalysisWithoutReplacingKeyboardGrid() {
        let proxy = FakeTextDocumentProxy(initialText: "how to fix")
        let service = FakeKeyboardAIService(result: KeyboardActionOperationResult(
            operation: "fix_grammar",
            items: [],
            summary: nil,
            correctedText: nil
        ))
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            advanceToNextInputMode: {},
            aiService: service,
            loadConfig: { Self.configuredTestAppConfig },
            productionTestFullAccess: true
        )

        XCTAssertEqual(viewModel.panelMode, .keyboard)
        viewModel.handleToolbarLogoTap()

        XCTAssertEqual(viewModel.panelMode, .keyboard)
        XCTAssertTrue(viewModel.isPerformingAIAction, "Logo tap should start analysis while keeping the keyboard grid usable.")
        XCTAssertEqual(viewModel.aiStatus, "Analyzing your text...")
    }

    @MainActor
    func testKeyboardActionPathShowsMultipleCorrectionsInsteadOfFirstReplacementOnly() async throws {
        let proxy = FakeTextDocumentProxy(initialText: "i has a apple and ths")
        let service = FakeKeyboardAIService(result: KeyboardActionOperationResult(
            operation: "fix_grammar",
            items: [
                KeyboardActionOperationResult.Item(id: "verb", type: "correction", title: "Verb", text: "Use have", original: "has", replacement: "have", explanation: nil),
                KeyboardActionOperationResult.Item(id: "spelling", type: "correction", title: "Spelling", text: "Fix ths", original: "ths", replacement: "this", explanation: nil)
            ],
            summary: "Two issues.",
            correctedText: nil
        ))
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            advanceToNextInputMode: {},
            aiService: service,
            loadConfig: { Self.configuredTestAppConfig },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.fixGrammar)
        try await waitUntil { !viewModel.isPerformingAIAction }

        XCTAssertEqual(viewModel.panelMode, .correctionDetail)
        XCTAssertEqual(viewModel.suggestionState?.correctionCount, 2)
        let suggestionState = try XCTUnwrap(viewModel.suggestionState)
        XCTAssertEqual(suggestionState.corrections.map(\.replacement), ["have", "this"])
        XCTAssertEqual(proxy.deletedCharacterCount, 0, "Structured grammar results should create correction state instead of replacing with only the first item.")
        XCTAssertEqual(proxy.storage, "i has a apple and ths")
    }

    @MainActor
    func testKeyboardActionPathCanUseCorrectedTextForApplyAllOrLegacyReplacement() async throws {
        let proxy = FakeTextDocumentProxy(initialText: "i has a apple")
        let service = FakeKeyboardAIService(result: KeyboardActionOperationResult(
            operation: "fix_grammar",
            items: [
                KeyboardActionOperationResult.Item(id: "article", type: "correction", title: "Article", text: "Use an", original: "a apple", replacement: "an apple", explanation: "Use an before apple.")
            ],
            summary: "One issue.",
            correctedText: "I have an apple."
        ))
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            advanceToNextInputMode: {},
            aiService: service,
            loadConfig: { Self.configuredTestAppConfig },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.fixGrammar)
        try await waitUntil { !viewModel.isPerformingAIAction }

        XCTAssertEqual(viewModel.panelMode, .correctionDetail)
        XCTAssertEqual(viewModel.suggestionState?.correctionCount, 1)
        XCTAssertEqual(viewModel.suggestionState?.correctedText, "I have an apple.")
        XCTAssertEqual(proxy.storage, "i has a apple", "Corrected text is preserved on state but should not silently replace and discard structured correction cards.")
    }

    @MainActor
    func testSummarizeOrRewriteStructuredResultStillProducesExpectedReplacement() async throws {
        let proxy = FakeTextDocumentProxy(initialText: "The keyboard supports private AI. It can fix grammar and summarize text.")
        let service = FakeKeyboardAIService(result: KeyboardActionOperationResult(
            operation: "summarize",
            items: [KeyboardActionOperationResult.Item(id: "summary", type: "summary", title: "Summary", text: "The keyboard offers private AI writing help.", original: nil, replacement: nil, explanation: nil)],
            summary: "The keyboard offers private AI writing help.",
            correctedText: nil
        ))
        let viewModel = KeyboardViewModel(
            textDocumentProxy: proxy,
            advanceToNextInputMode: {},
            aiService: service,
            loadConfig: { Self.configuredTestAppConfig },
            productionTestFullAccess: true
        )

        viewModel.performAIAction(.summarize)
        try await waitUntil { !viewModel.isPerformingAIAction }

        XCTAssertEqual(viewModel.panelMode, .correctionComplete)
        XCTAssertEqual(proxy.storage, "The keyboard offers private AI writing help.")
    }

    func testPromptRequestsDynamicStrictJSONAndBoundedCurrentText() {
        let prompt = KeyboardSuggestionParser.prompt(for: String(repeating: "a", count: 700))
        XCTAssertTrue(prompt.contains("strict JSON only"))
        XCTAssertTrue(prompt.contains("issue_count"))
        XCTAssertTrue(prompt.contains("corrected_text"))
        XCTAssertTrue(prompt.contains("overall_status"))
        XCTAssertTrue(prompt.contains("Analyze ONLY the provided user text"))
        XCTAssertTrue(prompt.contains("Never return canned examples"))
        XCTAssertTrue(prompt.contains("<<<"))
        XCTAssertFalse(prompt.contains("Subject-verb agreement\",\"original\":\"has"), "Prompt must not include old canned has→have fixture")
        XCTAssertLessThan(prompt.count, 2400)
    }

    func testRetryPromptRejectsCannedOrReusedOutput() {
        let prompt = KeyboardSuggestionParser.retryPrompt(for: "this are not working good")

        XCTAssertTrue(prompt.contains("Previous output was invalid"))
        XCTAssertTrue(prompt.contains("reused a canned example"))
        XCTAssertTrue(prompt.contains("Re-analyze ONLY the current user text"))
        XCTAssertTrue(prompt.contains("this are not working good"))
    }
}

private extension KeyboardSuggestionModelsTests {
    static var configuredTestAppConfig: AppConfig {
        AppConfig(
            apiKey: "test-key",
            gatewayURL: "https://gateway.example.invalid",
            selectedModel: "test-model",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
    }

    func waitUntil(_ predicate: @MainActor @escaping () -> Bool) async throws {
        for _ in 0..<100 {
            if await predicate() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for async keyboard action")
    }
}

private final class FakeKeyboardAIService: KeyboardAIServiceProviding {
    let result: KeyboardActionOperationResult

    init(result: KeyboardActionOperationResult) {
        self.result = result
    }

    func analyzeSuggestions(for text: String, config: AppConfig) async throws -> KeyboardSuggestionResponse {
        result.suggestionResponse()
    }

    func perform(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> String {
        result.displayText
    }

    func performResult(action: KeyboardAIAction, on text: String, config: AppConfig) async throws -> KeyboardActionOperationResult {
        result
    }
}

private final class FakeTextDocumentProxy: NSObject, UITextDocumentProxy {
    var storage: String
    let documentIdentifier = UUID()
    private(set) var deletedCharacterCount = 0

    init(initialText: String) {
        self.storage = initialText
        super.init()
    }

    var documentContextBeforeInput: String? { storage }
    var documentContextAfterInput: String? { nil }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var hasText: Bool { !storage.isEmpty }

    func insertText(_ text: String) {
        storage.append(text)
    }

    func deleteBackward() {
        guard !storage.isEmpty else { return }
        storage.removeLast()
        deletedCharacterCount += 1
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) { storage.append(markedText) }
    func unmarkText() {}
}
