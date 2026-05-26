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
                .frame(height: 30)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(settingsViewModel)
        }
    }
}

struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "keyboard.badge.eye")
                .font(.system(size: 42, weight: .regular))
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)
                .padding(.top, 12)

            VStack(spacing: 6) {
                Text("Welcome to\nOpen Keyboard")
                    .accessibilityIdentifier("onboarding_title")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)

                Text("AI-powered typing with privacy in mind")
                    .accessibilityIdentifier("onboarding_subtitle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 10) {
                FeatureRow(icon: "cpu", title: "Your Own LLM", description: "Connect to your self-hosted LLM gateway", titleIdentifier: "onboarding_feature_llm_title", descriptionIdentifier: "onboarding_feature_llm_description")
                FeatureRow(icon: "lock.shield", title: "Privacy First", description: "Your data never leaves your control", titleIdentifier: "onboarding_feature_privacy_title", descriptionIdentifier: "onboarding_feature_privacy_description")
                FeatureRow(icon: "sparkles", title: "AI Powered", description: "Smart suggestions and text improvements", titleIdentifier: "onboarding_feature_ai_title", descriptionIdentifier: "onboarding_feature_ai_description")
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Text("Swipe to continue →")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 16)
    }
}
struct GatewaySetupPage: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "link.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("Connect to Gateway")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("You'll need an API key from your LLM gateway")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 20) {
                SetupStep(number: "1", text: "Set up LLM Gateway on your Mac")
                SetupStep(number: "2", text: "Get your API key from admin panel")
                SetupStep(number: "3", text: "Enter API key in app settings")
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            Button(action: {
                showingSettings = true
            }) {
                Text("Configure API Key")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(settingsViewModel.config.isConfigured ? Color.green : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 30)
            
            if settingsViewModel.config.isConfigured {
                Label("Gateway configured ✓", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.headline)
            }
            
            Spacer()
        }
    }
}

struct KeyboardSetupPage: View {
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "keyboard")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("Enable Keyboard")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Follow these steps to add Open Keyboard")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 20) {
                SetupStep(number: "1", text: "Tap 'Open Keyboard Settings' below")
                SetupStep(number: "2", text: "Select 'Keyboards' → 'Add New Keyboard'")
                SetupStep(number: "3", text: "Choose 'Open Keyboard'")
                SetupStep(number: "4", text: "Enable 'Allow Full Access'")
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            Button(action: {
                if let url = URL(string: "App-Prefs:root=General&path=Keyboard") {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Open Keyboard Settings")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal, 30)
            
            Spacer()
        }
    }
}

struct CompletePage: View {
    @Binding var hasCompletedOnboarding: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Text("🎉")
                .font(.system(size: 100))
            
            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Open any app and start typing with AI assistance")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 20) {
                TipRow(icon: "globe", title: "Switch Keyboards", description: "Long-press the 🌐 globe icon")
                TipRow(icon: "sparkles", title: "AI Features", description: "Tap ✨ for AI interaction mode")
                TipRow(icon: "bubble.left.and.bubble.right", title: "Suggestions", description: "AI suggestions appear as you type")
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            Button(action: {
                hasCompletedOnboarding = true
            }) {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 30)
            
            Spacer()
        }
    }
}

// Helper Views

struct PageIndicator: View {
    let currentPage: Int
    let pageCount: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
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
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                identifiedText(title, identifier: titleIdentifier)
                    .fontWeight(.semibold)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                identifiedText(description, identifier: descriptionIdentifier)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
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
        HStack(alignment: .top, spacing: 15) {
            Text(number)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.accentColor)
                .cornerRadius(16)
            
            Text(text)
                .font(.body)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TipRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
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
