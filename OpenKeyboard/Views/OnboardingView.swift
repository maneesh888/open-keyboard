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
    @State private var currentPage = 0
    @State private var showingSettings = false
    
    var body: some View {
        VStack {
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
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(settingsViewModel)
        }
    }
}

struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Text("🔓")
                .font(.system(size: 100))
            
            Text("Welcome to\nOpen Keyboard")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("AI-powered typing with privacy in mind")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "cpu", title: "Your Own LLM", description: "Connect to your self-hosted LLM gateway")
                FeatureRow(icon: "lock.shield", title: "Privacy First", description: "Your data never leaves your control")
                FeatureRow(icon: "sparkles", title: "AI Powered", description: "Smart suggestions and text improvements")
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            Text("Swipe to continue →")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 40)
        }
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

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
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
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(hasCompletedOnboarding: .constant(false))
            .environmentObject(SettingsViewModel())
    }
}
