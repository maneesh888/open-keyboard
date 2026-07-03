//
//  SettingsView.swift
//  OpenKeyboard
//
//  Settings screen for API key configuration
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var viewModel: SettingsViewModel
    @FocusState private var focusedField: SettingsField?

    private enum SettingsField: Hashable {
        case gatewayURL
        case apiKey
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Label("Gateway Configuration", systemImage: "sparkles")) {
                    TextField("Gateway URL", text: Binding(
                        get: { viewModel.gatewayURLInput },
                        set: { viewModel.updateGatewayURLInput($0) }
                    ))
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .gatewayURL)
                        .onSubmit {
                            viewModel.normalizeGatewayURLInputForEditing()
                            dismissKeyboard()
                        }

                    SecureField("API Key", text: Binding(
                        get: { viewModel.apiKeyInput },
                        set: { viewModel.updateAPIKeyInput($0) }
                    ))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .apiKey)
                        .onSubmit {
                            viewModel.normalizeGatewayURLInputForEditing()
                            dismissKeyboard()
                        }

                    Text("Enter your gateway as https://host. Bare hosts are saved as https://host; /v1 is added automatically for model/chat endpoints.")
                        .font(.footnote)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

                    if viewModel.shouldShowConnectionActions {
                        Button(action: {
                            dismissKeyboard()
                            Task {
                                await viewModel.testConnection()
                            }
                        }) {
                            HStack {
                                if viewModel.isTestingConnection {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }

                                Text(viewModel.isTestingConnection ? "Testing..." : "Test Connection & Save")
                            }
                        }
                        .disabled(!viewModel.canTestConnection)
                    }

                    Text("Tip: enter your gateway host and Open Keyboard will use https:// automatically.")
                        .font(.caption)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

                    if viewModel.showsValidatedGatewayDetails {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Model")
                            Spacer(minLength: 12)
                            Text(viewModel.trustedModelDisplay)
                                .foregroundColor(viewModel.trustedModelLoaded ? .primary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("Structured corrections")
                            Spacer(minLength: 12)
                            Text(viewModel.structuredCapabilityDisplay)
                                .foregroundColor(viewModel.config.supportsStructuredCorrections ? .primary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Text("Model and structured corrections are trusted from the latest successful Test Connection.")
                            .font(.footnote)
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    }

                    if viewModel.connectionStatus == .success {
                        Label("Connection verified. Model and structured corrections loaded from gateway.", systemImage: "checkmark.circle.fill")
                            .foregroundColor(OpenKeyboardTheme.Semantic.success)
                            .listRowBackground(OpenKeyboardTheme.Surface.successBackground)
                            .accessibilityIdentifier("settings_connection_success")
                    }

                    if viewModel.connectionStatus == .failure {
                        Label(viewModel.errorMessage ?? "Connection failed", systemImage: "xmark.circle.fill")
                            .foregroundColor(OpenKeyboardTheme.Semantic.error)
                            .listRowBackground(OpenKeyboardTheme.Surface.errorBackground)
                            .accessibilityIdentifier("settings_connection_error")
                    }
                }

                Section(header: Label("Gateway Diagnostics", systemImage: "waveform.path.ecg")) {
                    Text("Run the full gateway contract check when basic connection passes but keyboard AI behavior needs deeper verification.")
                        .font(.footnote)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

                    Button(action: {
                        dismissKeyboard()
                        Task {
                            await viewModel.runDiagnostics()
                        }
                    }) {
                        HStack {
                            if viewModel.isRunningDiagnostics {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }

                            Text(viewModel.isRunningDiagnostics ? "Diagnosing..." : "Diagnose Gateway")
                        }
                    }
                    .disabled(!viewModel.canRunDiagnostics)
                    .accessibilityIdentifier("settings_diagnose_gateway")

                    if let report = viewModel.diagnosticReport {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Model")
                            Spacer(minLength: 12)
                            Text(report.selectedModel.isEmpty ? "Unavailable" : report.selectedModel)
                                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Text(report.summary)
                            .font(.footnote)
                            .foregroundColor(report.hasFailures ? OpenKeyboardTheme.Semantic.error : OpenKeyboardTheme.Semantic.success)
                            .accessibilityIdentifier("settings_gateway_diagnostic_summary")

                        ForEach(report.checks) { check in
                            GatewayDiagnosticRow(check: check)
                        }
                    }
                }

                Section(header: Label("Privacy & Full Access", systemImage: "lock.shield.fill")) {
                    Text("Basic typing stays local on the keyboard. Full Access is only needed for AI actions so Open Keyboard can send bounded text/context to your configured gateway and receive suggestions. Text sent to the gateway may follow that gateway or model provider logging policy.")
                        .font(.footnote)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                }


                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    }

                    Link("Documentation", destination: SettingsDocumentationLink.url)
                }

                Section {
                    Button("Reset Onboarding") {
                        viewModel.resetOnboarding()
                        dismiss()
                    }
                    .foregroundColor(OpenKeyboardTheme.Semantic.error)
                    .accessibilityIdentifier("settings_reset_onboarding")

                    if let message = viewModel.onboardingResetMessage {
                        Label(message, systemImage: "arrow.counterclockwise.circle.fill")
                            .foregroundColor(OpenKeyboardTheme.Semantic.success)
                            .accessibilityIdentifier("settings_reset_onboarding_confirmation")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        viewModel.saveSettings()
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissKeyboard()
                    }
                }
            }
        }
        .onAppear {
            viewModel.applyConfig(viewModel.config)
        }
        .tint(OpenKeyboardTheme.Brand.cyan)
    }

    private func dismissKeyboard() {
        focusedField = nil
    }

}

private struct GatewayDiagnosticRow: View {
    let check: GatewayDiagnosticCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(check.title, systemImage: statusIcon)
                    .foregroundColor(statusColor)
                Spacer(minLength: 12)
                Text(check.durationDisplay)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
            }

            Text(check.endpoint)
                .font(.caption)
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

            Text(check.message)
                .font(.footnote)
                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: String {
        switch check.status {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }

    private var statusColor: Color {
        switch check.status {
        case .passed: return OpenKeyboardTheme.Semantic.success
        case .failed: return OpenKeyboardTheme.Semantic.error
        case .skipped: return OpenKeyboardTheme.Text.secondaryStrong
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsViewModel())
    }
}
