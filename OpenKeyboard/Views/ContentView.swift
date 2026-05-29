//
//  ContentView.swift
//  OpenKeyboard
//
//  Main app view
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    // Header
                    VStack(spacing: 10) {
                        Text("🔓")
                            .font(.system(size: 58))
                            .lineLimit(1)

                        Text("Open Keyboard")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("AI-Powered Typing")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 28)

                    // Status Card
                    StatusCard(config: settingsViewModel.config)

                    // Actions
                    VStack(spacing: 16) {
                        // Open Keyboard Settings Button
                        Button(action: {
                            settingsViewModel.openKeyboardSettings()
                        }) {
                            HStack {
                                Image(systemName: "keyboard")
                                Text("Open Keyboard Settings")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        // Settings Button
                        Button(action: {
                            showingSettings = true
                        }) {
                            HStack {
                                Image(systemName: "gearshape")
                                Text("App Settings")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 28)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(settingsViewModel)
            }
        }
    }
}

struct StatusCard: View {
    let config: AppConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: config.isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(config.isConfigured ? .green : .orange)
                    .font(.title2)

                Text(config.isConfigured ? "Keyboard Configured" : "Setup Required")
                    .font(.headline)
            }

            if !config.isConfigured {
                Text("Configure your API key in Settings to start using AI features.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Gateway:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(config.gatewayURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("API Key:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(config.apiKey.prefix(10) + "...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SettingsViewModel())
    }
}
