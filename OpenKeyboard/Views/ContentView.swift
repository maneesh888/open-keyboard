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
    @State private var showingPlayground = false

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

                        StatusCard(viewModel: settingsViewModel)

                        VStack(spacing: 12) {
                            PrimaryButton(title: "Open Keyboard Settings", systemImage: "keyboard") {
                                settingsViewModel.openKeyboardSettings()
                            }

                            if settingsViewModel.trustedModelLoaded {
                                Button(action: {
                                    showingPlayground = true
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "sparkles")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Open Playground")
                                                .font(.headline)
                                            Text("Try AI writing actions in a real text field")
                                                .font(.caption)
                                                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                                    }
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 16)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(OpenKeyboardTheme.Brand.cyan.opacity(0.45), lineWidth: 1.2)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("playground_entry_button")
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
                                        .stroke(settingsViewModel.trustedModelLoaded ? OpenKeyboardTheme.Semantic.success.opacity(0.45) : OpenKeyboardTheme.Semantic.warning.opacity(0.42), lineWidth: 1.2)
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
            .sheet(isPresented: $showingPlayground) {
                NavigationView {
                    PlaygroundView()
                }
                .environmentObject(settingsViewModel)
            }
        }
        .tint(OpenKeyboardTheme.Brand.cyan)
        .task {
            await settingsViewModel.validateSavedGatewayOnceOnLaunch()
        }
    }
}

struct StatusCard: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var config: AppConfig { viewModel.config }

    private var isReady: Bool { viewModel.showsValidatedGatewayDetails && viewModel.connectionStatus == .success }
    private var isChecking: Bool { viewModel.isTestingConnection || viewModel.connectionStatus == .checking || viewModel.shouldShowGatewayValidationPending }
    private var isFailure: Bool { viewModel.connectionStatus == .failure }

    private var statusTitle: String {
        if isReady { return "Gateway Ready" }
        if isChecking { return "Checking gateway…" }
        if isFailure { return "Gateway needs attention" }
        return "Setup Required"
    }

    private var statusMessage: String {
        if isReady { return "Connection verified just now." }
        if isChecking { return "Testing your saved gateway before enabling AI features." }
        if isFailure { return viewModel.errorMessage ?? "Connection failed. Open Settings to retry." }
        return "Add your API key to unlock AI features."
    }

    private var statusImage: String {
        if isReady { return "checkmark.circle.fill" }
        if isChecking { return "arrow.triangle.2.circlepath" }
        if isFailure { return "xmark.circle.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        if isReady { return OpenKeyboardTheme.Semantic.success }
        if isFailure { return OpenKeyboardTheme.Semantic.error }
        return OpenKeyboardTheme.Semantic.warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Image(systemName: statusImage)
                        .foregroundColor(statusColor)
                        .font(.title3)
                    if isChecking {
                        ProgressView()
                            .scaleEffect(0.72)
                            .accessibilityIdentifier("gateway_status_progress")
                    }
                }
                .frame(width: 34, height: 34)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusMessage)
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

            if isFailure, viewModel.hasSavedGatewayConfig {
                Button("Retry gateway check") {
                    Task { await viewModel.retrySavedGatewayValidation() }
                }
                .font(.footnote.weight(.semibold))
                .accessibilityIdentifier("gateway_status_retry")
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
