import XCTest

final class KeyboardSuggestionModelsTests: XCTestCase {
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

    func testAppliesAndDismissesStructuredCorrectionsInSequence() {
        let response = KeyboardSuggestionResponse(
            corrections: [
                KeyboardCorrectionSuggestion(label: "Subject-verb agreement", original: "has", replacement: "have"),
                KeyboardCorrectionSuggestion(label: "Article", original: "a apple", replacement: "an apple"),
                KeyboardCorrectionSuggestion(label: "Spelling", original: "ths", replacement: "this")
            ],
            predictions: []
        )
        var state = KeyboardSuggestionState(response: response)
        var text = "i has a apple ths"

        XCTAssertEqual(state.textByApplyingCurrentCorrection(to: text), "i have a apple ths")
        text = state.textByApplyingCurrentCorrection(to: text) ?? text
        state.applyCurrentCorrection()
        XCTAssertEqual(state.currentCorrection?.original, "a apple")

        state.dismissCurrentCorrection()
        XCTAssertEqual(state.currentCorrection?.original, "ths")
        XCTAssertEqual(text, "i have a apple ths", "Dismiss should not mutate caller text")

        XCTAssertEqual(state.textByApplyingCurrentCorrection(to: text), "i have a apple this")
        text = state.textByApplyingCurrentCorrection(to: text) ?? text
        state.applyCurrentCorrection()
        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(text, "i have a apple this")
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

    func testCorrectionOnlyPredictionOnlyAndNoSuggestionsStates() {
        let correctionOnly = KeyboardSuggestionState(response: KeyboardSuggestionResponse(corrections: [KeyboardCorrectionSuggestion(label: "Correct", original: "i", replacement: "I")], predictions: []))
        XCTAssertEqual(correctionOnly.compactCorrectionReplacement, "I")
        XCTAssertNil(correctionOnly.compactPredictionText)

        let predictionOnly = KeyboardSuggestionState(response: KeyboardSuggestionResponse(corrections: [], predictions: [KeyboardPredictionSuggestion(label: "Suggestion", text: "apple")]))
        XCTAssertNil(predictionOnly.compactCorrectionReplacement)
        XCTAssertEqual(predictionOnly.compactPredictionText, "apple")

        XCTAssertTrue(KeyboardSuggestionState(response: KeyboardSuggestionResponse(corrections: [], predictions: [])).isComplete)
    }

    func testPromptRequestsStrictJSONAndBoundedContext() {
        let prompt = KeyboardSuggestionParser.prompt(for: String(repeating: "a", count: 700))
        XCTAssertTrue(prompt.contains("strict JSON only"))
        XCTAssertTrue(prompt.contains("corrections and predictions separately"))
        XCTAssertTrue(prompt.contains("Do not include markdown"))
        XCTAssertLessThan(prompt.count, 1200)
    }

    func testMapsStructuredCorrectionItemsToSuggestionResponse() throws {
        let result = try KeyboardActionOperationResult.parse(Self.canonicalGrammarJSON(correctedText: nil), operation: "fix_grammar", fallbackText: "i has a apple ths")

        let response = result.suggestionResponse()

        XCTAssertEqual(response.corrections.count, 3)
        XCTAssertEqual(response.corrections.map(\.original), ["has", "a apple", "ths"])
        XCTAssertEqual(response.corrections.map(\.replacement), ["have", "an apple", "this"])
        XCTAssertEqual(response.corrections.map(\.label), ["Subject-verb agreement", "Article", "Spelling"])
        XCTAssertEqual(response.corrections.map(\.category), ["grammar", "correction", "spelling"])
        XCTAssertEqual(response.corrections[1].explanation, "Use an before a vowel sound.")
    }

    func testStructuredResultWithoutCorrectedTextStillCreatesCorrections() throws {
        let result = try KeyboardActionOperationResult.parse(Self.canonicalGrammarJSON(correctedText: nil), operation: "fix_grammar", fallbackText: "i has a apple ths")

        let outcome = KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result)

        guard case .showCorrections(let response) = outcome else {
            return XCTFail("Expected correction state, got \(outcome)")
        }
        let state = KeyboardSuggestionState(response: response)
        XCTAssertNil(response.correctedText)
        XCTAssertEqual(state.correctionCount, 3)
        XCTAssertEqual(state.currentCorrection?.replacement, "have")
    }

    func testStructuredResultWithCorrectedTextDoesNotDropCorrections() throws {
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

    func testNonCorrectionItemsAreHandledSafely() throws {
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

    func testKeyboardActionPathShowsMultipleCorrectionsInsteadOfFirstReplacementOnly() throws {
        let result = try KeyboardActionOperationResult.parse(Self.canonicalGrammarJSON(correctedText: nil), operation: "fix_grammar", fallbackText: "i has a apple ths")

        let outcome = KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result)

        XCTAssertEqual(result.displayText, "have", "String-only legacy display fallback would collapse to the first replacement.")
        guard case .showCorrections(let response) = outcome else {
            return XCTFail("Expected product path to route structured grammar items to correction state")
        }
        let state = KeyboardSuggestionState(response: response)
        XCTAssertEqual(state.correctionCount, 3)
        XCTAssertEqual(state.corrections.map(\.replacement), ["have", "an apple", "this"])
    }

    func testKeyboardActionPathCanUseCorrectedTextForApplyAllOrLegacyReplacement() throws {
        let result = try KeyboardActionOperationResult.parse(Self.canonicalGrammarJSON(correctedText: "I have an apple this"), operation: "fix_grammar", fallbackText: "i has a apple ths")

        let outcome = KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result)

        XCTAssertEqual(result.displayText, "I have an apple this")
        guard case .showCorrections(let response) = outcome else {
            return XCTFail("Expected correction cards instead of silent full replacement for structured grammar result")
        }
        XCTAssertEqual(response.correctedText, "I have an apple this")
        XCTAssertEqual(response.corrections.count, 3)
    }

    func testSummarizeOrRewriteStructuredResultStillProducesExpectedReplacement() throws {
        let summary = try KeyboardActionOperationResult.parse(#"{"operation":"summarize","results":[{"id":"summary-1","type":"summary","title":"Summary","text":"The keyboard helps with writing."}],"summary":"The keyboard helps with writing."}"#, operation: "summarize", fallbackText: "Long source text")
        let rewrite = try KeyboardActionOperationResult.parse(#"{"operation":"rewrite","results":[{"id":"rewrite-1","type":"suggestion","title":"Rewrite","text":"Clearer text.","replacement":"Clearer text."}]}"#, operation: "rewrite", fallbackText: "bad text")

        XCTAssertEqual(KeyboardActionResultHandler.outcome(operation: "summarize", result: summary), .replaceText("The keyboard helps with writing."))
        XCTAssertEqual(KeyboardActionResultHandler.outcome(operation: "rewrite", result: rewrite), .replaceText("Clearer text."))
    }

    private static func canonicalGrammarJSON(correctedText: String?) -> String {
        let correctedTextField = correctedText.map { #", "corrected_text": "\#($0)""# } ?? ""
        return #"{"operation":"fix_grammar","results":[{"id":"subject-verb","type":"correction","title":"Subject-verb agreement","text":"Use have.","original":"has","replacement":"have","category":"grammar","explanation":"Use have for first-person agreement."},{"id":"article","type":"correction","title":"Article","text":"Use an.","original":"a apple","replacement":"an apple","explanation":"Use an before a vowel sound."},{"id":"spelling-this","type":"correction","title":"Spelling","text":"Fix typo.","original":"ths","replacement":"this","category":"spelling","explanation":"Correct the misspelling."}], "summary":"Three issues found."\#(correctedTextField)}"#
    }

}
