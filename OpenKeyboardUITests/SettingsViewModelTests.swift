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

        XCTAssertEqual(tester.healthChecks, 1)
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

        XCTAssertEqual(tester.healthChecks, 0)
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

        XCTAssertEqual(tester.healthChecks, 1)
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

        XCTAssertEqual(tester.healthChecks, 0)
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
        XCTAssertEqual(tester.healthChecks, 1)
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
        XCTAssertEqual(tester.testedGatewayURLs, ["https://gateway.example", "https://gateway.example"])
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

        XCTAssertEqual(tester.healthChecks, 0)
        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.errorMessage, "Keyboard detected gateway timeout")
        XCTAssertEqual(AppConfig.gatewayConnectionError(from: defaults), "Keyboard detected gateway timeout")

        await viewModel.retrySavedGatewayValidation()

        XCTAssertEqual(tester.healthChecks, 1)
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
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()
        XCTAssertTrue(viewModel.modelSelectionRequired)
        viewModel.updateSelectedModelInput("gpt-oss:120b-cloud")

        await viewModel.runDiagnostics()

        XCTAssertFalse(viewModel.isRunningDiagnostics)
        XCTAssertEqual(viewModel.diagnosticReport, tester.diagnosticReport)
        XCTAssertEqual(tester.diagnosticGatewayURL, "https://gateway.example")
        XCTAssertEqual(tester.diagnosticAPIKey, "test-key")
        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertNil(defaults.string(forKey: AppConfig.gatewayURLKey))
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
        for _ in 0..<100 where tester.healthChecks == 0 { await Task.yield() }
        XCTAssertEqual(tester.healthChecks, 1)

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

    func loadLegacyAPIKey() -> String? { legacyAPIKey }
    func loadLegacyAPIKey(reference: String) -> String? { referencedAPIKeys[reference] }

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
    var healthSucceeds: Bool
    var models: [String]
    var smokeSucceeds: Bool
    var failingSmokeModels: Set<String>
    var connectionFailure: Error?
    var modelFetchFailure: Error?
    var smokeFailure: Error
    var connectionDelayNanoseconds: UInt64 = 0
    var diagnosticDelayNanoseconds: UInt64 = 0
    private(set) var smokeModel: String?
    private(set) var smokeModels: [String] = []
    private(set) var testedGatewayURLs: [String] = []
    private(set) var healthChecks = 0
    private(set) var modelFetches = 0
    var diagnosticReport = GatewayDiagnosticReport(selectedModel: "gpt-oss:120b-cloud", checks: [])
    private(set) var diagnosticGatewayURL: String?
    private(set) var diagnosticAPIKey: String?
    private(set) var diagnosticPreferredModel: String?
    var fetchedGatewayURL: String? { testedGatewayURLs.last }

    init(
        healthSucceeds: Bool = true,
        models: [String] = [],
        smokeSucceeds: Bool = true,
        failingSmokeModels: Set<String> = [],
        connectionFailure: Error? = nil,
        modelFetchFailure: Error? = nil,
        smokeFailure: Error = NetworkError.unusableCorrection
    ) {
        self.healthSucceeds = healthSucceeds
        self.models = models
        self.smokeSucceeds = smokeSucceeds
        self.failingSmokeModels = failingSmokeModels
        self.connectionFailure = connectionFailure
        self.modelFetchFailure = modelFetchFailure
        self.smokeFailure = smokeFailure
    }

    func testConnection(gatewayURL: String, apiKey: String) async throws -> Bool {
        healthChecks += 1
        testedGatewayURLs.append(gatewayURL)
        if connectionDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: connectionDelayNanoseconds)
        }
        if let connectionFailure { throw connectionFailure }
        return healthSucceeds
    }

    func fetchModels(gatewayURL: String, apiKey: String) async throws -> [String] {
        modelFetches += 1
        testedGatewayURLs.append(gatewayURL)
        if let modelFetchFailure { throw modelFetchFailure }
        return models
    }

    func testCorrectionSmoke(gatewayURL: String, apiKey: String, model: String) async throws {
        smokeModel = model
        smokeModels.append(model)
        if !smokeSucceeds || failingSmokeModels.contains(model) { throw smokeFailure }
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
}
