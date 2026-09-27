import Foundation
import OSLog

/// A privacy-safe, shareable record of one production AI operation.
///
/// The App Group ledger intentionally stores only typed lifecycle metadata. It never accepts
/// request/response text, credentials, provider URLs, or model identifiers as inputs.
enum AIOperationDiagnosticStage: String, Codable, CaseIterable, Sendable {
    case contextCapture = "context_capture"
    case promptConstruction = "prompt_construction"
    case transport = "transport"
    case decoding = "decoding"
    case validation = "validation"
    case retry = "retry"
    case cancellation = "cancellation"
    case staleResultSuppression = "stale_result_suppression"
    case finalOutcome = "final_outcome"
}

enum AIOperationDiagnosticFailure: String, Codable, CaseIterable, Sendable {
    case gatewayNonresponse = "gateway_nonresponse"
    case transportTimeout = "transport_timeout"
    case malformedResponse = "malformed_response"
    case validationRejected = "validation_rejected"
    case retryFailed = "retry_failed"
    case cancelled = "cancelled"
    case staleResultSuppressed = "stale_result_suppressed"
    case gatewayRejected = "gateway_rejected"
    case transportFailure = "transport_failure"
}

/// A closed, support-facing detail for a malformed connector response.
///
/// These values intentionally identify only adapter-controlled conditions or documented connector
/// error codes. They never retain provider messages, payload values, response IDs, or any other
/// arbitrary strings.
enum AIOperationDiagnosticSubreason: String, Codable, CaseIterable, Sendable {
    case malformedProviderResponse = "malformed_provider_response"
    case malformedProviderStream = "malformed_provider_stream"
    case invalidStructuredProviderResponse = "invalid_structured_provider_response"
    case connectorContractValidationFailure = "connector_contract_validation_failure"
    case targetMismatch = "target_mismatch"
    case unexpectedCompletionReason = "unexpected_completion_reason"
    case invalidOutputCount = "invalid_output_count"
    case unexpectedOutputIndex = "unexpected_output_index"
    case nonTextOutput = "non_text_output"
    case unexpectedStructuredOutput = "unexpected_structured_output"
    case missingOrEmptyText = "missing_or_empty_text"
}

enum AIOperationDiagnosticOutcome: String, Codable, Sendable {
    case succeeded
    case failed
    case cancelled
    case staleResultSuppressed = "stale_result_suppressed"
}

enum AIOperationDiagnosticHTTPStatusCategory: String, Codable, Sendable {
    case informational = "1xx"
    case success = "2xx"
    case redirect = "3xx"
    case clientError = "4xx"
    case serverError = "5xx"
    case unknown

    init(statusCode: Int?) {
        guard let statusCode else {
            self = .unknown
            return
        }
        switch statusCode {
        case 100..<200: self = .informational
        case 200..<300: self = .success
        case 300..<400: self = .redirect
        case 400..<500: self = .clientError
        case 500..<600: self = .serverError
        default: self = .unknown
        }
    }
}

enum AIOperationDiagnosticOperation: String, Codable, Sendable {
    case improve
    case fixGrammar = "fix_grammar"
    case rewrite
    case summarize
    case translate
    case gatewayConnectionCheck = "gateway_connection_check"
    case gatewayDiagnostics = "gateway_diagnostics"
    case modelDiscovery = "model_discovery"
}

enum AIOperationDiagnosticOrigin: String, Codable, Sendable {
    case keyboardManualAction = "keyboard_manual_action"
    case keyboardActionPanel = "keyboard_action_panel"
    case keyboardAutomaticAnalysis = "keyboard_automatic_analysis"
    case hostAppGatewayCheck = "host_app_gateway_check"
    case hostAppDiagnostics = "host_app_diagnostics"
    case hostAppModelDiscovery = "host_app_model_discovery"
}

struct AIOperationDiagnosticEvent: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let stage: AIOperationDiagnosticStage
    let attempt: Int
    let elapsedMilliseconds: Int
    let durationMilliseconds: Int?
    let httpStatusCategory: AIOperationDiagnosticHTTPStatusCategory?
    let requestBytes: Int?
    let responseBytes: Int?
    let failure: AIOperationDiagnosticFailure?
    /// An additive optional field. Records written before this was introduced decode as `nil`, so
    /// the existing v1 App Group ledger remains backward compatible without migration.
    let subreason: AIOperationDiagnosticSubreason?
}

struct AIOperationDiagnosticRecord: Codable, Equatable, Sendable, Identifiable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let traceID: String
    let operation: AIOperationDiagnosticOperation
    let origin: AIOperationDiagnosticOrigin
    let startedAt: Date
    var updatedAt: Date
    let appVersion: String
    let buildVersion: String
    let operatingSystemVersion: String
    var events: [AIOperationDiagnosticEvent]
    var outcome: AIOperationDiagnosticOutcome?
    var failure: AIOperationDiagnosticFailure?

    var id: String { traceID }
}

enum AIOperationDiagnosticContext {
    @TaskLocal static var traceID: String?
    @TaskLocal static var attempt = 1
}

/// Bounded, expiring diagnostic ledger shared by the app and keyboard extension.
///
/// The storage format is deliberately separate from gateway configuration. The record type has no
/// free-form text fields, so callers cannot accidentally persist text typed into the keyboard,
/// generated output, API keys, authorization headers, private endpoints, or model IDs.
final class AIOperationDiagnostics: @unchecked Sendable {
    static let shared = AIOperationDiagnostics()

    static let retention: TimeInterval = 7 * 24 * 60 * 60
    static let maximumRecords = 48
    static let maximumEventsPerRecord = 64

    private static let storageKey = "aiOperationDiagnostics.v1"
    // Both the host app and keyboard extension update the App Group defaults. Coordinate every
    // read-modify-write operation through this shared file URL so independent processes cannot
    // overwrite each other's diagnostic events.
    private static let storageLockFileName = "ai-operation-diagnostics.lock"
    private static let logger = Logger(
        subsystem: "com.maneesh.openkeyboard",
        category: "ai-operation-diagnostics"
    )
    private static let signposter = OSSignposter(logger: logger)

    private let defaults: UserDefaults?
    private let now: () -> Date
    private let storageLockURL: URL?
    private let lock = NSLock()
    private var activeSignposts: [String: OSSignpostIntervalState] = [:]

    init(
        defaults: UserDefaults? = AppConfig.sharedDefaults(),
        now: @escaping () -> Date = Date.init,
        storageLockURL: URL? = nil
    ) {
        self.defaults = defaults
        self.now = now
        self.storageLockURL = storageLockURL ?? Self.appGroupStorageLockURL()
    }

    @discardableResult
    func begin(
        operation: AIOperationDiagnosticOperation,
        origin: AIOperationDiagnosticOrigin
    ) -> String {
        let timestamp = now()
        let traceID = UUID().uuidString.lowercased()
        let record = AIOperationDiagnosticRecord(
            schemaVersion: AIOperationDiagnosticRecord.schemaVersion,
            traceID: traceID,
            operation: operation,
            origin: origin,
            startedAt: timestamp,
            updatedAt: timestamp,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            events: [],
            outcome: nil,
            failure: nil
        )

        let didPersist = withExclusiveStorageAccess {
            var records = prunedRecords(from: readRecords(), at: timestamp)
            records.append(record)
            write(records)
            let signpostID = Self.signposter.makeSignpostID()
            activeSignposts[traceID] = Self.signposter.beginInterval("AI operation", id: signpostID)
            return true
        } ?? false

        guard didPersist else {
            Self.logger.error("AI diagnostic ledger could not start an operation")
            return traceID
        }

        Self.logger.info("AI diagnostic started trace=\(traceID, privacy: .public) operation=\(operation.rawValue, privacy: .public)")
        return traceID
    }

    func record(
        traceID: String,
        stage: AIOperationDiagnosticStage,
        attempt: Int = AIOperationDiagnosticContext.attempt,
        durationMilliseconds: Int? = nil,
        httpStatusCategory: AIOperationDiagnosticHTTPStatusCategory? = nil,
        requestBytes: Int? = nil,
        responseBytes: Int? = nil,
        failure: AIOperationDiagnosticFailure? = nil,
        subreason: AIOperationDiagnosticSubreason? = nil
    ) {
        let timestamp = now()
        let didRecord = withExclusiveStorageAccess {
            var records = prunedRecords(from: readRecords(), at: timestamp)
            guard let index = records.firstIndex(where: { $0.traceID == traceID }),
                  records[index].outcome == nil else {
                write(records)
                return false
            }

            let elapsedMilliseconds = max(
                0,
                Int(timestamp.timeIntervalSince(records[index].startedAt) * 1_000)
            )
            records[index].events.append(AIOperationDiagnosticEvent(
                id: UUID(),
                stage: stage,
                attempt: max(1, attempt),
                elapsedMilliseconds: elapsedMilliseconds,
                durationMilliseconds: durationMilliseconds.map { max(0, $0) },
                httpStatusCategory: httpStatusCategory,
                requestBytes: requestBytes.map { max(0, $0) },
                responseBytes: responseBytes.map { max(0, $0) },
                failure: failure,
                subreason: subreason
            ))
            records[index].events = Array(records[index].events.suffix(Self.maximumEventsPerRecord))
            records[index].updatedAt = timestamp
            write(records)
            return true
        } ?? false

        if didRecord {
            Self.logger.debug("AI diagnostic trace=\(traceID, privacy: .public) stage=\(stage.rawValue, privacy: .public)")
        }
    }

    func complete(
        traceID: String,
        outcome: AIOperationDiagnosticOutcome,
        failure: AIOperationDiagnosticFailure? = nil,
        attempt: Int = AIOperationDiagnosticContext.attempt
    ) {
        let timestamp = now()
        var signpostState: OSSignpostIntervalState?
        let didComplete = withExclusiveStorageAccess {
            var records = prunedRecords(from: readRecords(), at: timestamp)
            guard let index = records.firstIndex(where: { $0.traceID == traceID }),
                  records[index].outcome == nil else {
                write(records)
                return false
            }

            let resolvedFailure = Self.resolvedTerminalFailure(
                requested: failure,
                outcome: outcome,
                events: records[index].events
            )

            let elapsedMilliseconds = max(
                0,
                Int(timestamp.timeIntervalSince(records[index].startedAt) * 1_000)
            )
            records[index].events.append(AIOperationDiagnosticEvent(
                id: UUID(),
                stage: .finalOutcome,
                attempt: max(1, attempt),
                elapsedMilliseconds: elapsedMilliseconds,
                durationMilliseconds: nil,
                httpStatusCategory: nil,
                requestBytes: nil,
                responseBytes: nil,
                failure: resolvedFailure,
                subreason: nil
            ))
            records[index].events = Array(records[index].events.suffix(Self.maximumEventsPerRecord))
            records[index].updatedAt = timestamp
            records[index].outcome = outcome
            records[index].failure = resolvedFailure
            write(records)
            signpostState = activeSignposts.removeValue(forKey: traceID)
            return true
        } ?? false

        guard didComplete else { return }

        if let signpostState {
            Self.signposter.endInterval("AI operation", signpostState)
        }
        Self.logger.info("AI diagnostic finished trace=\(traceID, privacy: .public) outcome=\(outcome.rawValue, privacy: .public)")
    }

    func records() -> [AIOperationDiagnosticRecord] {
        let timestamp = now()
        return withExclusiveStorageAccess {
            let records = prunedRecords(from: readRecords(), at: timestamp)
            write(records)
            return records.sorted { $0.updatedAt > $1.updatedAt }
        } ?? []
    }

    func record(traceID: String) -> AIOperationDiagnosticRecord? {
        records().first(where: { $0.traceID == traceID })
    }

    /// A redacted text export suitable for a support ticket or the keyboard's Copy Details action.
    func export(traceID: String? = nil) -> String {
        let selected = traceID.flatMap { record(traceID: $0) }.map { [$0] } ?? records()
        var lines = [
            "OpenKeyboard AI diagnostics schema=1",
            "Privacy boundary: no typed text, generated text, API keys, authorization headers, gateway endpoints, or model identifiers are included.",
            "records=\(selected.count) retention=7d maxRecords=\(Self.maximumRecords)"
        ]
        for record in selected {
            lines.append(
                "trace=\(record.traceID) operation=\(record.operation.rawValue) origin=\(record.origin.rawValue) outcome=\(record.outcome?.rawValue ?? "in_progress") failure=\(record.failure?.rawValue ?? "none") app=\(record.appVersion) build=\(record.buildVersion) os=\(record.operatingSystemVersion)"
            )
            for event in record.events {
                var eventLine = "  stage=\(event.stage.rawValue) attempt=\(event.attempt) elapsed_ms=\(event.elapsedMilliseconds)"
                if let durationMilliseconds = event.durationMilliseconds {
                    eventLine += " duration_ms=\(durationMilliseconds)"
                }
                if let httpStatusCategory = event.httpStatusCategory {
                    eventLine += " http=\(httpStatusCategory.rawValue)"
                }
                if let requestBytes = event.requestBytes {
                    eventLine += " request_bytes=\(requestBytes)"
                }
                if let responseBytes = event.responseBytes {
                    eventLine += " response_bytes=\(responseBytes)"
                }
                if let failure = event.failure {
                    eventLine += " failure=\(failure.rawValue)"
                }
                if let subreason = event.subreason {
                    eventLine += " subreason=\(subreason.rawValue)"
                }
                lines.append(eventLine)
            }
        }
        return lines.joined(separator: "\n")
    }

    func removeAll() {
        _ = withExclusiveStorageAccess {
            defaults?.removeObject(forKey: Self.storageKey)
            defaults?.synchronize()
            activeSignposts.removeAll()
        }
    }

    private func readRecords() -> [AIOperationDiagnosticRecord] {
        defaults?.synchronize()
        guard let data = defaults?.data(forKey: Self.storageKey),
              let records = try? JSONDecoder().decode([AIOperationDiagnosticRecord].self, from: data) else {
            return []
        }
        return records.filter { $0.schemaVersion == AIOperationDiagnosticRecord.schemaVersion }
    }

    private func prunedRecords(
        from records: [AIOperationDiagnosticRecord],
        at timestamp: Date
    ) -> [AIOperationDiagnosticRecord] {
        let earliest = timestamp.addingTimeInterval(-Self.retention)
        return Array(
            records
                .filter { $0.updatedAt >= earliest }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(Self.maximumRecords)
        )
    }

    private func write(_ records: [AIOperationDiagnosticRecord]) {
        guard let defaults,
              let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.storageKey)
        defaults.synchronize()
    }

    private static func appGroupStorageLockURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier)?
            .appendingPathComponent(storageLockFileName, isDirectory: false)
    }

    /// The file itself is only a coordination token; the diagnostic ledger remains in the existing
    /// App Group defaults key. A writer coordination block is synchronous and serializes writers
    /// in both the host app and keyboard-extension processes before each read-modify-write cycle.
    private func withExclusiveStorageAccess<Result>(_ operation: () -> Result) -> Result? {
        lock.lock()
        defer { lock.unlock() }

        guard let storageLockURL else {
            return operation()
        }

        var result: Result?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: storageLockURL,
            options: [],
            error: &coordinationError
        ) { _ in
            result = operation()
        }

        if let coordinationError {
            Self.logger.error("AI diagnostic ledger coordination failed code=\(coordinationError.code, privacy: .public)")
        }
        return result
    }

    /// A view-model terminal error may be deliberately broad after a lower layer has already
    /// classified the cause. Keep that support-facing cause when terminal completion supplies no
    /// narrower category. A genuine output validation rejection already records the same typed
    /// category at the validation stage, so it remains unchanged.
    private static func resolvedTerminalFailure(
        requested: AIOperationDiagnosticFailure?,
        outcome: AIOperationDiagnosticOutcome,
        events: [AIOperationDiagnosticEvent]
    ) -> AIOperationDiagnosticFailure? {
        guard outcome == .failed,
              requested == nil || requested == .validationRejected,
              let recordedFailure = events.reversed().compactMap(\.failure).first else {
            return requested
        }
        return recordedFailure
    }
}
