import Foundation
import OSLog
import Combine
import MachO

/// Local, bounded diagnostic records. Text requires an explicit, expiring capture session.
/// Configuration credentials and endpoints are never passed to this ledger.
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
    case outputLimitReached = "output_limit_reached"
    case providerIncompleteResponse = "provider_incomplete_response"
    case incompleteStream = "incomplete_stream"
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

/// Bounded content, with explicit truncation rather than an implied complete reproduction.
struct AIOperationDiagnosticText: Codable, Equatable, Sendable {
    let text: String
    let truncated: Bool

    init(_ value: String) {
        var bytes = Array(value.utf8.prefix(4_096))
        while String(bytes: bytes, encoding: .utf8) == nil { bytes.removeLast() }
        text = String(decoding: bytes, as: UTF8.self)
        truncated = bytes.count < value.utf8.count
    }
}

struct AIOperationDiagnosticRequest: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let attempt: Int
    let provider: OpenKeyboardAIProvider
    let modelID: String?
    let maxOutputTokens: Int?
    let temperature: Double?
    let topP: Double?
    let timeoutMilliseconds: Int?
    let promptContractVersion: String
    var userMessage: AIOperationDiagnosticText?
    var responseText: AIOperationDiagnosticText?
    var completionReason: String?
    var outputCount: Int?
}

private struct AIOperationTextCaptureConsent: Codable {
    let id: String
    let expiresAt: Date
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
    var requestID: String? = nil
    var httpStatusCode: Int? = nil
    var connectorResponseAccepted: Bool? = nil
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

    // Optional additions keep old v1 exports readable.
    var binaryID: String? = nil
    var captureSessionID: String? = nil
    var sourceText: AIOperationDiagnosticText? = nil
    var requests: [AIOperationDiagnosticRequest]? = nil
    var requestsOmitted: Int? = nil

    var id: String { traceID }
}

enum AIOperationDiagnosticContext {
    @TaskLocal static var traceID: String?
    @TaskLocal static var attempt = 1
}

/// Bounded, expiring diagnostic ledger shared by the app and keyboard extension.
///
/// Text capture is independently consented, bounded, and never sent to OSLog. Metadata-only
/// export is the default, including for the keyboard Copy Details action.
final class AIOperationDiagnostics: @unchecked Sendable {
    static let shared = AIOperationDiagnostics()

    static let retention: TimeInterval = 7 * 24 * 60 * 60
    static let maximumRecords = 48
    static let maximumEventsPerRecord = 64
    static let maximumRequestsPerRecord = 8
    static let maximumTextRecords = 8
    static let textRetention: TimeInterval = 24 * 60 * 60
    static let captureDuration: TimeInterval = 10 * 60
    private static let consentKey = "aiOperationDiagnostics.textConsent.v1"

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
        origin: AIOperationDiagnosticOrigin,
        sourceText: String? = nil
    ) -> String {
        let timestamp = now()
        let traceID = UUID().uuidString.lowercased()
        var record = AIOperationDiagnosticRecord(
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
            record.binaryID = Self.binaryIdentifier()
            if let consent = activeConsent(at: timestamp) {
                record.captureSessionID = consent.id
                record.sourceText = sourceText.map(AIOperationDiagnosticText.init)
            }
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
        subreason: AIOperationDiagnosticSubreason? = nil,
        requestID: String? = nil,
        httpStatusCode: Int? = nil,
        connectorResponseAccepted: Bool? = nil
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
                subreason: subreason,
                requestID: requestID,
                httpStatusCode: httpStatusCode.flatMap { (100...599).contains($0) ? $0 : nil },
                connectorResponseAccepted: connectorResponseAccepted
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

    /// Text is excluded unless a separate, explicit preview/share action requests it.
    func export(traceID: String? = nil, includeText: Bool = false) -> String {
        let selected = records().filter { traceID == nil || $0.traceID == traceID }
        var lines = [
            "OpenKeyboard AI diagnostics schema=1 context_version=2",
            "Includes provider/model and request settings. Configuration credentials and endpoints are excluded.",
            includeText ? "SENSITIVE: consented phrase/response text may be included below. Review before sharing." : "Phrase and response text excluded.",
            "records=\(selected.count) metadata_retention=7d text_retention=24h"
        ]
        let dateFormat = ISO8601DateFormatter()
        for record in selected {
            lines.append("trace=\(record.traceID) operation=\(record.operation.rawValue) origin=\(record.origin.rawValue) outcome=\(record.outcome?.rawValue ?? "in_progress") failure=\(record.failure?.rawValue ?? "none") app=\(record.appVersion) build=\(record.buildVersion) binary=\(record.binaryID ?? "unknown") os=\(record.operatingSystemVersion) started_at=\(dateFormat.string(from: record.startedAt))")
            if let count = record.requestsOmitted { lines.append("  request_records_omitted=\(count)") }
            if includeText, let source = record.sourceText { lines.append(Self.textLine("source_text", source)) }
            for request in record.requests ?? [] {
                lines.append("  request=\(request.id) attempt=\(request.attempt) provider=\(request.provider.rawValue) model=\(request.modelID ?? "not_recorded") contract=\(request.promptContractVersion) max_output_tokens=\(request.maxOutputTokens.map(String.init) ?? "default") temperature=\(request.temperature.map(String.init(describing:)) ?? "provider_default") top_p=\(request.topP.map(String.init(describing:)) ?? "provider_default") timeout_ms=\(request.timeoutMilliseconds.map(String.init) ?? "unknown") completion=\(request.completionReason ?? "unavailable") outputs=\(request.outputCount.map(String.init) ?? "unavailable")")
                if includeText {
                    if let input = request.userMessage { lines.append(Self.textLine("user_message", input)) }
                    if let output = request.responseText { lines.append(Self.textLine("response_text", output)) }
                }
            }
            for event in record.events {
                var line = "  stage=\(event.stage.rawValue) attempt=\(event.attempt) elapsed_ms=\(event.elapsedMilliseconds)"
                if let value = event.requestID { line += " request=\(value)" }
                if let value = event.durationMilliseconds { line += " duration_ms=\(value)" }
                if let value = event.httpStatusCategory { line += " http=\(value.rawValue)" }
                if let value = event.httpStatusCode { line += " http_status=\(value)" }
                if let value = event.connectorResponseAccepted { line += " connector_response_accepted=\(value)" }
                if let value = event.requestBytes { line += " request_bytes=\(value)" }
                if let value = event.responseBytes { line += " response_bytes=\(value)" }
                if let value = event.failure { line += " failure=\(value.rawValue)" }
                if let value = event.subreason { line += " subreason=\(value.rawValue)" }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func textLine(_ name: String, _ value: AIOperationDiagnosticText) -> String {
        // JSON quoting keeps untrusted text from forging additional diagnostic lines.
        let encoded = (try? JSONEncoder().encode(value.text)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        return "  \(name)_truncated=\(value.truncated) \(name)=\(encoded)"
    }

    var textCaptureExpiresAt: Date? {
        withExclusiveStorageAccess { activeConsent(at: now())?.expiresAt } ?? nil
    }

    /// Called only after the host app's explicit capture confirmation.
    func startTextCapture() {
        _ = withExclusiveStorageAccess {
            let consent = AIOperationTextCaptureConsent(id: UUID().uuidString, expiresAt: now().addingTimeInterval(Self.captureDuration))
            guard let data = try? JSONEncoder().encode(consent) else { return }
            defaults?.set(data, forKey: Self.consentKey)
            defaults?.synchronize()
        }
    }

    func stopTextCaptureAndDelete() {
        _ = withExclusiveStorageAccess {
            defaults?.removeObject(forKey: Self.consentKey)
            write(readRecords().map(Self.withoutText))
        }
    }

    @discardableResult
    func beginRequest(traceID: String, provider: OpenKeyboardAIProvider, request: OpenKeyboardAIRequest? = nil) -> String? {
        withExclusiveStorageAccess {
            let timestamp = now()
            var records = prunedRecords(from: readRecords(), at: timestamp)
            guard let index = records.firstIndex(where: { $0.traceID == traceID }), records[index].outcome == nil else { return nil }
            guard (records[index].requests?.count ?? 0) < Self.maximumRequestsPerRecord else {
                records[index].requestsOmitted = (records[index].requestsOmitted ?? 0) + 1
                write(records)
                return nil
            }
            let capture = activeConsent(at: timestamp)?.id == records[index].captureSessionID && records[index].captureSessionID != nil
            let id = UUID().uuidString.lowercased()
            let providerUsesDefaults = provider == .openAI || provider == .anthropic
            let context = AIOperationDiagnosticRequest(
                id: id, attempt: AIOperationDiagnosticContext.attempt, provider: provider,
                modelID: request.flatMap { Self.safeModelID($0.modelID) },
                maxOutputTokens: request?.maxOutputTokens,
                temperature: providerUsesDefaults ? nil : request?.temperature,
                topP: providerUsesDefaults ? nil : request?.topP,
                timeoutMilliseconds: request.map { Int(min(86_400, max(0, $0.timeoutInterval)) * 1_000) },
                promptContractVersion: KeyboardGatewayActionContract.contractVersion,
                userMessage: capture ? request?.messages.last(where: { $0.role == .user }).map { AIOperationDiagnosticText($0.content) } : nil,
                responseText: nil, completionReason: nil, outputCount: nil
            )
            records[index].requests = (records[index].requests ?? []) + [context]
            write(records)
            return id
        } ?? nil
    }

    func recordResponse(traceID: String, requestID: String, text: String?, completionReason: String, outputCount: Int) {
        _ = withExclusiveStorageAccess {
            let timestamp = now()
            var records = prunedRecords(from: readRecords(), at: timestamp)
            guard let index = records.firstIndex(where: { $0.traceID == traceID }), records[index].outcome == nil,
                  let requestIndex = records[index].requests?.firstIndex(where: { $0.id == requestID }) else { return }
            let knownReasons = ["stop", "max_output_tokens", "content_filter", "tool_call", "unknown"]
            records[index].requests?[requestIndex].completionReason = knownReasons.contains(completionReason) ? completionReason : "other"
            records[index].requests?[requestIndex].outputCount = outputCount
            if let sessionID = records[index].captureSessionID, activeConsent(at: timestamp)?.id == sessionID {
                records[index].requests?[requestIndex].responseText = text.map(AIOperationDiagnosticText.init)
            }
            write(records)
        }
    }

    private func activeConsent(at date: Date) -> AIOperationTextCaptureConsent? {
        defaults?.synchronize()
        guard let data = defaults?.data(forKey: Self.consentKey),
              let consent = try? JSONDecoder().decode(AIOperationTextCaptureConsent.self, from: data),
              consent.expiresAt > date else { return nil }
        return consent
    }

    private static func safeModelID(_ value: String) -> String? {
        guard value.utf8.count <= 255, value.range(of: "^[A-Za-z0-9][A-Za-z0-9._:/+-]*$", options: .regularExpression) != nil else { return nil }
        return value
    }

    private static func withoutText(_ value: AIOperationDiagnosticRecord) -> AIOperationDiagnosticRecord {
        var record = value
        record.captureSessionID = nil
        record.sourceText = nil
        if var requests = record.requests {
            for index in requests.indices { requests[index].userMessage = nil; requests[index].responseText = nil }
            record.requests = requests
        }
        return record
    }

    private static func binaryIdentifier() -> String? {
        guard let header = _dyld_get_image_header(0), header.pointee.magic == MH_MAGIC_64 else { return nil }
        var cursor = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<header.pointee.ncmds {
            let command = cursor.load(as: load_command.self)
            guard command.cmdsize >= MemoryLayout<load_command>.size else { return nil }
            if command.cmd == LC_UUID { return UUID(uuid: cursor.load(as: uuid_command.self).uuid).uuidString.lowercased() }
            cursor = cursor.advanced(by: Int(command.cmdsize))
        }
        return nil
    }

    func removeAll() {
        _ = withExclusiveStorageAccess {
            defaults?.removeObject(forKey: Self.storageKey)
            defaults?.removeObject(forKey: Self.consentKey)
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
        let retained = Array(records.filter { $0.updatedAt >= earliest }
            .sorted { $0.startedAt > $1.startedAt }.prefix(Self.maximumRecords))
        var textCount = 0
        return retained.map { record in
            guard record.captureSessionID != nil else { return record }
            textCount += 1
            guard textCount <= Self.maximumTextRecords, record.startedAt >= timestamp.addingTimeInterval(-Self.textRetention) else {
                return Self.withoutText(record)
            }
            return record
        }
    }

    private func write(_ records: [AIOperationDiagnosticRecord]) {
        guard let defaults,
              let data = try? JSONEncoder().encode(prunedRecords(from: records, at: now())) else { return }
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


/// Presentation state stays outside the view; the service owns App Group storage and consent.
@MainActor
final class AIOperationDiagnosticsViewModel: ObservableObject {
    @Published private(set) var records: [AIOperationDiagnosticRecord] = []
    @Published private(set) var captureExpiresAt: Date?
    @Published private(set) var metadataExport = ""
    @Published private(set) var textPreview = ""
    private let diagnostics: AIOperationDiagnostics

    init(diagnostics: AIOperationDiagnostics = .shared) { self.diagnostics = diagnostics }
    func refresh() {
        records = diagnostics.records()
        captureExpiresAt = diagnostics.textCaptureExpiresAt
        metadataExport = diagnostics.export()
    }
    func startCapture() { diagnostics.startTextCapture(); refresh() }
    func stopAndDeleteText() { diagnostics.stopTextCaptureAndDelete(); textPreview = ""; refresh() }
    func clear() { diagnostics.removeAll(); textPreview = ""; refresh() }
    func prepareTextPreview() { textPreview = diagnostics.export(includeText: true) }
    func dismissTextPreview() { textPreview = "" }
}
