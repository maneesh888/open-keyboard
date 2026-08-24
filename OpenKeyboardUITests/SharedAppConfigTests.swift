import Security
import XCTest

private enum RejectedGatewayFixture {
    static let gatewayURL = ["https://gateway", "example", "invalid"].joined(separator: ".")
    static let apiKey = ["test", "placeholder", "key"].joined(separator: "-")
    static let selectedModel = ["test", "placeholder", "model"].joined(separator: "-")
}

private final class InMemoryAppConfigSecureStore: AppConfigSecureStore {
    private var profileData: Data?
    private var legacyAPIKey: String?
    private var referencedAPIKeys: [String: String] = [:]
    var beforeProfileReplacement: (() -> Void)?
    var apiKey: String? {
        get { Self.apiKey(from: profileData) ?? legacyAPIKey }
        set { legacyAPIKey = newValue }
    }

    var shouldFailSave = false

    func loadProfile() -> Data? { profileData }

    @discardableResult
    func saveProfile(_ profile: Data) -> Bool {
        guard !shouldFailSave else { return false }
        if profileData != nil {
            beforeProfileReplacement?()
        }
        profileData = profile
        return true
    }

    @discardableResult
    func clearProfile() -> Bool {
        profileData = nil
        return true
    }

    func loadLegacyAPIKey() -> String? { legacyAPIKey }
    func loadLegacyAPIKey(reference: String) -> String? { referencedAPIKeys[reference] }

    @discardableResult
    func saveLegacyAPIKey(_ apiKey: String) -> Bool {
        guard !shouldFailSave else { return false }
        legacyAPIKey = apiKey
        return true
    }

    func saveLegacyAPIKey(_ apiKey: String, reference: String) {
        referencedAPIKeys[reference] = apiKey
    }

    @discardableResult
    func clearLegacyAPIKey() -> Bool {
        legacyAPIKey = nil
        return true
    }

    @discardableResult
    func clearLegacyAPIKey(reference: String) -> Bool {
        referencedAPIKeys.removeValue(forKey: reference)
        return true
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
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        secretStore = nil
        AppConfig.secureStore = KeychainAppConfigSecureStore()
        AppConfig.resetKeyboardUITestConfigProcessAuthorizationForTesting()
        try super.tearDownWithError()
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
        XCTAssertNil(secretStore.apiKey)
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.selectedModelKey))
        XCTAssertFalse(defaults.bool(forKey: AppConfig.isConfiguredKey))
    }


    func testRedactedVisibilityDiagnosticReportsPresenceWithoutLeakingAPIKey() throws {
        let rawAPIKey = "super-secret-test-key"
        secretStore.apiKey = rawAPIKey
        defaults.set("https://gateway.test.local/v1", forKey: AppConfig.gatewayURLKey)
        defaults.set("safe-model", forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")

        let diagnostic = AppConfig.redactedVisibilityDiagnostic(from: defaults)
        let description = diagnostic.redactedDescription

        XCTAssertTrue(diagnostic.uiTestDebugStateEnabled)
        XCTAssertTrue(diagnostic.gatewayURLPresent)
        XCTAssertEqual(diagnostic.gatewayHost, "gateway.test.local")
        XCTAssertTrue(diagnostic.selectedModelPresent)
        XCTAssertEqual(diagnostic.selectedModel, "safe-model")
        XCTAssertTrue(diagnostic.keychainAPIKeyPresent)
        XCTAssertFalse(diagnostic.legacyDefaultsAPIKeyPresent)
        XCTAssertTrue(diagnostic.loadedConfigIsConfigured)
        XCTAssertFalse(description.contains(rawAPIKey))
        XCTAssertFalse(description.contains("https://gateway.test.local/v1"))
        XCTAssertTrue(description.contains("gatewayHost=gateway.test.local"))
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
        XCTAssertNil(secretStore.apiKey)
        XCTAssertFalse(defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled"))
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
        XCTAssertNil(secretStore.apiKey)
        XCTAssertFalse(defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled"))
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
        XCTAssertNil(secretStore.apiKey)
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

        let dummyConfig = AppConfig(
            apiKey: RejectedGatewayFixture.apiKey,
            gatewayURL: RejectedGatewayFixture.gatewayURL,
            selectedModel: RejectedGatewayFixture.selectedModel,
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        XCTAssertFalse(dummyConfig.saveTestSeed(to: defaults, mirrorAPIKeyToDefaultsForUITest: true))

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

    func testResolvedGatewayModelPrefersCurrentModelBeforeAppleFallback() {
        let model = AppConfig.resolvedGatewayModel(
            from: ["gemma4:latest", "apple-foundationmodel", "gpt-oss:120b-cloud"],
            currentModel: "gemma4:latest"
        )

        XCTAssertEqual(model, "gemma4:latest")
        XCTAssertEqual(
            AppConfig.gatewayModelCandidates(from: ["gemma4:latest", "apple-foundationmodel", "gpt-oss:120b-cloud"], currentModel: "gemma4:latest"),
            ["gemma4:latest", "apple-foundationmodel", "gpt-oss:120b-cloud"]
        )
    }

    func testResolvedGatewayModelFallsBackToCurrentModelWhenAppleFoundationModelUnavailable() {
        let model = AppConfig.resolvedGatewayModel(
            from: ["qwen2.5-coder:3b", "gpt-oss:120b-cloud"],
            currentModel: "gpt-oss:120b-cloud"
        )

        XCTAssertEqual(model, "gpt-oss:120b-cloud")
    }

    func testResolvedGatewayModelTrimsAndFallsBackToFirstGatewayModel() {
        XCTAssertEqual(AppConfig.resolvedGatewayModel(from: ["  qwen2.5-coder:3b  "], currentModel: "missing"), "qwen2.5-coder:3b")
        XCTAssertNil(AppConfig.resolvedGatewayModel(from: ["  ", ""], currentModel: "missing"))
    }

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

        AppConfig.clear(from: defaults)

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
