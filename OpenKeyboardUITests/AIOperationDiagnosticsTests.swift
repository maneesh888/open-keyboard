import XCTest

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

    func testHTTPStatusCategoriesDiscardExactStatusCode() {
        XCTAssertEqual(AIOperationDiagnosticHTTPStatusCategory(statusCode: 204), .success)
        XCTAssertEqual(AIOperationDiagnosticHTTPStatusCategory(statusCode: 429), .clientError)
        XCTAssertEqual(AIOperationDiagnosticHTTPStatusCategory(statusCode: 503), .serverError)
        XCTAssertEqual(AIOperationDiagnosticHTTPStatusCategory(statusCode: 700), .unknown)
    }
}
