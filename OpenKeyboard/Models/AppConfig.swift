//
//  AppConfig.swift
//  OpenKeyboard
//
//  Configuration model
//

import Foundation
import NaturalLanguage
import Security

private final class KeyboardUITestConfigProcessAuthorization: @unchecked Sendable {
    private let lock = NSLock()
    private var fingerprint: String?

    func authorize(_ fingerprint: String) {
        lock.lock()
        defer { lock.unlock() }
        self.fingerprint = fingerprint
    }

    func isAuthorized(_ fingerprint: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return self.fingerprint == fingerprint
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        fingerprint = nil
    }
}

enum SettingsDocumentationLink {
    static let url = URL(string: "https://myadidi.com/projects/open-keyboard-llm-gateway/")!
}

protocol AppConfigSecureStore {
    func loadProfile() -> Data?
    @discardableResult func saveProfile(_ profile: Data) -> Bool
    @discardableResult func clearProfile() -> Bool

    // Migration-only accessors for profiles saved by earlier releases.
    func loadLegacyAPIKey() -> String?
    func loadLegacyAPIKey(reference: String) -> String?
    @discardableResult func saveLegacyAPIKey(_ apiKey: String) -> Bool
    @discardableResult func clearLegacyAPIKey() -> Bool
    @discardableResult func clearLegacyAPIKey(reference: String) -> Bool
}

final class KeychainAppConfigSecureStore: AppConfigSecureStore {
    static let sharedAccessGroupSuffix = "com.maneesh.openkeyboard.shared"

    private let service = "com.maneesh.openkeyboard.gateway"
    private let profileAccount = "gateway-profile-v2"
    private let legacyAPIKeyAccount = "gateway-api-key"
    private let accessGroup: String?

    init(accessGroup: String? = KeychainAppConfigSecureStore.defaultSharedAccessGroup()) {
        self.accessGroup = accessGroup
    }

    func loadProfile() -> Data? {
        loadData(account: profileAccount)
    }

    @discardableResult
    func saveProfile(_ profile: Data) -> Bool {
        saveData(profile, account: profileAccount)
    }

    @discardableResult
    func clearProfile() -> Bool {
        clearData(account: profileAccount)
    }

    func loadLegacyAPIKey() -> String? {
        loadString(account: legacyAPIKeyAccount)
    }

    func loadLegacyAPIKey(reference: String) -> String? {
        loadString(account: versionedLegacyAccount(reference: reference))
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
        guard let data = loadData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func loadData(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func saveData(_ data: Data, account: String) -> Bool {
        var query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
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

    var config: AppConfig {
        AppConfig(
            apiKey: apiKey,
            gatewayURL: gatewayURL,
            selectedModel: selectedModel,
            isConfigured: isConfigured,
            grammarCorrectionVerified: grammarCorrectionVerified,
            grammarCorrectionContractVersion: grammarCorrectionContractVersion
        )
    }
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

    init(
        apiKey: String,
        gatewayURL: String,
        selectedModel: String,
        isConfigured: Bool,
        grammarCorrectionVerified: Bool,
        grammarCorrectionContractVersion: String
    ) {
        self.apiKey = apiKey
        self.gatewayURL = gatewayURL
        self.selectedModel = selectedModel
        self.isConfigured = isConfigured
        self.grammarCorrectionVerified = grammarCorrectionVerified
        self.grammarCorrectionContractVersion = grammarCorrectionContractVersion
    }

    // Source compatibility for older tests and callers. These labels map only to the new
    // plain-text grammar validation state; no structured grammar response is supported.
    init(
        apiKey: String,
        gatewayURL: String,
        selectedModel: String,
        isConfigured: Bool,
        supportsStructuredCorrections: Bool,
        structuredCorrectionSchemaVersion: String
    ) {
        self.init(
            apiKey: apiKey,
            gatewayURL: gatewayURL,
            selectedModel: selectedModel,
            isConfigured: isConfigured,
            grammarCorrectionVerified: supportsStructuredCorrections,
            grammarCorrectionContractVersion: structuredCorrectionSchemaVersion
        )
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
    static let gatewayConnectionLastTestedAtKey = "gatewayConnectionLastTestedAt"
    static let gatewayProfileKey = "gatewayProfile.v1"
    static let gatewayProfileConfiguredHintKey = "gatewayProfile.configuredHint.v2"
    static let gatewayProfileRevisionHintKey = "gatewayProfile.revisionHint.v2"
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let gatewayConnectionRetestInterval: TimeInterval = 60 * 60
    private static let keyboardUITestConfigOriginKey = "keyboardExtension.gatewayConfigIsUITestSeed"
    private static let keyboardUITestConfigSeedIDKey = "keyboardExtension.gatewayConfigSeedID"
    private static let keyboardUITestConfigSeededAtKey = "keyboardExtension.gatewayConfigSeededAt"
    private static let keyboardUITestConfigAuthorization = KeyboardUITestConfigProcessAuthorization()

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
            guard let config = storedGatewayProfile()?.config.runtimeNormalized(),
                  !config.isKnownTestPlaceholderConfig else {
                return .default
            }
            return config
        }

        return load(from: sharedDefaults)
    }

    static func load(from defaults: UserDefaults) -> AppConfig {
        let loadedConfig: AppConfig
        if let storedProfile = storedGatewayProfile() {
            loadedConfig = storedProfile.config.runtimeNormalized()
            removeLegacyProfileStorage(from: defaults, removeValidationTimestamp: false)
            publishProfileHint(revision: storedProfile.revision, to: defaults)
        } else {
            let legacy = legacyConfig(from: defaults)
            loadedConfig = legacy.config.runtimeNormalized()
            let migrationRevision = UUID().uuidString.lowercased()
            if loadedConfig.isConfigured,
               loadedConfig.hasCompleteGatewayRuntimeConfig,
               publishSecureProfile(
                    for: loadedConfig,
                    revision: migrationRevision,
                    lastValidatedAt: legacy.lastValidatedAt
               ) {
                removeLegacyProfileStorage(from: defaults, secretReference: legacy.secretReference)
                publishProfileHint(revision: migrationRevision, to: defaults)
            }
        }

        let requiresUITestSeedAuthorization = loadedConfig.isKnownTestPlaceholderConfig ||
            defaults.bool(forKey: keyboardUITestConfigOriginKey)
        if requiresUITestSeedAuthorization,
           !ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let fingerprint = keyboardUITestConfigFingerprint(for: loadedConfig)
            if keyboardUITestConfigAuthorization.isAuthorized(fingerprint) {
                return loadedConfig
            }
            if hasFreshKeyboardExtensionUITestConfigSeed(in: defaults) ||
                (loadedConfig.isKnownTestPlaceholderConfig && hasFreshKeyboardExtensionUITestSeed(in: defaults)) {
                keyboardUITestConfigAuthorization.authorize(fingerprint)
                consumeKeyboardExtensionUITestConfigSeed(from: defaults)
                return loadedConfig
            }
            clear(from: defaults)
            return .default
        }

        return loadedConfig
    }

    @discardableResult
    func save(validatedAt: Date? = nil) -> Bool {
        guard let sharedDefaults = AppConfig.sharedDefaults() else {
            return false
        }

        return save(to: sharedDefaults, validatedAt: validatedAt)
    }

    @discardableResult
    func save(to defaults: UserDefaults, validatedAt: Date? = nil) -> Bool {
        let runtimeConfig = runtimeNormalized()
        let previousProfile = AppConfig.storedGatewayProfile()

        guard runtimeConfig.isConfigured else {
            guard AppConfig.secureStore.clearProfile() else { return false }
            AppConfig.removeLegacyProfileStorage(from: defaults)
            AppConfig.clearProfileHint(from: defaults)
            AppConfig.clearKeyboardUITestConfigMetadata(from: defaults)
            return true
        }
        guard runtimeConfig.hasCompleteGatewayRuntimeConfig else { return false }

        // SecItemUpdate replaces one encoded envelope, so concurrent readers observe either the
        // complete previous revision or the complete replacement revision.
        let revision = UUID().uuidString.lowercased()
        guard AppConfig.publishSecureProfile(
            for: runtimeConfig,
            revision: revision,
            lastValidatedAt: validatedAt?.timeIntervalSince1970 ?? previousProfile?.lastValidatedAt
        ) else { return false }

        AppConfig.removeLegacyProfileStorage(from: defaults)
        AppConfig.publishProfileHint(revision: revision, to: defaults)
        AppConfig.clearKeyboardUITestConfigMetadata(from: defaults)
        return true
    }

    private static func storedGatewayProfile() -> StoredGatewayProfile? {
        guard let data = secureStore.loadProfile(),
              let profile = try? JSONDecoder().decode(StoredGatewayProfile.self, from: data),
              profile.schemaVersion == StoredGatewayProfile.schemaVersion,
              !profile.revision.isEmpty,
              !profile.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return profile
    }

    private static func publishSecureProfile(
        for config: AppConfig,
        revision: String,
        lastValidatedAt: TimeInterval?
    ) -> Bool {
        let profile = StoredGatewayProfile(
            schemaVersion: StoredGatewayProfile.schemaVersion,
            revision: revision,
            apiKey: config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            gatewayURL: config.gatewayURL,
            selectedModel: config.selectedModel,
            isConfigured: config.isConfigured,
            grammarCorrectionVerified: config.grammarCorrectionVerified,
            grammarCorrectionContractVersion: config.grammarCorrectionContractVersion,
            lastValidatedAt: lastValidatedAt
        )
        guard let data = try? JSONEncoder().encode(profile) else { return false }
        return secureStore.saveProfile(data)
    }

    private static func legacyConfig(from defaults: UserDefaults) -> (
        config: AppConfig,
        secretReference: String?,
        lastValidatedAt: TimeInterval?
    ) {
        let legacyProfile = legacyStoredGatewayProfile(from: defaults)
        let legacyDefaultsAPIKey = defaults.string(forKey: apiKeyKey) ?? ""
        let legacyKeychainAPIKey: String
        if let reference = legacyProfile?.secretReference {
            legacyKeychainAPIKey = secureStore.loadLegacyAPIKey(reference: reference) ?? ""
        } else {
            legacyKeychainAPIKey = secureStore.loadLegacyAPIKey() ?? ""
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
        return (config, legacyProfile?.secretReference, legacyProfile?.lastValidatedAt ?? defaultsValidatedAt)
    }

    private static func legacyStoredGatewayProfile(from defaults: UserDefaults) -> LegacyStoredGatewayProfile? {
        guard let data = defaults.data(forKey: gatewayProfileKey),
              let profile = try? JSONDecoder().decode(LegacyStoredGatewayProfile.self, from: data),
              profile.schemaVersion == LegacyStoredGatewayProfile.schemaVersion,
              !profile.secretReference.isEmpty else { return nil }
        return profile
    }

    private static func removeLegacyProfileStorage(
        from defaults: UserDefaults,
        secretReference: String? = nil,
        removeValidationTimestamp: Bool = true
    ) {
        let reference = secretReference ?? legacyStoredGatewayProfile(from: defaults)?.secretReference
        if let reference {
            _ = secureStore.clearLegacyAPIKey(reference: reference)
        }
        _ = secureStore.clearLegacyAPIKey()
        var legacyKeys = [
            gatewayProfileKey,
            apiKeyKey,
            gatewayURLKey,
            selectedModelKey,
            isConfiguredKey,
            grammarCorrectionVerifiedKey,
            grammarCorrectionContractVersionKey
        ]
        if removeValidationTimestamp {
            legacyKeys.append(gatewayConnectionLastTestedAtKey)
        }
        legacyKeys.forEach { defaults.removeObject(forKey: $0) }
        defaults.synchronize()
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

    @discardableResult
    func saveTestSeed(
        to defaults: UserDefaults,
        overwriteExistingRealConfig: Bool = false,
        mirrorAPIKeyToDefaultsForUITest: Bool = false
    ) -> Bool {
        guard overwriteExistingRealConfig || !AppConfig.hasExistingRealConfig(in: defaults) else {
            return false
        }
        if overwriteExistingRealConfig {
            guard AppConfig.secureStore.clearProfile() else { return false }
            AppConfig.removeLegacyProfileStorage(from: defaults)
        }

        let runtimeConfig = runtimeNormalized()
        let revision = UUID().uuidString.lowercased()
        let didSaveProfile = runtimeConfig.isConfigured && AppConfig.publishSecureProfile(
            for: runtimeConfig,
            revision: revision,
            lastValidatedAt: nil
        )
        if didSaveProfile {
            AppConfig.removeLegacyProfileStorage(from: defaults)
            AppConfig.publishProfileHint(revision: revision, to: defaults)
        } else if mirrorAPIKeyToDefaultsForUITest {
            // Explicit UI-test-only fallback for unsigned simulator processes that cannot share
            // Keychain access. Production save/load never publishes a split profile.
            defaults.set(apiKey, forKey: AppConfig.apiKeyKey)
            runtimeConfig.saveLegacyValuesForUITest(to: defaults)
        }

        guard didSaveProfile || mirrorAPIKeyToDefaultsForUITest else {
            AppConfig.clearKeyboardUITestConfigMetadata(from: defaults)
            return false
        }

        defaults.set(true, forKey: AppConfig.keyboardUITestConfigOriginKey)
        defaults.set(UUID().uuidString, forKey: AppConfig.keyboardUITestConfigSeedIDKey)
        defaults.set(Date().timeIntervalSince1970, forKey: AppConfig.keyboardUITestConfigSeededAtKey)
        defaults.synchronize()
        return true
    }

    private func saveLegacyValuesForUITest(to defaults: UserDefaults) {
        defaults.set(gatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(selectedModel, forKey: AppConfig.selectedModelKey)
        defaults.set(isConfigured, forKey: AppConfig.isConfiguredKey)
        defaults.set(grammarCorrectionVerified, forKey: AppConfig.grammarCorrectionVerifiedKey)
        defaults.set(grammarCorrectionContractVersion, forKey: AppConfig.grammarCorrectionContractVersionKey)
        defaults.synchronize()
    }

    static func hasExistingRealConfig(in defaults: UserDefaults) -> Bool {
        if let profile = storedGatewayProfile() {
            let candidate = profile.config.runtimeNormalized()
            return candidate.isConfigured
                && !candidate.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !candidate.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !candidate.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !candidate.isKnownTestPlaceholderConfig
                && !defaults.bool(forKey: keyboardUITestConfigOriginKey)
        }
        let candidate = legacyConfig(from: defaults).config

        return candidate.isConfigured
            && !candidate.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !candidate.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !candidate.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !candidate.isKnownTestPlaceholderConfig
            && !defaults.bool(forKey: keyboardUITestConfigOriginKey)
    }

    static func clearSharedConfig() {
        guard let sharedDefaults = sharedDefaults() else { return }
        clear(from: sharedDefaults)
    }

    static func resolvedGatewayModel(from availableModels: [String], currentModel: String = "") -> String? {
        gatewayModelCandidates(from: availableModels, currentModel: currentModel).first
    }

    static func gatewayModelCandidates(from availableModels: [String], currentModel: String = "") -> [String] {
        let models = availableModels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !models.isEmpty else { return [] }

        var candidates: [String] = []
        let current = currentModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let currentMatch = models.first(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            candidates.append(currentMatch)
        }

        if let appleFoundationModel = models.first(where: { $0.caseInsensitiveCompare("apple-foundationmodel") == .orderedSame }),
           !candidates.contains(where: { $0.caseInsensitiveCompare(appleFoundationModel) == .orderedSame }) {
            candidates.append(appleFoundationModel)
        }

        for model in models where !candidates.contains(where: { $0.caseInsensitiveCompare(model) == .orderedSame }) {
            candidates.append(model)
        }
        return candidates
    }

    static func gatewayConnectionError(from defaults: UserDefaults) -> String? {
        let value = defaults.string(forKey: gatewayConnectionErrorMessageKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    static func sharedGatewayConnectionError() -> String? {
        guard let defaults = sharedDefaults() else { return nil }
        return gatewayConnectionError(from: defaults)
    }

    static func gatewayConnectionLastTestedAt(from defaults: UserDefaults) -> Date? {
        if defaults.object(forKey: gatewayConnectionLastTestedAtKey) != nil {
            let timestamp = defaults.double(forKey: gatewayConnectionLastTestedAtKey)
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        if let timestamp = storedGatewayProfile()?.lastValidatedAt, timestamp > 0 {
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }

    static func saveGatewayConnectionLastTestedAt(_ date: Date = Date(), to defaults: UserDefaults? = sharedDefaults()) {
        guard let defaults else { return }
        if var profile = storedGatewayProfile() {
            profile.lastValidatedAt = date.timeIntervalSince1970
            if let data = try? JSONEncoder().encode(profile), secureStore.saveProfile(data) {
                defaults.removeObject(forKey: gatewayConnectionLastTestedAtKey)
                defaults.synchronize()
                return
            }
        }
        defaults.set(date.timeIntervalSince1970, forKey: gatewayConnectionLastTestedAtKey)
        defaults.synchronize()
    }

    static func clearGatewayConnectionLastTestedAt(from defaults: UserDefaults? = sharedDefaults()) {
        guard let defaults else { return }
        var didClearSecureTimestamp = true
        if var profile = storedGatewayProfile() {
            profile.lastValidatedAt = nil
            if let data = try? JSONEncoder().encode(profile) {
                didClearSecureTimestamp = secureStore.saveProfile(data)
            } else {
                didClearSecureTimestamp = false
            }
        }
        if didClearSecureTimestamp {
            defaults.removeObject(forKey: gatewayConnectionLastTestedAtKey)
        } else {
            // A non-sensitive fail-closed override prevents a stale secure validation timestamp
            // from suppressing the next explicit retry when Keychain is temporarily unavailable.
            defaults.set(0, forKey: gatewayConnectionLastTestedAtKey)
        }
        defaults.synchronize()
    }

    static func saveGatewayConnectionError(_ message: String, to defaults: UserDefaults? = sharedDefaults()) {
        guard let defaults else { return }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearGatewayConnectionError(from: defaults)
            return
        }
        defaults.set(trimmed, forKey: gatewayConnectionErrorMessageKey)
        defaults.set(Date().timeIntervalSince1970, forKey: gatewayConnectionErrorUpdatedAtKey)
        defaults.synchronize()
    }

    static func clearGatewayConnectionError(from defaults: UserDefaults? = sharedDefaults()) {
        guard let defaults else { return }
        defaults.removeObject(forKey: gatewayConnectionErrorMessageKey)
        defaults.removeObject(forKey: gatewayConnectionErrorUpdatedAtKey)
        defaults.synchronize()
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
        let gatewayHost: String
        let selectedModelPresent: Bool
        let selectedModel: String
        let profileConfiguredHint: Bool
        let legacyDefaultsAPIKeyPresent: Bool
        let keychainAPIKeyPresent: Bool
        let loadedConfigIsConfigured: Bool

        var redactedDescription: String {
            [
                "keyboardExtension.uiTestDebugStateEnabled=\(uiTestDebugStateEnabled)",
                "gatewayURLPresent=\(gatewayURLPresent)",
                "gatewayHost=\(gatewayHost)",
                "selectedModelPresent=\(selectedModelPresent)",
                "selectedModel=\(selectedModel)",
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
                gatewayHost: "shared-defaults-unavailable",
                selectedModelPresent: false,
                selectedModel: "missing",
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
        let keychainProfilePresent = storedGatewayProfile() != nil
        let legacyKeychainAPIKey = secureStore.loadLegacyAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return RedactedVisibilityDiagnostic(
            uiTestDebugStateEnabled: isUITestDebugStateEnabled(in: defaults),
            gatewayURLPresent: !rawGatewayURL.isEmpty,
            gatewayHost: redactedGatewayHost(from: rawGatewayURL),
            selectedModelPresent: !rawSelectedModel.isEmpty,
            selectedModel: rawSelectedModel.isEmpty ? "missing" : rawSelectedModel,
            profileConfiguredHint: defaults.bool(forKey: gatewayProfileConfiguredHintKey),
            legacyDefaultsAPIKeyPresent: !legacyDefaultsAPIKey.isEmpty,
            keychainAPIKeyPresent: keychainProfilePresent || !legacyKeychainAPIKey.isEmpty,
            loadedConfigIsConfigured: loadedConfig.isConfigured
        )
    }

    private static func redactedGatewayHost(from gatewayURL: String) -> String {
        guard !gatewayURL.isEmpty else { return "missing" }
        if let host = URL(string: gatewayURL)?.host, !host.isEmpty {
            return host
        }
        return "present-unparseable"
    }

    static func isUITestDebugStateEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled")
    }

    private static func hasFreshKeyboardExtensionUITestSeed(in defaults: UserDefaults) -> Bool {
        guard isUITestDebugStateEnabled(in: defaults) else { return false }
        let suggestionSeedID = defaults.string(forKey: "keyboardExtension.suggestionStateSeedID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let panelSeedID = defaults.string(forKey: "keyboardExtension.initialPanelModeSeedID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !suggestionSeedID.isEmpty,
              suggestionSeedID == panelSeedID,
              let suggestionSeededAt = defaults.object(forKey: "keyboardExtension.suggestionStateSeededAt") as? TimeInterval,
              let panelSeededAt = defaults.object(forKey: "keyboardExtension.initialPanelModeSeededAt") as? TimeInterval else {
            return false
        }
        let now = Date().timeIntervalSince1970
        let maximumSeedAge: TimeInterval = 30
        let maximumClockSkew: TimeInterval = 5
        return suggestionSeededAt >= now - maximumSeedAge &&
            suggestionSeededAt <= now + maximumClockSkew &&
            panelSeededAt >= now - maximumSeedAge &&
            panelSeededAt <= now + maximumClockSkew
    }

    private static func hasFreshKeyboardExtensionUITestConfigSeed(in defaults: UserDefaults) -> Bool {
        guard defaults.bool(forKey: keyboardUITestConfigOriginKey),
              isUITestDebugStateEnabled(in: defaults),
              !(defaults.string(forKey: keyboardUITestConfigSeedIDKey) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let seededAt = defaults.object(forKey: keyboardUITestConfigSeededAtKey) as? TimeInterval else {
            return false
        }
        let now = Date().timeIntervalSince1970
        return seededAt >= now - 30 && seededAt <= now + 5
    }

    private static func keyboardUITestConfigFingerprint(for config: AppConfig) -> String {
        [
            config.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            config.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ].joined(separator: "\u{1F}")
    }

    private static func consumeKeyboardExtensionUITestConfigSeed(from defaults: UserDefaults) {
        defaults.removeObject(forKey: keyboardUITestConfigSeedIDKey)
        defaults.removeObject(forKey: keyboardUITestConfigSeededAtKey)
        defaults.synchronize()
    }

    private static func clearKeyboardUITestConfigMetadata(from defaults: UserDefaults) {
        keyboardUITestConfigAuthorization.reset()
        defaults.removeObject(forKey: keyboardUITestConfigOriginKey)
        defaults.removeObject(forKey: keyboardUITestConfigSeedIDKey)
        defaults.removeObject(forKey: keyboardUITestConfigSeededAtKey)
        defaults.synchronize()
    }

    static func resetKeyboardUITestConfigProcessAuthorizationForTesting() {
        keyboardUITestConfigAuthorization.reset()
    }

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

    static func clear(from defaults: UserDefaults) {
        if let profile = legacyStoredGatewayProfile(from: defaults) {
            secureStore.clearLegacyAPIKey(reference: profile.secretReference)
        }
        secureStore.clearProfile()
        secureStore.clearLegacyAPIKey()
        [gatewayProfileKey, gatewayProfileConfiguredHintKey, gatewayProfileRevisionHintKey, apiKeyKey, gatewayURLKey, selectedModelKey, isConfiguredKey, grammarCorrectionVerifiedKey, grammarCorrectionContractVersionKey, gatewayConnectionErrorMessageKey, gatewayConnectionErrorUpdatedAtKey, gatewayConnectionLastTestedAtKey].forEach {
            defaults.removeObject(forKey: $0)
        }
        clearKeyboardUITestState(from: defaults)
        clearKeyboardUITestConfigMetadata(from: defaults)
    }
}

extension Notification.Name {
    static let openKeyboardOnboardingReset = Notification.Name("openKeyboardOnboardingReset")
}
