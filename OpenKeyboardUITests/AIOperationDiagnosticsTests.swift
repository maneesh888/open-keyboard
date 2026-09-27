import XCTest
import UniversalAiConnector

final class AIOperationDiagnosticsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AIOperationDiagnosticsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLedgerStoresOnlyTypedSafeMetadataAndBoundsEvents() throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let traceID = ledger.begin(operation: .rewrite, origin: .keyboardManualAction)

        for event in 0..<(AIOperationDiagnostics.maximumEventsPerRecord + 10) {
            ledger.record(
                traceID: traceID,
                stage: .transport,
                attempt: 1,
                durationMilliseconds: event,
                httpStatusCategory: .success,
                requestBytes: event,
                responseBytes: event + 1
            )
        }
        ledger.complete(traceID: traceID, outcome: .succeeded)

        let record = try XCTUnwrap(ledger.record(traceID: traceID))
        XCTAssertEqual(record.schemaVersion, 1)
        XCTAssertEqual(record.events.count, AIOperationDiagnostics.maximumEventsPerRecord)
        XCTAssertEqual(record.operation, .rewrite)
        XCTAssertEqual(record.origin, .keyboardManualAction)
        XCTAssertEqual(record.outcome, .succeeded)
        XCTAssertTrue(record.events.allSatisfy { $0.requestBytes != nil || $0.stage == .finalOutcome })

        let encoded = try JSONEncoder().encode(record)
        let encodedDescription = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(encodedDescription.contains("apiKey"))
        XCTAssertFalse(encodedDescription.contains("authorization"))
        XCTAssertFalse(encodedDescription.contains("gatewayURL"))
        XCTAssertFalse(encodedDescription.contains("modelID"))
        XCTAssertFalse(encodedDescription.contains("typedText"))

        let exported = ledger.export(traceID: traceID)
        XCTAssertTrue(exported.contains("trace=\(traceID)"))
        XCTAssertTrue(exported.contains("request_bytes="))
        XCTAssertFalse(exported.contains("apiKey"))
        XCTAssertFalse(exported.contains("gatewayURL"))
    }

    func testLedgerExpiresRecordsAfterSevenDays() {
        var current = Date(timeIntervalSince1970: 1_000)
        let ledger = AIOperationDiagnostics(defaults: defaults, now: { current })
        _ = ledger.begin(operation: .fixGrammar, origin: .keyboardAutomaticAnalysis)
        XCTAssertEqual(ledger.records().count, 1)

        current = current.addingTimeInterval(AIOperationDiagnostics.retention + 1)

        XCTAssertTrue(ledger.records().isEmpty)
    }

    func testLedgerReadsV1RecordsWrittenBeforeOptionalSubreason() throws {
        struct LegacyEvent: Codable {
            let id: UUID
            let stage: AIOperationDiagnosticStage
            let attempt: Int
            let elapsedMilliseconds: Int
            let durationMilliseconds: Int?
            let httpStatusCategory: AIOperationDiagnosticHTTPStatusCategory?
            let requestBytes: Int?
            let responseBytes: Int?
            let failure: AIOperationDiagnosticFailure?
        }
        struct LegacyRecord: Codable {
            let schemaVersion: Int
            let traceID: String
            let operation: AIOperationDiagnosticOperation
            let origin: AIOperationDiagnosticOrigin
            let startedAt: Date
            let updatedAt: Date
            let appVersion: String
            let buildVersion: String
            let operatingSystemVersion: String
            let events: [LegacyEvent]
            let outcome: AIOperationDiagnosticOutcome?
            let failure: AIOperationDiagnosticFailure?
        }

        let timestamp = Date()
        let legacy = LegacyRecord(
            schemaVersion: 1,
            traceID: "legacy-trace",
            operation: .rewrite,
            origin: .keyboardManualAction,
            startedAt: timestamp,
            updatedAt: timestamp,
            appVersion: "1.0",
            buildVersion: "1",
            operatingSystemVersion: "iOS",
            events: [
                LegacyEvent(
                    id: UUID(),
                    stage: .decoding,
                    attempt: 1,
                    elapsedMilliseconds: 0,
                    durationMilliseconds: nil,
                    httpStatusCategory: nil,
                    requestBytes: nil,
                    responseBytes: nil,
                    failure: .malformedResponse
                ),
            ],
            outcome: .failed,
            failure: .malformedResponse
        )
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "aiOperationDiagnostics.v1")

        let ledger = AIOperationDiagnostics(defaults: defaults)
        let decoded = try XCTUnwrap(ledger.record(traceID: "legacy-trace"))
        XCTAssertNil(decoded.events.first?.subreason)
    }

    func testCompletedTraceCannotBeOverwrittenByLateResult() throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let traceID = ledger.begin(operation: .translate, origin: .keyboardActionPanel)

        ledger.record(
            traceID: traceID,
            stage: .staleResultSuppression,
            failure: .staleResultSuppressed
        )
        ledger.complete(
            traceID: traceID,
            outcome: .staleResultSuppressed,
            failure: .staleResultSuppressed
        )
        ledger.complete(traceID: traceID, outcome: .succeeded)

        let record = try XCTUnwrap(ledger.record(traceID: traceID))
        XCTAssertEqual(record.outcome, .staleResultSuppressed)
        XCTAssertEqual(record.failure, .staleResultSuppressed)
    }

    func testSeparateLedgerInstancesCoordinateConcurrentSharedDefaultsWrites() throws {
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIOperationDiagnosticsTests.\(UUID().uuidString).lock")
        let hostDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let keyboardDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let hostLedger = AIOperationDiagnostics(defaults: hostDefaults, storageLockURL: lockURL)
        let keyboardLedger = AIOperationDiagnostics(defaults: keyboardDefaults, storageLockURL: lockURL)
        let completed = expectation(description: "concurrent App Group ledger writes")
        completed.expectedFulfillmentCount = 24
        let queue = DispatchQueue(label: "AIOperationDiagnosticsTests.concurrent", attributes: .concurrent)

        for index in 0..<24 {
            queue.async {
                let ledger = index.isMultiple(of: 2) ? hostLedger : keyboardLedger
                _ = ledger.begin(
                    operation: .fixGrammar,
                    origin: index.isMultiple(of: 2) ? .hostAppGatewayCheck : .keyboardManualAction
                )
                completed.fulfill()
            }
        }

        wait(for: [completed], timeout: 10)
        XCTAssertEqual(hostLedger.records().count, 24)
    }

    func testMalformedConnectorFailureRemainsTheFinalSupportFacingCategory() throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let traceID = ledger.begin(operation: .fixGrammar, origin: .keyboardManualAction)

        ledger.record(
            traceID: traceID,
            stage: .decoding,
            durationMilliseconds: 2_300,
            failure: .malformedResponse
        )
        // The view model only knows that no usable operation result was produced. Its broad
        // validation category must not hide the adapter's already-recorded decode cause.
        ledger.complete(
            traceID: traceID,
            outcome: .failed,
            failure: .validationRejected
        )

        let record = try XCTUnwrap(ledger.record(traceID: traceID))
        XCTAssertEqual(record.failure, .malformedResponse)
        XCTAssertEqual(record.events.last?.failure, .malformedResponse)

        let exported = ledger.export(traceID: traceID)
        XCTAssertTrue(exported.contains("failure=malformed_response"))
        XCTAssertFalse(exported.contains("validation_rejected"))
        XCTAssertFalse(exported.contains("private response fixture"))
    }

    func testExportIncludesClosedSubreasonWithoutPrivateValues() throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let traceID = ledger.begin(operation: .fixGrammar, origin: .keyboardManualAction)

        ledger.record(
            traceID: traceID,
            stage: .decoding,
            failure: .malformedResponse,
            subreason: .malformedProviderStream
        )
        ledger.complete(traceID: traceID, outcome: .failed)

        let record = try XCTUnwrap(ledger.record(traceID: traceID))
        XCTAssertEqual(record.events.first?.subreason, .malformedProviderStream)

        let exported = ledger.export(traceID: traceID)
        XCTAssertTrue(exported.contains("subreason=malformed_provider_stream"))
        XCTAssertFalse(exported.contains("raw provider message"))
        XCTAssertFalse(exported.contains("generated response text"))
        XCTAssertFalse(exported.contains("https://private-gateway.example"))
        XCTAssertFalse(exported.contains("private-model-id"))
        XCTAssertFalse(exported.contains("Authorization: Bearer private-token"))
    }

    func testAppOutputValidationRejectionRemainsTheFinalSupportFacingCategory() throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let traceID = ledger.begin(operation: .rewrite, origin: .keyboardManualAction)

        ledger.record(
            traceID: traceID,
            stage: .validation,
            failure: .validationRejected
        )
        ledger.complete(
            traceID: traceID,
            outcome: .failed,
            failure: .validationRejected
        )

        let record = try XCTUnwrap(ledger.record(traceID: traceID))
        XCTAssertEqual(record.failure, .validationRejected)
        XCTAssertEqual(record.events.last?.failure, .validationRejected)
    }

    private func request(_ text: String = "The cat are asleep.", model: String = "fixture/model") throws -> OpenKeyboardAIRequest {
        try OpenKeyboardAIRequest(modelID: model, messages: [.init(role: .user, content: text)], maxOutputTokens: 512, temperature: 0.1)
    }

    func testMetadataIncludesExactModelAndSettingsButNeverTextWithoutConsent() throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let trace = ledger.begin(operation: .fixGrammar, origin: .keyboardManualAction, sourceText: "private fixture source")
        let id = try XCTUnwrap(ledger.beginRequest(traceID: trace, provider: .openRouter, request: request("private fixture input")))
        ledger.recordResponse(traceID: trace, requestID: id, text: "private fixture output", completionReason: "stop", outputCount: 1)
        let record = try XCTUnwrap(ledger.record(traceID: trace))
        XCTAssertNil(record.sourceText)
        XCTAssertNil(record.requests?.first?.userMessage)
        XCTAssertNil(record.requests?.first?.responseText)
        XCTAssertEqual(record.requests?.first?.modelID, "fixture/model")
        XCTAssertEqual(record.requests?.first?.maxOutputTokens, 512)
        XCTAssertEqual(record.requests?.first?.timeoutMilliseconds, 15_000)
        XCTAssertNotNil(record.binaryID)
        let export = ledger.export(includeText: true)
        XCTAssertTrue(export.contains("provider=openrouter model=fixture/model"))
        XCTAssertTrue(export.contains("started_at="))
        XCTAssertFalse(export.contains("private fixture"))
    }

    func testConsentedTextRequiresSeparateExportAndQuotesNewlines() throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        ledger.startTextCapture()
        let trace = ledger.begin(operation: .fixGrammar, origin: .keyboardManualAction, sourceText: "private fixture source\ntrace=forged")
        let id = try XCTUnwrap(ledger.beginRequest(traceID: trace, provider: .openRouter, request: request("private fixture input")))
        ledger.recordResponse(traceID: trace, requestID: id, text: "private fixture output", completionReason: "stop", outputCount: 1)
        XCTAssertFalse(ledger.export().contains("private fixture"))
        let detailed = ledger.export(traceID: trace, includeText: true)
        XCTAssertTrue(detailed.contains("private fixture input"))
        XCTAssertTrue(detailed.contains("private fixture output"))
        XCTAssertFalse(detailed.contains("\ntrace=forged"))
        XCTAssertTrue(ledger.export(traceID: "missing", includeText: true).contains("records=0"))
    }

    func testConsentCannotRetroactivelyCaptureInFlightOperation() throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let trace = ledger.begin(operation: .fixGrammar, origin: .keyboardManualAction)
        ledger.startTextCapture()
        let id = try XCTUnwrap(ledger.beginRequest(traceID: trace, provider: .openRouter, request: request("private fixture input")))
        ledger.recordResponse(traceID: trace, requestID: id, text: "private fixture output", completionReason: "stop", outputCount: 1)
        XCTAssertFalse(ledger.export(includeText: true).contains("private fixture"))
    }

    func testRevocationDeletesTextAcrossInstancesAndBlocksLateResponsesAfterReenable() throws {
        let host = AIOperationDiagnostics(defaults: defaults)
        let keyboard = AIOperationDiagnostics(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        host.startTextCapture()
        let trace = keyboard.begin(operation: .fixGrammar, origin: .keyboardAutomaticAnalysis, sourceText: "private fixture source")
        let id = try XCTUnwrap(keyboard.beginRequest(traceID: trace, provider: .openRouter, request: request()))
        host.stopTextCaptureAndDelete()
        host.startTextCapture()
        keyboard.recordResponse(traceID: trace, requestID: id, text: "private fixture late output", completionReason: "stop", outputCount: 1)
        XCTAssertFalse(host.export(includeText: true).contains("private fixture"))
        XCTAssertNil(host.record(traceID: trace)?.captureSessionID)
    }

    func testCaptureExpiresAndTextRetentionPurgesIndependentlyOfMetadata() throws {
        var current = Date(timeIntervalSince1970: 10_000)
        let ledger = AIOperationDiagnostics(defaults: defaults, now: { current })
        ledger.startTextCapture()
        let trace = ledger.begin(operation: .fixGrammar, origin: .keyboardManualAction, sourceText: "private fixture source")
        let id = try XCTUnwrap(ledger.beginRequest(traceID: trace, provider: .openRouter, request: request()))
        current = current.addingTimeInterval(AIOperationDiagnostics.captureDuration + 1)
        XCTAssertNil(ledger.textCaptureExpiresAt)
        ledger.recordResponse(traceID: trace, requestID: id, text: "private fixture late output", completionReason: "stop", outputCount: 1)
        XCTAssertNil(ledger.record(traceID: trace)?.requests?.first?.responseText)
        let later = ledger.begin(operation: .rewrite, origin: .keyboardManualAction, sourceText: "private fixture new source")
        XCTAssertNil(ledger.record(traceID: later)?.sourceText)
        current = current.addingTimeInterval(AIOperationDiagnostics.textRetention)
        XCTAssertEqual(ledger.records().count, 2)
        XCTAssertFalse(ledger.export(includeText: true).contains("private fixture"))
    }

    func testTextAndRequestBoundsAreReportedAndClearRevokesConsent() throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        ledger.startTextCapture()
        let text = String(repeating: "🐱", count: 2_000)
        let trace = ledger.begin(operation: .fixGrammar, origin: .keyboardManualAction, sourceText: text)
        for _ in 0..<(AIOperationDiagnostics.maximumRequestsPerRecord + 2) {
            _ = ledger.beginRequest(traceID: trace, provider: .openRouter, request: try request(text))
        }
        let record = try XCTUnwrap(ledger.record(traceID: trace))
        XCTAssertEqual(record.sourceText?.text.utf8.count, 4_096)
        XCTAssertEqual(record.sourceText?.truncated, true)
        XCTAssertEqual(record.requests?.count, AIOperationDiagnostics.maximumRequestsPerRecord)
        XCTAssertEqual(record.requestsOmitted, 2)
        ledger.removeAll()
        XCTAssertNil(ledger.textCaptureExpiresAt)
        XCTAssertTrue(ledger.records().isEmpty)
    }

    func testOnlyEightOperationsKeepTextWhileMetadataRemains() throws {
        var current = Date(timeIntervalSince1970: 10_000)
        let ledger = AIOperationDiagnostics(defaults: defaults, now: { current })
        ledger.startTextCapture()
        for _ in 0..<12 {
            _ = ledger.begin(operation: .rewrite, origin: .keyboardManualAction, sourceText: "private fixture source")
            current = current.addingTimeInterval(1)
        }
        XCTAssertEqual(ledger.records().count, 12)
        XCTAssertEqual(ledger.records().filter { $0.sourceText != nil }.count, 8)
    }

    func testUnsafeModelIDCannotInjectExportLines() throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let trace = ledger.begin(operation: .rewrite, origin: .keyboardManualAction)
        _ = ledger.beginRequest(traceID: trace, provider: .openRouter, request: try request(model: "fixture\nsecret=value"))
        XCTAssertNil(ledger.record(traceID: trace)?.requests?.first?.modelID)
        XCTAssertFalse(ledger.export().contains("secret=value"))
    }

    func testAdapterCapturesAvailableRejectedResponseAndLinksFailureToRequest() async throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        ledger.startTextCapture()
        let trace = ledger.begin(operation: .fixGrammar, origin: .keyboardManualAction, sourceText: "Synthetic source")
        let adapter = UniversalAIConnectorAdapter(factory: { _ in DiagnosticRuntime(completion: .maxOutputTokens) }, diagnostics: ledger)
        let profile = try OpenKeyboardGatewayProfile(provider: .openRouter, baseURL: "https://openrouter.ai/api/v1", apiKey: "fixture-credential-never-export")
        do {
            _ = try await AIOperationDiagnosticContext.$traceID.withValue(trace) {
                try await adapter.respond(to: request(), profile: profile)
            }
            XCTFail("Expected truncated response")
        } catch let error as OpenKeyboardAIConnectorError { XCTAssertEqual(error, .truncatedResponse) }
        let record = try XCTUnwrap(ledger.record(traceID: trace))
        let context = try XCTUnwrap(record.requests?.first)
        XCTAssertEqual(context.responseText?.text, "Synthetic response")
        XCTAssertEqual(record.events.last?.requestID, context.id)
        XCTAssertEqual(record.events.last?.subreason, .outputLimitReached)
        XCTAssertFalse(ledger.export(includeText: true).contains("fixture-credential-never-export"))
        XCTAssertFalse(ledger.export(includeText: true).contains("https://openrouter.ai"))
    }

    func testConnectorSuccessDoesNotInventAnHTTPStatus() async throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let trace = ledger.begin(operation: .fixGrammar, origin: .keyboardManualAction)
        let adapter = UniversalAIConnectorAdapter(factory: { _ in DiagnosticRuntime(completion: .stop) }, diagnostics: ledger)
        let profile = try OpenKeyboardGatewayProfile(provider: .openRouter, baseURL: "https://openrouter.ai/api/v1", apiKey: "fixture-credential")
        _ = try await AIOperationDiagnosticContext.$traceID.withValue(trace) {
            try await adapter.respond(to: request(), profile: profile)
        }
        let record = try XCTUnwrap(ledger.record(traceID: trace))
        XCTAssertTrue(record.events.contains { $0.connectorResponseAccepted == true })
        XCTAssertTrue(record.events.allSatisfy { $0.httpStatusCode == nil && $0.httpStatusCategory == nil })
    }

    func testConcurrentChunkCancellationCannotReplaceMalformedResponseCause() async throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let trace = ledger.begin(operation: .fixGrammar, origin: .keyboardManualAction)
        let runtime = DiagnosticChunkRuntime(failsFirst: true)
        let adapter = UniversalAIConnectorAdapter(factory: { _ in runtime }, diagnostics: ledger)
        let service = KeyboardAIService(connector: adapter, diagnostics: ledger)
        let config = AppConfig(apiKey: "fixture-key", gatewayURL: "https://gateway.example/v1", selectedModel: "fixture-model", isConfigured: true, grammarCorrectionVerified: true, grammarCorrectionContractVersion: "fixture-contract")
        do {
            _ = try await AIOperationDiagnosticContext.$traceID.withValue(trace) {
                try await service.performResult(action: .fixGrammar, on: "The cat are sleepy. The dog are happy.", config: config)
            }
            XCTFail("Expected malformed response")
        } catch let error as KeyboardAIError { XCTAssertEqual(error, .invalidResponse) }
        ledger.complete(traceID: trace, outcome: .failed, failure: .validationRejected)
        let record = try XCTUnwrap(ledger.record(traceID: trace))
        XCTAssertEqual(record.failure, .malformedResponse)
        XCTAssertTrue(record.events.contains { $0.failure == .cancelled && $0.stage == .cancellation })
        XCTAssertFalse(record.events.contains { $0.failure == .transportFailure })
        let requests = try XCTUnwrap(record.requests)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(Set(requests.map(\.id)).count, 2)
        for request in requests {
            XCTAssertTrue(record.events.contains { $0.requestID == request.id && $0.stage == .promptConstruction })
            XCTAssertTrue(record.events.contains { $0.requestID == request.id && $0.stage == .transport })
        }
    }

    func testOutOfOrderGrammarChunksKeepPromptResponseAndValidationCorrelated() async throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        ledger.startTextCapture()
        let trace = ledger.begin(operation: .fixGrammar, origin: .keyboardManualAction)
        let runtime = DiagnosticChunkRuntime(failsFirst: false)
        let adapter = UniversalAIConnectorAdapter(factory: { _ in runtime }, diagnostics: ledger)
        let service = KeyboardAIService(connector: adapter, diagnostics: ledger)
        let config = AppConfig(apiKey: "fixture-key", gatewayURL: "https://gateway.example/v1", selectedModel: "fixture-model", isConfigured: true, grammarCorrectionVerified: true, grammarCorrectionContractVersion: "fixture-contract")
        _ = try await AIOperationDiagnosticContext.$traceID.withValue(trace) {
            try await service.performResult(action: .fixGrammar, on: "The cat are sleepy. The dog are happy.", config: config)
        }
        let record = try XCTUnwrap(ledger.record(traceID: trace))
        let requests = try XCTUnwrap(record.requests)
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.responseText?.text, request.userMessage?.text.replacingOccurrences(of: " are ", with: " is "))
            let stages = Set(record.events.filter { $0.requestID == request.id }.map(\.stage))
            XCTAssertTrue(stages.isSuperset(of: [.promptConstruction, .transport, .decoding, .validation]))
        }
        let completed = await runtime.completedInputs
        XCTAssertTrue(completed.first?.contains("dog") == true, "Second chunk must complete first")
    }

    func testHostDiagnosticCancellationDuringAndBetweenProbesIsAWarning() async throws {
        for cancelBetweenProbes in [false, true] {
            let ledger = AIOperationDiagnostics(defaults: defaults)
            ledger.removeAll()
            let connector = DiagnosticCancellationConnector()
            let manager: NetworkManager = cancelBetweenProbes
                ? DiagnosticCancelledAfterDiscoveryManager(connector: connector, diagnostics: ledger)
                : NetworkManager(connector: connector, diagnostics: ledger)
            let report = await Task {
                await manager.runGatewayDiagnostics(gatewayURL: "https://gateway.example/v1", apiKey: "fixture-key", preferredModel: "fixture-model")
            }.value
            XCTAssertEqual(report.checks.count, cancelBetweenProbes ? 1 : 2)
            XCTAssertEqual(report.checks.first?.status, .passed)
            let record = try XCTUnwrap(ledger.records().first { $0.operation == .gatewayDiagnostics })
            XCTAssertEqual(record.outcome, .cancelled)
            XCTAssertEqual(record.failure, .cancelled)
            XCTAssertTrue(AIOperationDiagnosticFilter.warnings.includes(record))
            XCTAssertFalse(AIOperationDiagnosticFilter.errors.includes(record))
        }
    }

    func testRejectedTranslationRetriesKeepAttemptAndRequestCorrelation() async throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let trace = ledger.begin(operation: .translate, origin: .keyboardManualAction)
        let adapter = UniversalAIConnectorAdapter(factory: { _ in DiagnosticRuntime(completion: .stop) }, diagnostics: ledger)
        let service = KeyboardAIService(connector: adapter, diagnostics: ledger)
        let config = AppConfig(apiKey: "fixture-key", gatewayURL: "https://gateway.example/v1", selectedModel: "fixture-model", isConfigured: true, grammarCorrectionVerified: true, grammarCorrectionContractVersion: "fixture-contract")
        do {
            _ = try await AIOperationDiagnosticContext.$traceID.withValue(trace) {
                try await service.performResult(action: .translate(.arabic), on: "Good morning, I hope you are well today.", config: config)
            }
            XCTFail("Expected two rejected translations")
        } catch let error as KeyboardAIError {
            XCTAssertEqual(error, .unreliableTranslation(.arabic))
        }
        let record = try XCTUnwrap(ledger.record(traceID: trace))
        let requests = try XCTUnwrap(record.requests)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(Set(requests.map(\.id)).count, 2)
        for (offset, request) in requests.enumerated() {
            let events = record.events.filter { $0.requestID == request.id }
            XCTAssertTrue(Set(events.map(\.stage)).isSuperset(of: [.promptConstruction, .transport, .validation]))
            let validation = events.filter { $0.stage == .validation && $0.failure != nil }
            XCTAssertFalse(validation.isEmpty)
            XCTAssertTrue(validation.allSatisfy { $0.attempt == offset + 1 })
        }
        let exhausted = try XCTUnwrap(record.events.last { $0.failure == .retryFailed })
        XCTAssertEqual(exhausted.attempt, 2)
        XCTAssertEqual(exhausted.requestID, requests.last?.id)
    }

    @MainActor
    func testCaptureSwitchAndShareConfirmationRespectCancellationAndRevocation() {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let vm = AIOperationDiagnosticsViewModel(diagnostics: ledger)
        vm.setTextCaptureEnabled(true)
        XCTAssertNotNil(vm.captureExpiresAt)
        let trace = ledger.begin(operation: .rewrite, origin: .keyboardManualAction, sourceText: "consented fixture")
        vm.prepareTextPreview()
        XCTAssertTrue(vm.confirmShare())
        XCTAssertTrue(vm.textPreview.contains("consented fixture"))
        vm.dismissTextPreview()
        XCTAssertFalse(vm.confirmShare(), "Cancel must discard the pending share")
        vm.prepareTextPreview()
        vm.setTextCaptureEnabled(false)
        XCTAssertNil(vm.captureExpiresAt)
        XCTAssertFalse(vm.confirmShare(), "Disabling capture invalidates pending sensitive sharing")
        XCTAssertNil(ledger.record(traceID: trace)?.sourceText)
        vm.prepareTextPreview()
        XCTAssertTrue(vm.confirmShare())
        XCTAssertFalse(vm.textPreview.contains("consented fixture"))
    }

    @MainActor
    func testReportTabsAndCheckboxesRestrictBothExportsToVisibleSelection() {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        ledger.startTextCapture()
        let error = ledger.begin(operation: .fixGrammar, origin: .keyboardManualAction, sourceText: "error fixture")
        ledger.complete(traceID: error, outcome: .failed, failure: .malformedResponse)
        let success = ledger.begin(operation: .rewrite, origin: .keyboardManualAction, sourceText: "success fixture")
        ledger.complete(traceID: success, outcome: .succeeded)
        let warning = ledger.begin(operation: .rewrite, origin: .keyboardManualAction, sourceText: "warning fixture")
        ledger.complete(traceID: warning, outcome: .cancelled, failure: .cancelled)
        let vm = AIOperationDiagnosticsViewModel(diagnostics: ledger)
        vm.refresh()
        XCTAssertEqual(vm.exportTraceIDs.count, 3)
        vm.selectFilter(.errors)
        XCTAssertEqual(vm.visibleRecords.map(\.traceID), [error])
        XCTAssertTrue(vm.metadataExport.contains("trace=\(error)"))
        XCTAssertFalse(vm.metadataExport.contains("trace=\(success)"))
        vm.prepareTextPreview()
        XCTAssertTrue(vm.textPreview.contains("error fixture"))
        XCTAssertFalse(vm.textPreview.contains("success fixture"))
        vm.toggleSelection(error)
        XCTAssertTrue(vm.exportTraceIDs.isEmpty)
        XCTAssertTrue(vm.metadataExport.contains("records=0"))
        XCTAssertTrue(vm.textPreview.isEmpty)
        vm.selectFilter(.warnings)
        XCTAssertEqual(vm.visibleRecords.map(\.traceID), [warning])
        vm.selectFilter(.all)
        vm.toggleSelection(success)
        XCTAssertEqual(vm.exportTraceIDs, [error, warning])
        vm.prepareTextPreview()
        XCTAssertFalse(vm.textPreview.contains("success fixture"))
    }

    @MainActor
    func testManualSelectionDoesNotSilentlyAddNewReportsOnRefresh() {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let first = ledger.begin(operation: .rewrite, origin: .keyboardManualAction)
        let vm = AIOperationDiagnosticsViewModel(diagnostics: ledger)
        vm.refresh()
        vm.toggleSelection(first)
        vm.toggleSelection(first)
        _ = ledger.begin(operation: .rewrite, origin: .keyboardManualAction)
        vm.refresh()
        XCTAssertEqual(vm.exportTraceIDs, [first])
        vm.selectFilter(.all)
        XCTAssertEqual(vm.exportTraceIDs.count, 2)
        ledger.removeAll()
        vm.refresh()
        XCTAssertTrue(vm.exportTraceIDs.isEmpty)
    }

    @MainActor
    func testWarningsIncludeRecoveredFailuresButExcludeCleanInProgressAndSuccess() {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let recovered = ledger.begin(operation: .rewrite, origin: .keyboardManualAction)
        ledger.record(traceID: recovered, stage: .transport, failure: .transportTimeout)
        ledger.complete(traceID: recovered, outcome: .succeeded)
        _ = ledger.begin(operation: .rewrite, origin: .keyboardManualAction)
        let clean = ledger.begin(operation: .rewrite, origin: .keyboardManualAction)
        ledger.complete(traceID: clean, outcome: .succeeded)
        let vm = AIOperationDiagnosticsViewModel(diagnostics: ledger)
        vm.selectFilter(.warnings)
        XCTAssertEqual(vm.visibleRecords.map(\.traceID), [recovered])
    }

    @MainActor
    func testSensitivePreviewInvalidatesAfterAnotherInstanceDeletesText() throws {
        let ledger = AIOperationDiagnostics(defaults: defaults)
        let other = AIOperationDiagnostics(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        ledger.startTextCapture()
        _ = ledger.begin(operation: .rewrite, origin: .keyboardManualAction, sourceText: "sensitive fixture")
        let vm = AIOperationDiagnosticsViewModel(diagnostics: ledger)
        vm.prepareTextPreview()
        XCTAssertTrue(vm.textPreview.contains("sensitive fixture"))
        other.stopTextCaptureAndDelete()
        vm.refresh()
        XCTAssertTrue(vm.textPreview.isEmpty)
        vm.prepareTextPreview()
        XCTAssertFalse(vm.textPreview.contains("sensitive fixture"))
    }

    @MainActor
    func testSensitivePreviewInvalidatesWhenTextRetentionExpires() {
        var now = Date(timeIntervalSince1970: 10_000)
        let ledger = AIOperationDiagnostics(defaults: defaults, now: { now })
        ledger.startTextCapture()
        _ = ledger.begin(operation: .rewrite, origin: .keyboardManualAction, sourceText: "sensitive fixture")
        let vm = AIOperationDiagnosticsViewModel(diagnostics: ledger)
        vm.prepareTextPreview()
        XCTAssertTrue(vm.textPreview.contains("sensitive fixture"))
        now = now.addingTimeInterval(AIOperationDiagnostics.textRetention + 1)
        vm.refresh()
        XCTAssertTrue(vm.textPreview.isEmpty)
        XCTAssertEqual(vm.records.count, 1)
    }

    func testHTTPStatusCategoriesDiscardExactStatusCode() {
        XCTAssertEqual(AIOperationDiagnosticHTTPStatusCategory(statusCode: 204), .success)
        XCTAssertEqual(AIOperationDiagnosticHTTPStatusCategory(statusCode: 429), .clientError)
        XCTAssertEqual(AIOperationDiagnosticHTTPStatusCategory(statusCode: 503), .serverError)
        XCTAssertEqual(AIOperationDiagnosticHTTPStatusCategory(statusCode: 700), .unknown)
    }
}

private final class DiagnosticRuntime: UniversalAIConnectorRuntime, @unchecked Sendable {
    let completion: UniversalAiCompletionReason
    init(completion: UniversalAiCompletionReason) { self.completion = completion }
    func close() {}
    func listModels(providerId: UniversalAiProviderId) async throws -> UniversalAiModelListResult { .unsupported(providerId: providerId) }
    func respond(to request: UniversalAiRequest) async throws -> UniversalAiResponse {
        UniversalAiResponse(contractVersion: UniversalAiRequest.currentContractVersion, id: .init(rawValue: "fixture-response"), target: request.target,
            outputs: [.init(id: .init(rawValue: "fixture-output"), index: 0, kind: .text, text: "Synthetic response")], completionReason: completion)
    }
}

/// The first request waits for its sibling before failing; cancellation must pass through the
/// actual service task group and adapter. In success mode the second chunk finishes first.
private actor DiagnosticChunkRuntime: UniversalAIConnectorRuntime {
    let failsFirst: Bool
    private var started = 0
    private(set) var completedInputs: [String] = []
    init(failsFirst: Bool) { self.failsFirst = failsFirst }
    nonisolated func close() {}
    func listModels(providerId: UniversalAiProviderId) async throws -> UniversalAiModelListResult { .unsupported(providerId: providerId) }
    func respond(to request: UniversalAiRequest) async throws -> UniversalAiResponse {
        started += 1
        let input = request.input.last?.content ?? ""
        if input.contains("cat") {
            while started < 2 { try await Task.sleep(nanoseconds: 1_000_000) }
            if failsFirst { throw OpenKeyboardAIConnectorError.invalidResponse }
            try await Task.sleep(nanoseconds: 30_000_000)
        } else if failsFirst {
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        completedInputs.append(input)
        return UniversalAiResponse(contractVersion: UniversalAiRequest.currentContractVersion,
            id: .init(rawValue: UUID().uuidString), target: request.target,
            outputs: [.init(id: .init(rawValue: UUID().uuidString), index: 0, kind: .text,
                            text: input.replacingOccurrences(of: " are ", with: " is "))], completionReason: .stop)
    }
}

private final class DiagnosticCancellationConnector: OpenKeyboardAIConnectorServing, @unchecked Sendable {
    func close() {}
    func listModels(profile: OpenKeyboardGatewayProfile) async throws -> [String] {
        return ["fixture-model"]
    }
    func respond(to request: OpenKeyboardAIRequest, profile: OpenKeyboardGatewayProfile) async throws -> String {
        throw CancellationError()
    }
}

/// Completes discovery while marking the manager task cancelled, exercising the loop guard
/// between probes without relying on timing in the connector deadline's child task.
private final class DiagnosticCancelledAfterDiscoveryManager: NetworkManager {
    override func fetchModels(profile: OpenKeyboardGatewayProfile) async throws -> [String] {
        withUnsafeCurrentTask { $0?.cancel() }
        return ["fixture-model"]
    }
}
