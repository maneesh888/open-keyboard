import XCTest

private enum RejectedGatewayFixture {
    static let gatewayURL = ["https://gateway", "example", "invalid"].joined(separator: ".")
    static let apiKey = ["test", "placeholder", "key"].joined(separator: "-")
    static let selectedModel = ["test", "placeholder", "model"].joined(separator: "-")
}

@MainActor
final class SettingsViewModelTests: XCTestCase {




    func testSettingsViewModelRejectsPlaceholderConfigAsVerifiedState() {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.placeholder.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let placeholder = AppConfig(
            apiKey: RejectedGatewayFixture.apiKey,
            gatewayURL: RejectedGatewayFixture.gatewayURL,
            selectedModel: RejectedGatewayFixture.selectedModel,
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
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
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
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
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
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
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
        let viewModel = SettingsViewModel(config: config, gatewayTester: FakeGatewayTester())

        XCTAssertFalse(viewModel.isEditingGatewayDraft)
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertTrue(viewModel.canTestConnection)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(viewModel.connectionStatus, .unknown)
        XCTAssertEqual(viewModel.trustedModelDisplay, "Test connection to load model")
        XCTAssertEqual(viewModel.structuredCapabilityDisplay, "Loaded after Test Connection")
    }

    func testEditingValidatedGatewayHidesTrustedDetailsAndShowsConnectionActions() {
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
        let viewModel = SettingsViewModel(config: config, gatewayTester: FakeGatewayTester())

        viewModel.updateGatewayURLInput("https://edited-gateway.example")

        XCTAssertTrue(viewModel.isEditingGatewayDraft)
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertTrue(viewModel.canTestConnection)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.trustedModelLoaded)
        XCTAssertEqual(viewModel.trustedModelDisplay, "Test connection to load model")
        XCTAssertEqual(viewModel.structuredCapabilityDisplay, "Loaded after Test Connection")
    }

    func testEditingValidatedAPIKeyHidesTrustedDetailsAndShowsConnectionActions() {
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
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
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
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
        XCTAssertEqual(viewModel.structuredCapabilityDisplay, "Loaded after Test Connection")
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
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        let viewModel = SettingsViewModel(config: config, gatewayTester: FakeGatewayTester(), defaults: defaults)

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.errorMessage, "Gateway timed out")
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.trustedModelLoaded)
        XCTAssertEqual(viewModel.trustedModelDisplay, "Test connection to load model")
    }


    func testSavedConfigStartsUnverifiedUntilLaunchValidationSucceeds() async {
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
        let tester = FakeGatewayTester(models: ["apple-foundationmodel"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: config, gatewayTester: tester)

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
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
        let tester = FakeGatewayTester(healthSucceeds: false)
        let viewModel = SettingsViewModel(config: config, gatewayTester: tester)

        await viewModel.validateSavedGatewayOnceOnLaunch()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertEqual(viewModel.config.gatewayURL, "https://gateway.example")
        XCTAssertEqual(viewModel.config.apiKey, "working-key")
        XCTAssertEqual(viewModel.config.selectedModel, "apple-foundationmodel")
        XCTAssertTrue(viewModel.config.isConfigured)
    }

    func testSavedConfigLaunchValidationRunsOnlyOnceAndGuardsConcurrentCalls() async {
        let config = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://gateway.example",
            selectedModel: "apple-foundationmodel",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )
        let tester = FakeGatewayTester(models: ["apple-foundationmodel"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: config, gatewayTester: tester)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await viewModel.validateSavedGatewayOnceOnLaunch() }
            group.addTask { await viewModel.validateSavedGatewayOnceOnLaunch() }
        }
        await viewModel.validateSavedGatewayOnceOnLaunch()

        XCTAssertEqual(tester.healthChecks, 1)
        XCTAssertEqual(tester.modelFetches, 1)
        XCTAssertEqual(tester.smokeModels, ["apple-foundationmodel"])
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

    func testModelFallbackUsesWorkingNonAppleModelWhenAppleSmokeFails() async {
        let tester = FakeGatewayTester(
            models: ["apple-foundationmodel", "gpt-oss:120b-cloud"],
            failingSmokeModels: ["apple-foundationmodel"]
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.updateGatewayURLInput("https://gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(viewModel.config.selectedModel, "gpt-oss:120b-cloud")
        XCTAssertEqual(tester.smokeModels, ["apple-foundationmodel", "gpt-oss:120b-cloud"])
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

    func testSuccessfulTestConnectionPersistsValidatedModelAndStructuredCapability() async {
        let tester = FakeGatewayTester(
            healthSucceeds: true,
            models: ["gemma4:latest", "apple-foundationmodel"],
            smokeSucceeds: true
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.gatewayURLInput = " https://gateway.example "
        viewModel.apiKeyInput = " test-key "

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(viewModel.config.gatewayURL, "https://gateway.example")
        XCTAssertEqual(viewModel.config.apiKey, "test-key")
        XCTAssertEqual(viewModel.config.selectedModel, "apple-foundationmodel")
        XCTAssertTrue(viewModel.config.isConfigured)
        XCTAssertTrue(viewModel.config.supportsStructuredCorrections)
        XCTAssertEqual(viewModel.config.structuredCorrectionSchemaVersion, "openkeyboard.structured-corrections.v1")
        XCTAssertEqual(tester.smokeModel, "apple-foundationmodel")
        XCTAssertTrue(viewModel.showsValidatedGatewayDetails)
        XCTAssertTrue(viewModel.trustedModelLoaded)
        XCTAssertEqual(viewModel.trustedModelDisplay, "apple-foundationmodel")
        XCTAssertEqual(viewModel.structuredCapabilityDisplay, "openkeyboard.structured-corrections.v1")
    }

    func testFailedTestConnectionDoesNotOverwriteExistingWorkingConfig() async {
        let existing = AppConfig(
            apiKey: "working-key",
            gatewayURL: "https://working.example",
            selectedModel: "gemma4:latest",
            isConfigured: true,
            supportsStructuredCorrections: true,
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
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
        XCTAssertEqual(viewModel.structuredCapabilityDisplay, "Loaded after Test Connection")
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

    func testSmokeFailureDoesNotPersistDraftConfigOrModel() async {
        let tester = FakeGatewayTester(
            healthSucceeds: true,
            models: ["apple-foundationmodel"],
            smokeSucceeds: false
        )
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester)
        viewModel.gatewayURLInput = "https://gateway.example"
        viewModel.apiKeyInput = "test-key"

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.config.gatewayURL, "")
        XCTAssertEqual(viewModel.config.apiKey, "")
        XCTAssertEqual(viewModel.config.selectedModel, "")
        XCTAssertFalse(viewModel.config.isConfigured)
        XCTAssertFalse(viewModel.config.supportsStructuredCorrections)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.trustedModelLoaded)
    }

    func testDefaultGatewayInputShowsHTTPSHelpButCannotTestUntilHostExists() {
        let viewModel = SettingsViewModel(config: .default, gatewayTester: FakeGatewayTester())

        XCTAssertEqual(viewModel.gatewayURLInput, "https://")
        XCTAssertNil(viewModel.normalizedGatewayURLForTesting)
        XCTAssertFalse(viewModel.canTestConnection)
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
            structuredCorrectionSchemaVersion: "openkeyboard.structured-corrections.v1"
        )

        let viewModel = SettingsViewModel(config: config, gatewayTester: FakeGatewayTester(), defaults: defaults)

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(viewModel.errorMessage, "Keyboard detected gateway timeout")
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
        XCTAssertFalse(viewModel.trustedModelLoaded)
    }

    func testFailedTestConnectionPersistsGlobalErrorForSettingsRetry() async {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.failure.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let tester = FakeGatewayTester(healthSucceeds: false)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .failure)
        XCTAssertEqual(AppConfig.gatewayConnectionError(from: defaults), "Connection failed")
        XCTAssertTrue(viewModel.shouldShowConnectionActions)
        XCTAssertFalse(viewModel.showsValidatedGatewayDetails)
    }

    func testSuccessfulRetryClearsGlobalErrorAndSavesToInjectedSharedDefaultsAndSecretStore() async {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.success.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let oldSecretStore = AppConfig.secretStore
        let secretStore = SettingsInMemorySecretStore()
        AppConfig.secretStore = secretStore
        defer { AppConfig.secretStore = oldSecretStore }
        AppConfig.saveGatewayConnectionError("Previous keyboard error", to: defaults)
        let tester = FakeGatewayTester(healthSucceeds: true, models: ["gpt-oss:120b-cloud"], smokeSucceeds: true)
        let viewModel = SettingsViewModel(config: .default, gatewayTester: tester, defaults: defaults)
        viewModel.updateGatewayURLInput("gateway.example")
        viewModel.updateAPIKeyInput("test-key")

        await viewModel.testConnection()

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertNil(AppConfig.gatewayConnectionError(from: defaults))
        XCTAssertEqual(defaults.string(forKey: AppConfig.gatewayURLKey), "https://gateway.example")
        XCTAssertEqual(defaults.string(forKey: AppConfig.selectedModelKey), "gpt-oss:120b-cloud")
        XCTAssertTrue(defaults.bool(forKey: AppConfig.isConfiguredKey))
        XCTAssertNil(defaults.string(forKey: AppConfig.apiKeyKey))
        XCTAssertEqual(secretStore.apiKey, "test-key")
    }

    func testModelValidationFallsBackWhenAppleFoundationModelFailsSmoke() async {
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

        XCTAssertEqual(viewModel.connectionStatus, .success)
        XCTAssertEqual(tester.smokeModels, ["apple-foundationmodel", "gpt-oss:120b-cloud"])
        XCTAssertEqual(viewModel.config.selectedModel, "gpt-oss:120b-cloud")
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

private final class SettingsInMemorySecretStore: AppConfigSecretStore {
    var apiKey: String?

    func loadAPIKey() -> String? { apiKey }

    @discardableResult
    func saveAPIKey(_ apiKey: String) -> Bool {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }

    @discardableResult
    func clearAPIKey() -> Bool {
        apiKey = nil
        return true
    }
}

private final class FakeGatewayTester: GatewayConnectionTesting {
    var healthSucceeds: Bool
    var models: [String]
    var smokeSucceeds: Bool
    var failingSmokeModels: Set<String>
    private(set) var smokeModel: String?
    private(set) var smokeModels: [String] = []
    private(set) var testedGatewayURLs: [String] = []
    private(set) var healthChecks = 0
    private(set) var modelFetches = 0
    var fetchedGatewayURL: String? { testedGatewayURLs.last }

    init(healthSucceeds: Bool = true, models: [String] = [], smokeSucceeds: Bool = true, failingSmokeModels: Set<String> = []) {
        self.healthSucceeds = healthSucceeds
        self.models = models
        self.smokeSucceeds = smokeSucceeds
        self.failingSmokeModels = failingSmokeModels
    }

    func testConnection(gatewayURL: String, apiKey: String) async throws -> Bool {
        healthChecks += 1
        testedGatewayURLs.append(gatewayURL)
        return healthSucceeds
    }

    func fetchModels(gatewayURL: String, apiKey: String) async throws -> [String] {
        modelFetches += 1
        testedGatewayURLs.append(gatewayURL)
        return models
    }

    func testCorrectionSmoke(gatewayURL: String, apiKey: String, model: String) async throws {
        smokeModel = model
        smokeModels.append(model)
        if !smokeSucceeds || failingSmokeModels.contains(model) { throw NetworkError.unusableCorrection }
    }
}
