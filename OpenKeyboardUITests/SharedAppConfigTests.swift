import Security
import XCTest

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
    private let placeholderGatewayURL = "https://gateway.example.invalid"
    private let placeholderModel = "test-placeholder-model"

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
            apiKey: "sk-shared-test-token",
            gatewayURL: placeholderGatewayURL,
            selectedModel: placeholderModel,
            isConfigured: true
        )

        mainAppConfig.save(to: defaults)

        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertEqual(secretStore.apiKey, "sk-shared-test-token")

        let extensionLoadedConfig = AppConfig.load(from: defaults)
        XCTAssertEqual(extensionLoadedConfig.gatewayURL, placeholderGatewayURL)
        XCTAssertEqual(extensionLoadedConfig.apiKey, "sk-shared-test-token")
        XCTAssertEqual(extensionLoadedConfig.selectedModel, placeholderModel)
        XCTAssertTrue(extensionLoadedConfig.isConfigured)
    }

    func testLegacyDefaultsAPIKeyMigratesToSecretStoreAndIsRemovedFromDefaults() throws {
        defaults.set("sk-legacy-test-token", forKey: AppConfig.apiKeyKey)
        defaults.set(placeholderGatewayURL, forKey: AppConfig.gatewayURLKey)
        defaults.set(placeholderModel, forKey: AppConfig.selectedModelKey)
        defaults.set(true, forKey: AppConfig.isConfiguredKey)

        let migratedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(migratedConfig.apiKey, "sk-legacy-test-token")
        XCTAssertEqual(secretStore.apiKey, "sk-legacy-test-token")
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertEqual(migratedConfig.gatewayURL, placeholderGatewayURL)
        XCTAssertEqual(migratedConfig.selectedModel, placeholderModel)
        XCTAssertTrue(migratedConfig.isConfigured)
    }

    func testLegacyDefaultsAPIKeyIsPreservedWhenSecretStoreMigrationFails() throws {
        secretStore.shouldFailSave = true
        defaults.set("sk-legacy-test-token", forKey: AppConfig.apiKeyKey)
        defaults.set(placeholderGatewayURL, forKey: AppConfig.gatewayURLKey)

        let loadedConfig = AppConfig.load(from: defaults)

        XCTAssertEqual(loadedConfig.apiKey, "sk-legacy-test-token")
        XCTAssertNil(secretStore.apiKey)
        XCTAssertEqual(defaults.string(forKey: AppConfig.apiKeyKey), "sk-legacy-test-token")
    }

    func testKeychainSecretStoreUsesSharedAccessGroup() throws {
        let query = KeychainAppConfigSecretStore(accessGroup: "ABCDE12345.com.maneesh.openkeyboard.shared").baseQueryForTesting()

        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, "ABCDE12345.com.maneesh.openkeyboard.shared")
    }

    func testConfigWrittenToStandardDefaultsIsNotVisibleToAppGroupSuite() throws {
        UserDefaults.standard.set("sk-main-app-only", forKey: AppConfig.apiKeyKey)
        UserDefaults.standard.set(placeholderGatewayURL, forKey: AppConfig.gatewayURLKey)
        UserDefaults.standard.set(placeholderModel, forKey: AppConfig.selectedModelKey)
        UserDefaults.standard.set(true, forKey: AppConfig.isConfiguredKey)
        defer {
            [AppConfig.apiKeyKey, AppConfig.gatewayURLKey, AppConfig.selectedModelKey, AppConfig.isConfiguredKey].forEach {
                UserDefaults.standard.removeObject(forKey: $0)
            }
        }

        let extensionLoadedConfig = AppConfig.load(from: defaults)
        XCTAssertFalse(extensionLoadedConfig.isConfigured)
        XCTAssertNotEqual(extensionLoadedConfig.apiKey, "sk-main-app-only")
        XCTAssertEqual(extensionLoadedConfig.apiKey, "")
    }

    func testClearRemovesSecretStoreAPIKeyAndKeyboardDebugAndPanelSeedState() throws {
        secretStore.apiKey = "sk-keychain-test-token"
        defaults.set("sk-legacy-test-token", forKey: AppConfig.apiKeyKey)
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
    }
}
