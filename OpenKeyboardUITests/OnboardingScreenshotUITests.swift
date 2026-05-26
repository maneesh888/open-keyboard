import XCTest

final class OnboardingScreenshotUITests: BaseOpenKeyboardUITestCase {
    override func launchArguments() -> [String] {
        OpenKeyboardUITestDataHelper.showOnboarding(page: 0)
    }

    func testWelcomePageContentIsVisibleAndNonOverlapping() throws {
        let title = assertVisible("onboarding_title")
        let subtitle = assertVisible("onboarding_subtitle")
        let llmTitle = assertVisible("onboarding_feature_llm_title")
        let llmDescription = assertVisible("onboarding_feature_llm_description")
        let privacyTitle = assertVisible("onboarding_feature_privacy_title")
        let privacyDescription = assertVisible("onboarding_feature_privacy_description")
        let aiTitle = assertVisible("onboarding_feature_ai_title")
        let aiDescription = assertVisible("onboarding_feature_ai_description")
        let pageIndicator = assertVisible("onboarding_page_indicator")

        XCTAssertEqual(title.label, "Welcome to\nOpen Keyboard")
        XCTAssertEqual(subtitle.label, "AI-powered typing with privacy in mind")
        XCTAssertEqual(llmTitle.label, "Your Own LLM")
        XCTAssertEqual(llmDescription.label, "Connect to your self-hosted LLM gateway")
        XCTAssertEqual(privacyTitle.label, "Privacy First")
        XCTAssertEqual(privacyDescription.label, "Your data never leaves your control")
        XCTAssertEqual(aiTitle.label, "AI Powered")
        XCTAssertEqual(aiDescription.label, "Smart suggestions and text improvements")

        XCTAssertLessThan(aiDescription.frame.maxY, pageIndicator.frame.minY, "Page indicator should not overlap the final feature row")
        attachScreenshot(named: "onboarding-welcome-iPhone")
    }
}
