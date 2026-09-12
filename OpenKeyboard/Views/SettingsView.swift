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
    @State private var connectionTask: Task<Void, Never>?
    @State private var modelDiscoveryTask: Task<Void, Never>?
    @State private var diagnosticsTask: Task<Void, Never>?

    private enum SettingsField: Hashable {
        case baseURL
        case apiKey
        case manualModel
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Label("AI Provider", systemImage: "sparkles")) {
                    Picker("Provider", selection: Binding(
                        get: { viewModel.selectedProvider },
                        set: {
                            cancelGatewayTaskHandles()
                            viewModel.updateProvider($0)
                        }
                    )) {
                        ForEach(OpenKeyboardAIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .accessibilityIdentifier("settings_provider_picker")

                    TextField("Base URL", text: Binding(
                        get: { viewModel.gatewayURLInput },
                        set: {
                            cancelGatewayTaskHandles()
                            viewModel.updateGatewayURLInput($0)
                        }
                    ))
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .baseURL)
                        .onSubmit {
                            viewModel.normalizeGatewayURLInputForEditing()
                            dismissKeyboard()
                        }
                        .accessibilityIdentifier("settings_provider_base_url")

                    SecureField("API Key", text: Binding(
                        get: { viewModel.apiKeyInput },
                        set: {
                            cancelGatewayTaskHandles()
                            viewModel.updateAPIKeyInput($0)
                        }
                    ))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .apiKey)
                        .onSubmit {
                            viewModel.normalizeGatewayURLInputForEditing()
                            dismissKeyboard()
                        }
                        .accessibilityIdentifier("settings_provider_api_key")

                    Text("The provider default is editable. OpenAI-compatible gateways accept a bare host and add the connector's /v1 API root exactly once.")
                        .font(.footnote)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

                    HStack {
                        Button(action: startModelDiscovery) {
                            HStack {
                                if viewModel.isLoadingModels {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Text(viewModel.modelDiscoveryActionTitle)
                            }
                        }
                        .disabled(!viewModel.canLoadModels)
                        .accessibilityIdentifier("settings_load_models")

                        if viewModel.canCancelModelDiscovery {
                            Button("Cancel", role: .cancel) {
                                modelDiscoveryTask?.cancel()
                                modelDiscoveryTask = nil
                                viewModel.cancelModelDiscovery()
                            }
                            .accessibilityIdentifier("settings_cancel_model_loading")
                        }
                    }

                    if viewModel.shouldShowModelSelection {
                        Picker("Model", selection: Binding(
                            get: { viewModel.selectedModelInput },
                            set: {
                                cancelGatewayTaskHandles()
                                viewModel.updateSelectedModelInput($0)
                            }
                        )) {
                            Text("Select a model").tag("")
                            ForEach(viewModel.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .accessibilityIdentifier("settings_gateway_model_picker")

                        if let message = viewModel.modelSelectionMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundColor(OpenKeyboardTheme.Semantic.warning)
                                .accessibilityIdentifier("settings_gateway_model_selection_required")
                        }
                    }

                    if viewModel.shouldShowManualModelEntry {
                        TextField("Exact model identifier", text: Binding(
                            get: { viewModel.selectedModelInput },
                            set: {
                                cancelGatewayTaskHandles()
                                viewModel.updateSelectedModelInput($0)
                            }
                        ))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .manualModel)
                        .onSubmit { dismissKeyboard() }
                        .accessibilityIdentifier("settings_manual_model")
                    }

                    if let message = modelDiscoveryStatusMessage {
                        Label(message, systemImage: modelDiscoveryStatusIcon)
                            .font(.footnote)
                            .foregroundColor(modelDiscoveryStatusColor)
                            .accessibilityIdentifier("settings_model_discovery_status")
                    }

                    if viewModel.shouldShowConnectionActions {
                        Button(action: {
                            dismissKeyboard()
                            connectionTask?.cancel()
                            connectionTask = Task {
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
                        .accessibilityIdentifier("settings_test_connection_save")
                    }

                    Text("Test Connection always rechecks the authenticated catalog and probes the exact selected model without substituting another model.")
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
                                .accessibilityIdentifier("settings_validated_model")
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("Grammar correction")
                            Spacer(minLength: 12)
                            Text(viewModel.grammarCapabilityDisplay)
                                .foregroundColor(viewModel.config.grammarCorrectionVerified ? .primary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Text(viewModel.connectionStatus == .limited
                             ? "The gateway and selected model are available, but plain-text grammar correction was not verified."
                             : "Model and plain-text grammar correction are trusted from the latest successful Test Connection.")
                            .font(.footnote)
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    }

                    if viewModel.connectionStatus == .success {
                        Label("Connection verified. Model and plain-text grammar correction are ready.", systemImage: "checkmark.circle.fill")
                            .foregroundColor(OpenKeyboardTheme.Semantic.success)
                            .listRowBackground(OpenKeyboardTheme.Surface.successBackground)
                            .accessibilityIdentifier("settings_connection_success")
                    }

                    if viewModel.connectionStatus == .limited {
                        Label(viewModel.modelCapabilityMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(OpenKeyboardTheme.Semantic.warning)
                            .listRowBackground(OpenKeyboardTheme.Surface.warningBackground)
                            .accessibilityIdentifier("settings_model_capability_warning")
                    }

                    if viewModel.connectionStatus == .failure {
                        Label(viewModel.errorMessage ?? "Connection failed", systemImage: "xmark.circle.fill")
                            .foregroundColor(OpenKeyboardTheme.Semantic.error)
                            .listRowBackground(OpenKeyboardTheme.Surface.errorBackground)
                            .accessibilityIdentifier("settings_connection_error")
                    }
                }

                Section(header: Label("Provider Diagnostics", systemImage: "waveform.path.ecg")) {
                    Text("Check the exact selected model with one fast probe each for grammar, Rewrite/Improve, and translation to Dutch.")
                        .font(.footnote)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

                    Button(action: {
                        dismissKeyboard()
                        diagnosticsTask?.cancel()
                        diagnosticsTask = Task {
                            await viewModel.runDiagnostics()
                        }
                    }) {
                        HStack {
                            if viewModel.isRunningDiagnostics {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }

                            Text(viewModel.isRunningDiagnostics ? "Diagnosing..." : "Diagnose Provider")
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
                    Text("Basic typing stays local on the keyboard. Full Access is only needed for AI actions so Open Keyboard can send bounded text/context to your configured provider and receive suggestions. Text may be subject to that provider's logging policy.")
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
                        cancelGatewayTasks()
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
            #if DEBUG && targetEnvironment(simulator)
            viewModel.applyUITestSettingsStateIfNeeded()
            #endif
        }
        .onDisappear {
            cancelGatewayTasks()
        }
        .tint(OpenKeyboardTheme.Brand.cyan)
    }

    private func dismissKeyboard() {
        focusedField = nil
    }

    private func cancelGatewayTasks() {
        cancelGatewayTaskHandles()
        viewModel.cancelInFlightGatewayOperations()
    }

    private func cancelGatewayTaskHandles() {
        connectionTask?.cancel()
        modelDiscoveryTask?.cancel()
        diagnosticsTask?.cancel()
        connectionTask = nil
        modelDiscoveryTask = nil
        diagnosticsTask = nil
    }

    private func startModelDiscovery() {
        dismissKeyboard()
        modelDiscoveryTask?.cancel()
        #if DEBUG && targetEnvironment(simulator)
        if viewModel.applyUITestModelDiscoveryActionIfNeeded() {
            return
        }
        #endif
        modelDiscoveryTask = Task {
            if viewModel.canRetryModelDiscovery {
                await viewModel.retryModelDiscovery()
            } else {
                await viewModel.loadModels()
            }
        }
    }

    private var modelDiscoveryStatusMessage: String? {
        switch viewModel.modelDiscoveryState {
        case .idle, .loading, .loaded:
            return nil
        case .unsupported:
            return "This provider explicitly reported that model discovery is unsupported. Enter the exact model identifier."
        case .failed(let message):
            return message
        case .cancelled:
            return "Model loading was cancelled."
        }
    }

    private var modelDiscoveryStatusIcon: String {
        switch viewModel.modelDiscoveryState {
        case .unsupported: return "info.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        default: return "info.circle"
        }
    }

    private var modelDiscoveryStatusColor: Color {
        switch viewModel.modelDiscoveryState {
        case .failed: return OpenKeyboardTheme.Semantic.error
        case .unsupported: return OpenKeyboardTheme.Semantic.warning
        default: return OpenKeyboardTheme.Text.secondaryStrong
        }
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
        .accessibilityIdentifier("settings_gateway_diagnostic_\(check.id)")
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
