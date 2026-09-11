//
//  AppConfig.swift
//  OpenKeyboard
//
//  Configuration model
//

import Foundation
import NaturalLanguage
import Security

enum OpenKeyboardAIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAI = "openai"
    case anthropic = "anthropic"
    case openRouter = "openrouter"
    case openAICompatible = "openai-compatible"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .openRouter: "OpenRouter"
        case .openAICompatible: "OpenAI-compatible LLM Gateway"
        }
    }

    var defaultBaseURL: URL? {
        URL(string: defaultBaseURLString)
    }

    var defaultBaseURLString: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .openAICompatible: "https://"
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
private final class KeyboardUITestConfigProcessAuthorization: @unchecked Sendable {
    private struct Grant {
        let fingerprint: String
        let sessionID: String
        let expiresAt: TimeInterval
    }

    private let lock = NSLock()
    private var grant: Grant?

    func authorize(
        fingerprint: String,
        sessionID: String,
        expiresAt: TimeInterval
    ) {
        lock.lock()
        defer { lock.unlock() }
        grant = Grant(
            fingerprint: fingerprint,
            sessionID: sessionID,
            expiresAt: expiresAt
        )
    }

    func isAuthorized(
        fingerprint: String,
        sessionID: String,
        now: TimeInterval
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let grant,
              grant.fingerprint == fingerprint,
              grant.sessionID == sessionID,
              now <= grant.expiresAt else {
            return false
        }
        return true
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        grant = nil
    }
}
#endif

enum SettingsDocumentationLink {
    static let url = URL(string: "https://myadidi.com/projects/open-keyboard-llm-gateway/")!
}

enum AppConfigSecureStoreReadResult: Equatable {
    case found(Data)
    case notFound
    case unavailable
}

enum AppConfigSecureStoreCreateResult: Equatable {
    case created
    case alreadyExists
    case unavailable
}

enum AppConfigSecureStoreStringReadResult: Equatable {
    case found(String)
    case notFound
    case unavailable
}

struct AppConfigSecureClearIntent: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let legacySecretReferences: [String]
    let clearsUnversionedLegacyKey: Bool

    init(
        legacySecretReferences: [String],
        clearsUnversionedLegacyKey: Bool = true
    ) {
        schemaVersion = Self.schemaVersion
        self.legacySecretReferences = Array(Set(legacySecretReferences.filter { !$0.isEmpty })).sorted()
        self.clearsUnversionedLegacyKey = clearsUnversionedLegacyKey
    }

    var isValid: Bool {
        schemaVersion == Self.schemaVersion
            && clearsUnversionedLegacyKey
            && legacySecretReferences.allSatisfy { !$0.isEmpty }
    }
}

enum AppConfigSecureStoreClearIntentReadResult: Equatable {
    case found(AppConfigSecureClearIntent)
    case notFound
    case unavailable
}

protocol AppConfigSecureStore {
    func loadProfile() -> Data?
    func loadProfileResult() -> AppConfigSecureStoreReadResult
    @discardableResult func saveProfile(_ profile: Data) -> Bool
    func createProfileIfAbsent(_ profile: Data) -> AppConfigSecureStoreCreateResult
    @discardableResult func clearProfile() -> Bool

    // A credential-free Keychain tombstone makes an interrupted clear fail closed even when the
    // App Group domain is unavailable or reset independently.
    func loadClearIntentResult() -> AppConfigSecureStoreClearIntentReadResult
    @discardableResult func saveClearIntent(_ intent: AppConfigSecureClearIntent) -> Bool
    @discardableResult func clearClearIntent() -> Bool

    // Migration-only accessors for profiles saved by earlier releases.
    func loadLegacyAPIKey() -> String?
    func loadLegacyAPIKey(reference: String) -> String?
    func loadLegacyAPIKeyResult() -> AppConfigSecureStoreStringReadResult
    func loadLegacyAPIKeyResult(reference: String) -> AppConfigSecureStoreStringReadResult
    @discardableResult func saveLegacyAPIKey(_ apiKey: String) -> Bool
    @discardableResult func clearLegacyAPIKey() -> Bool
    @discardableResult func clearLegacyAPIKey(reference: String) -> Bool
}

extension AppConfigSecureStore {
    func loadProfileResult() -> AppConfigSecureStoreReadResult {
        loadProfile().map(AppConfigSecureStoreReadResult.found) ?? .notFound
    }

    func createProfileIfAbsent(_ profile: Data) -> AppConfigSecureStoreCreateResult {
        switch loadProfileResult() {
        case .found:
            return .alreadyExists
        case .unavailable:
            return .unavailable
        case .notFound:
            return saveProfile(profile) ? .created : .unavailable
        }
    }

    func loadLegacyAPIKeyResult() -> AppConfigSecureStoreStringReadResult {
        loadLegacyAPIKey().map(AppConfigSecureStoreStringReadResult.found) ?? .notFound
    }

    func loadLegacyAPIKeyResult(reference: String) -> AppConfigSecureStoreStringReadResult {
        loadLegacyAPIKey(reference: reference)
            .map(AppConfigSecureStoreStringReadResult.found) ?? .notFound
    }
}

final class KeychainAppConfigSecureStore: AppConfigSecureStore {
    static let sharedAccessGroupSuffix = "com.maneesh.openkeyboard.shared"

    private let service = "com.maneesh.openkeyboard.gateway"
    private let profileAccount = "gateway-profile-v2"
    private let clearIntentAccount = "gateway-profile-clear-intent-v1"
    private let legacyAPIKeyAccount = "gateway-api-key"
    private let accessGroup: String?

    init(accessGroup: String? = KeychainAppConfigSecureStore.defaultSharedAccessGroup()) {
        self.accessGroup = accessGroup
    }

    func loadProfile() -> Data? {
        guard case .found(let data) = loadProfileResult() else { return nil }
        return data
    }

    func loadProfileResult() -> AppConfigSecureStoreReadResult {
        loadDataResult(account: profileAccount)
    }

    @discardableResult
    func saveProfile(_ profile: Data) -> Bool {
        saveData(profile, account: profileAccount)
    }

    func createProfileIfAbsent(_ profile: Data) -> AppConfigSecureStoreCreateResult {
        createDataIfAbsent(profile, account: profileAccount)
    }

    @discardableResult
    func clearProfile() -> Bool {
        clearData(account: profileAccount)
    }

    func loadClearIntentResult() -> AppConfigSecureStoreClearIntentReadResult {
        switch loadDataResult(account: clearIntentAccount) {
        case .found(let data):
            guard let intent = try? JSONDecoder().decode(
                AppConfigSecureClearIntent.self,
                from: data
            ), intent.isValid else {
                return .unavailable
            }
            return .found(intent)
        case .notFound:
            return .notFound
        case .unavailable:
            return .unavailable
        }
    }

    @discardableResult
    func saveClearIntent(_ intent: AppConfigSecureClearIntent) -> Bool {
        guard let data = try? JSONEncoder().encode(intent) else { return false }
        return saveData(data, account: clearIntentAccount)
    }

    @discardableResult
    func clearClearIntent() -> Bool {
        clearData(account: clearIntentAccount)
    }

    func loadLegacyAPIKey() -> String? {
        loadString(account: legacyAPIKeyAccount)
    }

    func loadLegacyAPIKey(reference: String) -> String? {
        loadString(account: versionedLegacyAccount(reference: reference))
    }

    func loadLegacyAPIKeyResult() -> AppConfigSecureStoreStringReadResult {
        loadStringResult(account: legacyAPIKeyAccount)
    }

    func loadLegacyAPIKeyResult(reference: String) -> AppConfigSecureStoreStringReadResult {
        loadStringResult(account: versionedLegacyAccount(reference: reference))
    }

    @discardableResult
    func saveLegacyAPIKey(_ apiKey: String) -> Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return clearLegacyAPIKey()
        }
        return saveData(data, account: legacyAPIKeyAccount)
    }

    @discardableResult
    func clearLegacyAPIKey() -> Bool {
        clearData(account: legacyAPIKeyAccount)
    }

    @discardableResult
    func clearLegacyAPIKey(reference: String) -> Bool {
        clearData(account: versionedLegacyAccount(reference: reference))
    }

    private func loadString(account: String) -> String? {
        guard case .found(let value) = loadStringResult(account: account) else { return nil }
        return value
    }

    private func loadStringResult(account: String) -> AppConfigSecureStoreStringReadResult {
        switch loadDataResult(account: account) {
        case .found(let data):
            guard let value = String(data: data, encoding: .utf8) else { return .unavailable }
            return .found(value)
        case .notFound:
            return .notFound
        case .unavailable:
            return .unavailable
        }
    }

    private func loadDataResult(account: String) -> AppConfigSecureStoreReadResult {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return .unavailable }
            return .found(data)
        case errSecItemNotFound:
            return .notFound
        default:
            return .unavailable
        }
    }

    private func saveData(_ data: Data, account: String) -> Bool {
        var query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }
        guard addStatus == errSecDuplicateItem else { return false }
        return SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            attributes as CFDictionary
        ) == errSecSuccess
    }

    private func createDataIfAbsent(
        _ data: Data,
        account: String
    ) -> AppConfigSecureStoreCreateResult {
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        switch SecItemAdd(query as CFDictionary, nil) {
        case errSecSuccess:
            return .created
        case errSecDuplicateItem:
            return .alreadyExists
        default:
            return .unavailable
        }
    }

    private func clearData(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func baseQueryForTesting() -> [String: Any] {
        baseQuery(account: profileAccount)
    }

    private static func defaultSharedAccessGroup() -> String? {
        guard let appIdentifierPrefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !appIdentifierPrefix.isEmpty else {
            return nil
        }
        return appIdentifierPrefix + sharedAccessGroupSuffix
    }

    private func versionedLegacyAccount(reference: String) -> String {
        "\(legacyAPIKeyAccount).profile.\(reference)"
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup, !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

private struct StoredGatewayProfile: Codable, Equatable {
    static let schemaVersion = 3

    let schemaVersion: Int
    let revision: String
    let provider: OpenKeyboardAIProvider
    let apiKey: String
    let gatewayURL: String
    let selectedModel: String
    let isConfigured: Bool
    let grammarCorrectionVerified: Bool
    let grammarCorrectionContractVersion: String
    var lastValidatedAt: TimeInterval?
    let uiTestSeedID: String?

    var config: AppConfig {
        AppConfig(
            apiKey: apiKey,
            gatewayURL: gatewayURL,
            selectedModel: selectedModel,
            isConfigured: isConfigured,
            grammarCorrectionVerified: grammarCorrectionVerified,
            grammarCorrectionContractVersion: grammarCorrectionContractVersion,
            provider: provider
        )
    }

    init(
        schemaVersion: Int,
        revision: String,
        provider: OpenKeyboardAIProvider,
        apiKey: String,
        gatewayURL: String,
        selectedModel: String,
        isConfigured: Bool,
        grammarCorrectionVerified: Bool,
        grammarCorrectionContractVersion: String,
        lastValidatedAt: TimeInterval?,
        uiTestSeedID: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.provider = provider
        self.apiKey = apiKey
        self.gatewayURL = gatewayURL
        self.selectedModel = selectedModel
        self.isConfigured = isConfigured
        self.grammarCorrectionVerified = grammarCorrectionVerified
        self.grammarCorrectionContractVersion = grammarCorrectionContractVersion
        self.lastValidatedAt = lastValidatedAt
        self.uiTestSeedID = uiTestSeedID
    }

    init(migrating profile: LegacySecureGatewayProfileV2) {
        schemaVersion = Self.schemaVersion
        revision = profile.revision
        provider = .openAICompatible
        apiKey = profile.apiKey
        gatewayURL = profile.gatewayURL
        selectedModel = profile.selectedModel
        isConfigured = profile.isConfigured
        grammarCorrectionVerified = profile.grammarCorrectionVerified
        grammarCorrectionContractVersion = profile.grammarCorrectionContractVersion
        lastValidatedAt = profile.lastValidatedAt
        uiTestSeedID = nil
    }
}

private struct LegacySecureGatewayProfileV2: Codable, Equatable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let revision: String
    let apiKey: String
    let gatewayURL: String
    let selectedModel: String
    let isConfigured: Bool
    let grammarCorrectionVerified: Bool
    let grammarCorrectionContractVersion: String
    var lastValidatedAt: TimeInterval?
}

private struct LegacyStoredGatewayProfile: Codable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let secretReference: String
    let gatewayURL: String
    let selectedModel: String
    let isConfigured: Bool
    let grammarCorrectionVerified: Bool
    let grammarCorrectionContractVersion: String
    var lastValidatedAt: TimeInterval?
}

private enum StoredGatewayProfileReadResult {
    case found(StoredGatewayProfile, format: StoredGatewayProfileFormat)
    case notFound
    case unavailable
}

private enum StoredGatewayProfileFormat: Equatable {
    case current
    case legacyV2
}

private typealias LegacyGatewayProfileCandidate = (
    config: AppConfig,
    secretReference: String?,
    lastValidatedAt: TimeInterval?
)

private enum LegacyGatewayProfileReadResult {
    case available(LegacyGatewayProfileCandidate)
    case unavailable
}

enum KeyboardTranslationValidationFailure: Equatable {
    case predominantlyWrongLanguage
    case suspiciousMixedScripts
}

struct TranslationLanguageOutputValidator {
    enum Script: Hashable {
        case latin
        case arabic
        case devanagari
        case bengali
        case telugu
        case tamil
        case malayalam
        case cyrillic
        case han
        case other
    }

    func validationFailure(
        for output: String,
        expectedScript: Script,
        expectedLanguageCodes: Set<String>
    ) -> KeyboardTranslationValidationFailure? {
        let scriptCounts = output.unicodeScalars.reduce(into: [Script: Int]()) { counts, scalar in
            guard let script = Self.script(for: scalar) else { return }
            counts[script, default: 0] += 1
        }
        let totalScriptLetters = scriptCounts.values.reduce(0, +)
        guard totalScriptLetters > 0 else { return nil }

        let expectedScriptCount = scriptCounts[expectedScript, default: 0]
        let unexpectedScriptCount = totalScriptLetters - expectedScriptCount
        let expectedScriptRatio = Double(expectedScriptCount) / Double(totalScriptLetters)
        let unexpectedScriptRatio = Double(unexpectedScriptCount) / Double(totalScriptLetters)
        if expectedScriptRatio < 0.55 { return .predominantlyWrongLanguage }
        if unexpectedScriptCount >= 4, unexpectedScriptRatio >= 0.20 { return .suspiciousMixedScripts }

        guard totalScriptLetters >= 4 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(output)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 4)
        let expectedConfidence = hypotheses
            .filter { expectedLanguageCodes.contains($0.key.rawValue) }
            .map(\.value)
            .max() ?? 0
        let dominantConfidence = hypotheses.values.max() ?? 0
        let isShortOutput = totalScriptLetters < 18
        let minimumExpectedConfidence = isShortOutput ? 0.08 : 0.12
        let minimumDominantConfidence = isShortOutput ? 0.60 : 0.55
        if expectedConfidence < minimumExpectedConfidence,
           dominantConfidence >= minimumDominantConfidence {
            return .predominantlyWrongLanguage
        }
        return nil
    }

    private static func script(for scalar: Unicode.Scalar) -> Script? {
        switch scalar.value {
        case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F, 0x1E00...0x1EFF: return .latin
        case 0x0400...0x052F: return .cyrillic
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: return .arabic
        case 0x0900...0x097F, 0xA8E0...0xA8FF: return .devanagari
        case 0x0980...0x09FF: return .bengali
        case 0x0B80...0x0BFF: return .tamil
        case 0x0C00...0x0C7F: return .telugu
        case 0x0D00...0x0D7F: return .malayalam
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2EBEF: return .han
        default: return CharacterSet.letters.contains(scalar) ? .other : nil
        }
    }
}

struct AppConfig: Codable, Equatable {
    var apiKey: String
    var gatewayURL: String
    var selectedModel: String
    var isConfigured: Bool
    var grammarCorrectionVerified: Bool
    var grammarCorrectionContractVersion: String
    var provider: OpenKeyboardAIProvider

    init(
        apiKey: String,
        gatewayURL: String,
        selectedModel: String,
        isConfigured: Bool,
        grammarCorrectionVerified: Bool,
        grammarCorrectionContractVersion: String,
        provider: OpenKeyboardAIProvider = .openAICompatible
    ) {
        self.apiKey = apiKey
        self.gatewayURL = gatewayURL
        self.selectedModel = selectedModel
        self.isConfigured = isConfigured
        self.grammarCorrectionVerified = grammarCorrectionVerified
        self.grammarCorrectionContractVersion = grammarCorrectionContractVersion
        self.provider = provider
    }

    // Source compatibility for older tests and callers. These labels map only to the new
    // plain-text grammar validation state; no structured grammar response is supported.
    init(
        apiKey: String,
        gatewayURL: String,
        selectedModel: String,
        isConfigured: Bool,
        supportsStructuredCorrections: Bool,
        structuredCorrectionSchemaVersion: String,
        provider: OpenKeyboardAIProvider = .openAICompatible
    ) {
        self.init(
            apiKey: apiKey,
            gatewayURL: gatewayURL,
            selectedModel: selectedModel,
            isConfigured: isConfigured,
            grammarCorrectionVerified: supportsStructuredCorrections,
            grammarCorrectionContractVersion: structuredCorrectionSchemaVersion,
            provider: provider
        )
    }

    private enum CodingKeys: String, CodingKey {
        case apiKey
        case gatewayURL
        case selectedModel
        case isConfigured
        case grammarCorrectionVerified
        case grammarCorrectionContractVersion
        case provider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        gatewayURL = try container.decode(String.self, forKey: .gatewayURL)
        selectedModel = try container.decode(String.self, forKey: .selectedModel)
        isConfigured = try container.decode(Bool.self, forKey: .isConfigured)
        grammarCorrectionVerified = try container.decode(Bool.self, forKey: .grammarCorrectionVerified)
        grammarCorrectionContractVersion = try container.decode(String.self, forKey: .grammarCorrectionContractVersion)
        provider = try container.decodeIfPresent(OpenKeyboardAIProvider.self, forKey: .provider) ?? .openAICompatible
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(gatewayURL, forKey: .gatewayURL)
        try container.encode(selectedModel, forKey: .selectedModel)
        try container.encode(isConfigured, forKey: .isConfigured)
        try container.encode(grammarCorrectionVerified, forKey: .grammarCorrectionVerified)
        try container.encode(grammarCorrectionContractVersion, forKey: .grammarCorrectionContractVersion)
        try container.encode(provider, forKey: .provider)
    }

    var baseURL: String {
        get { gatewayURL }
        set { gatewayURL = newValue }
    }

    var supportsStructuredCorrections: Bool {
        get { grammarCorrectionVerified }
        set { grammarCorrectionVerified = newValue }
    }

    var structuredCorrectionSchemaVersion: String {
        get { grammarCorrectionContractVersion }
        set { grammarCorrectionContractVersion = newValue }
    }
    
    static let `default` = AppConfig(
        apiKey: "",
        gatewayURL: "",
        selectedModel: "",
        isConfigured: false,
        grammarCorrectionVerified: false,
        grammarCorrectionContractVersion: ""
    )
    
    // App Group identifier for non-authoritative hints, connection errors, and debug metadata.
    static let appGroupIdentifier = "group.com.maneesh.openkeyboard"

    // Darwin notifications cross the host-app/keyboard-extension process boundary. The signal
    // intentionally contains no profile revision, provider data, or credentials; observers must
    // reload the complete secure profile after receiving it.
    static let activeProfileDidChangeDarwinNotification =
        "com.maneesh.openkeyboard.active-profile-did-change"
    
    // UserDefaults keys. apiKeyKey is legacy-only and is removed after Keychain migration.
    static let apiKeyKey = "apiKey"
    static let gatewayURLKey = "gatewayURL"
    static let selectedModelKey = "selectedModel"
    static let isConfiguredKey = "isConfigured"
    // Preserve the existing App Group storage keys so installed builds migrate without losing
    // their saved gateway state. Their values now describe plain-text grammar verification.
    static let grammarCorrectionVerifiedKey = "supportsStructuredCorrections"
    static let grammarCorrectionContractVersionKey = "structuredCorrectionSchemaVersion"
    static let supportsStructuredCorrectionsKey = grammarCorrectionVerifiedKey
    static let structuredCorrectionSchemaVersionKey = grammarCorrectionContractVersionKey
    static let gatewayConnectionErrorMessageKey = "gatewayConnectionErrorMessage"
    static let gatewayConnectionErrorUpdatedAtKey = "gatewayConnectionErrorUpdatedAt"
    static let gatewayConnectionErrorProfileRevisionKey = "gatewayConnectionErrorProfileRevision"
    static let gatewayConnectionLastTestedAtKey = "gatewayConnectionLastTestedAt"
    static let gatewayConnectionLastTestedAtProfileRevisionKey = "gatewayConnectionLastTestedAtProfileRevision"
    static let gatewayProfileKey = "gatewayProfile.v1"
    static let gatewayProfileConfiguredHintKey = "gatewayProfile.configuredHint.v2"
    static let gatewayProfileRevisionHintKey = "gatewayProfile.revisionHint.v2"
    static let gatewayProfileClearPendingKey = "gatewayProfile.clearPending.v1"
    static let gatewayLegacySecretCleanupReferenceKey = "gatewayProfile.legacySecretCleanupReference.v1"
    static let gatewayLegacyUnversionedSecretCleanupPendingKey = "gatewayProfile.legacyUnversionedSecretCleanupPending.v1"
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let gatewayConnectionRetestInterval: TimeInterval = 60 * 60
    private static let keyboardUITestConfigOriginKey = "keyboardExtension.gatewayConfigIsUITestSeed"
    private static let keyboardUITestConfigSeedIDKey = "keyboardExtension.gatewayConfigSeedID"
    private static let keyboardUITestConfigSeededAtKey = "keyboardExtension.gatewayConfigSeededAt"
    private static let noSecureProfileRevision = "none"
    #if DEBUG && targetEnvironment(simulator)
    private static let keyboardUITestConfigAuthorization = KeyboardUITestConfigProcessAuthorization()
    private static let keyboardUITestConfigSeedFreshness: TimeInterval = 30
    private static let keyboardUITestConfigAuthorizationLifetime: TimeInterval = 10 * 60
    private static var keyboardUITestCurrentTimeOverride: TimeInterval?
    #endif

    static var grammarCorrectionCapabilityVersion: String {
        "fix_grammar/plain-text/\(SemanticPromptContract.version)"
    }

    var hasCurrentGrammarCorrectionCapabilityRecord: Bool {
        grammarCorrectionContractVersion == Self.grammarCorrectionCapabilityVersion
    }


    static var secureStore: AppConfigSecureStore = KeychainAppConfigSecureStore()
}

// The complete runtime profile is one shared Keychain item. App Group defaults retain only
// transient connection/UI metadata plus migration-only values from earlier releases.
extension AppConfig {
    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: AppConfig.appGroupIdentifier)
    }

    static func load() -> AppConfig {
        guard let sharedDefaults = sharedDefaults() else {
            guard case .notFound = secureStore.loadClearIntentResult(),
                  case .found(let profile, _) = storedGatewayProfileRead(),
                  profile.uiTestSeedID == nil else {
                return .default
            }
            let config = profile.config.runtimeNormalized()
            guard !config.isKnownTestPlaceholderConfig else { return .default }
            return config
        }

        return load(from: sharedDefaults)
    }

    static func load(
        from defaults: UserDefaults,
        clearRetryNotificationPoster: () -> Void = AppConfig.postActiveProfileDidChangeDarwinNotification
    ) -> AppConfig {
        switch secureStore.loadClearIntentResult() {
        case .found:
            _ = clear(
                from: defaults,
                notificationPoster: clearRetryNotificationPoster
            )
            return .default
        case .unavailable:
            // A clear may already be in progress. Never expose credentials when Keychain cannot
            // prove that the durable clear-intent tombstone is absent.
            return .default
        case .notFound:
            break
        }

        if defaults.bool(forKey: gatewayProfileClearPendingKey) {
            // Recover App-Group-only pending state written by builds that predate the durable
            // Keychain tombstone, establishing the secure intent before deleting anything.
            _ = clear(
                from: defaults,
                notificationPoster: clearRetryNotificationPoster
            )
            return .default
        }

        let loadedProfile: StoredGatewayProfile?
        let loadedConfig: AppConfig
        switch storedGatewayProfileRead() {
        case .found(let storedProfile, let format):
            loadedProfile = storedProfile
            loadedConfig = storedProfile.config.runtimeNormalized()
            if format == .current {
                _ = removeLegacyProfileStorage(from: defaults, removeValidationTimestamp: false)
                publishProfileHint(revision: storedProfile.revision, to: defaults)
            } else {
                // Schema v2 has no provider or test-origin discriminator. It remains read-only and
                // compatible until an explicit validated save upgrades it; load performs no
                // Keychain/defaults mutation. A functional simulator seed written by an old build
                // is consequently indistinguishable from a real v2 user profile after App Group
                // loss. Simulator and physical-device Keychain stores remain isolated.
            }

        case .notFound:
            let legacy: LegacyGatewayProfileCandidate
            switch legacyConfigRead(from: defaults) {
            case .available(let candidate):
                legacy = candidate
            case .unavailable:
                // A referenced or unversioned legacy Keychain read failure must not promote a
                // possibly stale plaintext App Group key or attempt migration.
                return .default
            }
            let legacyConfig = legacy.config.runtimeNormalized()
            guard legacyConfig.isConfigured,
                  legacyConfig.hasCompleteGatewayRuntimeConfig else {
                loadedProfile = nil
                loadedConfig = legacyConfig
                break
            }

            let migrationRevision = UUID().uuidString.lowercased()
            let legacyTestSeedID = migratedLegacyTestSeedID(from: defaults)
            guard let profileData = encodedSecureProfile(
                for: legacyConfig,
                revision: migrationRevision,
                lastValidatedAt: legacy.lastValidatedAt,
                uiTestSeedID: legacyTestSeedID
            ) else {
                loadedProfile = nil
                loadedConfig = legacyConfig
                break
            }

            switch secureStore.createProfileIfAbsent(profileData) {
            case .created:
                let profile = makeStoredGatewayProfile(
                    for: legacyConfig,
                    revision: migrationRevision,
                    lastValidatedAt: legacy.lastValidatedAt,
                    uiTestSeedID: legacyTestSeedID
                )
                loadedProfile = profile
                loadedConfig = profile.config.runtimeNormalized()
                _ = removeLegacyProfileStorage(
                    from: defaults,
                    secretReference: legacy.secretReference
                )
                publishProfileHint(revision: migrationRevision, to: defaults)

            case .alreadyExists:
                guard case .found(let winner, _) = storedGatewayProfileRead() else {
                    return .default
                }
                loadedProfile = winner
                loadedConfig = winner.config.runtimeNormalized()
                _ = removeLegacyProfileStorage(from: defaults, removeValidationTimestamp: false)
                publishProfileHint(revision: winner.revision, to: defaults)

            case .unavailable:
                // A valid legacy profile remains usable, but never overwrite a possibly existing
                // secure profile when Keychain cannot prove absence or complete an atomic create.
                loadedProfile = nil
                loadedConfig = legacyConfig
            }

        case .unavailable:
            // Invalid data and transient Keychain failures are indistinguishable from this
            // process's perspective. Do not fall back to a less authoritative profile.
            return .default
        }

        let requiresUITestSeedAuthorization = loadedProfile?.uiTestSeedID != nil
            || loadedConfig.isKnownTestPlaceholderConfig
            || defaults.bool(forKey: keyboardUITestConfigOriginKey)
        #if DEBUG && targetEnvironment(simulator)
        if requiresUITestSeedAuthorization {
            let now = keyboardUITestCurrentTime()
            let fingerprint = keyboardUITestConfigFingerprint(
                for: loadedConfig,
                profile: loadedProfile
            )
            if let sessionID = currentKeyboardUITestConfigSessionID(
                in: defaults,
                expectedProfile: loadedProfile,
                config: loadedConfig
            ), keyboardUITestConfigAuthorization.isAuthorized(
                fingerprint: fingerprint,
                sessionID: sessionID,
                now: now
            ) {
                return loadedConfig
            }

            if let grant = freshKeyboardExtensionUITestConfigGrant(
                in: defaults,
                expectedProfile: loadedProfile,
                now: now
            ) {
                keyboardUITestConfigAuthorization.authorize(
                    fingerprint: fingerprint,
                    sessionID: grant.sessionID,
                    expiresAt: grant.seededAt + keyboardUITestConfigAuthorizationLifetime
                )
                // The explicitly launched UI-test host writes the grant and may read the profile
                // before the keyboard extension starts. Leave the one-time freshness value for
                // that separate extension process; the extension consumes it on first use.
                if !ProcessInfo.processInfo.arguments.contains("--uitesting") {
                    consumeKeyboardExtensionUITestConfigSeed(from: defaults)
                }
                return loadedConfig
            }

            if loadedProfile?.uiTestSeedID == nil,
               loadedConfig.isKnownTestPlaceholderConfig,
               let grant = freshKeyboardExtensionUITestStateGrant(in: defaults, now: now) {
                keyboardUITestConfigAuthorization.authorize(
                    fingerprint: fingerprint,
                    sessionID: grant.sessionID,
                    expiresAt: grant.seededAt + keyboardUITestConfigAuthorizationLifetime
                )
                return loadedConfig
            }

            keyboardUITestConfigAuthorization.reset()
            // Quarantine without deleting. A delayed unauthorized reader must never erase a
            // newer profile written concurrently by the settings process.
            return .default
        }
        #else
        if requiresUITestSeedAuthorization {
            // Release and device builds can never authorize test-origin credentials. Cleanup is
            // explicit so a delayed reader cannot delete a concurrently replaced real profile.
            return .default
        }
        #endif

        return loadedConfig
    }

    @discardableResult
    func save(
        validatedAt: Date? = nil,
        notifyActiveProfileChange: Bool = true
    ) -> Bool {
        guard let sharedDefaults = AppConfig.sharedDefaults() else {
            return false
        }

        return save(
            to: sharedDefaults,
            validatedAt: validatedAt,
            notifyActiveProfileChange: notifyActiveProfileChange
        )
    }

    @discardableResult
    func save(
        to defaults: UserDefaults,
        validatedAt: Date? = nil,
        notifyActiveProfileChange: Bool = true
    ) -> Bool {
        let requestedClear = !isConfigured
        let runtimeConfig = runtimeNormalized()

        if requestedClear {
            return AppConfig.clear(
                from: defaults,
                notifyActiveProfileChange: notifyActiveProfileChange
            )
        }
        guard !defaults.bool(forKey: AppConfig.gatewayProfileClearPendingKey),
              case .notFound = AppConfig.secureStore.loadClearIntentResult() else {
            return false
        }
        // A caller that requested a configured profile must never be reinterpreted as an
        // explicit clear after normalization. Reject malformed replacements so the last complete
        // Keychain profile remains available to both processes.
        guard runtimeConfig.isConfigured,
              runtimeConfig.hasCompleteGatewayRuntimeConfig else { return false }

        let existingProfile: StoredGatewayProfile?
        let existingProfileFormat: StoredGatewayProfileFormat?
        switch AppConfig.storedGatewayProfileRead() {
        case .found(let profile, let format):
            existingProfile = profile
            existingProfileFormat = format
        case .notFound:
            existingProfile = nil
            existingProfileFormat = nil
        case .unavailable:
            return false
        }

        let equivalentCurrentProfile: StoredGatewayProfile?
        if let existingProfile,
           existingProfileFormat == .current,
           existingProfile == AppConfig.makeStoredGatewayProfile(
               for: runtimeConfig,
               revision: existingProfile.revision,
               lastValidatedAt: existingProfile.lastValidatedAt,
               uiTestSeedID: existingProfile.uiTestSeedID
           ) {
            equivalentCurrentProfile = existingProfile
        } else {
            equivalentCurrentProfile = nil
        }

        // SecItemUpdate replaces one encoded envelope, so concurrent readers observe either the
        // complete previous revision or the complete replacement revision.
        // A DEBUG-simulator test origin is sticky across ordinary replacements. Removing it would
        // turn a quarantined test profile into unrestricted credentials after authorization
        // metadata is revoked. A real profile has no origin marker and remains unaffected.
        let uiTestSeedID = existingProfile?.uiTestSeedID
        let revision = equivalentCurrentProfile?.revision ?? UUID().uuidString.lowercased()
        let lastValidatedAt = validatedAt?.timeIntervalSince1970
            ?? equivalentCurrentProfile?.lastValidatedAt
        let requiresSecureProfileWrite = equivalentCurrentProfile == nil
            || equivalentCurrentProfile?.lastValidatedAt != lastValidatedAt
        if requiresSecureProfileWrite {
            guard AppConfig.publishSecureProfile(
                for: runtimeConfig,
                revision: revision,
                lastValidatedAt: lastValidatedAt,
                uiTestSeedID: uiTestSeedID
            ) else { return false }
        }

        _ = AppConfig.removeLegacyProfileStorage(
            from: defaults,
            removeValidationTimestamp: equivalentCurrentProfile == nil
        )
        AppConfig.publishProfileHint(revision: revision, to: defaults)
        if let validatedAt {
            defaults.set(validatedAt.timeIntervalSince1970, forKey: AppConfig.gatewayConnectionLastTestedAtKey)
            defaults.set(revision, forKey: AppConfig.gatewayConnectionLastTestedAtProfileRevisionKey)
        } else if equivalentCurrentProfile == nil {
            defaults.removeObject(forKey: AppConfig.gatewayConnectionLastTestedAtKey)
            defaults.removeObject(forKey: AppConfig.gatewayConnectionLastTestedAtProfileRevisionKey)
        }
        defaults.synchronize()
        if requiresSecureProfileWrite || uiTestSeedID == nil {
            AppConfig.clearKeyboardUITestConfigMetadata(from: defaults)
        }
        if notifyActiveProfileChange && requiresSecureProfileWrite {
            AppConfig.postActiveProfileDidChangeDarwinNotification()
        }
        return true
    }

    static func postActiveProfileDidChangeDarwinNotification() {
        let name = CFNotificationName(
            rawValue: activeProfileDidChangeDarwinNotification as CFString
        )
        // The Darwin center does not carry userInfo here. This is a credential-free invalidation
        // signal only; receivers reload from shared Keychain/App Group storage.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name,
            nil,
            nil,
            true
        )
    }

    private static func storedGatewayProfileRead() -> StoredGatewayProfileReadResult {
        switch secureStore.loadProfileResult() {
        case .notFound:
            return .notFound
        case .unavailable:
            return .unavailable
        case .found(let data):
            if let profile = try? JSONDecoder().decode(StoredGatewayProfile.self, from: data),
               isValid(profile) {
                return .found(profile, format: .current)
            }

            if let legacyProfile = try? JSONDecoder().decode(
                LegacySecureGatewayProfileV2.self,
                from: data
            ), isValid(legacyProfile) {
                // Schema v2 stays read-compatible. Loading never writes: a later explicit,
                // validated save is the only operation that upgrades the envelope to schema v3.
                return .found(
                    StoredGatewayProfile(migrating: legacyProfile),
                    format: .legacyV2
                )
            }

            // Corrupt or unknown secure data is not absence. Falling back could expose a stale
            // split/defaults profile over an authoritative but unreadable secure item.
            return .unavailable
        }
    }

    private static func isValid(_ profile: StoredGatewayProfile) -> Bool {
        profile.schemaVersion == StoredGatewayProfile.schemaVersion
            && !profile.revision.isEmpty
            && profile.isConfigured
            && !profile.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !profile.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !profile.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isValid(_ profile: LegacySecureGatewayProfileV2) -> Bool {
        profile.schemaVersion == LegacySecureGatewayProfileV2.schemaVersion
            && !profile.revision.isEmpty
            && profile.isConfigured
            && !profile.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !profile.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !profile.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func publishSecureProfile(
        for config: AppConfig,
        revision: String,
        lastValidatedAt: TimeInterval?,
        uiTestSeedID: String? = nil
    ) -> Bool {
        guard let data = encodedSecureProfile(
            for: config,
            revision: revision,
            lastValidatedAt: lastValidatedAt,
            uiTestSeedID: uiTestSeedID
        ) else { return false }
        return secureStore.saveProfile(data)
    }

    private static func makeStoredGatewayProfile(
        for config: AppConfig,
        revision: String,
        lastValidatedAt: TimeInterval?,
        uiTestSeedID: String? = nil
    ) -> StoredGatewayProfile {
        StoredGatewayProfile(
            schemaVersion: StoredGatewayProfile.schemaVersion,
            revision: revision,
            provider: config.provider,
            apiKey: config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            gatewayURL: config.gatewayURL,
            selectedModel: config.selectedModel,
            isConfigured: config.isConfigured,
            grammarCorrectionVerified: config.grammarCorrectionVerified,
            grammarCorrectionContractVersion: config.grammarCorrectionContractVersion,
            lastValidatedAt: lastValidatedAt,
            uiTestSeedID: uiTestSeedID
        )
    }

    private static func encodedSecureProfile(
        for config: AppConfig,
        revision: String,
        lastValidatedAt: TimeInterval?,
        uiTestSeedID: String? = nil
    ) -> Data? {
        try? JSONEncoder().encode(
            makeStoredGatewayProfile(
                for: config,
                revision: revision,
                lastValidatedAt: lastValidatedAt,
                uiTestSeedID: uiTestSeedID
            )
        )
    }

    private static func migratedLegacyTestSeedID(from defaults: UserDefaults) -> String? {
        guard defaults.bool(forKey: keyboardUITestConfigOriginKey) else { return nil }
        let existing = defaults.string(forKey: keyboardUITestConfigSeedIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Missing external metadata must make the migrated profile harder—not easier—to use.
        return existing.isEmpty ? UUID().uuidString.lowercased() : existing
    }

    private static func legacyConfigRead(
        from defaults: UserDefaults
    ) -> LegacyGatewayProfileReadResult {
        let legacyProfile = legacyStoredGatewayProfile(from: defaults)
        let legacyDefaultsAPIKey = defaults.string(forKey: apiKeyKey) ?? ""
        let legacyKeychainAPIKey: String
        let legacyKeyRead: AppConfigSecureStoreStringReadResult
        if let reference = legacyProfile?.secretReference {
            legacyKeyRead = secureStore.loadLegacyAPIKeyResult(reference: reference)
        } else {
            legacyKeyRead = secureStore.loadLegacyAPIKeyResult()
        }
        switch legacyKeyRead {
        case .found(let value):
            legacyKeychainAPIKey = value
        case .notFound:
            legacyKeychainAPIKey = ""
        case .unavailable:
            return .unavailable
        }
        let apiKey = legacyKeychainAPIKey.isEmpty ? legacyDefaultsAPIKey : legacyKeychainAPIKey
        let config = AppConfig(
            apiKey: apiKey,
            gatewayURL: legacyProfile?.gatewayURL ?? defaults.string(forKey: gatewayURLKey) ?? "",
            selectedModel: legacyProfile?.selectedModel ?? defaults.string(forKey: selectedModelKey) ?? "",
            isConfigured: legacyProfile?.isConfigured ?? defaults.bool(forKey: isConfiguredKey),
            grammarCorrectionVerified: legacyProfile?.grammarCorrectionVerified ?? defaults.bool(forKey: grammarCorrectionVerifiedKey),
            grammarCorrectionContractVersion: legacyProfile?.grammarCorrectionContractVersion ?? defaults.string(forKey: grammarCorrectionContractVersionKey) ?? ""
        )
        let defaultsValidatedAt = defaults.object(forKey: gatewayConnectionLastTestedAtKey) == nil
            ? nil
            : defaults.double(forKey: gatewayConnectionLastTestedAtKey)
        return .available((
            config,
            legacyProfile?.secretReference,
            legacyProfile?.lastValidatedAt ?? defaultsValidatedAt
        ))
    }

    private static func legacyStoredGatewayProfile(from defaults: UserDefaults) -> LegacyStoredGatewayProfile? {
        guard let data = defaults.data(forKey: gatewayProfileKey),
              let profile = try? JSONDecoder().decode(LegacyStoredGatewayProfile.self, from: data),
              profile.schemaVersion == LegacyStoredGatewayProfile.schemaVersion,
              !profile.secretReference.isEmpty else { return nil }
        return profile
    }

    @discardableResult
    private static func removeLegacyProfileStorage(
        from defaults: UserDefaults,
        secretReference: String? = nil,
        removeValidationTimestamp: Bool = true
    ) -> Bool {
        let retainedCleanupReference = defaults.string(
            forKey: gatewayLegacySecretCleanupReferenceKey
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = [
            retainedCleanupReference,
            secretReference,
            legacyStoredGatewayProfile(from: defaults)?.secretReference
        ]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        let didClearReferencedKey = reference.map {
            secureStore.clearLegacyAPIKey(reference: $0)
        } ?? true
        let didClearUnversionedKey = secureStore.clearLegacyAPIKey()

        // Persist only nonsecret retry metadata before deleting the plaintext legacy profile.
        // The complete secure envelope is already authoritative, so a failed legacy Keychain
        // cleanup must never retain a second credential-bearing App Group representation.
        if didClearReferencedKey {
            defaults.removeObject(forKey: gatewayLegacySecretCleanupReferenceKey)
        } else if let reference {
            defaults.set(reference, forKey: gatewayLegacySecretCleanupReferenceKey)
        }
        if didClearUnversionedKey {
            defaults.removeObject(forKey: gatewayLegacyUnversionedSecretCleanupPendingKey)
        } else {
            defaults.set(true, forKey: gatewayLegacyUnversionedSecretCleanupPendingKey)
        }
        defaults.synchronize()

        var legacyKeys = [
            gatewayProfileKey,
            apiKeyKey,
            gatewayURLKey,
            selectedModelKey,
            isConfiguredKey,
            grammarCorrectionVerifiedKey,
            grammarCorrectionContractVersionKey
        ]
        if removeValidationTimestamp ||
            defaults.object(forKey: gatewayConnectionLastTestedAtProfileRevisionKey) == nil {
            legacyKeys.append(gatewayConnectionLastTestedAtKey)
            legacyKeys.append(gatewayConnectionLastTestedAtProfileRevisionKey)
        }
        legacyKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.synchronize()
        return didClearReferencedKey && didClearUnversionedKey
    }

    private static func publishProfileHint(revision: String, to defaults: UserDefaults) {
        if defaults.bool(forKey: gatewayProfileConfiguredHintKey),
           defaults.string(forKey: gatewayProfileRevisionHintKey) == revision {
            return
        }
        defaults.set(true, forKey: gatewayProfileConfiguredHintKey)
        defaults.set(revision, forKey: gatewayProfileRevisionHintKey)
        defaults.synchronize()
    }

    private static func clearProfileHint(from defaults: UserDefaults) {
        defaults.removeObject(forKey: gatewayProfileConfiguredHintKey)
        defaults.removeObject(forKey: gatewayProfileRevisionHintKey)
        defaults.synchronize()
    }

    #if DEBUG && targetEnvironment(simulator)
    @discardableResult
    func saveTestSeed(
        to defaults: UserDefaults,
        overwriteExistingRealConfig: Bool = false,
        mirrorAPIKeyToDefaultsForUITest: Bool = false,
        notificationPoster: () -> Void = AppConfig.postActiveProfileDidChangeDarwinNotification
    ) -> Bool {
        // Retained for source compatibility with older UI-test launch helpers. Credentials are
        // never mirrored into App Group defaults; the complete seed is one secure envelope.
        _ = mirrorAPIKeyToDefaultsForUITest

        let runtimeConfig = runtimeNormalized()
        guard !defaults.bool(forKey: AppConfig.gatewayProfileClearPendingKey),
              case .notFound = AppConfig.secureStore.loadClearIntentResult(),
              runtimeConfig.isConfigured,
              runtimeConfig.hasCompleteGatewayRuntimeConfig else {
            return false
        }
        if !overwriteExistingRealConfig,
           AppConfig.hasExistingRealConfig(in: defaults) {
            return false
        }
        let revision = UUID().uuidString.lowercased()
        let seedID = UUID().uuidString.lowercased()
        guard let profileData = AppConfig.encodedSecureProfile(
            for: runtimeConfig,
            revision: revision,
            lastValidatedAt: nil,
            uiTestSeedID: seedID
        ) else { return false }

        let didSaveProfile: Bool
        if overwriteExistingRealConfig {
            didSaveProfile = AppConfig.secureStore.saveProfile(profileData)
        } else {
            didSaveProfile = AppConfig.secureStore.createProfileIfAbsent(profileData) == .created
        }
        guard didSaveProfile else {
            return false
        }

        _ = AppConfig.removeLegacyProfileStorage(from: defaults)
        AppConfig.publishProfileHint(revision: revision, to: defaults)
        defaults.set(true, forKey: AppConfig.keyboardUITestConfigOriginKey)
        defaults.set(seedID, forKey: AppConfig.keyboardUITestConfigSeedIDKey)
        defaults.set(
            AppConfig.keyboardUITestCurrentTime(),
            forKey: AppConfig.keyboardUITestConfigSeededAtKey
        )
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        if !runtimeConfig.grammarCorrectionVerified {
            AppConfig.saveGatewayConnectionLastTestedAt(to: defaults)
        }
        defaults.synchronize()
        // Test-origin profile, authorization metadata, and validation state form one observable
        // transaction. A running extension must not reload until every field is committed.
        notificationPoster()
        return true
    }

    static func hasExistingRealConfig(in defaults: UserDefaults) -> Bool {
        switch secureStore.loadClearIntentResult() {
        case .notFound:
            break
        case .found, .unavailable:
            return true
        }
        switch storedGatewayProfileRead() {
        case .found(let profile, _):
            let candidate = profile.config.runtimeNormalized()
            return candidate.isConfigured
                && !candidate.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !candidate.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !candidate.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !candidate.isKnownTestPlaceholderConfig
                && profile.uiTestSeedID == nil
        case .unavailable:
            // An unreadable secure item may be a real profile. Non-overwrite seeding must stop.
            return true
        case .notFound:
            break
        }
        let candidate: AppConfig
        switch legacyConfigRead(from: defaults) {
        case .available(let legacy):
            candidate = legacy.config
        case .unavailable:
            // Failure to read a legacy Keychain slot cannot prove that the remaining App Group
            // values are disposable. Refuse non-overwrite debug seeding.
            return true
        }

        return candidate.isConfigured
            && !candidate.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !candidate.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !candidate.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !candidate.isKnownTestPlaceholderConfig
            && !defaults.bool(forKey: keyboardUITestConfigOriginKey)
    }
    #endif

    static func clearSharedConfig() {
        guard let sharedDefaults = sharedDefaults() else { return }
        clear(from: sharedDefaults)
    }

    private static func activeProfileRevision() -> String? {
        guard case .notFound = secureStore.loadClearIntentResult() else { return nil }
        switch storedGatewayProfileRead() {
        case .found(let profile, _):
            return profile.revision
        case .notFound:
            return noSecureProfileRevision
        case .unavailable:
            return nil
        }
    }

    static func gatewayConnectionError(from defaults: UserDefaults) -> String? {
        let value = defaults.string(forKey: gatewayConnectionErrorMessageKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty,
              let revision = activeProfileRevision(),
              defaults.string(forKey: gatewayConnectionErrorProfileRevisionKey) == revision else {
            return nil
        }
        let sanitized = KeyboardActionErrorState.sanitized(value)
        if sanitized != value {
            defaults.set(sanitized, forKey: gatewayConnectionErrorMessageKey)
            defaults.synchronize()
        }
        return sanitized
    }

    static func sharedGatewayConnectionError() -> String? {
        guard let defaults = sharedDefaults() else { return nil }
        return gatewayConnectionError(from: defaults)
    }

    static func gatewayConnectionLastTestedAt(from defaults: UserDefaults) -> Date? {
        if defaults.object(forKey: gatewayConnectionLastTestedAtKey) != nil {
            let timestamp = defaults.double(forKey: gatewayConnectionLastTestedAtKey)
            // A zero override is deliberately revision-independent: if Keychain was unavailable
            // while clearing validation state, no older secure timestamp may become trusted later.
            guard timestamp > 0 else { return nil }
            if let revision = activeProfileRevision(),
               defaults.string(forKey: gatewayConnectionLastTestedAtProfileRevisionKey) == revision {
                return Date(timeIntervalSince1970: timestamp)
            }
            return nil
        }
        guard case .notFound = secureStore.loadClearIntentResult() else { return nil }
        if case .found(let profile, _) = storedGatewayProfileRead(),
           let timestamp = profile.lastValidatedAt,
           timestamp > 0 {
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }

    static func saveGatewayConnectionLastTestedAt(_ date: Date = Date(), to defaults: UserDefaults? = sharedDefaults()) {
        guard let defaults, let revision = activeProfileRevision() else { return }
        defaults.set(date.timeIntervalSince1970, forKey: gatewayConnectionLastTestedAtKey)
        defaults.set(revision, forKey: gatewayConnectionLastTestedAtProfileRevisionKey)
        defaults.synchronize()
    }

    static func clearGatewayConnectionLastTestedAt(from defaults: UserDefaults? = sharedDefaults()) {
        guard let defaults else { return }
        defaults.set(0, forKey: gatewayConnectionLastTestedAtKey)
        if let revision = activeProfileRevision() {
            defaults.set(revision, forKey: gatewayConnectionLastTestedAtProfileRevisionKey)
        } else {
            defaults.removeObject(forKey: gatewayConnectionLastTestedAtProfileRevisionKey)
        }
        defaults.synchronize()
    }

    static func saveGatewayConnectionError(
        _ message: String,
        to defaults: UserDefaults? = sharedDefaults(),
        notifyActiveProfileChange: Bool = true
    ) {
        guard let defaults else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearGatewayConnectionError(
                from: defaults,
                notifyActiveProfileChange: notifyActiveProfileChange
            )
            return
        }
        let sanitized = KeyboardActionErrorState.sanitized(trimmed)
        guard let revision = activeProfileRevision() else { return }
        let previousMessage = defaults.string(forKey: gatewayConnectionErrorMessageKey)
        let previousRevision = defaults.string(forKey: gatewayConnectionErrorProfileRevisionKey)
        defaults.set(sanitized, forKey: gatewayConnectionErrorMessageKey)
        defaults.set(Date().timeIntervalSince1970, forKey: gatewayConnectionErrorUpdatedAtKey)
        defaults.set(revision, forKey: gatewayConnectionErrorProfileRevisionKey)
        defaults.synchronize()
        if notifyActiveProfileChange &&
            (previousMessage != sanitized || previousRevision != revision) {
            postActiveProfileDidChangeDarwinNotification()
        }
    }

    static func clearGatewayConnectionError(
        from defaults: UserDefaults? = sharedDefaults(),
        notifyActiveProfileChange: Bool = true
    ) {
        guard let defaults else { return }
        let hadPersistedError = defaults.object(forKey: gatewayConnectionErrorMessageKey) != nil
            || defaults.object(forKey: gatewayConnectionErrorUpdatedAtKey) != nil
            || defaults.object(forKey: gatewayConnectionErrorProfileRevisionKey) != nil
        defaults.removeObject(forKey: gatewayConnectionErrorMessageKey)
        defaults.removeObject(forKey: gatewayConnectionErrorUpdatedAtKey)
        defaults.removeObject(forKey: gatewayConnectionErrorProfileRevisionKey)
        defaults.synchronize()
        if notifyActiveProfileChange && hadPersistedError {
            postActiveProfileDidChangeDarwinNotification()
        }
    }

    static func resetOnboardingState(in defaults: UserDefaults? = sharedDefaults()) {
        defaults?.set(false, forKey: hasCompletedOnboardingKey)
        defaults?.synchronize()
        UserDefaults.standard.set(false, forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.synchronize()
        NotificationCenter.default.post(name: .openKeyboardOnboardingReset, object: nil)
    }

    var isKnownTestPlaceholderConfig: Bool {
        let normalizedGatewayURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        return AppConfig.rejectedGatewayURLs.contains { $0.caseInsensitiveCompare(normalizedGatewayURL) == .orderedSame }
            || AppConfig.rejectedSelectedModels.contains(normalizedSelectedModel)
            || AppConfig.rejectedAPIKeys.contains(normalizedAPIKey)
    }

    var hasCompleteGatewayRuntimeConfig: Bool {
        hasGatewayRuntimeConfig
            && !selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasGatewayRuntimeConfig: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runtimeNormalized() -> AppConfig {
        guard isConfigured else {
            var copy = self
            copy.grammarCorrectionVerified = false
            copy.grammarCorrectionContractVersion = ""
            return copy
        }
        guard !hasGatewayRuntimeConfig else { return self }

        var copy = self
        copy.isConfigured = false
        copy.grammarCorrectionVerified = false
        copy.grammarCorrectionContractVersion = ""
        return copy
    }

    private static var rejectedGatewayURLs: [String] {
        [
            ["https://gateway", "example", "invalid"].joined(separator: "."),
            ["https://mock", "local", "invalid"].joined(separator: ".")
        ]
    }

    private static var rejectedSelectedModels: [String] {
        [
            ["test", "placeholder", "model"].joined(separator: "-"),
            ["mock", "ui", "test", "model"].joined(separator: "-")
        ]
    }

    private static var rejectedAPIKeys: [String] {
        [
            ["test", "placeholder", "key"].joined(separator: "-"),
            ["mock", "ui", "test", "key"].joined(separator: "-")
        ]
    }

    struct RedactedVisibilityDiagnostic: Equatable {
        let uiTestDebugStateEnabled: Bool
        let gatewayURLPresent: Bool
        let selectedModelPresent: Bool
        let profileConfiguredHint: Bool
        let legacyDefaultsAPIKeyPresent: Bool
        let keychainAPIKeyPresent: Bool
        let loadedConfigIsConfigured: Bool

        var redactedDescription: String {
            [
                "keyboardExtension.uiTestDebugStateEnabled=\(uiTestDebugStateEnabled)",
                "gatewayURLPresent=\(gatewayURLPresent)",
                "selectedModelPresent=\(selectedModelPresent)",
                "profileConfiguredHint=\(profileConfiguredHint)",
                "legacyAppGroupAPIKeyPresent=\(legacyDefaultsAPIKeyPresent)",
                "keychainAPIKeyPresent=\(keychainAPIKeyPresent)",
                "loadedExtensionAppConfig.isConfigured=\(loadedConfigIsConfigured)"
            ].joined(separator: "; ")
        }
    }

    static func redactedVisibilityDiagnostic(from defaults: UserDefaults? = sharedDefaults()) -> RedactedVisibilityDiagnostic {
        guard let defaults else {
            return RedactedVisibilityDiagnostic(
                uiTestDebugStateEnabled: false,
                gatewayURLPresent: false,
                selectedModelPresent: false,
                profileConfiguredHint: false,
                legacyDefaultsAPIKeyPresent: false,
                keychainAPIKeyPresent: false,
                loadedConfigIsConfigured: false
            )
        }

        let loadedConfig = load(from: defaults)
        let rawGatewayURL = loadedConfig.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawSelectedModel = loadedConfig.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyDefaultsAPIKey = defaults.string(forKey: apiKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let keychainProfilePresent: Bool
        if case .found = storedGatewayProfileRead() {
            keychainProfilePresent = true
        } else {
            keychainProfilePresent = false
        }
        let legacyKeychainAPIKey = secureStore.loadLegacyAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return RedactedVisibilityDiagnostic(
            uiTestDebugStateEnabled: isUITestDebugStateEnabled(in: defaults),
            gatewayURLPresent: !rawGatewayURL.isEmpty,
            selectedModelPresent: !rawSelectedModel.isEmpty,
            profileConfiguredHint: defaults.bool(forKey: gatewayProfileConfiguredHintKey),
            legacyDefaultsAPIKeyPresent: !legacyDefaultsAPIKey.isEmpty,
            keychainAPIKeyPresent: keychainProfilePresent || !legacyKeychainAPIKey.isEmpty,
            loadedConfigIsConfigured: loadedConfig.isConfigured
        )
    }

    static func isUITestDebugStateEnabled(in defaults: UserDefaults) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled")
        #else
        false
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private static func freshKeyboardExtensionUITestStateGrant(
        in defaults: UserDefaults,
        now: TimeInterval
    ) -> (sessionID: String, seededAt: TimeInterval)? {
        guard isUITestDebugStateEnabled(in: defaults) else { return nil }
        let suggestionSeedID = defaults.string(forKey: "keyboardExtension.suggestionStateSeedID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let panelSeedID = defaults.string(forKey: "keyboardExtension.initialPanelModeSeedID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !suggestionSeedID.isEmpty,
              suggestionSeedID == panelSeedID,
              let suggestionSeededAt = defaults.object(forKey: "keyboardExtension.suggestionStateSeededAt") as? TimeInterval,
              let panelSeededAt = defaults.object(forKey: "keyboardExtension.initialPanelModeSeededAt") as? TimeInterval else {
            return nil
        }
        let maximumClockSkew: TimeInterval = 5
        guard suggestionSeededAt >= now - keyboardUITestConfigSeedFreshness &&
            suggestionSeededAt <= now + maximumClockSkew &&
            panelSeededAt >= now - keyboardUITestConfigSeedFreshness &&
            panelSeededAt <= now + maximumClockSkew else {
            return nil
        }
        return (suggestionSeedID, min(suggestionSeededAt, panelSeededAt))
    }

    private static func freshKeyboardExtensionUITestConfigGrant(
        in defaults: UserDefaults,
        expectedProfile: StoredGatewayProfile?,
        now: TimeInterval
    ) -> (sessionID: String, seededAt: TimeInterval)? {
        let seedID = defaults.string(forKey: keyboardUITestConfigSeedIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard defaults.bool(forKey: keyboardUITestConfigOriginKey),
              isUITestDebugStateEnabled(in: defaults),
              !seedID.isEmpty,
              let seededAt = defaults.object(forKey: keyboardUITestConfigSeededAtKey) as? TimeInterval else {
            return nil
        }
        guard let expectedProfile,
              let expectedSeedID = expectedProfile.uiTestSeedID,
              seedID == expectedSeedID,
              defaults.string(forKey: gatewayProfileRevisionHintKey) == expectedProfile.revision else {
            return nil
        }
        guard seededAt >= now - keyboardUITestConfigSeedFreshness,
              seededAt <= now + 5 else {
            return nil
        }
        return (seedID, seededAt)
    }

    private static func currentKeyboardUITestConfigSessionID(
        in defaults: UserDefaults,
        expectedProfile: StoredGatewayProfile?,
        config: AppConfig
    ) -> String? {
        guard isUITestDebugStateEnabled(in: defaults) else { return nil }
        if let expectedProfile,
           let expectedSeedID = expectedProfile.uiTestSeedID {
            let currentSeedID = defaults.string(forKey: keyboardUITestConfigSeedIDKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard defaults.bool(forKey: keyboardUITestConfigOriginKey),
                  currentSeedID == expectedSeedID,
                  defaults.string(forKey: gatewayProfileRevisionHintKey) == expectedProfile.revision else {
                return nil
            }
            return currentSeedID
        }

        guard config.isKnownTestPlaceholderConfig else { return nil }
        let suggestionSeedID = defaults.string(forKey: "keyboardExtension.suggestionStateSeedID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let panelSeedID = defaults.string(forKey: "keyboardExtension.initialPanelModeSeedID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !suggestionSeedID.isEmpty, suggestionSeedID == panelSeedID else { return nil }
        return suggestionSeedID
    }

    private static func keyboardUITestCurrentTime() -> TimeInterval {
        keyboardUITestCurrentTimeOverride ?? Date().timeIntervalSince1970
    }

    private static func keyboardUITestConfigFingerprint(
        for config: AppConfig,
        profile: StoredGatewayProfile?
    ) -> String {
        if let profile {
            return [profile.revision, profile.uiTestSeedID ?? "legacy-test-origin"]
                .joined(separator: "\u{1F}")
        }
        // Legacy-only placeholder authorization still binds every credential-bearing field.
        return [
            config.provider.rawValue,
            config.apiKey,
            config.gatewayURL,
            config.selectedModel
        ].joined(separator: "\u{1F}")
    }

    private static func consumeKeyboardExtensionUITestConfigSeed(from defaults: UserDefaults) {
        // Keep the noncredential session ID so every subsequent in-process read can prove that
        // debug state has not been revoked or replaced. Remove only the one-time freshness grant;
        // a new process cannot authorize from the retained session ID alone.
        defaults.removeObject(forKey: keyboardUITestConfigSeededAtKey)
        defaults.synchronize()
    }
    #endif

    private static func clearKeyboardUITestConfigMetadata(from defaults: UserDefaults) {
        #if DEBUG && targetEnvironment(simulator)
        keyboardUITestConfigAuthorization.reset()
        #endif
        defaults.removeObject(forKey: keyboardUITestConfigOriginKey)
        defaults.removeObject(forKey: keyboardUITestConfigSeedIDKey)
        defaults.removeObject(forKey: keyboardUITestConfigSeededAtKey)
        defaults.synchronize()
    }

    #if DEBUG && targetEnvironment(simulator)
    static func resetKeyboardUITestConfigProcessAuthorizationForTesting() {
        keyboardUITestConfigAuthorization.reset()
    }

    static func setKeyboardUITestCurrentTimeForTesting(_ value: TimeInterval?) {
        keyboardUITestCurrentTimeOverride = value
    }
    #endif

    static func clearKeyboardUITestState(from defaults: UserDefaults) {
        [
            "keyboardExtension.composingBuffer",
            "keyboardExtension.lastDebugEvent",
            "keyboardExtension.debugEvents",
            "keyboardExtension.uiTestDebugStateEnabled",
            "keyboardExtension.initialPanelMode",
            "keyboardExtension.initialPanelModeSeedID",
            "keyboardExtension.initialPanelModeSeededAt",
            "keyboardExtension.suggestionState",
            "keyboardExtension.suggestionStateSeedID",
            "keyboardExtension.suggestionStateSeededAt"
        ].forEach {
            defaults.removeObject(forKey: $0)
        }
        defaults.synchronize()
    }

    private static func removeAppGroupProfileStorageForClear(from defaults: UserDefaults) {
        [
            gatewayProfileKey,
            gatewayProfileConfiguredHintKey,
            gatewayProfileRevisionHintKey,
            gatewayLegacySecretCleanupReferenceKey,
            gatewayLegacyUnversionedSecretCleanupPendingKey,
            apiKeyKey,
            gatewayURLKey,
            selectedModelKey,
            isConfiguredKey,
            grammarCorrectionVerifiedKey,
            grammarCorrectionContractVersionKey,
            gatewayConnectionErrorMessageKey,
            gatewayConnectionErrorUpdatedAtKey,
            gatewayConnectionErrorProfileRevisionKey,
            gatewayConnectionLastTestedAtKey,
            gatewayConnectionLastTestedAtProfileRevisionKey
        ].forEach {
            defaults.removeObject(forKey: $0)
        }
        clearKeyboardUITestState(from: defaults)
        clearKeyboardUITestConfigMetadata(from: defaults)
        defaults.synchronize()
    }

    @discardableResult
    static func clear(
        from defaults: UserDefaults,
        notifyActiveProfileChange: Bool = true,
        notificationPoster: () -> Void = AppConfig.postActiveProfileDidChangeDarwinNotification
    ) -> Bool {
        let retainedCleanupReference = defaults.string(
            forKey: gatewayLegacySecretCleanupReferenceKey
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let appGroupLegacyReferences = Set([
            retainedCleanupReference,
            legacyStoredGatewayProfile(from: defaults)?.secretReference
        ].compactMap { $0 }.filter { !$0.isEmpty })

        let secureClearIntent: AppConfigSecureClearIntent
        switch secureStore.loadClearIntentResult() {
        case .found(let existingIntent):
            let mergedIntent = AppConfigSecureClearIntent(
                legacySecretReferences: Array(
                    Set(existingIntent.legacySecretReferences).union(appGroupLegacyReferences)
                ),
                clearsUnversionedLegacyKey: true
            )
            if mergedIntent == existingIntent {
                secureClearIntent = existingIntent
            } else {
                guard secureStore.saveClearIntent(mergedIntent) else { return false }
                secureClearIntent = mergedIntent
            }
        case .notFound:
            let newIntent = AppConfigSecureClearIntent(
                legacySecretReferences: Array(appGroupLegacyReferences)
            )
            guard secureStore.saveClearIntent(newIntent) else { return false }
            secureClearIntent = newIntent
        case .unavailable:
            // Do not delete credentials unless a durable, App-Group-independent quarantine is
            // known to exist. Load already treats an unavailable status as fail closed.
            return false
        }

        // The App Group marker accelerates recovery for older builds, but is not authoritative.
        // Persist it only after the Keychain tombstone exists.
        defaults.set(true, forKey: gatewayProfileClearPendingKey)
        defaults.synchronize()
        if notifyActiveProfileChange {
            // Repost on every retry. Darwin notifications are coalescible and payload-free, so
            // duplicates are safe; repetition closes the crash window between committing the
            // durable tombstone and notifying an already-running extension.
            notificationPoster()
        }

        // Once the durable intent contains every exact legacy reference, no credential-bearing
        // App Group representation is needed for retry. Remove plaintext and ancillary metadata
        // even when a Keychain delete below fails; the secure, noncredential tombstone plus the
        // pending marker keep all later reads quarantined and retain exact retry information.
        removeAppGroupProfileStorageForClear(from: defaults)

        let didClearSecureProfile = secureStore.clearProfile()
        let didClearReferencedLegacyKeys = secureClearIntent.legacySecretReferences.reduce(true) { result, reference in
            secureStore.clearLegacyAPIKey(reference: reference) && result
        }
        let didClearUnversionedLegacyKey = !secureClearIntent.clearsUnversionedLegacyKey
            || secureStore.clearLegacyAPIKey()
        guard didClearSecureProfile,
              didClearReferencedLegacyKeys,
              didClearUnversionedLegacyKey else {
            return false
        }

        // App Group cleanup has already completed. Remove its pending marker only after every
        // Keychain credential deletion succeeds, then clear the secure tombstone absolutely last.
        defaults.removeObject(forKey: gatewayProfileClearPendingKey)
        defaults.synchronize()

        return secureStore.clearClearIntent()
    }
}

extension Notification.Name {
    static let openKeyboardOnboardingReset = Notification.Name("openKeyboardOnboardingReset")
}
