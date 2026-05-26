import XCTest

enum OpenKeyboardUITestDataHelper {
    static func showOnboarding(page: Int? = nil) -> [String] {
        var args = ["--uitesting", "--show-onboarding"]
        if let page {
            args.append("--onboarding-page=\(page)")
        }
        return args
    }

    static func skipOnboarding() -> [String] {
        ["--uitesting", "--skip-onboarding"]
    }
}
