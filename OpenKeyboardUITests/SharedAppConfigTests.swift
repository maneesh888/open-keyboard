import Security
import XCTest

private enum RejectedGatewayFixture {
    static let gatewayURL = ["https://gateway", "example", "invalid"].joined(separator: ".")
    static let apiKey = ["test", "placeholder", "key"].joined(separator: "-")
    static let selectedModel = ["test", "placeholder", "model"].joined(separator: "-")
}

private final class InMemoryAppConfigSecureStore: AppConfigSecureStore {
    private(set) var profileData: Data?
    private var legacyAPIKey: String?
    private var referencedAPIKeys: [String: String] = [:]
    private(set) var clearIntent: AppConfigSecureClearIntent?
    var beforeProfileReplacement: (() -> Void)?
    var beforeProfileCreate: (() -> Void)?
    var beforeProfileClear: (() -> Void)?
    var beforeClearIntentRemoval: (() -> Void)?
    var profileReadResultOverride: AppConfigSecureStoreReadResult?
    var createResultOverride: AppConfigSecureStoreCreateResult?
    var clearIntentReadResultOverride: AppConfigSecureStoreClearIntentReadResult?
    var legacyAPIKeyReadResultOverride: AppConfigSecureStoreStringReadResult?
    var referencedLegacyAPIKeyReadResultOverrides: [String: AppConfigSecureStoreStringReadResult] = [:]
    var apiKey: String? {
        get { Self.apiKey(from: profileData) ?? legacyAPIKey }
        set { legacyAPIKey = newValue }
    }

    var shouldFailSave = false
    var shouldFailClearProfile = false
    var shouldFailSaveClearIntent = false
    var shouldFailClearClearIntent = false
    var shouldFailClearLegacyAPIKey = false
    var shouldFailClearReferencedLegacyAPIKey = false
    private(set) var saveProfileCallCount = 0
    private(set) var createProfileCallCount = 0
    private(set) var clearProfileCallCount = 0
    private(set) var saveClearIntentCallCount = 0
    private(set) var clearClearIntentCallCount = 0
    private(set) var saveLegacyAPIKeyCallCount = 0
    private(set) var clearLegacyAPIKeyCallCount = 0
    private(set) var clearReferencedLegacyAPIKeyCallCount = 0

    var totalMutationCallCount: Int {
        saveProfileCallCount
            + createProfileCallCount
            + clearProfileCallCount
            + saveClearIntentCallCount
            + clearClearIntentCallCount
            + saveLegacyAPIKeyCallCount
            + clearLegacyAPIKeyCallCount
            + clearReferencedLegacyAPIKeyCallCount
    }

    func loadProfile() -> Data? { profileData }

    func loadProfileResult() -> AppConfigSecureStoreReadResult {
        profileReadResultOverride ?? profileData.map(AppConfigSecureStoreReadResult.found) ?? .notFound
    }

    @discardableResult
    func saveProfile(_ profile: Data) -> Bool {
        saveProfileCallCount += 1
        guard !shouldFailSave else { return false }
        if profileData != nil {
            beforeProfileReplacement?()
        }
        profileData = profile
        return true
    }

    func createProfileIfAbsent(_ profile: Data) -> AppConfigSecureStoreCreateResult {
        createProfileCallCount += 1
        if let beforeProfileCreate {
            self.beforeProfileCreate = nil
            beforeProfileCreate()
        }
        if let createResultOverride { return createResultOverride }
        guard profileData == nil else { return .alreadyExists }
        guard !shouldFailSave else { return .unavailable }
        profileData = profile
        return .created
    }

    @discardableResult
    func clearProfile() -> Bool {
        clearProfileCallCount += 1
        guard !shouldFailClearProfile else { return false }
        beforeProfileClear?()
        profileData = nil
        return true
    }

    func loadClearIntentResult() -> AppConfigSecureStoreClearIntentReadResult {
        clearIntentReadResultOverride
            ?? clearIntent.map(AppConfigSecureStoreClearIntentReadResult.found)
            ?? .notFound
    }

    @discardableResult
    func saveClearIntent(_ intent: AppConfigSecureClearIntent) -> Bool {
        saveClearIntentCallCount += 1
        guard !shouldFailSaveClearIntent else { return false }
        clearIntent = intent
        return true
    }

    @discardableResult
    func clearClearIntent() -> Bool {
        clearClearIntentCallCount += 1
        guard !shouldFailClearClearIntent else { return false }
        beforeClearIntentRemoval?()
        clearIntent = nil
        return true
    }

    func loadLegacyAPIKey() -> String? {
        guard case .found(let value) = loadLegacyAPIKeyResult() else { return nil }
        return value
    }

    func loadLegacyAPIKey(reference: String) -> String? {
        guard case .found(let value) = loadLegacyAPIKeyResult(reference: reference) else {
            return nil
        }
        return value
    }

    func loadLegacyAPIKeyResult() -> AppConfigSecureStoreStringReadResult {
        legacyAPIKeyReadResultOverride
            ?? legacyAPIKey.map(AppConfigSecureStoreStringReadResult.found)
            ?? .notFound
    }

    func loadLegacyAPIKeyResult(reference: String) -> AppConfigSecureStoreStringReadResult {
        referencedLegacyAPIKeyReadResultOverrides[reference]
            ?? referencedAPIKeys[reference].map(AppConfigSecureStoreStringReadResult.found)
            ?? .notFound
    }

    @discardableResult
    func saveLegacyAPIKey(_ apiKey: String) -> Bool {
        saveLegacyAPIKeyCallCount += 1
        guard !shouldFailSave else { return false }
        legacyAPIKey = apiKey
        return true
    }

    func saveLegacyAPIKey(_ apiKey: String, reference: String) {
        saveLegacyAPIKeyCallCount += 1
        referencedAPIKeys[reference] = apiKey
    }

    @discardableResult
    func clearLegacyAPIKey() -> Bool {
        clearLegacyAPIKeyCallCount += 1
        guard !shouldFailClearLegacyAPIKey else { return false }
        legacyAPIKey = nil
        return true
    }

    @discardableResult
    func clearLegacyAPIKey(reference: String) -> Bool {
        clearReferencedLegacyAPIKeyCallCount += 1
        guard !shouldFailClearReferencedLegacyAPIKey else { return false }
        referencedAPIKeys.removeValue(forKey: reference)
        return true
    }

    func resetMutationCallCounts() {
        saveProfileCallCount = 0
        createProfileCallCount = 0
        clearProfileCallCount = 0
        saveClearIntentCallCount = 0
        clearClearIntentCallCount = 0
        saveLegacyAPIKeyCallCount = 0
        clearLegacyAPIKeyCallCount = 0
        clearReferencedLegacyAPIKeyCallCount = 0
    }

    private static func apiKey(from data: Data?) -> String? {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["apiKey"] as? String
    }
}

final class SharedAppConfigTests: XCTestCase {
    private let fixtureGatewayURL = "https://gateway.test.local"
    private let fixtureModel = "fixture-model"

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var secretStore: InMemoryAppConfigSecureStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "group.com.maneesh.openkeyboard.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        secretStore = InMemoryAppConfigSecureStore()
        AppConfig.secureStore = secretStore
        AppConfig.resetKeyboardUITestConfigProcessAuthorizationForTesting()
        AppConfig.setKeyboardUITestCurrentTimeForTesting(nil)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        secretStore = nil
        AppConfig.secureStore = KeychainAppConfigSecureStore()
        AppConfig.resetKeyboardUITestConfigProcessAuthorizationForTesting()
        AppConfig.setKeyboardUITestCurrentTimeForTesting(nil)
        try super.tearDownWithError()
    }

    func testProviderMetadataUsesCanonicalEditableDefaults() throws {
        let expectedProviders: [(OpenKeyboardAIProvider, String, String)] = [
            (.openAI, "OpenAI", "https://api.openai.com/v1"),
            (.anthropic, "Anthropic", "https://api.anthropic.com/v1"),
            (.openRouter, "OpenRouter", "https://openrouter.ai/api/v1"),
            (.openAICompatible, "OpenAI-compatible LLM Gateway", "https://")
        ]

        XCTAssertEqual(OpenKeyboardAIProvider.allCases.map(\.rawValue), [
            "openai",
            "anthropic",
            "openrouter",
            "openai-compatible"
        ])
        for (provider, displayName, defaultBaseURLString) in expectedProviders {
            XCTAssertEqual(provider.displayName, displayName)
            XCTAssertEqual(provider.defaultBaseURLString, defaultBaseURLString)
            if provider != .openAICompatible {
                XCTAssertEqual(try XCTUnwrap(provider.defaultBaseURL).absoluteString, defaultBaseURLString)
            }
        }

        var config = AppConfig.default
        XCTAssertEqual(config.provider, .openAICompatible)
        config.baseURL = "https://editable.example/v1"
        XCTAssertEqual(config.gatewayURL, "https://editable.example/v1")
        config.gatewayURL = "https://gateway-alias.example/v1"
        XCTAssertEqual(config.baseURL, "https://gateway-alias.example/v1")
    }

    func testAllProvidersRoundTripThroughSecureProfileAndRemainVisibleToExtension() throws {
        for provider in OpenKeyboardAIProvider.allCases {
            let baseURL = provider == .openAICompatible
                ? fixtureGatewayURL
                : provider.defaultBaseURLString
            let config = AppConfig(
                apiKey: "fake-\(provider.rawValue)-key",
                gatewayURL: baseURL,
                selectedModel: "model-\(provider.rawValue)",
                isConfigured: true,
                grammarCorrectionVerified: true,
                grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion,
                provider: provider
            )

            XCTAssertTrue(config.save(to: defaults))

            let secureData = try XCTUnwrap(secretStore.profileData)
            let secureObject = try XCTUnwrap(
                JSONSerialization.jsonObject(with: secureData) as? [String: Any]
            )
            XCTAssertEqual(secureObject["schemaVersion"] as? Int, 3)
            XCTAssertEqual(secureObject["provider"] as? String, provider.rawValue)
            XCTAssertEqual(secureObject["gatewayURL"] as? String, baseURL)
            XCTAssertEqual(secureObject["selectedModel"] as? String, config.selectedModel)

            // App and extension call the same loader against the shared App Group/Keychain pair.
            let extensionLoadedConfig = AppConfig.load(from: defaults)
            XCTAssertEqual(extensionLoadedConfig, config)
            XCTAssertEqual(extensionLoadedConfig.provider, provider)
            XCTAssertEqual(extensionLoadedConfig.baseURL, baseURL)
            XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        }
    }

    func testSchemaV2LoadsWithoutWritebackAndNextValidatedSavePersistsV3() throws {
        let validatedAt = Date(timeIntervalSince1970: 1_700_001_234)
        let legacyData = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2,
            "revision": "schema-v2-revision",
            "apiKey": "fake-schema-v2-key",
            "gatewayURL": "https://legacy-gateway.example/custom/path",
            "selectedModel": "legacy-model",
            "isConfigured": true,
            "grammarCorrectionVerified": true,
            "grammarCorrectionContractVersion": "legacy-trust-version",
            "lastValidatedAt": validatedAt.timeIntervalSince1970
        ])
        XCTAssertTrue(secretStore.saveProfile(legacyData))
        secretStore.resetMutationCallCounts()
        let defaultsBeforeLoad = defaults.dictionaryRepresentation()

        let extensionLoadedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(extensionLoadedConfig.provider, .openAICompatible)
        XCTAssertEqual(extensionLoadedConfig.apiKey, "fake-schema-v2-key")
        XCTAssertEqual(extensionLoadedConfig.gatewayURL, "https://legacy-gateway.example/custom/path")
        XCTAssertEqual(extensionLoadedConfig.selectedModel, "legacy-model")
        XCTAssertTrue(extensionLoadedConfig.isConfigured)
        XCTAssertTrue(extensionLoadedConfig.grammarCorrectionVerified)
        XCTAssertEqual(extensionLoadedConfig.grammarCorrectionContractVersion, "legacy-trust-version")
        XCTAssertEqual(AppConfig.gatewayConnectionLastTestedAt(from: defaults), validatedAt)
        XCTAssertEqual(secretStore.profileData, legacyData, "A read must not rewrite schema v2.")
        XCTAssertEqual(secretStore.totalMutationCallCount, 0)
        XCTAssertEqual(
            defaults.dictionaryRepresentation() as NSDictionary,
            defaultsBeforeLoad as NSDictionary,
            "A schema-v2 read must not mutate App Group metadata either."
        )

        let nextValidation = Date(timeIntervalSince1970: 1_700_002_345)
        XCTAssertTrue(extensionLoadedConfig.save(to: defaults, validatedAt: nextValidation))
        let migratedData = try XCTUnwrap(secretStore.profileData)
        let migratedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
        )
        XCTAssertEqual(migratedObject["schemaVersion"] as? Int, 3)
        XCTAssertNotEqual(migratedObject["revision"] as? String, "schema-v2-revision")
        XCTAssertEqual(migratedObject["provider"] as? String, OpenKeyboardAIProvider.openAICompatible.rawValue)
        XCTAssertEqual(migratedObject["apiKey"] as? String, "fake-schema-v2-key")
        XCTAssertEqual(migratedObject["gatewayURL"] as? String, "https://legacy-gateway.example/custom/path")
        XCTAssertEqual(migratedObject["selectedModel"] as? String, "legacy-model")
        XCTAssertEqual(migratedObject["grammarCorrectionVerified"] as? Bool, true)
        XCTAssertEqual(migratedObject["grammarCorrectionContractVersion"] as? String, "legacy-trust-version")
        XCTAssertEqual(migratedObject["lastValidatedAt"] as? TimeInterval, nextValidation.timeIntervalSince1970)
    }

    func testSchemaV2RepeatedLoadsRemainReadOnly() throws {
        let legacyData = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2,
            "revision": "schema-v2-retry-revision",
            "apiKey": "fake-schema-v2-retry-key",
            "gatewayURL": "https://legacy-retry.example/v1",
            "selectedModel": "legacy-retry-model",
            "isConfigured": true,
            "grammarCorrectionVerified": false,
            "grammarCorrectionContractVersion": "legacy-untrusted-version",
            "lastValidatedAt": 1_700_001_567
        ])
        XCTAssertTrue(secretStore.saveProfile(legacyData))

        let firstLoad = AppConfig.load(from: defaults)
        let secondLoad = AppConfig.load(from: defaults)

        XCTAssertEqual(firstLoad, secondLoad)
        XCTAssertEqual(firstLoad.provider, .openAICompatible)
        XCTAssertEqual(firstLoad.apiKey, "fake-schema-v2-retry-key")
        XCTAssertEqual(firstLoad.gatewayURL, "https://legacy-retry.example/v1")
        XCTAssertEqual(firstLoad.selectedModel, "legacy-retry-model")
        XCTAssertFalse(firstLoad.grammarCorrectionVerified)
        XCTAssertEqual(firstLoad.grammarCorrectionContractVersion, "legacy-untrusted-version")
        XCTAssertEqual(secretStore.profileData, legacyData)
        let preservedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: legacyData) as? [String: Any]
        )
        XCTAssertEqual(preservedObject["schemaVersion"] as? Int, 2)
        XCTAssertNil(preservedObject["provider"])
    }

    func testFunctionalSchemaV2ProfileRemainsCompatibleAfterAppGroupLoss() throws {
        let legacyData = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2,
            "revision": "schema-v2-origin-indistinguishable",
            "apiKey": "functional-schema-v2-key",
            "gatewayURL": "https://legacy-functional.example/v1",
            "selectedModel": "functional-schema-v2-model",
            "isConfigured": true,
            "grammarCorrectionVerified": false,
            "grammarCorrectionContractVersion": "",
            "lastValidatedAt": 1_700_001_890
        ])
        XCTAssertTrue(secretStore.saveProfile(legacyData))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.synchronize()
        secretStore.resetMutationCallCounts()

        let loaded = AppConfig.load(from: defaults)

        XCTAssertTrue(loaded.isConfigured)
        XCTAssertEqual(loaded.provider, .openAICompatible)
        XCTAssertEqual(loaded.apiKey, "functional-schema-v2-key")
        XCTAssertEqual(secretStore.profileData, legacyData)
        XCTAssertEqual(secretStore.totalMutationCallCount, 0)
        // Schema v2 did not encode test origin. After App Group loss, a functional legacy test
        // seed and a real legacy user profile are intentionally treated identically so installed
        // users retain access; simulator and physical-device Keychains are isolated.
    }

    func testLegacyCodableAppConfigWithoutProviderDefaultsToOpenAICompatible() throws {
        let legacyData = try JSONSerialization.data(withJSONObject: [
            "apiKey": "fake-codable-key",
            "gatewayURL": fixtureGatewayURL,
            "selectedModel": fixtureModel,
            "isConfigured": true,
            "grammarCorrectionVerified": false,
            "grammarCorrectionContractVersion": ""
        ])

        let decoded = try JSONDecoder().decode(AppConfig.self, from: legacyData)

        XCTAssertEqual(decoded.provider, .openAICompatible)
        let reencodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        )
        XCTAssertEqual(reencodedObject["provider"] as? String, OpenKeyboardAIProvider.openAICompatible.rawValue)
    }

    func testPersistedGatewayConnectionErrorsAreSanitized() {
        let rawError = "Authorization: Bearer fake-private-token"

        AppConfig.saveGatewayConnectionError(rawError, to: defaults)

        let storedError = defaults.string(forKey: AppConfig.gatewayConnectionErrorMessageKey)
        XCTAssertEqual(storedError, "Gateway request failed. Check settings and try again.")
        XCTAssertFalse(storedError?.contains("fake-private-token") ?? true)
        XCTAssertEqual(AppConfig.gatewayConnectionError(from: defaults), storedError)

        defaults.set(rawError, forKey: AppConfig.gatewayConnectionErrorMessageKey)
        XCTAssertEqual(
            AppConfig.gatewayConnectionError(from: defaults),
            "Gateway request failed. Check settings and try again."
        )
        XCTAssertNotEqual(defaults.string(forKey: AppConfig.gatewayConnectionErrorMessageKey), rawError)
    }

    func testGatewayConnectionErrorForStaleProfileRevisionIsIgnored() throws {
        let profileA = AppConfig(
            apiKey: "profile-a-key",
            gatewayURL: "https://profile-a.example",
            selectedModel: "profile-a-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(profileA.save(to: defaults))
        AppConfig.saveGatewayConnectionError("Profile A failed.", to: defaults)
        let revisionA = try XCTUnwrap(
            defaults.string(forKey: AppConfig.gatewayConnectionErrorProfileRevisionKey)
        )
        XCTAssertEqual(AppConfig.gatewayConnectionError(from: defaults), "Profile A failed.")

        var profileB = profileA
        profileB.apiKey = "profile-b-key"
        XCTAssertTrue(profileB.save(to: defaults))
        let revisionB = try XCTUnwrap(
            defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey)
        )

        XCTAssertNotEqual(revisionA, revisionB)
        XCTAssertNil(AppConfig.gatewayConnectionError(from: defaults))
        XCTAssertEqual(
            defaults.string(forKey: AppConfig.gatewayConnectionErrorMessageKey),
            "Profile A failed.",
            "The stale record may remain for cleanup, but it must not affect the active profile."
        )
    }

    func testValidationMetadataIsRevisionBoundAndNeverRewritesSecureProfile() throws {
        let profileA = AppConfig(
            apiKey: "validation-a-key",
            gatewayURL: "https://validation.example",
            selectedModel: "validation-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(profileA.save(to: defaults))
        let testedAt = Date(timeIntervalSince1970: 1_700_010_000)
        let secureDataBeforeTimestamp = try XCTUnwrap(secretStore.profileData)

        AppConfig.saveGatewayConnectionLastTestedAt(testedAt, to: defaults)

        XCTAssertEqual(secretStore.profileData, secureDataBeforeTimestamp)
        XCTAssertEqual(AppConfig.gatewayConnectionLastTestedAt(from: defaults), testedAt)

        var profileB = profileA
        profileB.apiKey = "validation-b-key"
        XCTAssertTrue(profileB.save(to: defaults))
        XCTAssertNil(
            AppConfig.gatewayConnectionLastTestedAt(from: defaults),
            "Profile A validation must not carry into profile B's revision."
        )

        let profileBTestedAt = Date(timeIntervalSince1970: 1_700_010_100)
        XCTAssertTrue(profileB.save(to: defaults, validatedAt: profileBTestedAt))
        XCTAssertEqual(AppConfig.gatewayConnectionLastTestedAt(from: defaults), profileBTestedAt)

        let secureDataBeforeUnavailableClear = try XCTUnwrap(secretStore.profileData)
        secretStore.profileReadResultOverride = .unavailable
        AppConfig.clearGatewayConnectionLastTestedAt(from: defaults)
        XCTAssertEqual(secretStore.profileData, secureDataBeforeUnavailableClear)
        secretStore.profileReadResultOverride = nil
        XCTAssertNil(AppConfig.gatewayConnectionLastTestedAt(from: defaults))
    }

    func testEquivalentSavePreservesSecureBytesRevisionValidationAndBoundError() throws {
        let testedAt = Date(timeIntervalSince1970: 1_700_015_000)
        let profile = AppConfig(
            apiKey: "idempotent-profile-key",
            gatewayURL: "https://idempotent.example",
            selectedModel: "idempotent-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(profile.save(to: defaults, validatedAt: testedAt))
        AppConfig.saveGatewayConnectionError(
            "The saved profile is temporarily unavailable.",
            to: defaults,
            notifyActiveProfileChange: false
        )
        let secureDataBeforeDone = try XCTUnwrap(secretStore.profileData)
        let revisionBeforeDone = try XCTUnwrap(
            defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey)
        )
        let errorRevisionBeforeDone = try XCTUnwrap(
            defaults.string(forKey: AppConfig.gatewayConnectionErrorProfileRevisionKey)
        )
        secretStore.resetMutationCallCounts()

        XCTAssertTrue(
            profile.save(
                to: defaults,
                notifyActiveProfileChange: false
            )
        )

        XCTAssertEqual(secretStore.saveProfileCallCount, 0)
        XCTAssertEqual(secretStore.profileData, secureDataBeforeDone)
        XCTAssertEqual(
            defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey),
            revisionBeforeDone
        )
        XCTAssertEqual(
            defaults.string(forKey: AppConfig.gatewayConnectionErrorProfileRevisionKey),
            errorRevisionBeforeDone
        )
        XCTAssertEqual(revisionBeforeDone, errorRevisionBeforeDone)
        XCTAssertEqual(AppConfig.gatewayConnectionLastTestedAt(from: defaults), testedAt)
        XCTAssertEqual(
            AppConfig.gatewayConnectionError(from: defaults),
            "The saved profile is temporarily unavailable."
        )
    }

    func testStaleRevisionBoundTimestampNeverFallsBackToRetainedSecureTimestamp() throws {
        let secureTimestamp = Date(timeIntervalSince1970: 1_700_020_000)
        let profile = AppConfig(
            apiKey: "timestamp-profile-key",
            gatewayURL: "https://timestamp.example",
            selectedModel: "timestamp-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(profile.save(to: defaults, validatedAt: secureTimestamp))
        let activeRevision = try XCTUnwrap(
            defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey)
        )
        defaults.set(
            secureTimestamp.addingTimeInterval(60).timeIntervalSince1970,
            forKey: AppConfig.gatewayConnectionLastTestedAtKey
        )
        defaults.set(
            "stale-" + activeRevision,
            forKey: AppConfig.gatewayConnectionLastTestedAtProfileRevisionKey
        )

        XCTAssertNil(
            AppConfig.gatewayConnectionLastTestedAt(from: defaults),
            "A retained secure timestamp must not become trusted behind mismatched App Group metadata."
        )
    }

    func testMainAppSaveStoresCompleteProfileInOneSecureItemForBothTargets() throws {
        let mainAppConfig = AppConfig(
            apiKey: "fake-shared-test-token",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        XCTAssertTrue(mainAppConfig.save(to: defaults))

        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.selectedModelKey))
        XCTAssertFalse(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertTrue(defaults.bool(forKey: AppConfig.gatewayProfileConfiguredHintKey))
        XCTAssertFalse((defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey) ?? "").isEmpty)
        XCTAssertEqual(secretStore.apiKey, "fake-shared-test-token")

        let extensionLoadedConfig = AppConfig.load(from: defaults)
        XCTAssertEqual(extensionLoadedConfig.gatewayURL, fixtureGatewayURL)
        XCTAssertEqual(extensionLoadedConfig.apiKey, "fake-shared-test-token")
        XCTAssertEqual(extensionLoadedConfig.selectedModel, fixtureModel)
        XCTAssertTrue(extensionLoadedConfig.isConfigured)
        XCTAssertTrue(extensionLoadedConfig.supportsStructuredCorrections)
        XCTAssertEqual(extensionLoadedConfig.structuredCorrectionSchemaVersion, "openkeyboard.structured-corrections.v1")
    }

    func testConfiguredStateRequiresAPIKeyVisibleToExtensionRuntime() throws {
        defaults.set(fixtureGatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(fixtureModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        defaults.set(true, forKey: AppConfig.supportsStructuredCorrectionsKey)
        defaults.set("openkeyboard.structured-corrections.v1", forKey: AppConfig.structuredCorrectionSchemaVersionKey)

        let extensionLoadedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(extensionLoadedConfig.gatewayURL, fixtureGatewayURL)
        XCTAssertEqual(extensionLoadedConfig.selectedModel, fixtureModel)
        XCTAssertEqual(extensionLoadedConfig.apiKey, "")
        XCTAssertFalse(extensionLoadedConfig.isConfigured)
        XCTAssertFalse(extensionLoadedConfig.supportsStructuredCorrections)
        XCTAssertEqual(extensionLoadedConfig.structuredCorrectionSchemaVersion, "")
    }

    func testSchemaCurrentSecureProfileWithoutSelectedModelFailsClosedForBothTargets() throws {
        let incompleteProfile: [String: Any] = [
            "schemaVersion": 3,
            "revision": "incomplete-current-profile",
            "provider": OpenKeyboardAIProvider.openAI.rawValue,
            "apiKey": "fake-shared-test-token",
            "gatewayURL": fixtureGatewayURL,
            "selectedModel": "",
            "isConfigured": true,
            "grammarCorrectionVerified": true,
            "grammarCorrectionContractVersion": AppConfig.grammarCorrectionCapabilityVersion,
            "lastValidatedAt": Date().timeIntervalSince1970
        ]
        XCTAssertTrue(secretStore.saveProfile(try JSONSerialization.data(withJSONObject: incompleteProfile)))
        defaults.set(true, forKey: AppConfig.gatewayProfileConfiguredHintKey)
        defaults.set("incomplete-current-profile", forKey: AppConfig.gatewayProfileRevisionHintKey)

        let hostLoadedConfig = AppConfig.load(from: defaults)
        let extensionLoadedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(hostLoadedConfig, .default)
        XCTAssertEqual(extensionLoadedConfig, .default)
        XCTAssertFalse(hostLoadedConfig.isConfigured)
        XCTAssertFalse(extensionLoadedConfig.isConfigured)
        XCTAssertFalse(hostLoadedConfig.hasGatewayRuntimeConfig)
        XCTAssertFalse(extensionLoadedConfig.hasGatewayRuntimeConfig)
    }

    func testConfiguredGatewayPreservesMissingModelAsDistinctRuntimeState() {
        secretStore.apiKey = "fake-shared-test-token"
        defaults.set(fixtureGatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set("", forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        defaults.set(false, forKey: AppConfig.supportsStructuredCorrectionsKey)

        let extensionLoadedConfig = AppConfig.load(from: defaults)

        XCTAssertTrue(extensionLoadedConfig.isConfigured)
        XCTAssertTrue(extensionLoadedConfig.hasGatewayRuntimeConfig)
        XCTAssertFalse(extensionLoadedConfig.hasCompleteGatewayRuntimeConfig)
        XCTAssertEqual(extensionLoadedConfig.selectedModel, "")
    }

    func testMainAppSaveDoesNotPublishConfiguredStateWhenSecretStoreSaveFails() throws {
        secretStore.shouldFailSave = true
        let mainAppConfig = AppConfig(
            apiKey: "fake-shared-test-token",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        XCTAssertFalse(mainAppConfig.save(to: defaults))

        let extensionLoadedConfig = AppConfig.load(from: defaults)
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertNil(secretStore.apiKey)
        XCTAssertEqual(extensionLoadedConfig.gatewayURL, "")
        XCTAssertEqual(extensionLoadedConfig.selectedModel, "")
        XCTAssertEqual(extensionLoadedConfig.apiKey, "")
        XCTAssertFalse(extensionLoadedConfig.isConfigured)
        XCTAssertFalse(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertFalse(extensionLoadedConfig.supportsStructuredCorrections)
    }

    func testFailedReplacementSavePreservesCompletePreviousSecureProfile() throws {
        let previous = AppConfig(
            apiKey: "previous-secret",
            gatewayURL: "https://previous.example",
            selectedModel: "previous-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(previous.save(to: defaults))
        let previousRevisionHint = defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey)
        secretStore.shouldFailSave = true

        let replacement = AppConfig(
            apiKey: "replacement-secret",
            gatewayURL: "https://replacement.example",
            selectedModel: "replacement-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )

        XCTAssertFalse(replacement.save(to: defaults))

        let loaded = AppConfig.load(from: defaults)
        XCTAssertEqual(loaded.apiKey, previous.apiKey)
        XCTAssertEqual(loaded.gatewayURL, previous.gatewayURL)
        XCTAssertEqual(loaded.selectedModel, previous.selectedModel)
        XCTAssertTrue(loaded.isConfigured)
        XCTAssertTrue(loaded.grammarCorrectionVerified)
        XCTAssertEqual(loaded.grammarCorrectionContractVersion, previous.grammarCorrectionContractVersion)
        XCTAssertEqual(defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey), previousRevisionHint)
    }

    func testMalformedConfiguredReplacementPreservesCompletePreviousSecureProfile() throws {
        let previous = AppConfig(
            apiKey: "previous-secret",
            gatewayURL: "https://previous.example",
            selectedModel: "previous-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(previous.save(to: defaults))
        let previousProfileData = try XCTUnwrap(secretStore.profileData)
        let previousRevisionHint = defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey)

        let malformedReplacement = AppConfig(
            apiKey: "",
            gatewayURL: "https://replacement.example",
            selectedModel: "replacement-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )

        XCTAssertFalse(malformedReplacement.save(to: defaults))
        XCTAssertEqual(secretStore.profileData, previousProfileData)
        XCTAssertEqual(defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey), previousRevisionHint)
        XCTAssertEqual(AppConfig.load(from: defaults), previous)
    }

    func testAtomicSecureProfileReplacementExposesOnlyCompleteOldOrNewRevision() throws {
        let previousDate = Date(timeIntervalSince1970: 1_700_000_000)
        let previous = AppConfig(
            apiKey: "previous-secret",
            gatewayURL: "https://previous.example",
            selectedModel: "previous-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(previous.save(to: defaults, validatedAt: previousDate))

        let replacementDate = Date(timeIntervalSince1970: 1_700_000_123)
        let replacement = AppConfig(
            apiKey: "replacement-secret",
            gatewayURL: "https://replacement.example",
            selectedModel: "replacement-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        var observedDuringReplacement: AppConfig?
        secretStore.beforeProfileReplacement = {
            observedDuringReplacement = AppConfig.load(from: self.defaults)
        }
        XCTAssertTrue(replacement.save(to: defaults, validatedAt: replacementDate))

        XCTAssertEqual(observedDuringReplacement, previous)

        let committed = AppConfig.load(from: defaults)
        XCTAssertEqual(committed.apiKey, replacement.apiKey)
        XCTAssertEqual(committed.gatewayURL, replacement.gatewayURL)
        XCTAssertEqual(committed.selectedModel, replacement.selectedModel)
        XCTAssertTrue(committed.grammarCorrectionVerified)
        XCTAssertEqual(AppConfig.gatewayConnectionLastTestedAt(from: defaults), replacementDate)
    }

    func testLegacyDefaultsProfileMigratesToAtomicSecureProfileAndIsRemovedFromDefaults() throws {
        defaults.set("fake-legacy-test-token", forKey: AppConfig.apiKeyKey)
        defaults.set(fixtureGatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(fixtureModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)

        let migratedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(migratedConfig.apiKey, "fake-legacy-test-token")
        XCTAssertEqual(secretStore.apiKey, "fake-legacy-test-token")
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertEqual(migratedConfig.gatewayURL, fixtureGatewayURL)
        XCTAssertEqual(migratedConfig.selectedModel, fixtureModel)
        XCTAssertTrue(migratedConfig.isConfigured)
        XCTAssertFalse(migratedConfig.supportsStructuredCorrections)
        XCTAssertEqual(migratedConfig.structuredCorrectionSchemaVersion, "")
    }

    func testVersionedSplitProfileMigratesToOneSecureEnvelopeWithoutLosingValidationState() throws {
        let reference = "legacy-profile-reference"
        let validatedAt = Date(timeIntervalSince1970: 1_700_000_456)
        secretStore.saveLegacyAPIKey("legacy-referenced-key", reference: reference)
        let legacyProfile = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "secretReference": reference,
            "gatewayURL": fixtureGatewayURL,
            "selectedModel": fixtureModel,
            "isConfigured": true,
            "grammarCorrectionVerified": true,
            "grammarCorrectionContractVersion": AppConfig.grammarCorrectionCapabilityVersion,
            "lastValidatedAt": validatedAt.timeIntervalSince1970
        ])
        defaults.set(legacyProfile, forKey: AppConfig.gatewayProfileKey)

        let migratedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(migratedConfig.apiKey, "legacy-referenced-key")
        XCTAssertEqual(migratedConfig.gatewayURL, fixtureGatewayURL)
        XCTAssertEqual(migratedConfig.selectedModel, fixtureModel)
        XCTAssertTrue(migratedConfig.grammarCorrectionVerified)
        XCTAssertEqual(AppConfig.gatewayConnectionLastTestedAt(from: defaults), validatedAt)
        XCTAssertNil(defaults.data(forKey: AppConfig.gatewayProfileKey))
        XCTAssertNil(secretStore.loadLegacyAPIKey(reference: reference))
        XCTAssertEqual(secretStore.apiKey, "legacy-referenced-key")
        XCTAssertTrue(defaults.bool(forKey: AppConfig.gatewayProfileConfiguredHintKey))
    }

    func testVersionedSplitProfileIsPreservedWhenAtomicSecureMigrationFails() throws {
        let reference = "legacy-profile-failed-migration-reference"
        secretStore.saveLegacyAPIKey("legacy-referenced-key", reference: reference)
        let legacyProfile = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "secretReference": reference,
            "gatewayURL": fixtureGatewayURL,
            "selectedModel": fixtureModel,
            "isConfigured": true,
            "grammarCorrectionVerified": true,
            "grammarCorrectionContractVersion": AppConfig.grammarCorrectionCapabilityVersion,
            "lastValidatedAt": 1_700_000_789
        ])
        defaults.set(legacyProfile, forKey: AppConfig.gatewayProfileKey)
        secretStore.shouldFailSave = true

        let loadedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(loadedConfig.apiKey, "legacy-referenced-key")
        XCTAssertEqual(loadedConfig.gatewayURL, fixtureGatewayURL)
        XCTAssertEqual(loadedConfig.selectedModel, fixtureModel)
        XCTAssertTrue(loadedConfig.isConfigured)
        XCTAssertEqual(defaults.data(forKey: AppConfig.gatewayProfileKey), legacyProfile)
        XCTAssertEqual(secretStore.loadLegacyAPIKey(reference: reference), "legacy-referenced-key")
        XCTAssertNil(secretStore.loadProfile())
        XCTAssertFalse(defaults.bool(forKey: AppConfig.gatewayProfileConfiguredHintKey))
    }

    func testLegacyDefaultsProfileIsPreservedWhenSecureMigrationFails() throws {
        secretStore.shouldFailSave = true
        defaults.set("fake-legacy-test-token", forKey: AppConfig.apiKeyKey)
        defaults.set(fixtureGatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(fixtureModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)

        let loadedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(loadedConfig.apiKey, "fake-legacy-test-token")
        XCTAssertEqual(loadedConfig.gatewayURL, fixtureGatewayURL)
        XCTAssertEqual(loadedConfig.selectedModel, fixtureModel)
        XCTAssertTrue(loadedConfig.isConfigured)
        XCTAssertNil(secretStore.apiKey)
        XCTAssertEqual(defaults.string(forKey: AppConfig.apiKeyKey), "fake-legacy-test-token")
        XCTAssertEqual(defaults.string(forKey: AppConfig.gatewayURLKey), fixtureGatewayURL)
        XCTAssertEqual(defaults.string(forKey: AppConfig.selectedModelKey), fixtureModel)
        XCTAssertTrue(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertEqual(secretStore.createProfileCallCount, 1)
    }

    func testUnavailableSecureReadDoesNotFallBackOrAttemptLegacyMigration() {
        defaults.set("legacy-key", forKey: AppConfig.apiKeyKey)
        defaults.set(fixtureGatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(fixtureModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        secretStore.profileReadResultOverride = .unavailable

        let loaded = AppConfig.load(from: defaults)

        XCTAssertEqual(loaded, .default)
        XCTAssertEqual(secretStore.createProfileCallCount, 0)
        XCTAssertEqual(defaults.string(forKey: AppConfig.apiKeyKey), "legacy-key")
    }

    func testUnavailableUnversionedLegacyKeyDoesNotUsePlaintextDefaultsOrMigrate() {
        defaults.set("stale-plaintext-key", forKey: AppConfig.apiKeyKey)
        defaults.set(fixtureGatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(fixtureModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        secretStore.legacyAPIKeyReadResultOverride = .unavailable

        let loaded = AppConfig.load(from: defaults)

        XCTAssertEqual(loaded, .default)
        XCTAssertNil(secretStore.profileData)
        XCTAssertEqual(secretStore.createProfileCallCount, 0)
        XCTAssertEqual(defaults.string(forKey: AppConfig.apiKeyKey), "stale-plaintext-key")
    }

    func testUnavailableReferencedLegacyKeyDoesNotUsePlaintextDefaultsOrMigrate() throws {
        let reference = "unavailable-legacy-reference"
        let legacyProfile = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "secretReference": reference,
            "gatewayURL": fixtureGatewayURL,
            "selectedModel": fixtureModel,
            "isConfigured": true,
            "grammarCorrectionVerified": true,
            "grammarCorrectionContractVersion": AppConfig.grammarCorrectionCapabilityVersion
        ])
        defaults.set(legacyProfile, forKey: AppConfig.gatewayProfileKey)
        defaults.set("stale-plaintext-key", forKey: AppConfig.apiKeyKey)
        secretStore.referencedLegacyAPIKeyReadResultOverrides[reference] = .unavailable

        let loaded = AppConfig.load(from: defaults)

        XCTAssertEqual(loaded, .default)
        XCTAssertNil(secretStore.profileData)
        XCTAssertEqual(secretStore.createProfileCallCount, 0)
        XCTAssertEqual(defaults.data(forKey: AppConfig.gatewayProfileKey), legacyProfile)
        XCTAssertEqual(defaults.string(forKey: AppConfig.apiKeyKey), "stale-plaintext-key")
    }

    func testConcurrentSecureCreateWinsLegacyMigrationWithoutBeingOverwritten() throws {
        let winner = AppConfig(
            apiKey: "winner-key",
            gatewayURL: "https://winner.example",
            selectedModel: "winner-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion,
            provider: .anthropic
        )
        XCTAssertTrue(winner.save(to: defaults))
        let winnerData = try XCTUnwrap(secretStore.profileData)
        XCTAssertTrue(secretStore.clearProfile())
        defaults.removeObject(forKey: AppConfig.gatewayProfileConfiguredHintKey)
        defaults.removeObject(forKey: AppConfig.gatewayProfileRevisionHintKey)
        defaults.set("losing-legacy-key", forKey: AppConfig.apiKeyKey)
        defaults.set("https://losing-legacy.example", forKey: AppConfig.gatewayURLKey)
        defaults.set("losing-legacy-model", forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        secretStore.beforeProfileCreate = {
            XCTAssertTrue(self.secretStore.saveProfile(winnerData))
        }

        let loaded = AppConfig.load(from: defaults)

        XCTAssertEqual(loaded, winner)
        XCTAssertEqual(secretStore.profileData, winnerData)
        XCTAssertEqual(secretStore.createProfileCallCount, 1)
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
    }

    func testVersionedLegacyDeletionFailureRemovesPlaintextAndRetainsOnlyRetryReference() throws {
        let reference = "legacy-retry-reference"
        secretStore.saveLegacyAPIKey("legacy-retry-key", reference: reference)
        let legacyProfile = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "secretReference": reference,
            "gatewayURL": fixtureGatewayURL,
            "selectedModel": fixtureModel,
            "isConfigured": true,
            "grammarCorrectionVerified": true,
            "grammarCorrectionContractVersion": AppConfig.grammarCorrectionCapabilityVersion
        ])
        defaults.set(legacyProfile, forKey: AppConfig.gatewayProfileKey)
        defaults.set("stale-plaintext-copy", forKey: AppConfig.apiKeyKey)
        defaults.set(fixtureGatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(fixtureModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        secretStore.shouldFailClearReferencedLegacyAPIKey = true

        XCTAssertTrue(AppConfig.load(from: defaults).isConfigured)
        XCTAssertNil(defaults.data(forKey: AppConfig.gatewayProfileKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.selectedModelKey))
        XCTAssertFalse(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertEqual(
            defaults.string(forKey: AppConfig.gatewayLegacySecretCleanupReferenceKey),
            reference
        )
        XCTAssertEqual(secretStore.loadLegacyAPIKey(reference: reference), "legacy-retry-key")
        XCTAssertEqual(secretStore.clearReferencedLegacyAPIKeyCallCount, 1)

        secretStore.shouldFailClearReferencedLegacyAPIKey = false
        XCTAssertTrue(AppConfig.load(from: defaults).isConfigured)
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayLegacySecretCleanupReferenceKey))
        XCTAssertNil(secretStore.loadLegacyAPIKey(reference: reference))
        XCTAssertEqual(secretStore.clearReferencedLegacyAPIKeyCallCount, 2)
    }

    func testUnversionedLegacyDeletionFailureRetainsOnlyNonsecretRetryTombstone() throws {
        secretStore.apiKey = "legacy-unversioned-retry-key"
        defaults.set("legacy-unversioned-retry-key", forKey: AppConfig.apiKeyKey)
        defaults.set(fixtureGatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(fixtureModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        secretStore.shouldFailClearLegacyAPIKey = true

        XCTAssertTrue(AppConfig.load(from: defaults).isConfigured)

        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.selectedModelKey))
        XCTAssertTrue(
            defaults.bool(forKey: AppConfig.gatewayLegacyUnversionedSecretCleanupPendingKey)
        )
        XCTAssertEqual(secretStore.loadLegacyAPIKey(), "legacy-unversioned-retry-key")

        secretStore.shouldFailClearLegacyAPIKey = false
        XCTAssertTrue(AppConfig.load(from: defaults).isConfigured)
        XCTAssertFalse(
            defaults.bool(forKey: AppConfig.gatewayLegacyUnversionedSecretCleanupPendingKey)
        )
        XCTAssertNil(secretStore.loadLegacyAPIKey())
    }


    func testKnownUITestPlaceholderConfigIsRejectedOutsideUITestingLaunch() throws {
        secretStore.apiKey = RejectedGatewayFixture.apiKey
        defaults.set(RejectedGatewayFixture.gatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(RejectedGatewayFixture.selectedModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        defaults.set(true, forKey: AppConfig.supportsStructuredCorrectionsKey)
        defaults.set("openkeyboard.structured-corrections.v1", forKey: AppConfig.structuredCorrectionSchemaVersionKey)

        let loadedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(loadedConfig.apiKey, "")
        XCTAssertEqual(loadedConfig.gatewayURL, "")
        XCTAssertEqual(loadedConfig.selectedModel, "")
        XCTAssertFalse(loadedConfig.isConfigured)
        XCTAssertFalse(loadedConfig.supportsStructuredCorrections)
        XCTAssertEqual(loadedConfig.structuredCorrectionSchemaVersion, "")
        XCTAssertEqual(secretStore.apiKey, RejectedGatewayFixture.apiKey)
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.selectedModelKey))
        XCTAssertFalse(defaults.bool(forKey: AppConfig.isConfiguredKey))
    }


    func testRedactedVisibilityDiagnosticReportsPresenceWithoutLeakingPrivateConfig() throws {
        let rawAPIKey = "super-secret-test-key"
        let rawBaseURL = "https://gateway.test.local/v1"
        let rawGatewayHost = "gateway.test.local"
        let rawModel = "safe-model"
        secretStore.apiKey = rawAPIKey
        defaults.set(rawBaseURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(rawModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")

        let diagnostic = AppConfig.redactedVisibilityDiagnostic(from: defaults)
        let description = diagnostic.redactedDescription

        XCTAssertTrue(diagnostic.uiTestDebugStateEnabled)
        XCTAssertTrue(diagnostic.gatewayURLPresent)
        XCTAssertTrue(diagnostic.selectedModelPresent)
        XCTAssertTrue(diagnostic.keychainAPIKeyPresent)
        XCTAssertFalse(diagnostic.legacyDefaultsAPIKeyPresent)
        XCTAssertTrue(diagnostic.loadedConfigIsConfigured)
        XCTAssertFalse(description.contains(rawAPIKey))
        XCTAssertFalse(description.contains(rawBaseURL))
        XCTAssertFalse(description.contains(rawGatewayHost))
        XCTAssertFalse(description.contains(rawModel))
    }

    func testKnownUITestPlaceholderConfigIsAcceptedOnlyWithFreshExtensionSeed() throws {
        secretStore.apiKey = RejectedGatewayFixture.apiKey
        defaults.set(RejectedGatewayFixture.gatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(RejectedGatewayFixture.selectedModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        defaults.set(true, forKey: AppConfig.supportsStructuredCorrectionsKey)
        defaults.set("openkeyboard.structured-corrections.v1", forKey: AppConfig.structuredCorrectionSchemaVersionKey)
        seedFreshKeyboardExtensionUITestState()

        let loadedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(loadedConfig.apiKey, RejectedGatewayFixture.apiKey)
        XCTAssertEqual(loadedConfig.gatewayURL, RejectedGatewayFixture.gatewayURL)
        XCTAssertEqual(loadedConfig.selectedModel, RejectedGatewayFixture.selectedModel)
        XCTAssertTrue(loadedConfig.isConfigured)
        XCTAssertTrue(loadedConfig.supportsStructuredCorrections)
        XCTAssertEqual(loadedConfig.structuredCorrectionSchemaVersion, "openkeyboard.structured-corrections.v1")

        [
            "keyboardExtension.suggestionState",
            "keyboardExtension.suggestionStateSeedID",
            "keyboardExtension.suggestionStateSeededAt",
            "keyboardExtension.initialPanelMode",
            "keyboardExtension.initialPanelModeSeedID",
            "keyboardExtension.initialPanelModeSeededAt"
        ].forEach { defaults.removeObject(forKey: $0) }

        AppConfig.resetKeyboardUITestConfigProcessAuthorizationForTesting()
        let afterSeedConsumption = AppConfig.load(from: defaults)
        XCTAssertFalse(afterSeedConsumption.isConfigured)
        XCTAssertTrue(afterSeedConsumption.gatewayURL.isEmpty)
        XCTAssertTrue(afterSeedConsumption.selectedModel.isEmpty)
    }

    func testKnownUITestPlaceholderConfigIsRejectedWhenOnlyStaleDebugFlagRemains() throws {
        secretStore.apiKey = RejectedGatewayFixture.apiKey
        defaults.set(RejectedGatewayFixture.gatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(RejectedGatewayFixture.selectedModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")

        let loadedConfig = AppConfig.load(from: defaults)

        XCTAssertFalse(loadedConfig.isConfigured)
        XCTAssertTrue(loadedConfig.apiKey.isEmpty)
        XCTAssertTrue(loadedConfig.gatewayURL.isEmpty)
        XCTAssertTrue(loadedConfig.selectedModel.isEmpty)
        XCTAssertEqual(secretStore.apiKey, RejectedGatewayFixture.apiKey)
        XCTAssertTrue(defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled"))
    }

    func testKnownUITestPlaceholderConfigIsRejectedAfterKeyboardSeedConsumptionWindow() throws {
        secretStore.apiKey = RejectedGatewayFixture.apiKey
        defaults.set(RejectedGatewayFixture.gatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(RejectedGatewayFixture.selectedModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        let seedID = UUID().uuidString
        let expiredSeededAt = Date().timeIntervalSince1970 - 31
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        defaults.set(seedID, forKey: "keyboardExtension.suggestionStateSeedID")
        defaults.set(expiredSeededAt, forKey: "keyboardExtension.suggestionStateSeededAt")
        defaults.set(seedID, forKey: "keyboardExtension.initialPanelModeSeedID")
        defaults.set(expiredSeededAt, forKey: "keyboardExtension.initialPanelModeSeededAt")

        let loadedConfig = AppConfig.load(from: defaults)

        XCTAssertFalse(loadedConfig.isConfigured)
        XCTAssertEqual(secretStore.apiKey, RejectedGatewayFixture.apiKey)
        XCTAssertTrue(defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled"))
    }

    func testConfiguredKeyboardUITestMockIsNotRealAndCannotLeakIntoANewExtensionProcess() throws {
        let mockConfig = AppConfig(
            apiKey: "mock-ui-test-key",
            gatewayURL: "https://mock.local.invalid",
            selectedModel: "mock-ui-test-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(mockConfig.saveTestSeed(to: defaults, mirrorAPIKeyToDefaultsForUITest: true))
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")

        XCTAssertFalse(AppConfig.hasExistingRealConfig(in: defaults))
        XCTAssertTrue(AppConfig.load(from: defaults).isConfigured)

        AppConfig.resetKeyboardUITestConfigProcessAuthorizationForTesting()
        let laterExtensionProcessConfig = AppConfig.load(from: defaults)

        XCTAssertFalse(laterExtensionProcessConfig.isConfigured)
        XCTAssertTrue(laterExtensionProcessConfig.gatewayURL.isEmpty)
        XCTAssertTrue(laterExtensionProcessConfig.selectedModel.isEmpty)
        XCTAssertEqual(secretStore.apiKey, mockConfig.apiKey)
    }

    func testNonOverwriteUITestSeedCannotDisplaceRealLegacyOnlyProfile() throws {
        let reference = "real-legacy-only-reference"
        secretStore.saveLegacyAPIKey("real-legacy-only-key", reference: reference)
        let legacyProfile = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "secretReference": reference,
            "gatewayURL": "https://real-legacy.example/v1",
            "selectedModel": "real-legacy-model",
            "isConfigured": true,
            "grammarCorrectionVerified": true,
            "grammarCorrectionContractVersion": AppConfig.grammarCorrectionCapabilityVersion
        ])
        defaults.set(legacyProfile, forKey: AppConfig.gatewayProfileKey)
        secretStore.resetMutationCallCounts()
        let testSeed = AppConfig(
            apiKey: RejectedGatewayFixture.apiKey,
            gatewayURL: RejectedGatewayFixture.gatewayURL,
            selectedModel: RejectedGatewayFixture.selectedModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )

        XCTAssertFalse(testSeed.saveTestSeed(to: defaults))

        XCTAssertNil(secretStore.profileData)
        XCTAssertEqual(secretStore.createProfileCallCount, 0)
        XCTAssertEqual(defaults.data(forKey: AppConfig.gatewayProfileKey), legacyProfile)
        XCTAssertEqual(secretStore.loadLegacyAPIKey(reference: reference), "real-legacy-only-key")
        XCTAssertFalse(defaults.bool(forKey: "keyboardExtension.gatewayConfigIsUITestSeed"))
    }

    func testAddOnlyUITestSeedLosesAtomicCreateRaceWithoutOverwritingWinner() throws {
        let winner = AppConfig(
            apiKey: "race-winner-key",
            gatewayURL: "https://race-winner.example/v1",
            selectedModel: "race-winner-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion,
            provider: .anthropic
        )
        XCTAssertTrue(winner.save(to: defaults))
        let winnerData = try XCTUnwrap(secretStore.profileData)
        XCTAssertTrue(secretStore.clearProfile())
        defaults.removeObject(forKey: AppConfig.gatewayProfileConfiguredHintKey)
        defaults.removeObject(forKey: AppConfig.gatewayProfileRevisionHintKey)
        secretStore.resetMutationCallCounts()
        secretStore.beforeProfileCreate = {
            XCTAssertTrue(self.secretStore.saveProfile(winnerData))
        }
        let testSeed = AppConfig(
            apiKey: RejectedGatewayFixture.apiKey,
            gatewayURL: RejectedGatewayFixture.gatewayURL,
            selectedModel: RejectedGatewayFixture.selectedModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )

        XCTAssertFalse(testSeed.saveTestSeed(to: defaults))

        XCTAssertEqual(secretStore.createProfileCallCount, 1)
        XCTAssertEqual(secretStore.profileData, winnerData)
        XCTAssertEqual(AppConfig.load(from: defaults), winner)
        XCTAssertFalse(defaults.bool(forKey: "keyboardExtension.gatewayConfigIsUITestSeed"))
    }

    func testUITestSeedRejectsDurableOrAppGroupPendingClear() {
        let testSeed = AppConfig(
            apiKey: RejectedGatewayFixture.apiKey,
            gatewayURL: RejectedGatewayFixture.gatewayURL,
            selectedModel: RejectedGatewayFixture.selectedModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(secretStore.saveClearIntent(AppConfigSecureClearIntent(legacySecretReferences: [])))
        secretStore.resetMutationCallCounts()

        XCTAssertFalse(testSeed.saveTestSeed(to: defaults, overwriteExistingRealConfig: true))
        XCTAssertNil(secretStore.profileData)
        XCTAssertEqual(secretStore.totalMutationCallCount, 0)

        XCTAssertTrue(secretStore.clearClearIntent())
        defaults.set(true, forKey: AppConfig.gatewayProfileClearPendingKey)
        secretStore.resetMutationCallCounts()

        XCTAssertFalse(testSeed.saveTestSeed(to: defaults, overwriteExistingRealConfig: true))
        XCTAssertNil(secretStore.profileData)
        XCTAssertEqual(secretStore.totalMutationCallCount, 0)
    }

    func testDummySeedDoesNotOverwriteExistingRealGatewayConfigOrAPIKey() throws {
        let realConfig = AppConfig(
            apiKey: "real-user-key-redacted",
            gatewayURL: "https://real.gateway.local",
            selectedModel: "real-model",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
        realConfig.save(to: defaults)
        let originalProfileData = try XCTUnwrap(secretStore.profileData)

        let dummyConfig = AppConfig(
            apiKey: RejectedGatewayFixture.apiKey,
            gatewayURL: RejectedGatewayFixture.gatewayURL,
            selectedModel: RejectedGatewayFixture.selectedModel,
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        XCTAssertFalse(dummyConfig.saveTestSeed(to: defaults, mirrorAPIKeyToDefaultsForUITest: true))

        XCTAssertEqual(secretStore.createProfileCallCount, 0)
        XCTAssertEqual(secretStore.profileData, originalProfileData)
        let loadedConfig = AppConfig.load(from: defaults)
        XCTAssertEqual(loadedConfig.apiKey, "real-user-key-redacted")
        XCTAssertEqual(loadedConfig.gatewayURL, "https://real.gateway.local")
        XCTAssertEqual(loadedConfig.selectedModel, "real-model")
        XCTAssertTrue(loadedConfig.isConfigured)
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey), "Dummy seed must not mirror test key into defaults when real key exists.")
    }

    func testDummySeedCanPopulateEmptyDisposableStore() throws {
        let dummyConfig = AppConfig(
            apiKey: RejectedGatewayFixture.apiKey,
            gatewayURL: RejectedGatewayFixture.gatewayURL,
            selectedModel: RejectedGatewayFixture.selectedModel,
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        XCTAssertTrue(dummyConfig.saveTestSeed(to: defaults, mirrorAPIKeyToDefaultsForUITest: true))
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))

        seedFreshKeyboardExtensionUITestState()
        let loadedConfig = AppConfig.load(from: defaults)
        XCTAssertEqual(loadedConfig.apiKey, RejectedGatewayFixture.apiKey)
        XCTAssertEqual(loadedConfig.gatewayURL, RejectedGatewayFixture.gatewayURL)
        XCTAssertEqual(loadedConfig.selectedModel, RejectedGatewayFixture.selectedModel)
        XCTAssertTrue(loadedConfig.isConfigured)
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey), "Load should migrate the legacy defaults API-key mirror back out after secret-store save succeeds.")
    }

    func testSeedWithoutSecretStoreOrMirrorDoesNotPublishConfiguredState() throws {
        secretStore.shouldFailSave = true
        let dummyConfig = AppConfig(
            apiKey: "fake-seed-token",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        XCTAssertFalse(dummyConfig.saveTestSeed(to: defaults, mirrorAPIKeyToDefaultsForUITest: false))

        let loadedConfig = AppConfig.load(from: defaults)
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertFalse(loadedConfig.isConfigured)
        XCTAssertEqual(loadedConfig.apiKey, "")
        XCTAssertFalse(loadedConfig.supportsStructuredCorrections)
        XCTAssertEqual(secretStore.createProfileCallCount, 1)
    }

    func testExplicitOverwriteFlagAllowsDisposableDummySeedReplacement() throws {
        let realConfig = AppConfig(
            apiKey: "real-user-key-redacted",
            gatewayURL: "https://real.gateway.local",
            selectedModel: "real-model",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
        realConfig.save(to: defaults)

        let dummyConfig = AppConfig(
            apiKey: RejectedGatewayFixture.apiKey,
            gatewayURL: RejectedGatewayFixture.gatewayURL,
            selectedModel: RejectedGatewayFixture.selectedModel,
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        XCTAssertTrue(dummyConfig.saveTestSeed(to: defaults, overwriteExistingRealConfig: true, mirrorAPIKeyToDefaultsForUITest: true))

        seedFreshKeyboardExtensionUITestState()
        let loadedConfig = AppConfig.load(from: defaults)
        XCTAssertEqual(loadedConfig.apiKey, RejectedGatewayFixture.apiKey)
        XCTAssertEqual(loadedConfig.gatewayURL, RejectedGatewayFixture.gatewayURL)
        XCTAssertEqual(loadedConfig.selectedModel, RejectedGatewayFixture.selectedModel)
    }

    func testUITestSeedPublishesOnceAfterCompleteAuthorizationState() throws {
        let dummyConfig = AppConfig(
            apiKey: RejectedGatewayFixture.apiKey,
            gatewayURL: RejectedGatewayFixture.gatewayURL,
            selectedModel: RejectedGatewayFixture.selectedModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        var notificationCount = 0
        var debugAuthorizationWasCommitted = false
        var configLoadedAtNotification: AppConfig?

        XCTAssertTrue(
            dummyConfig.saveTestSeed(
                to: defaults,
                mirrorAPIKeyToDefaultsForUITest: true,
                notificationPoster: {
                    notificationCount += 1
                    debugAuthorizationWasCommitted = self.defaults.bool(
                        forKey: "keyboardExtension.uiTestDebugStateEnabled"
                    )
                    configLoadedAtNotification = AppConfig.load(from: self.defaults)
                }
            )
        )

        XCTAssertEqual(notificationCount, 1)
        XCTAssertTrue(debugAuthorizationWasCommitted)
        XCTAssertEqual(configLoadedAtNotification, dummyConfig)
        XCTAssertEqual(AppConfig.load(from: defaults), dummyConfig)
    }

    func testNormalSavePreservesTestOriginAndFreshProcessStillRejectsIt() throws {
        let fixedNow: TimeInterval = 1_700_025_000
        AppConfig.setKeyboardUITestCurrentTimeForTesting(fixedNow)
        let functionalSeed = AppConfig(
            apiKey: "save-after-seed-key",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(functionalSeed.saveTestSeed(to: defaults))
        var editedSeed = AppConfig.load(from: defaults)
        XCTAssertEqual(editedSeed, functionalSeed)
        let seededObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(secretStore.profileData)) as? [String: Any]
        )
        let seedID = try XCTUnwrap(seededObject["uiTestSeedID"] as? String)
        let seededRevision = try XCTUnwrap(seededObject["revision"] as? String)
        editedSeed.selectedModel = "updated-functional-seed-model"

        XCTAssertTrue(
            editedSeed.save(
                to: defaults,
                notifyActiveProfileChange: false
            )
        )

        let savedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(secretStore.profileData)) as? [String: Any]
        )
        XCTAssertEqual(savedObject["uiTestSeedID"] as? String, seedID)
        XCTAssertNotEqual(savedObject["revision"] as? String, seededRevision)
        XCTAssertFalse(defaults.bool(forKey: "keyboardExtension.gatewayConfigIsUITestSeed"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.gatewayConfigSeedID"))
        XCTAssertNil(defaults.object(forKey: "keyboardExtension.gatewayConfigSeededAt"))

        AppConfig.resetKeyboardUITestConfigProcessAuthorizationForTesting()
        XCTAssertEqual(AppConfig.load(from: defaults), .default)

        XCTAssertTrue(AppConfig.clear(from: defaults, notifyActiveProfileChange: false))
        let realProfile = AppConfig(
            apiKey: "real-profile-after-seed-key",
            gatewayURL: "https://real-after-seed.example",
            selectedModel: "real-after-seed-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(realProfile.save(to: defaults, notifyActiveProfileChange: false))
        let realObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(secretStore.profileData)) as? [String: Any]
        )
        XCTAssertNil(realObject["uiTestSeedID"])
        AppConfig.resetKeyboardUITestConfigProcessAuthorizationForTesting()
        XCTAssertEqual(AppConfig.load(from: defaults), realProfile)
    }

    func testSameIdentityDifferentKeyTestSeedCannotReusePriorProcessAuthorization() throws {
        let seedA = AppConfig(
            apiKey: "functional-seed-a-key",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(seedA.saveTestSeed(to: defaults))
        XCTAssertEqual(AppConfig.load(from: defaults), seedA)

        var seedB = seedA
        seedB.apiKey = "functional-seed-b-key"
        XCTAssertTrue(seedB.saveTestSeed(to: defaults, overwriteExistingRealConfig: true))
        let seedBProfileData = try XCTUnwrap(secretStore.profileData)
        defaults.removeObject(forKey: "keyboardExtension.gatewayConfigSeedID")
        defaults.removeObject(forKey: "keyboardExtension.gatewayConfigSeededAt")
        defaults.synchronize()

        let loadedWithoutFreshSeedB = AppConfig.load(from: defaults)

        XCTAssertEqual(loadedWithoutFreshSeedB, .default)
        XCTAssertEqual(secretStore.profileData, seedBProfileData)
        XCTAssertEqual(secretStore.apiKey, seedB.apiKey)
    }

    func testUITestProcessAuthorizationIsRevokedWhenDebugSessionMetadataChanges() {
        let fixedNow: TimeInterval = 1_700_030_000
        AppConfig.setKeyboardUITestCurrentTimeForTesting(fixedNow)
        let functionalSeed = AppConfig(
            apiKey: "revocable-functional-seed-key",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(functionalSeed.saveTestSeed(to: defaults))
        XCTAssertEqual(AppConfig.load(from: defaults), functionalSeed)

        defaults.set(false, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        defaults.synchronize()
        XCTAssertEqual(AppConfig.load(from: defaults), .default)

        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        defaults.set("replacement-session", forKey: "keyboardExtension.gatewayConfigSeedID")
        defaults.synchronize()
        XCTAssertEqual(
            AppConfig.load(from: defaults),
            .default,
            "A consumed one-time grant cannot be revived by restoring or replacing session metadata."
        )
    }

    func testUITestProcessAuthorizationIsRevokedWhenSessionIDIsReplaced() {
        let fixedNow: TimeInterval = 1_700_035_000
        AppConfig.setKeyboardUITestCurrentTimeForTesting(fixedNow)
        let functionalSeed = AppConfig(
            apiKey: "session-bound-functional-seed-key",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(functionalSeed.saveTestSeed(to: defaults))
        XCTAssertEqual(AppConfig.load(from: defaults), functionalSeed)

        defaults.set("replacement-session", forKey: "keyboardExtension.gatewayConfigSeedID")
        defaults.synchronize()

        XCTAssertEqual(AppConfig.load(from: defaults), .default)
        XCTAssertTrue(defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled"))
    }

    func testUITestProcessAuthorizationExpiresWithoutSleeping() {
        let fixedNow: TimeInterval = 1_700_040_000
        AppConfig.setKeyboardUITestCurrentTimeForTesting(fixedNow)
        let functionalSeed = AppConfig(
            apiKey: "expiring-functional-seed-key",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(functionalSeed.saveTestSeed(to: defaults))
        XCTAssertEqual(AppConfig.load(from: defaults), functionalSeed)

        AppConfig.setKeyboardUITestCurrentTimeForTesting(fixedNow + 601)

        XCTAssertEqual(AppConfig.load(from: defaults), .default)
        XCTAssertTrue(defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled"))
        XCTAssertNotNil(defaults.string(forKey: "keyboardExtension.gatewayConfigSeedID"))
        XCTAssertNil(defaults.object(forKey: "keyboardExtension.gatewayConfigSeededAt"))
    }

    func testAppGroupLossCannotPromoteRetainedFunctionalTestSeed() throws {
        let functionalSeed = AppConfig(
            apiKey: "functional-simulator-seed-key",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(functionalSeed.saveTestSeed(to: defaults))
        let retainedProfileData = try XCTUnwrap(secretStore.profileData)
        let secureObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: retainedProfileData) as? [String: Any]
        )
        XCTAssertFalse((secureObject["uiTestSeedID"] as? String ?? "").isEmpty)

        defaults.removePersistentDomain(forName: suiteName)
        defaults.synchronize()
        AppConfig.resetKeyboardUITestConfigProcessAuthorizationForTesting()

        XCTAssertEqual(AppConfig.load(from: defaults), .default)
        XCTAssertEqual(secretStore.profileData, retainedProfileData)
        XCTAssertEqual(secretStore.apiKey, functionalSeed.apiKey)
    }

    func testFailedExplicitUITestSeedReplacementPreservesPreviousProfileWithoutDefaultsFallback() throws {
        let realConfig = AppConfig(
            apiKey: "real-user-key-redacted",
            gatewayURL: "https://real.gateway.local",
            selectedModel: "real-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(realConfig.save(to: defaults))
        let previousProfileData = try XCTUnwrap(secretStore.profileData)
        let previousRevisionHint = defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey)
        secretStore.shouldFailSave = true

        let dummyConfig = AppConfig(
            apiKey: RejectedGatewayFixture.apiKey,
            gatewayURL: RejectedGatewayFixture.gatewayURL,
            selectedModel: RejectedGatewayFixture.selectedModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )

        XCTAssertFalse(
            dummyConfig.saveTestSeed(
                to: defaults,
                overwriteExistingRealConfig: true,
                mirrorAPIKeyToDefaultsForUITest: true
            )
        )
        XCTAssertEqual(secretStore.profileData, previousProfileData)
        XCTAssertEqual(defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey), previousRevisionHint)
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertFalse(defaults.bool(forKey: "keyboardExtension.gatewayConfigIsUITestSeed"))
        XCTAssertEqual(AppConfig.load(from: defaults), realConfig)
    }

    func testKeychainSecureStoreUsesSharedAccessGroup() throws {
        let query = KeychainAppConfigSecureStore(accessGroup: "ABCDE12345.com.maneesh.openkeyboard.shared").baseQueryForTesting()

        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, "ABCDE12345.com.maneesh.openkeyboard.shared")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "gateway-profile-v2")
    }

    func testConfigWrittenToStandardDefaultsIsNotVisibleToAppGroupSuite() throws {
        UserDefaults.standard.set("fake-main-app-only", forKey: AppConfig.apiKeyKey)
        UserDefaults.standard.set(fixtureGatewayURL, forKey: AppConfig.gatewayURLKey)
        UserDefaults.standard.set(fixtureModel, forKey: AppConfig.selectedModelKey)
        UserDefaults.standard.set(true, forKey: AppConfig.isConfiguredKey)
        defer {
            [AppConfig.apiKeyKey, AppConfig.gatewayURLKey, AppConfig.selectedModelKey, AppConfig.isConfiguredKey].forEach {
                UserDefaults.standard.removeObject(forKey: $0)
            }
        }

        let extensionLoadedConfig = AppConfig.load(from: defaults)
        XCTAssertFalse(extensionLoadedConfig.isConfigured)
        XCTAssertNotEqual(extensionLoadedConfig.apiKey, "fake-main-app-only")
        XCTAssertEqual(extensionLoadedConfig.apiKey, "")
    }



    #if OPENKEYBOARD_APP_NETWORK_TESTS
    func testCorrectionSmokeResponseRequiresUsableCorrection() {
        XCTAssertTrue(NetworkManager.isUsableCorrectionSmokeResponse("I have an apple."))
        XCTAssertTrue(NetworkManager.isUsableCorrectionSmokeResponse("Corrected: I have an apple"))
        XCTAssertFalse(NetworkManager.isUsableCorrectionSmokeResponse("OK"))
        XCTAssertFalse(NetworkManager.isUsableCorrectionSmokeResponse(""))
    }

    func testSmokeErrorMappingUsesSpecificGenerationMessages() {
        XCTAssertEqual(
            NetworkManager.userFacingSmokeErrorMessage(for: NetworkError.serverError("HTTP 500 FoundationModels.LanguageModelSession.GenerationError error -1"), model: "apple-foundationmodel"),
            "Gateway connected, but Apple Foundation model did not respond. Try another key/model."
        )
        XCTAssertEqual(
            NetworkManager.userFacingSmokeErrorMessage(for: NetworkError.unusableCorrection, model: "gpt-oss:120b-cloud"),
            "Gateway connected, but the selected model did not return a usable correction."
        )
        XCTAssertEqual(
            NetworkManager.userFacingSmokeErrorMessage(for: NetworkError.timeout, model: "gpt-oss:120b-cloud"),
            "Gateway connected, but the selected model timed out during the test."
        )
        XCTAssertEqual(
            NetworkManager.userFacingSmokeErrorMessage(for: NetworkError.unauthorized, model: "gpt-oss:120b-cloud"),
            "API key was rejected by the gateway. Reconnect your gateway in the app."
        )
    }
    #endif

    func testClearRemovesSecretStoreAPIKeyAndKeyboardDebugAndPanelSeedState() throws {
        secretStore.apiKey = "fake-keychain-test-token"
        defaults.set("fake-legacy-test-token", forKey: AppConfig.apiKeyKey)
        defaults.set("actions", forKey: "keyboardExtension.initialPanelMode")
        defaults.set("initial-panel-seed", forKey: "keyboardExtension.initialPanelModeSeedID")
        defaults.set(Date().timeIntervalSince1970, forKey: "keyboardExtension.initialPanelModeSeededAt")
        defaults.set("rewriteOptions", forKey: "keyboardExtension.suggestionState")
        defaults.set("suggestion-state-seed", forKey: "keyboardExtension.suggestionStateSeedID")
        defaults.set(Date().timeIntervalSince1970, forKey: "keyboardExtension.suggestionStateSeededAt")
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        defaults.set("private typed text", forKey: "keyboardExtension.composingBuffer")
        defaults.set("debug event", forKey: "keyboardExtension.lastDebugEvent")
        defaults.set("debug events", forKey: "keyboardExtension.debugEvents")

        XCTAssertTrue(AppConfig.clear(from: defaults))

        XCTAssertNil(secretStore.apiKey)
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.initialPanelMode"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.initialPanelModeSeedID"))
        XCTAssertNil(defaults.object(forKey: "keyboardExtension.initialPanelModeSeededAt"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionState"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionStateSeedID"))
        XCTAssertNil(defaults.object(forKey: "keyboardExtension.suggestionStateSeededAt"))
        XCTAssertFalse(defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.composingBuffer"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.lastDebugEvent"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.debugEvents"))
        XCTAssertFalse(defaults.bool(forKey: AppConfig.supportsStructuredCorrectionsKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.structuredCorrectionSchemaVersionKey))
        XCTAssertNil(secretStore.clearIntent)
        XCTAssertFalse(defaults.bool(forKey: AppConfig.gatewayProfileClearPendingKey))
    }

    func testClearFailureRemainsQuarantinedAndEveryRetryRepostsInvalidation() throws {
        let profile = AppConfig(
            apiKey: "clear-retry-key",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(profile.save(to: defaults))
        let retainedProfileData = try XCTUnwrap(secretStore.profileData)
        secretStore.shouldFailClearProfile = true
        var notificationCount = 0

        XCTAssertFalse(
            AppConfig.clear(
                from: defaults,
                notificationPoster: { notificationCount += 1 }
            )
        )
        XCTAssertTrue(defaults.bool(forKey: AppConfig.gatewayProfileClearPendingKey))
        XCTAssertEqual(secretStore.profileData, retainedProfileData)
        XCTAssertEqual(notificationCount, 1)

        XCTAssertEqual(
            AppConfig.load(
                from: defaults,
                clearRetryNotificationPoster: { notificationCount += 1 }
            ),
            .default
        )
        XCTAssertEqual(secretStore.clearProfileCallCount, 2)
        XCTAssertTrue(defaults.bool(forKey: AppConfig.gatewayProfileClearPendingKey))
        XCTAssertEqual(secretStore.profileData, retainedProfileData)
        XCTAssertNotNil(secretStore.clearIntent)
        XCTAssertEqual(notificationCount, 2)

        secretStore.shouldFailClearProfile = false
        XCTAssertEqual(
            AppConfig.load(
                from: defaults,
                clearRetryNotificationPoster: { notificationCount += 1 }
            ),
            .default
        )
        XCTAssertEqual(secretStore.clearProfileCallCount, 3)
        XCTAssertNil(secretStore.profileData)
        XCTAssertFalse(defaults.bool(forKey: AppConfig.gatewayProfileClearPendingKey))
        XCTAssertNil(secretStore.clearIntent)
        XCTAssertEqual(notificationCount, 3)
    }

    func testLegacyKeyDeleteFailuresStillRemovePlaintextAndRetainSecureRetryIntent() throws {
        let profile = AppConfig(
            apiKey: "clear-delete-failure-profile-key",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(profile.save(to: defaults, notifyActiveProfileChange: false))
        let reference = "clear-delete-failure-reference"
        secretStore.saveLegacyAPIKey("referenced-legacy-secret", reference: reference)
        XCTAssertTrue(secretStore.saveLegacyAPIKey("unversioned-legacy-secret"))
        let legacyProfile = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "secretReference": reference,
            "gatewayURL": "https://legacy-clear.example",
            "selectedModel": "legacy-clear-model",
            "isConfigured": true,
            "grammarCorrectionVerified": true,
            "grammarCorrectionContractVersion": AppConfig.grammarCorrectionCapabilityVersion
        ])
        defaults.set(legacyProfile, forKey: AppConfig.gatewayProfileKey)
        defaults.set("plaintext-legacy-secret", forKey: AppConfig.apiKeyKey)
        defaults.set("https://legacy-clear.example", forKey: AppConfig.gatewayURLKey)
        defaults.set("legacy-clear-model", forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        defaults.set(true, forKey: AppConfig.grammarCorrectionVerifiedKey)
        defaults.set(
            AppConfig.grammarCorrectionCapabilityVersion,
            forKey: AppConfig.grammarCorrectionContractVersionKey
        )
        defaults.set(reference, forKey: AppConfig.gatewayLegacySecretCleanupReferenceKey)
        defaults.set(true, forKey: AppConfig.gatewayLegacyUnversionedSecretCleanupPendingKey)
        defaults.set("stale clear error", forKey: AppConfig.gatewayConnectionErrorMessageKey)
        defaults.set(1_700_050_000, forKey: AppConfig.gatewayConnectionLastTestedAtKey)
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        defaults.set("private typed text", forKey: "keyboardExtension.composingBuffer")
        defaults.synchronize()
        secretStore.shouldFailClearReferencedLegacyAPIKey = true
        secretStore.shouldFailClearLegacyAPIKey = true

        XCTAssertFalse(AppConfig.clear(from: defaults, notifyActiveProfileChange: false))

        XCTAssertNil(secretStore.profileData)
        XCTAssertEqual(secretStore.loadLegacyAPIKey(reference: reference), "referenced-legacy-secret")
        XCTAssertEqual(secretStore.loadLegacyAPIKey(), "unversioned-legacy-secret")
        let retainedIntent = try XCTUnwrap(secretStore.clearIntent)
        XCTAssertEqual(retainedIntent.legacySecretReferences, [reference])
        XCTAssertTrue(retainedIntent.clearsUnversionedLegacyKey)
        XCTAssertFalse(retainedIntent.legacySecretReferences.contains("plaintext-legacy-secret"))
        XCTAssertTrue(defaults.bool(forKey: AppConfig.gatewayProfileClearPendingKey))
        XCTAssertNil(defaults.data(forKey: AppConfig.gatewayProfileKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.selectedModelKey))
        XCTAssertNil(defaults.object(forKey: AppConfig.isConfiguredKey))
        XCTAssertNil(defaults.object(forKey: AppConfig.grammarCorrectionVerifiedKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.grammarCorrectionContractVersionKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayLegacySecretCleanupReferenceKey))
        XCTAssertNil(defaults.object(forKey: AppConfig.gatewayLegacyUnversionedSecretCleanupPendingKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayConnectionErrorMessageKey))
        XCTAssertNil(defaults.object(forKey: AppConfig.gatewayConnectionLastTestedAtKey))
        XCTAssertFalse(defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.composingBuffer"))

        secretStore.shouldFailClearReferencedLegacyAPIKey = false
        secretStore.shouldFailClearLegacyAPIKey = false
        XCTAssertEqual(AppConfig.load(from: defaults), .default)
        XCTAssertNil(secretStore.loadLegacyAPIKey(reference: reference))
        XCTAssertNil(secretStore.loadLegacyAPIKey())
        XCTAssertNil(secretStore.clearIntent)
        XCTAssertFalse(defaults.bool(forKey: AppConfig.gatewayProfileClearPendingKey))
    }

    func testCrashWindowClearRecoveryUsesSecureIntentAfterAppGroupLoss() throws {
        let profile = AppConfig(
            apiKey: "crash-window-profile-key",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(profile.save(to: defaults))
        let reference = "crash-window-legacy-reference"
        secretStore.saveLegacyAPIKey("crash-window-legacy-key", reference: reference)
        XCTAssertTrue(
            secretStore.saveClearIntent(
                AppConfigSecureClearIntent(legacySecretReferences: [reference])
            )
        )
        defaults.removePersistentDomain(forName: suiteName)
        defaults.synchronize()
        secretStore.resetMutationCallCounts()
        var notificationCount = 0

        let loaded = AppConfig.load(
            from: defaults,
            clearRetryNotificationPoster: { notificationCount += 1 }
        )

        XCTAssertEqual(loaded, .default)
        XCTAssertEqual(notificationCount, 1)
        XCTAssertNil(secretStore.profileData)
        XCTAssertNil(secretStore.loadLegacyAPIKey(reference: reference))
        XCTAssertNil(secretStore.clearIntent)
        XCTAssertFalse(defaults.bool(forKey: AppConfig.gatewayProfileClearPendingKey))
    }

    func testClearPersistsSecureIntentBeforeDeletionAndClearsItLast() throws {
        let reference = "clear-order-reference"
        secretStore.saveLegacyAPIKey("clear-order-key", reference: reference)
        let legacyProfile = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "secretReference": reference,
            "gatewayURL": fixtureGatewayURL,
            "selectedModel": fixtureModel,
            "isConfigured": true,
            "grammarCorrectionVerified": true,
            "grammarCorrectionContractVersion": AppConfig.grammarCorrectionCapabilityVersion
        ])
        defaults.set(legacyProfile, forKey: AppConfig.gatewayProfileKey)
        defaults.set("clear-order-plaintext-key", forKey: AppConfig.apiKeyKey)
        var sawIntentBeforeProfileDeletion = false
        var sawAppGroupCleanupBeforeIntentRemoval = false
        secretStore.beforeProfileClear = {
            sawIntentBeforeProfileDeletion = self.secretStore.clearIntent?
                .legacySecretReferences.contains(reference) == true
                && self.defaults.bool(forKey: AppConfig.gatewayProfileClearPendingKey)
        }
        secretStore.beforeClearIntentRemoval = {
            sawAppGroupCleanupBeforeIntentRemoval = self.secretStore.profileData == nil
                && self.secretStore.loadLegacyAPIKey(reference: reference) == nil
                && self.defaults.data(forKey: AppConfig.gatewayProfileKey) == nil
                && self.defaults.string(forKey: AppConfig.apiKeyKey) == nil
                && !self.defaults.bool(forKey: AppConfig.gatewayProfileClearPendingKey)
        }

        XCTAssertTrue(AppConfig.clear(from: defaults, notifyActiveProfileChange: false))

        XCTAssertTrue(sawIntentBeforeProfileDeletion)
        XCTAssertTrue(sawAppGroupCleanupBeforeIntentRemoval)
        XCTAssertNil(secretStore.clearIntent)
    }

    func testUnavailableClearIntentStatusFailsClosedWithoutMutatingCredentials() throws {
        let profile = AppConfig(
            apiKey: "unavailable-clear-intent-key",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(profile.save(to: defaults))
        let retainedProfile = try XCTUnwrap(secretStore.profileData)
        secretStore.clearIntentReadResultOverride = .unavailable
        secretStore.resetMutationCallCounts()

        XCTAssertEqual(AppConfig.load(from: defaults), .default)

        XCTAssertEqual(secretStore.profileData, retainedProfile)
        XCTAssertEqual(secretStore.totalMutationCallCount, 0)
    }

    func testFailedFinalTombstoneRemovalKeepsProfileQuarantinedUntilRetry() throws {
        let profile = AppConfig(
            apiKey: "final-tombstone-key",
            gatewayURL: fixtureGatewayURL,
            selectedModel: fixtureModel,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(profile.save(to: defaults))
        secretStore.shouldFailClearClearIntent = true
        var notificationCount = 0

        XCTAssertFalse(
            AppConfig.clear(
                from: defaults,
                notificationPoster: { notificationCount += 1 }
            )
        )
        XCTAssertNil(secretStore.profileData)
        XCTAssertNotNil(secretStore.clearIntent)
        XCTAssertFalse(defaults.bool(forKey: AppConfig.gatewayProfileClearPendingKey))
        XCTAssertEqual(notificationCount, 1)

        secretStore.shouldFailClearClearIntent = false
        XCTAssertEqual(
            AppConfig.load(
                from: defaults,
                clearRetryNotificationPoster: { notificationCount += 1 }
            ),
            .default
        )
        XCTAssertNil(secretStore.clearIntent)
        XCTAssertEqual(notificationCount, 2)
    }

    func testClearingKeyboardUITestStatePreservesRealGatewayConfiguration() {
        let realConfig = AppConfig(
            apiKey: "real-keychain-token",
            gatewayURL: "https://gateway.example.com",
            selectedModel: "gemma2:2b",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(realConfig.save(to: defaults))
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        defaults.set("stale test text", forKey: "keyboardExtension.composingBuffer")
        defaults.set("modelCapabilityError", forKey: "keyboardExtension.suggestionState")

        AppConfig.clearKeyboardUITestState(from: defaults)

        XCTAssertEqual(secretStore.apiKey, "real-keychain-token")
        XCTAssertEqual(AppConfig.load(from: defaults), realConfig)
        XCTAssertTrue(defaults.bool(forKey: AppConfig.gatewayProfileConfiguredHintKey))
        XCTAssertFalse((defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey) ?? "").isEmpty)
        XCTAssertFalse(defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.composingBuffer"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.suggestionState"))
    }

    private func seedFreshKeyboardExtensionUITestState() {
        let seedID = UUID().uuidString
        let seededAt = Date().timeIntervalSince1970
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        defaults.set("correctionCarousel", forKey: "keyboardExtension.suggestionState")
        defaults.set(seedID, forKey: "keyboardExtension.suggestionStateSeedID")
        defaults.set(seededAt, forKey: "keyboardExtension.suggestionStateSeededAt")
        defaults.set("correctionCarousel", forKey: "keyboardExtension.initialPanelMode")
        defaults.set(seedID, forKey: "keyboardExtension.initialPanelModeSeedID")
        defaults.set(seededAt, forKey: "keyboardExtension.initialPanelModeSeededAt")
    }
}
