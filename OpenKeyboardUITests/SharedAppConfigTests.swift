import XCTest

final class SharedAppConfigTests: XCTestCase {
    private let placeholderGatewayURL = "https://gateway.example.invalid"
    private let placeholderModel = "test-placeholder-model"

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "group.com.maneesh.openkeyboard.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testMainAppSaveIsVisibleToExtensionLoaderFromSameAppGroupSuite() throws {
        let mainAppConfig = AppConfig(
            apiKey: "sk-shared-test-token",
            gatewayURL: placeholderGatewayURL,
            selectedModel: placeholderModel,
            isConfigured: true
        )

        mainAppConfig.save(to: defaults)

        let extensionLoadedConfig = AppConfig.load(from: defaults)
        XCTAssertEqual(extensionLoadedConfig.gatewayURL, placeholderGatewayURL)
        XCTAssertEqual(extensionLoadedConfig.apiKey, "sk-shared-test-token")
        XCTAssertEqual(extensionLoadedConfig.selectedModel, placeholderModel)
        XCTAssertTrue(extensionLoadedConfig.isConfigured)
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
}
