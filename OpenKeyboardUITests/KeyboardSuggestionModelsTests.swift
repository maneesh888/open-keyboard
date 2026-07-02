import XCTest

final class KeyboardSuggestionModelsTests: XCTestCase {
    func testKeyboardActionErrorSanitizesRawJSONAndSecrets() {
        let error = KeyboardActionErrorState(message: "Gateway failed {\"api_key\":\"secret-token\",\"stack\":[1,2,3]}")

        XCTAssertEqual(error.title, "Gateway error")
        XCTAssertFalse(error.message.contains("{"))
        XCTAssertFalse(error.message.localizedCaseInsensitiveContains("api_key"))
        XCTAssertFalse(error.message.localizedCaseInsensitiveContains("token"))
        XCTAssertLessThanOrEqual(error.message.count, 140)
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

    func testLongPhraseCorrectionsApplyAfterEarlierLengthChangesAndDismissal() {
        let original = "Yesterday I has a apple before the meeting, and ths message still sound wrong when I send it to the client."
        XCTAssertGreaterThanOrEqual(original.count, 80)
        let response = KeyboardSuggestionResponse(
            corrections: [
                KeyboardCorrectionSuggestion(label: "Verb tense", original: "has", replacement: "had"),
                KeyboardCorrectionSuggestion(label: "Article", original: "a apple", replacement: "an apple"),
                KeyboardCorrectionSuggestion(label: "Spelling", original: "ths", replacement: "this"),
                KeyboardCorrectionSuggestion(label: "Subject-verb agreement", original: "sound", replacement: "sounds"),
                KeyboardCorrectionSuggestion(label: "Verb tense", original: "send", replacement: "sent")
            ],
            predictions: []
        )
        var state = KeyboardSuggestionState(response: response)
        var text = original

        text = state.textByApplyingCurrentCorrection(to: text) ?? text
        state.applyCurrentCorrection()
        XCTAssertEqual(text, "Yesterday I had a apple before the meeting, and ths message still sound wrong when I send it to the client.")

        text = state.textByApplyingCurrentCorrection(to: text) ?? text
        state.applyCurrentCorrection()
        XCTAssertEqual(text, "Yesterday I had an apple before the meeting, and ths message still sound wrong when I send it to the client.")

        state.dismissCurrentCorrection()
        XCTAssertEqual(text, "Yesterday I had an apple before the meeting, and ths message still sound wrong when I send it to the client.")
        XCTAssertEqual(state.currentCorrection?.original, "sound")

        text = state.textByApplyingCurrentCorrection(to: text) ?? text
        state.applyCurrentCorrection()
        XCTAssertEqual(text, "Yesterday I had an apple before the meeting, and ths message still sounds wrong when I send it to the client.")

        text = state.textByApplyingCurrentCorrection(to: text) ?? text
        state.applyCurrentCorrection()
        XCTAssertEqual(text, "Yesterday I had an apple before the meeting, and ths message still sounds wrong when I sent it to the client.")
        XCTAssertTrue(state.isComplete)
    }

    func testRangeAwareSingleCharacterCorrectionUsesNearestOriginalAfterEarlierEdits() {
        let response = KeyboardSuggestionResponse(
            corrections: [
                KeyboardCorrectionSuggestion(label: "Capitalization", original: "i", replacement: "I", range: KeyboardTextRange(start: 0, end: 1)),
                KeyboardCorrectionSuggestion(label: "Verb agreement", original: "has", replacement: "have", range: KeyboardTextRange(start: 2, end: 5)),
                KeyboardCorrectionSuggestion(label: "Article", original: "a", replacement: "an", range: KeyboardTextRange(start: 6, end: 7))
            ],
            predictions: [],
            correctedText: "I have an apple."
        )
        var state = KeyboardSuggestionState(response: response)
        var text = "i has a apple"

        text = state.textByApplyingCurrentCorrection(to: text) ?? text
        state.applyCurrentCorrection()
        XCTAssertEqual(text, "I has a apple")

        text = state.textByApplyingCurrentCorrection(to: text) ?? text
        state.applyCurrentCorrection()
        XCTAssertEqual(text, "I have a apple")

        text = state.textByApplyingCurrentCorrection(to: text) ?? text
        state.applyCurrentCorrection()
        XCTAssertEqual(text, "I have an apple")
        XCTAssertTrue(state.isComplete)
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

    func testStructuredCorrectionRangeMapsToSuggestion() throws {
        let json = """
        {"operation":"fix_grammar","results":[{"id":"article","type":"correction","title":"Article","text":"Use an.","original":"a","replacement":"an","range":{"start":6,"end":7}}],"corrected_text":"I have an apple."}
        """
        let result = try KeyboardActionOperationResult.parse(json, operation: "fix_grammar", fallbackText: "i has a apple")

        let correction = try XCTUnwrap(result.suggestionResponse().corrections.first)

        XCTAssertEqual(correction.range, KeyboardTextRange(start: 6, end: 7))
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

    func testParsesComplexGatewaySpellFixResponseIntoCorrectionCards() throws {
        let original = "i definately recieve teh adress tomorow, and seperate files wont upload because its recieve limit is to low."
        let assistantContent = """
        ```json
        {
          "operation": "fix_grammar",
          "results": [
            {"id":"cap-i","type":"correction","title":"Capitalization","text":"Capitalize the pronoun.","original":"i","replacement":"I","range":{"start":0,"end":1},"confidence":0.99,"category":"capitalization","explanation":"Capitalize the standalone pronoun I."},
            {"id":"spell-definitely","type":"correction","title":"Spelling","text":"Correct definitely.","original":"definately","replacement":"definitely","range":{"start":2,"end":12},"confidence":0.99,"category":"spelling","explanation":"Correct the misspelling."},
            {"id":"spell-receive-1","type":"correction","title":"Spelling","text":"Correct receive.","original":"recieve","replacement":"receive","range":{"start":13,"end":20},"confidence":0.98,"category":"spelling","explanation":"Use receive after c."},
            {"id":"spell-the","type":"correction","title":"Spelling","text":"Correct the.","original":"teh","replacement":"the","range":{"start":21,"end":24},"confidence":0.97,"category":"spelling"},
            {"id":"spell-address","type":"correction","title":"Spelling","text":"Correct address.","original":"adress","replacement":"address","range":{"start":25,"end":31},"confidence":0.98,"category":"spelling"},
            {"id":"spell-tomorrow","type":"correction","title":"Spelling","text":"Correct tomorrow.","original":"tomorow","replacement":"tomorrow","range":{"start":32,"end":39},"confidence":0.97,"category":"spelling"},
            {"id":"spell-separate","type":"correction","title":"Spelling","text":"Correct separate.","original":"seperate","replacement":"separate","range":{"start":45,"end":53},"confidence":0.95,"category":"spelling"},
            {"id":"contract-wont","type":"correction","title":"Contraction","text":"Add apostrophe.","original":"wont","replacement":"won't","range":{"start":60,"end":64},"confidence":0.93,"category":"grammar"},
            {"id":"pronoun-its","type":"correction","title":"Pronoun agreement","text":"Use a plural possessive pronoun.","original":"its","replacement":"their","range":{"start":80,"end":83},"confidence":0.88,"category":"grammar","explanation":"Files is plural."},
            {"id":"spell-receive-2","type":"correction","title":"Spelling","text":"Correct the second receive.","original":"recieve","replacement":"receive","range":{"start":84,"end":91},"confidence":0.98,"category":"spelling"},
            {"id":"too-low","type":"correction","title":"Word choice","text":"Use too for degree.","original":"to low","replacement":"too low","range":{"start":101,"end":107},"confidence":0.94,"category":"grammar"},
            {"id":"warning-domain","type":"warning","title":"Ambiguity","text":"The phrase receive limit may be domain-specific."}
          ],
          "summary": "Eleven corrections found.",
          "corrected_text": "I definitely receive the address tomorrow, and separate files won't upload because their receive limit is too low."
        }
        ```
        """
        let gatewayData = try JSONSerialization.data(withJSONObject: [
            "id": "chatcmpl-open-keyboard-spell-fix",
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": assistantContent
                    ]
                ]
            ]
        ])
        let gatewayResponse = String(data: gatewayData, encoding: .utf8)!

        let result = try KeyboardActionOperationResult.parse(gatewayResponse, operation: "fix_grammar", fallbackText: original)
        let response = result.suggestionResponse()
        let outcome = KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result)

        XCTAssertTrue(result.isStructuredResponse)
        XCTAssertEqual(result.operation, "fix_grammar")
        XCTAssertEqual(result.items.count, 12)
        XCTAssertEqual(result.items.last?.type, "warning")
        XCTAssertEqual(response.correctedText, "I definitely receive the address tomorrow, and separate files won't upload because their receive limit is too low.")
        XCTAssertEqual(response.corrections.count, 11)
        XCTAssertEqual(response.corrections.map(\.id), [
            "cap-i",
            "spell-definitely",
            "spell-receive-1",
            "spell-the",
            "spell-address",
            "spell-tomorrow",
            "spell-separate",
            "contract-wont",
            "pronoun-its",
            "spell-receive-2",
            "too-low"
        ])
        XCTAssertEqual(response.corrections.map(\.replacement), [
            "I",
            "definitely",
            "receive",
            "the",
            "address",
            "tomorrow",
            "separate",
            "won't",
            "their",
            "receive",
            "too low"
        ])
        XCTAssertEqual(response.corrections[9].range, KeyboardTextRange(start: 84, end: 91))
        guard case .showCorrections(let routedResponse) = outcome else {
            return XCTFail("Expected product path to show correction cards, got \(outcome)")
        }
        XCTAssertEqual(routedResponse.corrections.count, 11)

        var state = KeyboardSuggestionState(response: response)
        var text = original
        while state.currentCorrection != nil {
            text = state.textByApplyingCurrentCorrection(to: text) ?? text
            state.applyCurrentCorrection()
        }
        XCTAssertEqual(text, response.correctedText)
        XCTAssertTrue(state.isComplete)
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


    func testErrorCopyStructuredResultDoesNotBecomeReplacementText() throws {
        let result = try KeyboardActionOperationResult.parse(#"{"operation":"rewrite","results":[{"id":"error-1","type":"warning","title":"Error","text":"The model returned malformed JSON and no safe keyboard text could be extracted.","replacement":"The model returned malformed JSON and no safe keyboard text could be extracted."}]}"#, operation: "rewrite", fallbackText: "Keep my original words.")

        let outcome = KeyboardActionResultHandler.outcome(operation: "rewrite", result: result)

        XCTAssertEqual(outcome, .noUsableResult)
        XCTAssertNotEqual(outcome, .replaceText("The model returned malformed JSON and no safe keyboard text could be extracted."))
    }

    func testNoIssueStructuredGrammarResultDoesNotReplaceTextWithSummary() throws {
        let result = try KeyboardActionOperationResult.parse(#"{"operation":"fix_grammar","results":[],"summary":"No issues found."}"#, operation: "fix_grammar", fallbackText: "The app works well.")

        let outcome = KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result)

        XCTAssertTrue(result.isStructuredResponse)
        XCTAssertEqual(outcome, .noChanges)
        XCTAssertNotEqual(outcome, .replaceText("No issues found."))
    }

    func testNoIssueStructuredGrammarWithSameCorrectedTextDoesNotApplyReplacement() throws {
        let result = try KeyboardActionOperationResult.parse(#"{"operation":"fix_grammar","results":[],"corrected_text":"The app works well today."}"#, operation: "fix_grammar", fallbackText: "The app works well today.")

        let outcome = KeyboardActionResultHandler.outcome(operation: "fix_grammar", result: result)

        XCTAssertTrue(result.isStructuredResponse)
        XCTAssertTrue(result.isStructuredGrammarNoChange)
        XCTAssertEqual(outcome, .noChanges)
        XCTAssertNotEqual(outcome, .replaceText("The app works well today."))
    }

    func testMalformedJSONLikeResponseDoesNotBecomeLegacyReplacementText() {
        XCTAssertThrowsError(try KeyboardActionOperationResult.parse(#"{"operation":"fix_grammar","results": ["#, operation: "fix_grammar", fallbackText: "i has a apple")) { error in
            XCTAssertEqual(error as? KeyboardActionOperationResultError, .invalidResponse)
        }
    }

    func testStructuredOperationParsesCommonDisplayAliases() throws {
        let scenarios: [(String, String, String)] = [
            (#"{"operation":"rewrite","rewritten_text":"This is clearer."}"#, "rewrite", "This is clearer."),
            (#"{"operation":"fix_grammar","correctedText":"I have an apple."}"#, "fix_grammar", "I have an apple."),
            (#"{"operation":"rewrite","result":{"id":"rewrite-1","type":"suggestion","text":"Clearer text.","replacement":"Clearer text."}}"#, "rewrite", "Clearer text."),
            (#"{"operation":"fix_grammar","improved_text":"I have an apple."}"#, "fix_grammar", "I have an apple."),
            (#"{"operation":"rewrite","replacement":"Replacement text."}"#, "rewrite", "Replacement text."),
            (#"{"operation":"rewrite","text":"Top-level text."}"#, "rewrite", "Top-level text."),
            (#"{"operation":"rewrite","output":"Output text."}"#, "rewrite", "Output text.")
        ]

        for (json, operation, expectedDisplayText) in scenarios {
            let result = try KeyboardActionOperationResult.parse(json, operation: operation, fallbackText: "i has a apple")

            XCTAssertEqual(result.displayText, expectedDisplayText)
            XCTAssertTrue(result.isStructuredResponse)
        }
    }

    func testCorrectionSmokeAcceptsStructuredJSONResponses() {
        XCTAssertTrue(NetworkManager.isUsableCorrectionSmokeResponse(#"{"operation":"fix_grammar","results":[],"corrected_text":"I have an apple."}"#))
        XCTAssertTrue(NetworkManager.isUsableCorrectionSmokeResponse(#"{"operation":"fix_grammar","results":[{"type":"correction","original":"has","replacement":"have"},{"type":"correction","original":"a apple","replacement":"an apple"}]}"#))
    }

    private static func canonicalGrammarJSON(correctedText: String?) -> String {
        let correctedTextField = correctedText.map { #", "corrected_text": "\#($0)""# } ?? ""
        return #"{"operation":"fix_grammar","results":[{"id":"subject-verb","type":"correction","title":"Subject-verb agreement","text":"Use have.","original":"has","replacement":"have","category":"grammar","explanation":"Use have for first-person agreement."},{"id":"article","type":"correction","title":"Article","text":"Use an.","original":"a apple","replacement":"an apple","explanation":"Use an before a vowel sound."},{"id":"spelling-this","type":"correction","title":"Spelling","text":"Fix typo.","original":"ths","replacement":"this","category":"spelling","explanation":"Correct the misspelling."}], "summary":"Three issues found."\#(correctedTextField)}"#
    }

}
