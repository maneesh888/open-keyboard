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
}
