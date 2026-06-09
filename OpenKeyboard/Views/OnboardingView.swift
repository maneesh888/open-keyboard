//
//  OnboardingView.swift
//  OpenKeyboard
//
//  Onboarding flow for first-time users
//

import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @State private var currentPage: Int
    @State private var showingSettings = false

    init(hasCompletedOnboarding: Binding<Bool>, initialPage: Int = 0) {
        self._hasCompletedOnboarding = hasCompletedOnboarding
        self._currentPage = State(initialValue: initialPage)
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    WelcomePage()
                        .tag(0)

                    GatewaySetupPage(showingSettings: $showingSettings)
                        .tag(1)

                    KeyboardSetupPage()
                        .tag(2)

                    CompletePage(hasCompletedOnboarding: $hasCompletedOnboarding)
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                PageIndicator(currentPage: currentPage, pageCount: 4)
                    .accessibilityIdentifier("onboarding_page_indicator")
                    .padding(.top, 6)
                    .padding(.bottom, 14)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(settingsViewModel)
        }
        .tint(OpenKeyboardTheme.Brand.cyan)
    }
}

struct WelcomePage: View {
    var body: some View {
        ModernOnboardingPage(
            icon: "keyboard.badge.eye",
            eyebrow: "Private AI keyboard",
            title: "Welcome to\nOpen Keyboard",
            subtitle: "AI-powered typing with privacy in mind"
        ) {
            VStack(spacing: 10) {
                FeatureRow(
                    icon: "cpu",
                    title: "Your Own LLM",
                    description: "Connect to your self-hosted LLM gateway",
                    titleIdentifier: "onboarding_feature_llm_title",
                    descriptionIdentifier: "onboarding_feature_llm_description"
                )
                FeatureRow(
                    icon: "lock.shield",
                    title: "Privacy First",
                    description: "Your data never leaves your control",
                    titleIdentifier: "onboarding_feature_privacy_title",
                    descriptionIdentifier: "onboarding_feature_privacy_description"
                )
                FeatureRow(
                    icon: "sparkles",
                    title: "AI Powered",
                    description: "Smart suggestions and text improvements",
                    titleIdentifier: "onboarding_feature_ai_title",
                    descriptionIdentifier: "onboarding_feature_ai_description"
                )
            }
        } footer: {
            Text("Swipe to continue")
                .font(.footnote.weight(.semibold))
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
        }
        .accessibilityElement(children: .contain)
    }
}

struct GatewaySetupPage: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    var body: some View {
        ModernOnboardingPage(
            icon: "link.badge.plus",
            eyebrow: "Step 1",
            title: "Connect your gateway",
            subtitle: "Use an API key from your LLM Gateway admin panel."
        ) {
            VStack(spacing: 10) {
                SetupStep(number: "1", text: "Run LLM Gateway on your Mac")
                SetupStep(number: "2", text: "Create or copy an API key")
                SetupStep(number: "3", text: "Paste it in Open Keyboard")
            }
        } footer: {
            PrimaryButton(
                title: settingsViewModel.config.isConfigured ? "Gateway Configured" : "Configure API Key",
                systemImage: settingsViewModel.config.isConfigured ? "checkmark.circle.fill" : "key.fill",
                tint: settingsViewModel.config.isConfigured ? OpenKeyboardTheme.Semantic.success : OpenKeyboardTheme.Brand.blue,
                action: { showingSettings = true }
            )
        }
    }
}

struct KeyboardSetupPage: View {
    var body: some View {
        ModernOnboardingPage(
            icon: "keyboard",
            eyebrow: "Step 2",
            title: "Enable the keyboard",
            subtitle: "Add Open Keyboard in iOS Settings, then allow full access."
        ) {
            VStack(spacing: 10) {
                SetupStep(number: "1", text: "Open iOS Keyboard Settings")
                SetupStep(number: "2", text: "Choose Keyboards → Add New Keyboard")
                SetupStep(number: "3", text: "Select Open Keyboard")
                SetupStep(number: "4", text: "Enable Allow Full Access")
            }
        } footer: {
            PrimaryButton(title: "Open Keyboard Settings", systemImage: "gearshape.fill") {
                if let url = URL(string: "App-Prefs:root=General&path=Keyboard") {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}

struct CompletePage: View {
    @Binding var hasCompletedOnboarding: Bool

    var body: some View {
        ModernOnboardingPage(
            icon: "checkmark.seal.fill",
            eyebrow: "Ready",
            title: "You're all set",
            subtitle: "Switch keyboards in any app and start typing with AI assistance."
        ) {
            VStack(spacing: 10) {
                TipRow(icon: "globe", title: "Switch Keyboards", description: "Long-press the globe key")
                TipRow(icon: "sparkles", title: "AI Features", description: "Tap sparkles for AI actions")
                TipRow(icon: "bubble.left.and.bubble.right", title: "Suggestions", description: "Use suggestions while you type")
            }
        } footer: {
            PrimaryButton(title: "Get Started", systemImage: "arrow.right.circle.fill") {
                hasCompletedOnboarding = true
            }
        }
    }
}

// Helper Views

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [OpenKeyboardTheme.Surface.panelBackground, OpenKeyboardTheme.Surface.appBackgroundAccent, OpenKeyboardTheme.Surface.panelBackground],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct ModernOnboardingPage<Content: View, Footer: View>: View {
    let icon: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let content: Content
    let footer: Footer

    init(
        icon: String,
        eyebrow: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.icon = icon
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                VStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(OpenKeyboardTheme.Surface.iconBackground)
                            .frame(width: 58, height: 58)
                        Image(systemName: icon)
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundColor(OpenKeyboardTheme.Brand.blue)
                    }
                    .accessibilityHidden(true)

                    Text(eyebrow.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundColor(OpenKeyboardTheme.Brand.blue)

                    Text(title)
                        .accessibilityIdentifier(title == "Welcome to\nOpen Keyboard" ? "onboarding_title" : "")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .accessibilityIdentifier(title == "Welcome to\nOpen Keyboard" ? "onboarding_subtitle" : "")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)

                VStack(spacing: 9) {
                    content
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(OpenKeyboardTheme.Stroke.subtle, lineWidth: 1)
                )
                .shadow(color: OpenKeyboardTheme.Shadow.card, radius: 14, x: 0, y: 8)

                footer
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
        }
        .safeAreaPadding(.top, 4)
        .safeAreaPadding(.bottom, 2)
    }
}

struct PrimaryButton: View {
    let title: String
    let systemImage: String
    var tint: Color = OpenKeyboardTheme.Brand.blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.headline)
            .foregroundColor(OpenKeyboardTheme.Text.inverse)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: tint.opacity(0.25), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct PageIndicator: View {
    let currentPage: Int
    let pageCount: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? OpenKeyboardTheme.Brand.blue : OpenKeyboardTheme.Stroke.control)
                    .frame(width: index == currentPage ? 18 : 7, height: 7)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: currentPage)
            }
        }
        .accessibilityLabel("Page \(currentPage + 1) of \(pageCount)")
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let titleIdentifier: String?
    let descriptionIdentifier: String?

    init(icon: String, title: String, description: String, titleIdentifier: String? = nil, descriptionIdentifier: String? = nil) {
        self.icon = icon
        self.title = title
        self.description = description
        self.titleIdentifier = titleIdentifier
        self.descriptionIdentifier = descriptionIdentifier
    }

    @ViewBuilder
    private func identifiedText(_ text: String, identifier: String?) -> some View {
        if let identifier {
            Text(text)
                .accessibilityIdentifier(identifier)
        } else {
            Text(text)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Brand.blue)
                .frame(width: 34, height: 34)
                .background(OpenKeyboardTheme.Surface.iconBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                identifiedText(title, identifier: titleIdentifier)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                identifiedText(description, identifier: descriptionIdentifier)
                    .font(.footnote)
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SetupStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundColor(OpenKeyboardTheme.Brand.blue)
                .frame(width: 30, height: 30)
                .background(OpenKeyboardTheme.Surface.iconBackground, in: Circle())

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TipRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(OpenKeyboardTheme.Brand.blue)
                .frame(width: 34, height: 34)
                .background(OpenKeyboardTheme.Surface.iconBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(description)
                    .font(.footnote)
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(hasCompletedOnboarding: .constant(false))
            .environmentObject(SettingsViewModel())
    }
}
