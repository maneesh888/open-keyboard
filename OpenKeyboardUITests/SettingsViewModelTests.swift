import XCTest

private enum RejectedGatewayFixture {
    static let gatewayURL = ["https://gateway", "example", "invalid"].joined(separator: ".")
    static let apiKey = ["test", "placeholder", "key"].joined(separator: "-")
    static let selectedModel = ["test", "placeholder", "model"].joined(separator: "-")
}

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private var previousSecureStore: AppConfigSecureStore!

    override func setUp() {
        super.setUp()
        previousSecureStore = AppConfig.secureStore
        AppConfig.secureStore = SettingsInMemorySecureStore()
    }

    override func tearDown() {
        AppConfig.secureStore = previousSecureStore
        previousSecureStore = nil
        super.tearDown()
    }

    private func savedGatewayConfig(
        provider: OpenKeyboardAIProvider = .openAICompatible,
        baseURL: String = "https://existing.example",
        apiKey: String = "existing-key",
        model: String = "old-model"
    ) -> AppConfig {
        AppConfig(
            apiKey: apiKey,
            gatewayURL: baseURL,
            selectedModel: model,
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion,
            provider: provider
        )
    }




    func testSettingsViewModelRejectsPlaceholderConfigAsVerifiedState() {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.placeholder.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let placeholder = AppConfig(
            apiKey: RejectedGatewayFixture.apiKey,
            gatewayURL: RejectedGatewayFixture.gatewayURL,
            selectedModel: RejectedGatewayFixture.selectedModel,
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        defaults.set(true, forKey: "keyboardExtension.uiTestDebugStateEnabled")

        let viewModel = SettingsViewModel(config: placeholder, gatewayTester: FakeGatewayTester(), defaults: defaults)

        XCTAssertEqual(viewModel.gatewayURLInput, "https://")
        XCTAssertEqual(viewModel.apiKeyInput, "")
        XCTAssertEqual(viewModel.config.gatewayURL, "")
        XCTAssertEqual(viewModel.config.apiKey, "")
        XCTAssertEqual(viewModel.config.selectedModel, "")
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.trustedModelLoaded)
        XCTAssertEqual(viewModel.trustedModelDisplay, "Test connection to load model")
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
        XCTAssertFalse(defaults.bool(forKey: "keyboardExtension.uiTestDebugStateEnabled"))
    }

    func testApplyConfigRejectsPlaceholderConfigAsVerifiedState() {
        let viewModel = SettingsViewModel(config: .default, gatewayTester: FakeGatewayTester())
        let placeholder = AppConfig(
            apiKey: RejectedGatewayFixture.apiKey,
            gatewayURL: RejectedGatewayFixture.gatewayURL,
            selectedModel: RejectedGatewayFixture.selectedModel,
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )

        viewModel.applyConfig(placeholder)

        XCTAssertEqual(viewModel.gatewayURLInput, "https://")
        XCTAssertEqual(viewModel.config.gatewayURL, "")
        XCTAssertEqual(viewModel.config.apiKey, "")
        XCTAssertEqual(viewModel.config.selectedModel, "")
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.trustedModelLoaded)
    }

    func testDocumentationLinkUsesPublicPortfolioProjectURL() {
        let url = SettingsDocumentationLink.url

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "myadidi.com")
        XCTAssertEqual(url.path, "/projects/open-keyboard-llm-gateway")
        XCTAssertFalse(url.absoluteString.localizedCaseInsensitiveContains("Gateway Admin"))
        XCTAssertFalse(url.absoluteString.localizedCaseInsensitiveContains("admin"))
    }

    func testApplyConfigSyncsDraftInputsAndValidatedDisplay() {
        let viewModel = SettingsViewModel(config: .default, gatewayTester: FakeGatewayTester())
        let validated = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )

        viewModel.applyConfig(validated)

        XCTAssertEqual(viewModel.gatewayURLInput, "https://gateway.example")
        XCTAssertEqual(viewModel.apiKeyInput, "working-key")
        XCTAssertFalse(viewModel.isEditingGatewayDraft)
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(viewModel.connectionStatus, .unknown)
    }

    func testCleanValidatedSettingsHideConnectionActionsAndShowTrustedDetails() {
        let suiteName = "SettingsViewModelTests.clean-validated.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppConfig.saveGatewayConnectionLastTestedAt(Date(), to: defaults)
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let viewModel = SettingsViewModel(
            config: config,
            gatewayTester: FakeGatewayTester(),
            defaults: defaults
        )

        XCTAssertFalse(viewModel.isEditingGatewayDraft)
        XCTAssertFalse(viewModel.shouldShowConnectionActions)
        XCTAssertTrue(viewModel.canTestConnection)
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(viewModel.trustedModelDisplay, "apple-foundationmodel")
        XCTAssertEqual(
            viewModel.grammarCapabilityDisplay,
            "Plain text verified"
        )
    }

    func testEditingValidatedGatewayHidesTrustedDetailsAndShowsConnectionActions() {
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let viewModel = SettingsViewModel(config: config, gatewayTester: FakeGatewayTester())

        viewModel.updateGatewayURLInput("https://edited-gateway.example")

        XCTAssertTrue(viewModel.isEditingGatewayDraft)
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertTrue(viewModel.canTestConnection)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.trustedModelLoaded)
        XCTAssertEqual(viewModel.trustedModelDisplay, "Test connection to load model")
        XCTAssertEqual(viewModel.grammarCapabilityDisplay, "Loaded after Test Connection")
    }

    func testEditingValidatedAPIKeyHidesTrustedDetailsAndShowsConnectionActions() {
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let viewModel = SettingsViewModel(config: config, gatewayTester: FakeGatewayTester())

        viewModel.updateAPIKeyInput("edited-key")

        XCTAssertTrue(viewModel.isEditingGatewayDraft)
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertTrue(viewModel.canTestConnection)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
    }

    func testConnectionActionsDisableWhenDirtyDraftIsIncomplete() {
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let viewModel = SettingsViewModel(config: config, gatewayTester: FakeGatewayTester())

        viewModel.updateAPIKeyInput("   ")

        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertFalse(viewModel.canTestConnection)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
    }

    func testUnvalidatedConfigDoesNotExposeTrustedModel() {
        let viewModel = SettingsViewModel(
            config: AppConfig(
                apiKey: "draft-key",
                gatewayURL: "https://gateway.example",
                selectedModel: "locally-typed-model",
                isConfigured: false,
                supportsStructuredCorrections: false,
                structuredCorrectionSchemaVersion: ""
            ),
            gatewayTester: FakeGatewayTester()
        )

        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.trustedModelLoaded)
        XCTAssertEqual(viewModel.trustedModelDisplay, "Test connection to load model")
        XCTAssertEqual(viewModel.grammarCapabilityDisplay, "Loaded after Test Connection")
    }


    func testGlobalConnectionErrorAppearsAndHidesModelDetails() {
        let suiteName = "settings.error.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppConfig.saveGatewayConnectionError("Gateway timed out", to: defaults)
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )

        let viewModel = SettingsViewModel(config: config, gatewayTester: FakeGatewayTester(), defaults: defaults)

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.errorMessage, "Gateway timed out")
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.trustedModelLoaded)
        XCTAssertEqual(viewModel.trustedModelDisplay, "Test connection to load model")
        XCTAssertFalse(viewModel.isGatewayValidationInProgress)
    }

    func testGatewayFailureTakesPrecedenceOverInFlightCheckingFlag() {
        let viewModel = SettingsViewModel(config: .default, gatewayTester: FakeGatewayTester())
        viewModel.isTestingConnection = true
        viewModel.connectionStatus = .failure
        viewModel.errorMessage = "Gateway timed out"

        XCTAssertFalse(viewModel.isGatewayValidationInProgress)
    }


    func testSavedConfigStartsUnverifiedUntilLaunchValidationSucceeds() async {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.saved-success.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(models: ["apple-foundationmodel"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: config, gatewayTester: tester, defaults: defaults)

        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertTrue(viewModel.shouldShowGatewayValidationPending)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(viewModel.trustedModelDisplay, "Test connection to load model")

        await viewModel.validateSavedGatewayOnceOnLaunch()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(viewModel.trustedModelDisplay, "apple-foundationmodel")
    }

    func testSavedConfigLaunchValidationFailureKeepsCachedValuesButNotReady() async {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.saved-failure.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(healthSucceeds: false)
        let viewModel = SettingsViewModel(config: config, gatewayTester: tester, defaults: defaults)

        await viewModel.validateSavedGatewayOnceOnLaunch()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(viewModel.config.gatewayURL, "https://gateway.example")
        XCTAssertEqual(viewModel.config.apiKey, "working-key")
        XCTAssertEqual(viewModel.config.selectedModel, "apple-foundationmodel")
        XCTAssertTrue(viewModel.config.isConfigured)
    }

    func testSavedConfigLaunchValidationRunsOnlyOnceAndGuardsConcurrentCalls() async {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.saved-once.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(models: ["apple-foundationmodel"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: config, gatewayTester: tester, defaults: defaults)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await viewModel.validateSavedGatewayOnceOnLaunch() }
            group.addTask { await viewModel.validateSavedGatewayOnceOnLaunch() }
        }
        await viewModel.validateSavedGatewayOnceOnLaunch()

        XCTAssertEqual(tester.modelFetches, 1)
        XCTAssertEqual(tester.smokeModels, ["apple-foundationmodel"])
    }

    func testSavedConfigLaunchValidationUsesRecentDefaultTimestampWithoutNetwork() async {
        let suiteName = "SettingsViewModelTests.saved-recent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppConfig.saveGatewayConnectionLastTestedAt(Date(), to: defaults)
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(models: ["apple-foundationmodel"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: config, gatewayTester: tester, defaults: defaults)

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.shouldShowGatewayValidationPending)

        await viewModel.validateSavedGatewayOnceOnLaunch()

        XCTAssertEqual(tester.modelFetches, 0)
        XCTAssertTrue(viewModel.trustedModelLoaded)
    }

    func testRecentLegacyStructuredCapabilityForcesPlainTextGrammarRevalidation() async {
        let suiteName = "SettingsViewModelTests.saved-legacy-capability.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppConfig.saveGatewayConnectionLastTestedAt(Date(), to: defaults)
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: false,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
        let tester = FakeGatewayTester(models: ["apple-foundationmodel"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: config, gatewayTester: tester, defaults: defaults)

        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertTrue(viewModel.shouldShowGatewayValidationPending)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)

        await viewModel.validateSavedGatewayOnceOnLaunch()

        XCTAssertEqual(tester.modelFetches, 1)
        XCTAssertEqual(tester.smokeModels, ["apple-foundationmodel"])
        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertTrue(viewModel.config.supportsStructuredCorrections)
        XCTAssertEqual(viewModel.config.structuredCorrectionSchemaVersion, AppConfig.grammarCorrectionCapabilityVersion)
        XCTAssertEqual(viewModel.grammarCapabilityDisplay, "Plain text verified")
    }

    func testRecentConnectedConfigPreservesUnverifiedModelCapabilityWithoutGatewayError() async {
        let suiteName = "SettingsViewModelTests.saved-limited.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppConfig.saveGatewayConnectionLastTestedAt(Date(), to: defaults)
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "gemma2:2b",
            isConfigured: true,
            supportsStructuredCorrections: false,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(models: ["gemma2:2b"], smokeSucceeds: false)
        let viewModel = SettingsViewModel(config: config, gatewayTester: tester, defaults: defaults)

        XCTAssertEqual(viewModel.connectionStatus, .limited)
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
        XCTAssertTrue(viewModel.trustedModelLoaded)
        XCTAssertFalse(viewModel.hasConnectionError)
        XCTAssertEqual(viewModel.grammarCapabilityDisplay, "Not verified for selected model")

        await viewModel.validateSavedGatewayOnceOnLaunch()

        XCTAssertEqual(tester.modelFetches, 0)
        XCTAssertNil(AppConfig.gatewayConnectionError(from: defaults))
    }

    func testSavedConfigLaunchValidationRunsAgainAfterOneHourAndRefreshesTimestamp() async {
        let suiteName = "SettingsViewModelTests.saved-stale.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let staleTimestamp = Date().addingTimeInterval(-(AppConfig.gatewayConnectionRetestInterval + 1))
        AppConfig.saveGatewayConnectionLastTestedAt(staleTimestamp, to: defaults)
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(models: ["apple-foundationmodel"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: config, gatewayTester: tester, defaults: defaults)

        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertTrue(viewModel.shouldShowGatewayValidationPending)

        let validationStartedAt = Date()
        await viewModel.validateSavedGatewayOnceOnLaunch()

        let refreshedTimestamp = AppConfig.gatewayConnectionLastTestedAt(from: defaults)
        XCTAssertEqual(tester.modelFetches, 1)
        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertGreaterThanOrEqual(refreshedTimestamp?.timeIntervalSince1970 ?? 0, validationStartedAt.timeIntervalSince1970)
    }

    func testBareGatewayHostNormalizesToHTTPSBeforeSaving() async {
        let tester = FakeGatewayTester(models: ["gpt-oss:120b-cloud"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("localhost")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(viewModel.gatewayURLInput, "https://localhost")
        XCTAssertEqual(viewModel.config.gatewayURL, "https://localhost")
        XCTAssertEqual(tester.fetchedGatewayURL, "https://localhost")
    }

    func testGatewayURLWithV1PathDoesNotDuplicateEndpointPrefix() throws {
        let modelsURL = try NetworkManager.endpointURL(gatewayURL: "https://localhost/v1/", path: "v1/models")
        let chatURL = try NetworkManager.endpointURL(gatewayURL: "localhost", path: "/v1/chat/completions")

        XCTAssertEqual(modelsURL.absoluteString, "https://localhost/v1/models")
        XCTAssertEqual(chatURL.absoluteString, "https://localhost/v1/chat/completions")
    }

    func testRetrySuccessClearsGlobalConnectionError() async {
        let suiteName = "settings.retry.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppConfig.saveGatewayConnectionError("Previous failure", to: defaults)
        let tester = FakeGatewayTester(models: ["gpt-oss:120b-cloud"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(AppConfig.gatewayConnectionError(from: defaults))
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
    }

    func testRetryFailurePersistsGlobalConnectionErrorAndKeepsRetryVisible() async {
        let suiteName = "settings.retry.failure.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tester = FakeGatewayTester(healthSucceeds: false)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
        viewModel.updateGatewayURLInput("https://bad.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(AppConfig.gatewayConnectionError(from: defaults), viewModel.errorMessage)
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
    }

    func testChangedCredentialsWithMultipleModelsRequireExplicitSelectionAndDoNotFallback() async {
        let tester = FakeGatewayTester(
            models: ["apple-foundationmodel", "gpt-oss:120b-cloud"],
            failingSmokeModels: ["apple-foundationmodel"]
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertTrue(viewModel.shouldShowModelSelection)
        XCTAssertTrue(viewModel.modelSelectionRequired)
        XCTAssertTrue(tester.smokeModels.isEmpty)
        XCTAssertFalse(viewModel.config.isConfigured)

        viewModel.updateSelectedModelInput("apple-foundationmodel")
        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertEqual(tester.smokeModels, ["apple-foundationmodel"])
    }

    func testSameCredentialsRequireExactSavedModelWithoutCatalogFallback() async {
        let configured = AppConfig(
            apiKey: "existing-key",
            gatewayURL: "https://existing.example",
            selectedModel: "gemma2:2b",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(models: ["another-model"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester)

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.errorMessage, NetworkError.modelUnavailable.localizedDescription)
        XCTAssertEqual(viewModel.config.selectedModel, "gemma2:2b")
        XCTAssertTrue(tester.smokeModels.isEmpty)
    }

    func testSameCredentialsCanSaveANewExplicitlySelectedExactModel() async {
        let suiteName = "SettingsViewModelTests.same-credentials-model-change.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configured = savedGatewayConfig(
            provider: .openRouter,
            baseURL: "https://openrouter.ai/api/v1"
        )
        XCTAssertTrue(configured.save(to: defaults))
        AppConfig.saveGatewayConnectionLastTestedAt(Date(), to: defaults)
        let tester = FakeGatewayTester(models: ["old-model", "new-model"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester, defaults: defaults)

        XCTAssertEqual(viewModel.modelDiscoveryActionTitle, "Change Model")
        await viewModel.loadModels()

        XCTAssertEqual(tester.fetchedProfiles.count, 1)
        XCTAssertEqual(tester.fetchedProfiles[0].provider, .openRouter)
        XCTAssertEqual(tester.fetchedProfiles[0].baseURL, configured.baseURL)
        XCTAssertEqual(tester.fetchedProfiles[0].apiKey, configured.apiKey)
        XCTAssertTrue(viewModel.shouldShowModelSelection)
        XCTAssertEqual(viewModel.selectedModelInput, "old-model")
        XCTAssertEqual(viewModel.config, configured)
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)

        viewModel.updateSelectedModelInput("new-model")

        XCTAssertEqual(viewModel.selectedProvider, configured.provider)
        XCTAssertEqual(viewModel.gatewayURLInput, configured.baseURL)
        XCTAssertEqual(viewModel.apiKeyInput, configured.apiKey)
        XCTAssertEqual(viewModel.config, configured)
        XCTAssertEqual(AppConfig.load(from: defaults), configured)
        XCTAssertTrue(viewModel.isEditingGatewayDraft)
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(viewModel.connectionStatus, .unknown)

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(viewModel.config.selectedModel, "new-model")
        XCTAssertEqual(tester.smokeModels, ["new-model"])
        XCTAssertFalse(viewModel.shouldShowModelSelection)
        XCTAssertTrue(viewModel.availableModels.isEmpty)
        XCTAssertEqual(viewModel.modelDiscoveryState, .idle)
        XCTAssertEqual(viewModel.modelDiscoveryActionTitle, "Change Model")
        XCTAssertEqual(AppConfig.load(from: defaults).selectedModel, "new-model")
    }

    func testModelDiscoveryActionTitleTracksLoadLoadingAndRetryStates() async {
        let tester = FakeGatewayTester(models: ["late-model"])
        tester.connectionDelayNanoseconds = 50_000_000
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: nil)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        XCTAssertEqual(viewModel.modelDiscoveryActionTitle, "Load Models")

        let loadTask = Task { await viewModel.loadModels() }
        for _ in 0..<100 where tester.modelFetches == 0 { await Task.yield() }

        XCTAssertEqual(viewModel.modelDiscoveryActionTitle, "Loading Models...")

        viewModel.cancelModelDiscovery()
        await loadTask.value

        XCTAssertEqual(viewModel.modelDiscoveryActionTitle, "Retry Models")
    }

    func testChangeModelDoesNotSilentlySelectASoleReplacementForMissingSavedModel() async {
        let suiteName = "SettingsViewModelTests.change-missing-saved-model.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configured = savedGatewayConfig()
        XCTAssertTrue(configured.save(to: defaults))
        AppConfig.saveGatewayConnectionLastTestedAt(Date(), to: defaults)
        let tester = FakeGatewayTester(models: ["replacement-model"])
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester, defaults: defaults)

        await viewModel.loadModels()

        XCTAssertTrue(viewModel.shouldShowModelSelection)
        XCTAssertTrue(viewModel.modelSelectionRequired)
        XCTAssertTrue(viewModel.selectedModelInput.isEmpty)
        XCTAssertEqual(viewModel.availableModels, ["replacement-model"])
        XCTAssertNotNil(viewModel.modelSelectionMessage)
        XCTAssertFalse(viewModel.canTestConnection)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(viewModel.config, configured)
        XCTAssertEqual(AppConfig.load(from: defaults), configured)
        XCTAssertTrue(tester.smokeModels.isEmpty)

        viewModel.updateSelectedModelInput("replacement-model")

        XCTAssertEqual(viewModel.selectedModelInput, "replacement-model")
        XCTAssertFalse(viewModel.modelSelectionRequired)
        XCTAssertTrue(viewModel.canTestConnection)
        XCTAssertEqual(viewModel.config, configured)
    }

    func testFailedReplacementModelPreservesCommittedProfileValidationAndGlobalErrorState() async {
        let suiteName = "SettingsViewModelTests.failed-model-replacement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configured = savedGatewayConfig()
        XCTAssertTrue(configured.save(to: defaults))
        let previousValidationDate = Date().addingTimeInterval(-120)
        AppConfig.saveGatewayConnectionLastTestedAt(previousValidationDate, to: defaults)
        let tester = FakeGatewayTester(
            models: ["old-model", "failing-model"],
            failingSmokeModels: ["failing-model"]
        )
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester, defaults: defaults)

        await viewModel.loadModels()
        viewModel.updateSelectedModelInput("failing-model")
        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(tester.smokeModels, ["failing-model"])
        XCTAssertEqual(viewModel.config, configured)
        XCTAssertEqual(AppConfig.load(from: defaults), configured)
        XCTAssertNil(AppConfig.gatewayConnectionError(from: defaults))
        guard let retainedValidationDate = AppConfig.gatewayConnectionLastTestedAt(from: defaults) else {
            return XCTFail("The previous model validation timestamp should be preserved.")
        }
        XCTAssertEqual(
            retainedValidationDate.timeIntervalSince1970,
            previousValidationDate.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testStaleReplacementSmokeFailureCannotPoisonSavedModelAfterSelectionChanges() async {
        let suiteName = "SettingsViewModelTests.stale-model-replacement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configured = AppConfig(
            apiKey: "existing-key",
            gatewayURL: "https://existing.example",
            selectedModel: "old-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(configured.save(to: defaults))
        let previousValidationDate = Date().addingTimeInterval(-120)
        AppConfig.saveGatewayConnectionLastTestedAt(previousValidationDate, to: defaults)
        let tester = FakeGatewayTester(
            models: ["old-model", "failing-model"],
            failingSmokeModels: ["failing-model"]
        )
        tester.smokeDelayNanoseconds = 50_000_000
        tester.ignoresSmokeCancellation = true
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester, defaults: defaults)

        await viewModel.loadModels()
        viewModel.updateSelectedModelInput("failing-model")
        let connectionTask = Task { await viewModel.testConnection() }
        for _ in 0..<100 where tester.smokeModels.isEmpty { await Task.yield() }
        XCTAssertEqual(tester.smokeModels, ["failing-model"])

        connectionTask.cancel()
        viewModel.updateSelectedModelInput("old-model")
        await connectionTask.value

        XCTAssertEqual(viewModel.selectedModelInput, "old-model")
        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.config, configured)
        XCTAssertEqual(AppConfig.load(from: defaults), configured)
        XCTAssertNil(AppConfig.gatewayConnectionError(from: defaults))
        guard let retainedValidationDate = AppConfig.gatewayConnectionLastTestedAt(from: defaults) else {
            return XCTFail("The saved model validation timestamp should survive a stale failure.")
        }
        XCTAssertEqual(
            retainedValidationDate.timeIntervalSince1970,
            previousValidationDate.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testSavedModelValidationIsCaseSensitiveAndDoesNotRewriteConnectorIdentifiers() async {
        let configured = AppConfig(
            apiKey: "existing-key",
            gatewayURL: "https://existing.example",
            selectedModel: "Exact-Model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(models: ["exact-model"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester)

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.errorMessage, NetworkError.modelUnavailable.localizedDescription)
        XCTAssertEqual(viewModel.config.selectedModel, "Exact-Model")
        XCTAssertEqual(viewModel.availableModels, ["exact-model"])
        XCTAssertTrue(tester.smokeModels.isEmpty)
    }

    func testChangedGatewayURLDiscardsSavedModelForDraftAndAutoSelectsSingleDiscoveredModel() async {
        let configured = AppConfig(
            apiKey: "existing-key",
            gatewayURL: "https://existing.example",
            selectedModel: "old-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(models: ["new-model"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://new.example")

        XCTAssertEqual(viewModel.selectedModelInput, "")
        XCTAssertEqual(viewModel.config.selectedModel, "old-model")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(viewModel.config.gatewayURL, "https://new.example")
        XCTAssertEqual(viewModel.config.selectedModel, "new-model")
        XCTAssertEqual(tester.smokeModels, ["new-model"])
    }

    func testChangedAPIKeyDiscardsSavedModelForDraftAndAutoSelectsSingleDiscoveredModel() async {
        let configured = AppConfig(
            apiKey: "existing-key",
            gatewayURL: "https://existing.example",
            selectedModel: "old-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(models: ["new-model"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester)
        viewModel.updateAPIKeyInput("replacement-key")

        XCTAssertEqual(viewModel.selectedModelInput, "")
        XCTAssertEqual(viewModel.config.selectedModel, "old-model")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(viewModel.config.apiKey, "replacement-key")
        XCTAssertEqual(viewModel.config.selectedModel, "new-model")
    }

    func testChangedCredentialsWithZeroModelsPreserveCompletePreviousProfile() async {
        let suiteName = "SettingsViewModelTests.zero-models.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configured = AppConfig(
            apiKey: "existing-key",
            gatewayURL: "https://existing.example",
            selectedModel: "old-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(configured.save(to: defaults))
        let tester = FakeGatewayTester(models: [])
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester, defaults: defaults)
        viewModel.updateGatewayURLInput("https://empty.example")
        viewModel.updateAPIKeyInput("replacement-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.config.gatewayURL, "https://existing.example")
        XCTAssertEqual(viewModel.config.apiKey, "existing-key")
        XCTAssertEqual(viewModel.config.selectedModel, "old-model")
        XCTAssertTrue(tester.smokeModels.isEmpty)
        let persisted = AppConfig.load(from: defaults)
        XCTAssertEqual(persisted.gatewayURL, configured.gatewayURL)
        XCTAssertEqual(persisted.apiKey, configured.apiKey)
        XCTAssertEqual(persisted.selectedModel, configured.selectedModel)
        XCTAssertTrue(persisted.isConfigured)
        XCTAssertTrue(persisted.grammarCorrectionVerified)
    }

    func testResetOnboardingClearsPersistedFlagAndShowsConfirmation() {
        let suiteName = "settings.onboarding.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "hasCompletedOnboarding")
        let viewModel = SettingsViewModel(config: .default, gatewayTester: FakeGatewayTester(), defaults: defaults)

        viewModel.resetOnboarding()

        XCTAssertFalse(defaults.bool(forKey: "hasCompletedOnboarding"))
        XCTAssertEqual(viewModel.onboardingResetMessage, "Onboarding will show again after you close Settings.")
    }

    func testSuccessfulTestConnectionPersistsValidatedModelAndGrammarCapability() async {
        let tester = FakeGatewayTester(
            healthSucceeds: true,
            models: ["gemma4:latest", "apple-foundationmodel"],
            smokeSucceeds: true
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.gatewayURLInput = " https://gateway.example "
        viewModel.apiKeyInput = " test-key "

        await viewModel.testConnection()

        XCTAssertTrue(viewModel.modelSelectionRequired)
        XCTAssertFalse(viewModel.config.isConfigured)
        viewModel.updateSelectedModelInput("gemma4:latest")
        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(viewModel.config.gatewayURL, "https://gateway.example")
        XCTAssertEqual(viewModel.config.apiKey, "test-key")
        XCTAssertEqual(viewModel.config.selectedModel, "gemma4:latest")
        XCTAssertTrue(viewModel.config.isConfigured)
        XCTAssertTrue(viewModel.config.supportsStructuredCorrections)
        XCTAssertEqual(viewModel.config.structuredCorrectionSchemaVersion, AppConfig.grammarCorrectionCapabilityVersion)
        XCTAssertEqual(tester.smokeModel, "gemma4:latest")
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
        XCTAssertTrue(viewModel.trustedModelLoaded)
        XCTAssertEqual(viewModel.trustedModelDisplay, "gemma4:latest")
        XCTAssertEqual(viewModel.grammarCapabilityDisplay, "Plain text verified")
    }

    func testFailedTestConnectionDoesNotOverwriteExistingWorkingConfig() async {
        let existing = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://working.example",
            selectedModel: "gemma4:latest",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(healthSucceeds: false)
        let viewModel = SettingsViewModel(config: existing, gatewayTester: tester)
        viewModel.gatewayURLInput = "https://bad.example"
        viewModel.apiKeyInput = "bad-key"

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.config.gatewayURL, "https://working.example")
        XCTAssertEqual(viewModel.config.apiKey, "working-key")
        XCTAssertEqual(viewModel.config.selectedModel, "gemma4:latest")
        XCTAssertTrue(viewModel.config.isConfigured)
        XCTAssertTrue(viewModel.config.supportsStructuredCorrections)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.trustedModelLoaded)
    }

    func testEditingGatewayURLAfterSuccessHidesValidatedDetailsUntilRetested() async {
        let tester = FakeGatewayTester(
            healthSucceeds: true,
            models: ["apple-foundationmodel"],
            smokeSucceeds: true
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(viewModel.connectionStatus, .success)

        viewModel.updateGatewayURLInput("https://new-gateway.example")

        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertFalse(viewModel.trustedModelLoaded)
        XCTAssertEqual(viewModel.trustedModelDisplay, "Test connection to load model")
        XCTAssertEqual(viewModel.grammarCapabilityDisplay, "Loaded after Test Connection")
        XCTAssertEqual(viewModel.config.gatewayURL, "https://gateway.example")
    }

    func testEditingAPIKeyAfterSuccessHidesValidatedDetailsUntilRetested() async {
        let tester = FakeGatewayTester(
            healthSucceeds: true,
            models: ["apple-foundationmodel"],
            smokeSucceeds: true
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)

        viewModel.updateAPIKeyInput("new-test-key")

        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertFalse(viewModel.trustedModelLoaded)
        XCTAssertEqual(viewModel.config.apiKey, "test-key")
    }

    func testUnusableCorrectionDoesNotReplacePersistedAtomicSecureProfile() async {
        let suiteName = "SettingsViewModelTests.model-capability.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let previous = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://working.example",
            selectedModel: "working-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(previous.save(to: defaults))
        let previousValidationDate = Date().addingTimeInterval(-60)
        AppConfig.saveGatewayConnectionLastTestedAt(previousValidationDate, to: defaults)
        let tester = FakeGatewayTester(
            healthSucceeds: true,
            models: ["gemma2:2b"],
            smokeSucceeds: false
        )
        let viewModel = SettingsViewModel(config: previous, gatewayTester: tester, defaults: defaults)
        viewModel.gatewayURLInput = "https://gateway.example"
        viewModel.apiKeyInput = "test-key"

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertFalse(viewModel.isTestingConnection)
        XCTAssertFalse(viewModel.isGatewayValidationInProgress)
        XCTAssertEqual(viewModel.config.gatewayURL, "https://working.example")
        XCTAssertEqual(viewModel.config.apiKey, "working-key")
        XCTAssertEqual(viewModel.config.selectedModel, "working-model")
        XCTAssertTrue(viewModel.config.isConfigured)
        XCTAssertTrue(viewModel.config.supportsStructuredCorrections)
        XCTAssertEqual(viewModel.config.structuredCorrectionSchemaVersion, AppConfig.grammarCorrectionCapabilityVersion)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertTrue(viewModel.hasConnectionError)
        let persisted = AppConfig.load(from: defaults)
        XCTAssertEqual(persisted.gatewayURL, previous.gatewayURL)
        XCTAssertEqual(persisted.apiKey, previous.apiKey)
        XCTAssertEqual(persisted.selectedModel, previous.selectedModel)
        XCTAssertTrue(persisted.grammarCorrectionVerified)
        XCTAssertNil(AppConfig.gatewayConnectionError(from: defaults))
        guard let persistedValidationDate = AppConfig.gatewayConnectionLastTestedAt(from: defaults) else {
            XCTFail("The previous profile validation timestamp should be preserved.")
            return
        }
        XCTAssertEqual(
            persistedValidationDate.timeIntervalSinceReferenceDate,
            previousValidationDate.timeIntervalSinceReferenceDate,
            accuracy: 0.001
        )
    }

    func testCorrectionTimeoutShowsTimeoutFailureInsteadOfModelCapability() async {
        let suiteName = "SettingsViewModelTests.model-timeout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tester = FakeGatewayTester(
            healthSucceeds: true,
            models: ["gpt-oss:120b-cloud"],
            smokeSucceeds: false,
            smokeFailure: NetworkError.timeout
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
        viewModel.gatewayURLInput = "https://gateway.example"
        viewModel.apiKeyInput = "test-key"

        await viewModel.testConnection()

        let timeoutMessage = "Gateway connected, but the selected model did not respond within 20 seconds. Choose a faster model or retry."
        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertTrue(viewModel.config.gatewayURL.isEmpty)
        XCTAssertTrue(viewModel.config.selectedModel.isEmpty)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertTrue(viewModel.hasConnectionError)
        XCTAssertEqual(viewModel.errorMessage, timeoutMessage)
        XCTAssertEqual(AppConfig.gatewayConnectionError(from: defaults), timeoutMessage)
        XCTAssertNil(AppConfig.gatewayConnectionLastTestedAt(from: defaults))
    }

    func testCancelledConnectionCheckDoesNotPersistGatewayFailure() async {
        let suiteName = "SettingsViewModelTests.connection-cancelled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tester = FakeGatewayTester(connectionFailure: CancellationError())
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(AppConfig.gatewayConnectionError(from: defaults))
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
    }

    func testCancelledCorrectionCheckDoesNotPersistGatewayFailure() async {
        let suiteName = "SettingsViewModelTests.correction-cancelled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tester = FakeGatewayTester(
            healthSucceeds: true,
            models: ["gpt-oss:120b-cloud"],
            smokeSucceeds: false,
            smokeFailure: CancellationError()
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(AppConfig.gatewayConnectionError(from: defaults))
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
    }

    func testDefaultGatewayInputShowsHTTPSHelpButCannotTestUntilHostExists() {
        let viewModel = SettingsViewModel(config: .default, gatewayTester: FakeGatewayTester())

        XCTAssertEqual(viewModel.gatewayURLInput, "https://")
        XCTAssertNil(viewModel.normalizedGatewayURLForTesting)
        XCTAssertFalse(viewModel.canTestConnection)
    }

    func testDiagnosticsCannotOverlapConnectionValidation() {
        let config = AppConfig(
            apiKey: "test-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "selected-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let viewModel = SettingsViewModel(config: config, gatewayTester: FakeGatewayTester())
        viewModel.isTestingConnection = true

        XCTAssertFalse(viewModel.canTestConnection)
        XCTAssertFalse(viewModel.canRunDiagnostics)
    }

    func testBareGatewayURLNormalizesBeforeTestingAndSaving() async {
        let tester = FakeGatewayTester(
            healthSucceeds: true,
            models: ["gpt-oss:120b-cloud"],
            smokeSucceeds: true
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(viewModel.gatewayURLInput, "https://gateway.example")
        XCTAssertEqual(viewModel.config.gatewayURL, "https://gateway.example")
        XCTAssertEqual(tester.testedGatewayURLs, ["https://gateway.example"])
    }

    func testPersistedGlobalGatewayErrorIsVisibleAndHidesValidatedDetails() {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.global-error.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        AppConfig.saveGatewayConnectionError("Keyboard detected gateway timeout", to: defaults)
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )

        let viewModel = SettingsViewModel(config: config, gatewayTester: FakeGatewayTester(), defaults: defaults)

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.errorMessage, "Keyboard detected gateway timeout")
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.trustedModelLoaded)
    }

    func testLaunchValidationPreservesPersistedGlobalGatewayErrorUntilRetry() async {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.global-error-launch.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        AppConfig.saveGatewayConnectionError("Keyboard detected gateway timeout", to: defaults)
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(models: ["apple-foundationmodel"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: config, gatewayTester: tester, defaults: defaults)

        await viewModel.validateSavedGatewayOnceOnLaunch()

        XCTAssertEqual(tester.modelFetches, 0)
        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.errorMessage, "Keyboard detected gateway timeout")
        XCTAssertEqual(AppConfig.gatewayConnectionError(from: defaults), "Keyboard detected gateway timeout")

        await viewModel.retrySavedGatewayValidation()

        XCTAssertEqual(tester.modelFetches, 1)
        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(AppConfig.gatewayConnectionError(from: defaults))
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
    }

    func testFailedTestConnectionPersistsGlobalErrorForSettingsRetry() async {
        let suiteName = "SettingsViewModelTests.failure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppConfig.saveGatewayConnectionLastTestedAt(Date(), to: defaults)
        let tester = FakeGatewayTester(healthSucceeds: false)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(AppConfig.gatewayConnectionError(from: defaults), "Connection failed")
        XCTAssertNil(AppConfig.gatewayConnectionLastTestedAt(from: defaults))
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
    }

    func testSuccessfulRetryClearsGlobalErrorAndSavesAtomicKeychainProfile() async {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.success.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let oldSecureStore = AppConfig.secureStore
        let secureStore = SettingsInMemorySecureStore()
        AppConfig.secureStore = secureStore
        defer { AppConfig.secureStore = oldSecureStore }
        AppConfig.saveGatewayConnectionError("Previous keyboard error", to: defaults)
        let tester = FakeGatewayTester(healthSucceeds: true, models: ["gpt-oss:120b-cloud"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertNil(AppConfig.gatewayConnectionError(from: defaults))
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.selectedModelKey))
        XCTAssertFalse(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertTrue(defaults.bool(forKey: AppConfig.gatewayProfileConfiguredHintKey))
        XCTAssertFalse((defaults.string(forKey: AppConfig.gatewayProfileRevisionHintKey) ?? "").isEmpty)
        XCTAssertEqual(secureStore.apiKey, "test-key")
        XCTAssertEqual(AppConfig.load(from: defaults), viewModel.config)
    }

    func testSuccessfulGatewayValidationFailsIfSharedConfigCannotBePersisted() async {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.save-failure.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let oldSecureStore = AppConfig.secureStore
        let secureStore = SettingsInMemorySecureStore()
        secureStore.shouldFailSave = true
        AppConfig.secureStore = secureStore
        defer { AppConfig.secureStore = oldSecureStore }
        let tester = FakeGatewayTester(healthSucceeds: true, models: ["gpt-oss:120b-cloud"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.errorMessage, "Could not save gateway configuration. Check Keychain access and try again.")
        XCTAssertEqual(AppConfig.gatewayConnectionError(from: defaults), viewModel.errorMessage)
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertFalse(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertNil(secureStore.apiKey)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
    }

    func testGatewayDiagnosticUsesDraftConfigWithoutSavingOrMarkingConnectionReady() async {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.diagnostic.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let tester = FakeGatewayTester(models: ["gpt-oss:120b-cloud", "gemma-model"])
        tester.diagnosticReport = GatewayDiagnosticReport(
            selectedModel: "gpt-oss:120b-cloud",
            checks: [
                GatewayDiagnosticCheck(
                    id: "models",
                    title: "Models",
                    endpoint: "GET /v1/models",
                    status: .passed,
                    durationMilliseconds: 12,
                    message: "Loaded 1 model."
                )
            ]
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
        viewModel.updateProvider(.anthropic)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()
        XCTAssertTrue(viewModel.modelSelectionRequired)
        viewModel.updateSelectedModelInput("gpt-oss:120b-cloud")

        await viewModel.runDiagnostics()

        XCTAssertFalse(viewModel.isRunningDiagnostics)
        XCTAssertEqual(viewModel.diagnosticReport, tester.diagnosticReport)
        XCTAssertEqual(tester.diagnosticProvider, .anthropic)
        XCTAssertEqual(tester.diagnosticGatewayURL, "https://gateway.example")
        XCTAssertEqual(tester.diagnosticAPIKey, "test-key")
        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
    }

    func testGatewayDiagnosticUsesNewExactModelSelectedForSavedCredentials() async {
        let configured = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "old-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester(models: ["old-model", "new-model"])
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester)

        await viewModel.loadModels()
        viewModel.updateSelectedModelInput("new-model")
        await viewModel.runDiagnostics()

        XCTAssertEqual(tester.diagnosticPreferredModel, "new-model")
        XCTAssertEqual(viewModel.config.selectedModel, "old-model")
    }

    func testCredentialEditDuringConnectionPreservesPreviousCommittedProfile() async {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.stale-connection.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let oldSecureStore = AppConfig.secureStore
        let secureStore = SettingsInMemorySecureStore()
        AppConfig.secureStore = secureStore
        defer { AppConfig.secureStore = oldSecureStore }
        let previous = AppConfig(
            apiKey: "previous-key",
            gatewayURL: "https://previous.example",
            selectedModel: "previous-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        XCTAssertTrue(previous.save(to: defaults))
        let tester = FakeGatewayTester(models: ["draft-a-model"])
        tester.connectionDelayNanoseconds = 50_000_000
        let viewModel = SettingsViewModel(config: previous, gatewayTester: tester, defaults: defaults)
        viewModel.updateGatewayURLInput("https://draft-a.example")
        viewModel.updateAPIKeyInput("draft-a-key")

        let connectionTask = Task { await viewModel.testConnection() }
        for _ in 0..<100 where tester.modelFetches == 0 { await Task.yield() }
        XCTAssertEqual(tester.modelFetches, 1)

        viewModel.updateGatewayURLInput("https://draft-b.example")
        viewModel.updateAPIKeyInput("draft-b-key")
        await connectionTask.value

        XCTAssertEqual(viewModel.gatewayURLInput, "https://draft-b.example")
        XCTAssertEqual(viewModel.apiKeyInput, "draft-b-key")
        XCTAssertEqual(viewModel.config, previous)
        XCTAssertEqual(AppConfig.load(from: defaults), previous)
        XCTAssertTrue(tester.smokeModels.isEmpty)
        XCTAssertEqual(viewModel.connectionStatus, .unknown)
    }

    func testCredentialEditDuringDiagnosticsDiscardsStaleReport() async {
        let configured = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "selected-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester()
        tester.diagnosticDelayNanoseconds = 50_000_000
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester)

        let diagnosticTask = Task { await viewModel.runDiagnostics() }
        for _ in 0..<100 where tester.diagnosticPreferredModel == nil { await Task.yield() }
        XCTAssertEqual(tester.diagnosticPreferredModel, "selected-model")

        viewModel.updateAPIKeyInput("replacement-key")
        await diagnosticTask.value

        XCTAssertNil(viewModel.diagnosticReport)
        XCTAssertFalse(viewModel.isRunningDiagnostics)
        XCTAssertEqual(viewModel.apiKeyInput, "replacement-key")
    }

    func testCancelledDiagnosticsDiscardReportAndClearLoadingState() async {
        let configured = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "selected-model",
            isConfigured: true,
            grammarCorrectionVerified: true,
            grammarCorrectionContractVersion: AppConfig.grammarCorrectionCapabilityVersion
        )
        let tester = FakeGatewayTester()
        tester.diagnosticDelayNanoseconds = 1_000_000_000
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester)

        let diagnosticTask = Task { await viewModel.runDiagnostics() }
        for _ in 0..<100 where tester.diagnosticPreferredModel == nil { await Task.yield() }
        XCTAssertEqual(tester.diagnosticPreferredModel, "selected-model")

        diagnosticTask.cancel()
        await diagnosticTask.value

        XCTAssertNil(viewModel.diagnosticReport)
        XCTAssertFalse(viewModel.isRunningDiagnostics)
    }

    func testExplicitModelValidationDoesNotFallbackWhenSelectedModelFailsSmoke() async {
        let tester = FakeGatewayTester(
            healthSucceeds: true,
            models: ["apple-foundationmodel", "gpt-oss:120b-cloud"],
            smokeSucceeds: true,
            failingSmokeModels: ["apple-foundationmodel"]
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()
        viewModel.updateSelectedModelInput("apple-foundationmodel")
        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(tester.smokeModels, ["apple-foundationmodel"])
        XCTAssertFalse(viewModel.config.isConfigured)
    }

    func testResetOnboardingClearsSharedAndStandardFlags() {
        let suiteName = "SettingsViewModelTests.onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: AppConfig.hasCompletedOnboardingKey)
        UserDefaults.standard.set(true, forKey: AppConfig.hasCompletedOnboardingKey)
        defer { UserDefaults.standard.removeObject(forKey: AppConfig.hasCompletedOnboardingKey) }
        let viewModel = SettingsViewModel(config: .default, gatewayTester: FakeGatewayTester(), defaults: defaults)

        viewModel.resetOnboarding()

        XCTAssertFalse(defaults.bool(forKey: AppConfig.hasCompletedOnboardingKey))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppConfig.hasCompletedOnboardingKey))
        XCTAssertNotNil(viewModel.onboardingResetMessage)
    }

    func testEveryProviderSuppliesAnEditableDefaultBaseURL() {
        let expectations: [(OpenKeyboardAIProvider, String)] = [
            (.openAI, "https://api.openai.com/v1"),
            (.anthropic, "https://api.anthropic.com/v1"),
            (.openRouter, "https://openrouter.ai/api/v1"),
            (.openAICompatible, "https://")
        ]

        for (provider, expectedDefault) in expectations {
            let viewModel = SettingsViewModel(config: .default, gatewayTester: FakeGatewayTester())

            viewModel.updateProvider(provider)

            XCTAssertEqual(viewModel.selectedProvider, provider)
            XCTAssertEqual(viewModel.gatewayURLInput, expectedDefault)

            let customBaseURL = "https://custom-\(provider.rawValue).example/provider/path"
            viewModel.updateGatewayURLInput(customBaseURL)
            XCTAssertEqual(viewModel.gatewayURLInput, customBaseURL)
        }
    }

    func testProviderBaseURLTransportPolicyMatchesConnectorBoundary() throws {
        for provider in [
            OpenKeyboardAIProvider.openAI,
            .anthropic,
            .openRouter
        ] {
            XCTAssertThrowsError(
                try NetworkManager.normalizedProviderBaseURLString(
                    "http://provider.example/v1",
                    provider: provider
                )
            ) { error in
                guard let networkError = error as? NetworkError,
                      case .invalidURL = networkError else {
                    return XCTFail("Expected direct-provider HTTP to fail as an invalid URL.")
                }
            }
            XCTAssertEqual(
                try NetworkManager.normalizedProviderBaseURLString(
                    "https://provider.example/prefix/",
                    provider: provider
                ),
                "https://provider.example/prefix"
            )
        }

        let acceptedCompatibleURLs = [
            ("https://gateway.example/prefix/", "https://gateway.example/prefix"),
            ("http://localhost:11434/v1", "http://localhost:11434"),
            ("http://127.0.0.1:11434/v1/", "http://127.0.0.1:11434"),
            ("http://127.255.255.255:11434/v1", "http://127.255.255.255:11434"),
            ("http://[::1]:11434/v1", "http://[::1]:11434"),
            ("http://[0:0:0:0:0:0:0:1]:11434/v1", "http://[0:0:0:0:0:0:0:1]:11434")
        ]
        for (input, expected) in acceptedCompatibleURLs {
            XCTAssertEqual(
                try NetworkManager.normalizedProviderBaseURLString(
                    input,
                    provider: .openAICompatible
                ),
                expected,
                input
            )
        }

        let rejectedCompatibleURLs = [
            "http://gateway.local:11434/v1",
            "http://192.168.1.10:11434/v1",
            "http://example.com/v1",
            "http://localhost.example/v1",
            "http://localhost./v1",
            "http://127.0.0.01/v1",
            "http://127.0.0.1.example/v1",
            "http://[::2]/v1",
            "http://[::ffff:127.0.0.1]/v1",
            "https://user@example.com/v1",
            "https://user:password@example.com/v1",
            "https://example.com:/v1",
            "https://example.com:invalid/v1",
            "https://2001:db8::1/v1",
            "https://example.com/v1?mode=unsafe",
            "https://example.com/v1#fragment",
            "https://example.com/api//v1",
            "https://example.com/api/../v1",
            "https://example.com/api/%2e%2e/v1",
            "https://example.com/api/%252e%252e/v1",
            "https://example.com/api%2fv1",
            "https://example.com/api%5cv1",
            "https://example.com\\api",
            "https://example.com/api/\u{202e}v1"
        ]
        for input in rejectedCompatibleURLs {
            XCTAssertThrowsError(
                try NetworkManager.normalizedProviderBaseURLString(
                    input,
                    provider: .openAICompatible
                ),
                input
            ) { error in
                guard let networkError = error as? NetworkError,
                      case .invalidURL = networkError else {
                    return XCTFail("Expected connector-incompatible base URL to fail validation.")
                }
            }
        }
    }

    func testLoadModelsUsesProviderProfileAndPublishesExactCatalog() async {
        let tester = FakeGatewayTester(models: ["Exact-Model", "second-model", "Exact-Model"])
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateProvider(.anthropic)
        viewModel.updateGatewayURLInput("https://anthropic-proxy.example/v1")
        viewModel.updateAPIKeyInput(" anthropic-key ")

        await viewModel.loadModels()

        XCTAssertEqual(viewModel.modelDiscoveryState, .loaded)
        XCTAssertEqual(viewModel.availableModels, ["Exact-Model", "second-model"])
        XCTAssertTrue(viewModel.shouldShowModelSelection)
        XCTAssertTrue(viewModel.modelSelectionRequired)
        XCTAssertFalse(viewModel.shouldShowManualModelEntry)
        XCTAssertEqual(tester.modelFetches, 1)
        XCTAssertEqual(tester.fetchedProfiles.count, 1)
        XCTAssertEqual(tester.fetchedProfiles[0].provider, .anthropic)
        XCTAssertEqual(tester.fetchedProfiles[0].baseURL, "https://anthropic-proxy.example/v1")
        XCTAssertEqual(tester.fetchedProfiles[0].apiKey, "anthropic-key")
        XCTAssertTrue(tester.smokeModels.isEmpty)
    }

    func testLoadModelsTreatsEmptyCatalogAsFailureWithoutManualFallback() async {
        let tester = FakeGatewayTester(models: [])
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.loadModels()

        XCTAssertEqual(
            viewModel.modelDiscoveryState,
            .failed("No models were returned by this provider.")
        )
        XCTAssertEqual(viewModel.modelSelectionMessage, "No models were returned by this provider.")
        XCTAssertTrue(viewModel.availableModels.isEmpty)
        XCTAssertFalse(viewModel.shouldShowManualModelEntry)
        viewModel.updateSelectedModelInput("must-not-be-accepted")
        XCTAssertTrue(viewModel.selectedModelInput.isEmpty)
    }

    func testChangeModelEmptyCatalogPreservesCommittedModelAndCredentials() async {
        let configured = savedGatewayConfig()
        let viewModel = SettingsViewModel(
            config: configured,
            gatewayTester: FakeGatewayTester(models: []),
            defaults: nil
        )

        await viewModel.loadModels()

        XCTAssertEqual(
            viewModel.modelDiscoveryState,
            .failed("No models were returned by this provider.")
        )
        XCTAssertEqual(viewModel.selectedProvider, configured.provider)
        XCTAssertEqual(viewModel.gatewayURLInput, configured.baseURL)
        XCTAssertEqual(viewModel.apiKeyInput, configured.apiKey)
        XCTAssertEqual(viewModel.selectedModelInput, configured.selectedModel)
        XCTAssertEqual(viewModel.config, configured)
        XCTAssertEqual(viewModel.modelDiscoveryActionTitle, "Retry Models")
    }

    func testChangeModelFetchFailurePreservesCommittedModelAndCredentials() async {
        let configured = savedGatewayConfig()
        let viewModel = SettingsViewModel(
            config: configured,
            gatewayTester: FakeGatewayTester(modelFetchFailure: NetworkError.timeout),
            defaults: nil
        )

        await viewModel.loadModels()

        guard case .failed = viewModel.modelDiscoveryState else {
            return XCTFail("Change Model should expose a retryable discovery failure.")
        }
        XCTAssertEqual(viewModel.selectedProvider, configured.provider)
        XCTAssertEqual(viewModel.gatewayURLInput, configured.baseURL)
        XCTAssertEqual(viewModel.apiKeyInput, configured.apiKey)
        XCTAssertEqual(viewModel.selectedModelInput, configured.selectedModel)
        XCTAssertEqual(viewModel.config, configured)
        XCTAssertEqual(viewModel.modelDiscoveryActionTitle, "Retry Models")
    }

    func testCancellingChangeModelPreservesCommittedModelAndCredentials() async {
        let configured = savedGatewayConfig()
        let tester = FakeGatewayTester(models: ["old-model", "late-model"])
        tester.connectionDelayNanoseconds = 50_000_000
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester, defaults: nil)

        let loadTask = Task { await viewModel.loadModels() }
        for _ in 0..<100 where tester.modelFetches == 0 { await Task.yield() }
        viewModel.cancelModelDiscovery()
        await loadTask.value

        XCTAssertEqual(viewModel.modelDiscoveryState, .cancelled)
        XCTAssertEqual(viewModel.selectedProvider, configured.provider)
        XCTAssertEqual(viewModel.gatewayURLInput, configured.baseURL)
        XCTAssertEqual(viewModel.apiKeyInput, configured.apiKey)
        XCTAssertEqual(viewModel.selectedModelInput, configured.selectedModel)
        XCTAssertEqual(viewModel.config, configured)
        XCTAssertEqual(viewModel.modelDiscoveryActionTitle, "Retry Models")
    }

    func testLoadModelsKeepsAuthenticationMalformedAndTimeoutFailuresOutOfManualMode() async {
        let failures: [Error] = [
            NetworkError.unauthorized,
            FakeGatewayTestError.malformedCatalog,
            NetworkError.timeout
        ]

        for failure in failures {
            let tester = FakeGatewayTester(modelFetchFailure: failure)
            let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
            viewModel.updateGatewayURLInput("https://gateway.example")
            viewModel.updateAPIKeyInput("test-key")

            await viewModel.loadModels()

            guard case .failed(let message) = viewModel.modelDiscoveryState else {
                XCTFail("Expected a failed discovery state for \(failure)")
                continue
            }
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(viewModel.shouldShowManualModelEntry)
            XCTAssertTrue(viewModel.availableModels.isEmpty)
            viewModel.updateSelectedModelInput("must-not-be-accepted")
            XCTAssertTrue(viewModel.selectedModelInput.isEmpty)
        }
    }

    func testUnsupportedModelDiscoveryIsTheOnlyFailureThatEnablesManualModelEntry() async {
        let suiteName = "SettingsViewModelTests.unsupported-discovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tester = FakeGatewayTester(modelFetchFailure: NetworkError.unsupportedModelDiscovery)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
        viewModel.updateProvider(.openRouter)
        viewModel.updateAPIKeyInput("test-key")

        viewModel.updateSelectedModelInput("manual-before-discovery")
        XCTAssertTrue(viewModel.selectedModelInput.isEmpty)
        XCTAssertFalse(viewModel.shouldShowManualModelEntry)

        await viewModel.loadModels()

        XCTAssertEqual(viewModel.modelDiscoveryState, .unsupported)
        XCTAssertTrue(viewModel.shouldShowManualModelEntry)
        XCTAssertTrue(viewModel.modelSelectionRequired)
        viewModel.updateSelectedModelInput("vendor/Exact-Model")
        XCTAssertEqual(viewModel.selectedModelInput, "vendor/Exact-Model")
        XCTAssertFalse(viewModel.modelSelectionRequired)

        let discoveryCountBeforeTest = tester.modelFetches
        await viewModel.testConnection()

        XCTAssertEqual(tester.modelFetches - discoveryCountBeforeTest, 1)
        XCTAssertEqual(tester.smokeModels, ["vendor/Exact-Model"])
        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(viewModel.config.provider, .openRouter)
        XCTAssertEqual(viewModel.config.selectedModel, "vendor/Exact-Model")

        viewModel.updateGatewayURLInput("https://another-router.example/api/v1")
        XCTAssertEqual(viewModel.modelDiscoveryState, .idle)
        XCTAssertFalse(viewModel.shouldShowManualModelEntry)
        XCTAssertTrue(viewModel.selectedModelInput.isEmpty)
    }

    func testUnsupportedDiscoveryCanSaveANewManualModelForSavedCredentials() async {
        let suiteName = "SettingsViewModelTests.unsupported-saved-model-change.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configured = savedGatewayConfig(baseURL: "https://compatible.example")
        XCTAssertTrue(configured.save(to: defaults))
        AppConfig.saveGatewayConnectionLastTestedAt(Date(), to: defaults)
        let tester = FakeGatewayTester(modelFetchFailure: NetworkError.unsupportedModelDiscovery)
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester, defaults: defaults)

        XCTAssertEqual(viewModel.modelDiscoveryActionTitle, "Change Model")
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
        await viewModel.loadModels()

        XCTAssertTrue(viewModel.shouldShowManualModelEntry)
        XCTAssertEqual(viewModel.selectedModelInput, configured.selectedModel)
        XCTAssertEqual(viewModel.gatewayURLInput, configured.baseURL)
        XCTAssertEqual(viewModel.apiKeyInput, configured.apiKey)
        XCTAssertEqual(viewModel.config, configured)
        XCTAssertEqual(viewModel.modelDiscoveryActionTitle, "Change Model")

        viewModel.updateSelectedModelInput("new-manual-model")

        XCTAssertEqual(viewModel.config, configured)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(viewModel.config.selectedModel, "new-manual-model")
        XCTAssertEqual(tester.smokeModels, ["new-manual-model"])
        XCTAssertFalse(viewModel.shouldShowManualModelEntry)
        XCTAssertEqual(viewModel.modelDiscoveryState, .idle)
        XCTAssertEqual(viewModel.modelDiscoveryActionTitle, "Change Model")
    }

    func testStaleUnsupportedConnectionCannotReplaceNewerCredentialCatalog() async {
        let suiteName = "SettingsViewModelTests.stale-unsupported.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configured = savedGatewayConfig()
        XCTAssertTrue(configured.save(to: defaults))
        let tester = FakeGatewayTester(models: ["new-profile-model"])
        let discoveryStarted = expectation(description: "old profile discovery started")
        var pendingDiscovery: CheckedContinuation<[String], Error>?
        tester.modelFetchOverride = {
            try await withCheckedThrowingContinuation { continuation in
                pendingDiscovery = continuation
                discoveryStarted.fulfill()
            }
        }
        let viewModel = SettingsViewModel(config: configured, gatewayTester: tester, defaults: defaults)
        let connectionTask = Task { await viewModel.testConnection() }
        await fulfillment(of: [discoveryStarted], timeout: 1)

        viewModel.updateGatewayURLInput("https://new-profile.example")
        viewModel.updateAPIKeyInput("new-profile-key")
        tester.modelFetchOverride = nil
        await viewModel.loadModels()
        pendingDiscovery?.resume(throwing: NetworkError.unsupportedModelDiscovery)
        await connectionTask.value

        XCTAssertEqual(viewModel.gatewayURLInput, "https://new-profile.example")
        XCTAssertEqual(viewModel.apiKeyInput, "new-profile-key")
        XCTAssertEqual(viewModel.modelDiscoveryState, .loaded)
        XCTAssertEqual(viewModel.availableModels, ["new-profile-model"])
        XCTAssertEqual(viewModel.selectedModelInput, "new-profile-model")
        XCTAssertNil(viewModel.modelSelectionMessage)
        XCTAssertTrue(tester.smokeModels.isEmpty)
        XCTAssertEqual(viewModel.config, configured)
        XCTAssertEqual(AppConfig.load(from: defaults), configured)
    }

    func testCancelledUnsupportedConnectionDoesNotRestartSmokeOrManualEntry() async {
        for cancelTask in [false, true] {
            let suiteName = "SettingsViewModelTests.cancelled-unsupported.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let configured = savedGatewayConfig()
            XCTAssertTrue(configured.save(to: defaults))
            let tester = FakeGatewayTester()
            let discoveryStarted = expectation(description: "cancelled discovery started")
            var pendingDiscovery: CheckedContinuation<[String], Error>?
            // Deliberately finish with unsupported discovery even after cancellation, as a
            // transport result can already have won its race before the MainActor resumes.
            tester.modelFetchOverride = {
                try await withCheckedThrowingContinuation { continuation in
                    pendingDiscovery = continuation
                    discoveryStarted.fulfill()
                }
            }
            let viewModel = SettingsViewModel(config: configured, gatewayTester: tester, defaults: defaults)
            let connectionTask = Task { await viewModel.testConnection() }
            await fulfillment(of: [discoveryStarted], timeout: 1)

            if cancelTask {
                connectionTask.cancel()
            } else {
                viewModel.cancelInFlightGatewayOperations()
            }
            pendingDiscovery?.resume(throwing: NetworkError.unsupportedModelDiscovery)
            await connectionTask.value

            XCTAssertEqual(viewModel.modelDiscoveryState, .idle)
            XCTAssertTrue(viewModel.availableModels.isEmpty)
            XCTAssertEqual(viewModel.selectedModelInput, configured.selectedModel)
            XCTAssertNil(viewModel.modelSelectionMessage)
            XCTAssertFalse(viewModel.isTestingConnection)
            XCTAssertTrue(tester.smokeModels.isEmpty)
            XCTAssertEqual(viewModel.config, configured)
            XCTAssertEqual(AppConfig.load(from: defaults), configured)
        }
    }

    func testRetryModelDiscoveryReplacesFailureWithFreshCatalog() async {
        let tester = FakeGatewayTester(modelFetchFailure: NetworkError.timeout)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.loadModels()
        guard case .failed = viewModel.modelDiscoveryState else {
            return XCTFail("The first model load should fail.")
        }
        XCTAssertTrue(viewModel.canRetryModelDiscovery)

        tester.modelFetchFailure = nil
        tester.models = ["retry-model"]
        await viewModel.retryModelDiscovery()

        XCTAssertEqual(tester.modelFetches, 2)
        XCTAssertEqual(viewModel.modelDiscoveryState, .loaded)
        XCTAssertEqual(viewModel.availableModels, ["retry-model"])
        XCTAssertEqual(viewModel.selectedModelInput, "retry-model")
        XCTAssertFalse(viewModel.canRetryModelDiscovery)
    }

    func testCancelModelDiscoveryClosesConnectorAndSuppressesDelayedResult() async {
        let tester = FakeGatewayTester(models: ["late-model"])
        tester.connectionDelayNanoseconds = 50_000_000
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        let loadTask = Task { await viewModel.loadModels() }
        for _ in 0..<100 where tester.modelFetches == 0 { await Task.yield() }
        XCTAssertTrue(viewModel.canCancelModelDiscovery)
        let closeCountBeforeCancellation = tester.closeConnectorCalls

        viewModel.cancelModelDiscovery()
        await loadTask.value

        XCTAssertEqual(viewModel.modelDiscoveryState, .cancelled)
        XCTAssertEqual(viewModel.modelSelectionMessage, "Model loading was cancelled.")
        XCTAssertTrue(viewModel.availableModels.isEmpty)
        XCTAssertTrue(viewModel.selectedModelInput.isEmpty)
        XCTAssertEqual(tester.closeConnectorCalls, closeCountBeforeCancellation + 1)
    }

    func testProfileEditSuppressesStaleModelDiscoveryResult() async {
        let tester = FakeGatewayTester(models: ["stale-model"])
        tester.connectionDelayNanoseconds = 50_000_000
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://first.example")
        viewModel.updateAPIKeyInput("first-key")

        let loadTask = Task { await viewModel.loadModels() }
        for _ in 0..<100 where tester.modelFetches == 0 { await Task.yield() }
        let closeCountBeforeEdit = tester.closeConnectorCalls
        viewModel.updateGatewayURLInput("https://second.example")
        await loadTask.value

        XCTAssertEqual(viewModel.gatewayURLInput, "https://second.example")
        XCTAssertEqual(viewModel.modelDiscoveryState, .idle)
        XCTAssertTrue(viewModel.availableModels.isEmpty)
        XCTAssertTrue(viewModel.selectedModelInput.isEmpty)
        XCTAssertEqual(tester.closeConnectorCalls, closeCountBeforeEdit + 1)
    }

    func testModelSelectionRequiresAnExactCaseSensitiveCatalogIdentifier() async {
        let tester = FakeGatewayTester(models: ["Exact-Model", "another-model"])
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")
        await viewModel.loadModels()

        viewModel.updateSelectedModelInput("exact-model")

        XCTAssertTrue(viewModel.selectedModelInput.isEmpty)
        XCTAssertTrue(viewModel.modelSelectionRequired)

        viewModel.updateSelectedModelInput("Exact-Model")

        XCTAssertEqual(viewModel.selectedModelInput, "Exact-Model")
        XCTAssertFalse(viewModel.modelSelectionRequired)
    }

    func testExactModelSelectionKeepsReusableConnectorOpen() async {
        let tester = FakeGatewayTester(models: ["Exact-Model", "another-model"])
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")
        await viewModel.loadModels()
        let closeCountBeforeSelection = tester.closeConnectorCalls

        viewModel.updateSelectedModelInput("Exact-Model")

        XCTAssertEqual(viewModel.selectedModelInput, "Exact-Model")
        XCTAssertEqual(tester.closeConnectorCalls, closeCountBeforeSelection)
    }

    func testConnectionPerformsOneFreshDiscoveryAndOneExactGrammarRequestWithoutFallback() async {
        let tester = FakeGatewayTester(
            models: ["chosen-model", "fallback-model"],
            failingSmokeModels: ["chosen-model"]
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")
        await viewModel.loadModels()
        viewModel.updateSelectedModelInput("chosen-model")
        let discoveryCountBeforeTest = tester.modelFetches

        await viewModel.testConnection()

        XCTAssertEqual(tester.modelFetches - discoveryCountBeforeTest, 1)
        XCTAssertEqual(tester.smokeModels, ["chosen-model"])
        XCTAssertEqual(tester.smokeProfiles.count, 1)
        XCTAssertEqual(tester.smokeProfiles[0].model, "chosen-model")
        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertFalse(viewModel.config.isConfigured)
    }

    func testConnectionDoesNotSubstituteSoleReplacementForPreviouslySelectedExactModel() async {
        let tester = FakeGatewayTester(
            modelCatalogSequence: [
                ["chosen-model", "other-model"],
                ["replacement-model"]
            ]
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")
        await viewModel.loadModels()
        viewModel.updateSelectedModelInput("chosen-model")

        await viewModel.testConnection()

        XCTAssertEqual(tester.modelFetches, 2)
        XCTAssertEqual(viewModel.availableModels, ["replacement-model"])
        XCTAssertTrue(viewModel.selectedModelInput.isEmpty)
        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.errorMessage, NetworkError.modelUnavailable.localizedDescription)
        XCTAssertTrue(tester.smokeModels.isEmpty)
        XCTAssertFalse(tester.smokeModels.contains("replacement-model"))
        XCTAssertFalse(viewModel.config.isConfigured)
    }

    func testConnectionSavesTheValidatedProviderForEverySupportedProvider() async {
        let providers: [OpenKeyboardAIProvider] = [
            .openAI,
            .anthropic,
            .openRouter,
            .openAICompatible
        ]

        for provider in providers {
            let suiteName = "SettingsViewModelTests.provider-save.\(provider.rawValue).\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let tester = FakeGatewayTester(models: ["exact-model"])
            let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
            viewModel.updateProvider(provider)
            if provider == .openAICompatible {
                viewModel.updateGatewayURLInput("https://compatible.example/v1")
            }
            viewModel.updateAPIKeyInput("provider-key")

            await viewModel.testConnection()

            XCTAssertEqual(viewModel.connectionStatus, .success, "Provider: \(provider)")
            XCTAssertEqual(viewModel.config.provider, provider)
            XCTAssertEqual(AppConfig.load(from: defaults).provider, provider)
            XCTAssertEqual(tester.modelFetches, 1)
            XCTAssertEqual(tester.smokeModels, ["exact-model"])
            XCTAssertEqual(tester.fetchedProfiles.first?.provider, provider)
            XCTAssertEqual(tester.smokeProfiles.first?.provider, provider)
        }
    }

    func testEndpointConstructionNormalizesBaseURLAndAvoidsDuplicateV1() throws {
        XCTAssertEqual(try NetworkManager.normalizedGatewayBaseURLString("gateway.example/"), "https://gateway.example")
        XCTAssertEqual(try NetworkManager.normalizedGatewayBaseURLString("https://https://gateway.example/v1/"), "https://gateway.example")
        XCTAssertEqual(try NetworkManager.endpointURL(gatewayURL: "gateway.example/v1", path: "/v1/models").absoluteString, "https://gateway.example/v1/models")
        XCTAssertEqual(try NetworkManager.endpointURL(gatewayURL: "https://gateway.example/", path: "/v1/chat/completions").absoluteString, "https://gateway.example/v1/chat/completions")
    }
}

private extension SettingsViewModel {
    var normalizedGatewayURLForTesting: String? {
        try? NetworkManager.normalizedGatewayBaseURLString(gatewayURLInput)
    }
}

private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
    ""
}

private final class SettingsInMemorySecureStore: AppConfigSecureStore {
    private var profileData: Data?
    private var legacyAPIKey: String?
    private var referencedAPIKeys: [String: String] = [:]
    private var clearIntent: AppConfigSecureClearIntent?
    var apiKey: String? {
        Self.apiKey(from: profileData) ?? legacyAPIKey
    }
    var shouldFailSave = false

    func loadProfile() -> Data? { profileData }

    @discardableResult
    func saveProfile(_ profile: Data) -> Bool {
        guard !shouldFailSave else { return false }
        profileData = profile
        return true
    }

    @discardableResult
    func clearProfile() -> Bool {
        profileData = nil
        return true
    }

    func loadClearIntentResult() -> AppConfigSecureStoreClearIntentReadResult {
        clearIntent.map(AppConfigSecureStoreClearIntentReadResult.found) ?? .notFound
    }

    func saveClearIntent(_ intent: AppConfigSecureClearIntent) -> Bool {
        clearIntent = intent
        return true
    }

    func clearClearIntent() -> Bool {
        clearIntent = nil
        return true
    }

    func loadLegacyAPIKey() -> String? { legacyAPIKey }
    func loadLegacyAPIKey(reference: String) -> String? { referencedAPIKeys[reference] }
    func loadLegacyAPIKeyResult() -> AppConfigSecureStoreStringReadResult {
        legacyAPIKey.map(AppConfigSecureStoreStringReadResult.found) ?? .notFound
    }
    func loadLegacyAPIKeyResult(reference: String) -> AppConfigSecureStoreStringReadResult {
        referencedAPIKeys[reference].map(AppConfigSecureStoreStringReadResult.found) ?? .notFound
    }

    @discardableResult
    func saveLegacyAPIKey(_ apiKey: String) -> Bool {
        guard !shouldFailSave else { return false }
        legacyAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
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

private final class FakeGatewayTester: GatewayConnectionTesting {
    struct RecordedProfile {
        let provider: OpenKeyboardAIProvider
        let baseURL: String
        let apiKey: String
    }

    struct RecordedSmokeProfile {
        let provider: OpenKeyboardAIProvider
        let baseURL: String
        let model: String
    }

    var healthSucceeds: Bool
    var models: [String]
    var modelCatalogSequence: [[String]]
    var smokeSucceeds: Bool
    var failingSmokeModels: Set<String>
    var connectionFailure: Error?
    var modelFetchFailure: Error?
    var modelFetchOverride: (() async throws -> [String])?
    var smokeFailure: Error
    var connectionDelayNanoseconds: UInt64 = 0
    var smokeDelayNanoseconds: UInt64 = 0
    var ignoresSmokeCancellation = false
    var diagnosticDelayNanoseconds: UInt64 = 0
    private(set) var smokeModel: String?
    private(set) var smokeModels: [String] = []
    private(set) var testedGatewayURLs: [String] = []
    private(set) var modelFetches = 0
    private(set) var fetchedProfiles: [RecordedProfile] = []
    private(set) var smokeProfiles: [RecordedSmokeProfile] = []
    private(set) var closeConnectorCalls = 0
    var diagnosticReport = GatewayDiagnosticReport(selectedModel: "gpt-oss:120b-cloud", checks: [])
    private(set) var diagnosticGatewayURL: String?
    private(set) var diagnosticAPIKey: String?
    private(set) var diagnosticPreferredModel: String?
    private(set) var diagnosticProvider: OpenKeyboardAIProvider?
    var fetchedGatewayURL: String? { testedGatewayURLs.last }

    init(
        healthSucceeds: Bool = true,
        models: [String] = [],
        modelCatalogSequence: [[String]] = [],
        smokeSucceeds: Bool = true,
        failingSmokeModels: Set<String> = [],
        connectionFailure: Error? = nil,
        modelFetchFailure: Error? = nil,
        smokeFailure: Error = NetworkError.unusableCorrection
    ) {
        self.healthSucceeds = healthSucceeds
        self.models = models
        self.modelCatalogSequence = modelCatalogSequence
        self.smokeSucceeds = smokeSucceeds
        self.failingSmokeModels = failingSmokeModels
        self.connectionFailure = connectionFailure
        self.modelFetchFailure = modelFetchFailure
        self.smokeFailure = smokeFailure
    }

    func fetchModels(gatewayURL: String, apiKey: String) async throws -> [String] {
        modelFetches += 1
        testedGatewayURLs.append(gatewayURL)
        if let modelFetchOverride {
            return try await modelFetchOverride()
        }
        if connectionDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: connectionDelayNanoseconds)
        }
        if let connectionFailure { throw connectionFailure }
        if !healthSucceeds { throw FakeGatewayTestError.connectionFailed }
        if let modelFetchFailure { throw modelFetchFailure }
        if !modelCatalogSequence.isEmpty {
            return modelCatalogSequence.removeFirst()
        }
        return models
    }

    func fetchModels(profile: OpenKeyboardGatewayProfile) async throws -> [String] {
        fetchedProfiles.append(
            RecordedProfile(
                provider: profile.provider,
                baseURL: profile.baseURL,
                apiKey: profile.apiKey
            )
        )
        return try await fetchModels(gatewayURL: profile.baseURL, apiKey: profile.apiKey)
    }

    func testCorrectionSmoke(gatewayURL: String, apiKey: String, model: String) async throws {
        smokeModel = model
        smokeModels.append(model)
        if smokeDelayNanoseconds > 0 {
            if ignoresSmokeCancellation {
                try? await Task.sleep(nanoseconds: smokeDelayNanoseconds)
            } else {
                try await Task.sleep(nanoseconds: smokeDelayNanoseconds)
            }
        }
        if !smokeSucceeds || failingSmokeModels.contains(model) { throw smokeFailure }
    }

    func testCorrectionSmoke(profile: OpenKeyboardGatewayProfile, model: String) async throws {
        smokeProfiles.append(
            RecordedSmokeProfile(
                provider: profile.provider,
                baseURL: profile.baseURL,
                model: model
            )
        )
        try await testCorrectionSmoke(gatewayURL: profile.baseURL, apiKey: profile.apiKey, model: model)
    }

    func runGatewayDiagnostics(gatewayURL: String, apiKey: String, preferredModel: String) async -> GatewayDiagnosticReport {
        diagnosticGatewayURL = gatewayURL
        diagnosticAPIKey = apiKey
        diagnosticPreferredModel = preferredModel
        if diagnosticDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: diagnosticDelayNanoseconds)
        }
        return diagnosticReport
    }

    func runGatewayDiagnostics(
        profile: OpenKeyboardGatewayProfile,
        preferredModel: String
    ) async -> GatewayDiagnosticReport {
        diagnosticProvider = profile.provider
        return await runGatewayDiagnostics(
            gatewayURL: profile.baseURL,
            apiKey: profile.apiKey,
            preferredModel: preferredModel
        )
    }

    func closeConnector() {
        closeConnectorCalls += 1
    }
}

private enum FakeGatewayTestError: LocalizedError {
    case connectionFailed
    case malformedCatalog

    var errorDescription: String? {
        switch self {
        case .connectionFailed: "Connection failed"
        case .malformedCatalog: "Malformed models response"
        }
    }
}
