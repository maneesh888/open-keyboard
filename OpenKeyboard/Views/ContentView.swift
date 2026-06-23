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

                        if settingsViewModel.config.isConfigured {
                            NavigationLink(destination: PlaygroundView()) {
                                PlaygroundEntryCard()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("playground_entry_button")
                            .padding(.horizontal, 20)
                        }

                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                PrimaryButton(title: "Open Keyboard Settings", systemImage: "keyboard") {
                                    settingsViewModel.openKeyboardSettings()
                                }

                                Text(settingsViewModel.keyboardSettingsInstructions)
                                    .font(.footnote)
                                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                                    .fixedSize(horizontal: false, vertical: true)
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
                    Text(config.isConfigured ? "Ready to Type" : "Setup Required")
                        .font(.headline)
                    Text(config.isConfigured ? "Open Keyboard is connected. Switch to the keyboard from any text field to use AI actions." : "Connect your AI service in App Settings to unlock writing actions.")
                        .font(.footnote)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

struct PlaygroundEntryCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.cursor")
                .foregroundColor(OpenKeyboardTheme.Semantic.primaryAction)
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(OpenKeyboardTheme.Semantic.primaryAction.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Open Playground")
                    .font(.headline)
                Text("Try Open Keyboard AI in a real text field.")
                    .font(.footnote)
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpenKeyboardTheme.Surface.brandCardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(OpenKeyboardTheme.Semantic.primaryAction.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: OpenKeyboardTheme.Shadow.card, radius: 14, x: 0, y: 8)
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
