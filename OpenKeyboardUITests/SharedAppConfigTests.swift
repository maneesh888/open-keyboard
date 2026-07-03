import Security
import XCTest

private enum RejectedGatewayFixture {
    static let gatewayURL = ["https://gateway", "example", "invalid"].joined(separator: ".")
    static let apiKey = ["test", "placeholder", "key"].joined(separator: "-")
    static let selectedModel = ["test", "placeholder", "model"].joined(separator: "-")
}

private final class InMemoryAppConfigSecretStore: AppConfigSecretStore {
    var apiKey: String?

    func loadAPIKey() -> String? { apiKey }
    var shouldFailSave = false

    @discardableResult
    func saveAPIKey(_ apiKey: String) -> Bool {
        guard !shouldFailSave else { return false }
        self.apiKey = apiKey
        return true
    }

    @discardableResult
    func clearAPIKey() -> Bool {
        apiKey = nil
        return true
    }
}

final class SharedAppConfigTests: XCTestCase {
    private let fixtureGatewayURL = "https://gateway.test.local"
    private let fixtureModel = "fixture-model"

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var secretStore: InMemoryAppConfigSecretStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "group.com.maneesh.openkeyboard.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        secretStore = InMemoryAppConfigSecretStore()
        AppConfig.secretStore = secretStore
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        secretStore = nil
        AppConfig.secretStore = KeychainAppConfigSecretStore()
        try super.tearDownWithError()
    }

    func testMainAppSaveSharesNonSensitiveConfigAndStoresAPIKeyInSecretStore() throws {
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
        XCTAssertEqual(extensionLoadedConfig.gatewayURL, fixtureGatewayURL)
        XCTAssertEqual(extensionLoadedConfig.selectedModel, fixtureModel)
        XCTAssertEqual(extensionLoadedConfig.apiKey, "")
        XCTAssertFalse(extensionLoadedConfig.isConfigured)
        XCTAssertFalse(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertFalse(extensionLoadedConfig.supportsStructuredCorrections)
    }

    func testLegacyDefaultsAPIKeyMigratesToSecretStoreAndIsRemovedFromDefaults() throws {
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

    func testLegacyDefaultsAPIKeyIsPreservedWhenSecretStoreMigrationFails() throws {
        secretStore.shouldFailSave = true
        defaults.set("fake-legacy-test-token", forKey: AppConfig.apiKeyKey)
        defaults.set(fixtureGatewayURL, forKey: AppConfig.gatewayURLKey)

        let loadedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(loadedConfig.apiKey, "fake-legacy-test-token")
        XCTAssertNil(secretStore.apiKey)
        XCTAssertEqual(defaults.string(forKey: AppConfig.apiKeyKey), "fake-legacy-test-token")
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

    func testKnownUITestPlaceholderConfigIsAcceptedWhenKeyboardDebugStateEnabled() throws {
        secretStore.apiKey = RejectedGatewayFixture.apiKey
        defaults.set(RejectedGatewayFixture.gatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(RejectedGatewayFixture.selectedModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)
        defaults.set(true, forKey: AppConfig.supportsStructuredCorrectionsKey)
        defaults.set("openkeyboard.structured-corrections.v1", forKey: AppConfig.structuredCorrectionSchemaVersionKey)
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")

        let loadedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(loadedConfig.apiKey, RejectedGatewayFixture.apiKey)
        XCTAssertEqual(loadedConfig.gatewayURL, RejectedGatewayFixture.gatewayURL)
        XCTAssertEqual(loadedConfig.selectedModel, RejectedGatewayFixture.selectedModel)
        XCTAssertTrue(loadedConfig.isConfigured)
        XCTAssertTrue(loadedConfig.supportsStructuredCorrections)
        XCTAssertEqual(loadedConfig.structuredCorrectionSchemaVersion, "openkeyboard.structured-corrections.v1")
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
        XCTAssertEqual(defaults.string(forKey: AppConfig.apiKeyKey), RejectedGatewayFixture.apiKey)

        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
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

        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        let loadedConfig = AppConfig.load(from: defaults)
        XCTAssertEqual(loadedConfig.apiKey, RejectedGatewayFixture.apiKey)
        XCTAssertEqual(loadedConfig.gatewayURL, RejectedGatewayFixture.gatewayURL)
        XCTAssertEqual(loadedConfig.selectedModel, RejectedGatewayFixture.selectedModel)
    }

    func testKeychainSecretStoreUsesSharedAccessGroup() throws {
        let query = KeychainAppConfigSecretStore(accessGroup: "ABCDE12345.com.maneesh.openkeyboard.shared").baseQueryForTesting()

        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, "ABCDE12345.com.maneesh.openkeyboard.shared")
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
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")
        defaults.set("private typed text", forKey: "keyboardExtension.composingBuffer")
        defaults.set("debug event", forKey: "keyboardExtension.lastDebugEvent")
        defaults.set("debug events", forKey: "keyboardExtension.debugEvents")

        AppConfig.clear(from: defaults)

        XCTAssertNil(secretStore.apiKey)
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.initialPanelMode"))
        XCTAssertFalse(defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.composingBuffer"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.lastDebugEvent"))
        XCTAssertNil(defaults.string(forKey: "keyboardExtension.debugEvents"))
        XCTAssertFalse(defaults.bool(forKey: AppConfig.supportsStructuredCorrectionsKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.structuredCorrectionSchemaVersionKey))
    }
}
