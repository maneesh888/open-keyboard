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
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                                    .frame(width: 78, height: 78)
                                Image(systemName: "keyboard.badge.eye")
                                    .font(.system(size: 34, weight: .semibold))
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.top, 12)

                            Text("Open Keyboard")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)

                            Text("Private AI-powered typing")
                                .font(.headline.weight(.medium))
                                .foregroundColor(.secondary)
                        }

                        StatusCard(config: settingsViewModel.config)

                        VStack(spacing: 12) {
                            PrimaryButton(title: "Open Keyboard Settings", systemImage: "keyboard") {
                                settingsViewModel.openKeyboardSettings()
                            }

                            Button(action: {
                                showingSettings = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "gearshape.fill")
                                    Text("App Settings")
                                }
                                .font(.headline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 18)
                    .padding(.bottom, 28)
                }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: config.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(config.isConfigured ? .green : .orange)
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .background((config.isConfigured ? Color.green : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.isConfigured ? "Keyboard Configured" : "Setup Required")
                        .font(.headline)
                    Text(config.isConfigured ? "Your gateway is ready." : "Add your API key to unlock AI features.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if config.isConfigured {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Gateway", value: config.gatewayURL)
                    InfoRow(label: "API Key", value: String(config.apiKey.prefix(10)) + "...")
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
        .padding(.horizontal, 20)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 12)
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SettingsViewModel())
    }
}
