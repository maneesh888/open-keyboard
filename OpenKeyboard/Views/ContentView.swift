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
    @State private var showingKeyboardPreviewLab = false

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        VStack(spacing: 12) {
                            OpenKeyboardBrandMark(size: 86, symbolSize: 36)
                            .padding(.top, 12)

                            Text("Open Keyboard")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)

                            Text("Private AI-powered typing")
                                .font(.headline.weight(.medium))
                                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        }

                        StatusCard(config: settingsViewModel.config)

                        VStack(spacing: 12) {
                            PrimaryButton(title: "Open Keyboard Settings", systemImage: "keyboard") {
                                settingsViewModel.openKeyboardSettings()
                            }

                            if settingsViewModel.config.isConfigured {
                                NavigationLink(destination: KeyboardPreviewLabView(), isActive: $showingKeyboardPreviewLab) {
                                    Button(action: { showingKeyboardPreviewLab = true }) {
                                        HStack(spacing: 12) {
                                            OpenKeyboardBrandMark(size: 34, symbolSize: 14)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Keyboard Preview Lab")
                                                    .font(.headline.weight(.semibold))
                                                Text("Test zero-issue, issue count, correction cards, and AI actions.")
                                                    .font(.caption)
                                                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                                                    .lineLimit(2)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.bold))
                                                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                                        }
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(14)
                                        .background(OpenKeyboardTheme.Surface.brandPanelBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(OpenKeyboardTheme.Semantic.primaryAction.opacity(0.55), lineWidth: 1.2)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .accessibilityIdentifier("keyboard_preview_lab_entry")
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
                                        .stroke(settingsViewModel.config.isConfigured ? OpenKeyboardTheme.Semantic.success.opacity(0.45) : OpenKeyboardTheme.Semantic.warning.opacity(0.42), lineWidth: 1.2)
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
        .tint(OpenKeyboardTheme.Brand.cyan)
    }
}

struct StatusCard: View {
    let config: AppConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: config.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(config.isConfigured ? OpenKeyboardTheme.Semantic.success : OpenKeyboardTheme.Semantic.warning)
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .background((config.isConfigured ? OpenKeyboardTheme.Semantic.success : OpenKeyboardTheme.Semantic.warning).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.isConfigured ? "Keyboard Configured" : "Setup Required")
                        .font(.headline)
                    Text(config.isConfigured ? "Your gateway is ready." : "Add your API key to unlock AI features.")
                        .font(.footnote)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if config.isConfigured {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Gateway", value: config.gatewayURL)
                    InfoRow(label: "Model", value: config.selectedModel)
                    InfoRow(label: "API Key", value: config.apiKey.isEmpty ? "Not set" : "Configured")
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenKeyboardTheme.Surface.brandCardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(OpenKeyboardTheme.Stroke.subtle, lineWidth: 1)
        )
        .shadow(color: OpenKeyboardTheme.Shadow.card, radius: 14, x: 0, y: 8)
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
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
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
