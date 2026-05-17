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
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Text("🔓")
                        .font(.system(size: 72))
                    
                    Text("Open Keyboard")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("AI-Powered Typing")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 60)
                
                Spacer()
                
                // Status Card
                StatusCard(config: settingsViewModel.config)
                
                Spacer()
                
                // Actions
                VStack(spacing: 16) {
                    // Open Keyboard Settings Button
                    Button(action: {
                        settingsViewModel.openKeyboardSettings()
                    }) {
                        HStack {
                            Image(systemName: "keyboard")
                            Text("Open Keyboard Settings")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
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
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
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
