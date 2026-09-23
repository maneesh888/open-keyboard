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
    @State private var showingAIDiagnostics = false

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
                                showingAIDiagnostics = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "stethoscope")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("AI Diagnostics")
                                            .font(.headline)
                                        Text("View and export redacted operation traces")
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
                            .accessibilityIdentifier("ai_diagnostics_entry_button")

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
            .sheet(isPresented: $showingAIDiagnostics) {
                AIOperationDiagnosticsView()
            }
        }
        .tint(OpenKeyboardTheme.Brand.cyan)
        .task {
            await settingsViewModel.validateSavedGatewayOnceOnLaunch()
        }
    }
}

private struct AIOperationDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [AIOperationDiagnosticRecord] = []

    private var export: String {
        AIOperationDiagnostics.shared.export()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Privacy-safe export") {
                    Text("These traces contain only operation IDs, typed stages and failures, timing, byte counts, HTTP status categories, app/build, and OS metadata. They never include typed or generated text, credentials, endpoints, or model identifiers.")
                        .font(.footnote)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)

                    ShareLink(
                        item: export,
                        subject: Text("OpenKeyboard AI diagnostics"),
                        message: Text("Redacted AI operation diagnostics")
                    ) {
                        Label("Export Redacted Diagnostics", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("ai_diagnostics_export")
                }

                Section("Recent operations") {
                    if records.isEmpty {
                        Text("No recent AI operations. The ledger keeps at most 48 traces for seven days.")
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    }

                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(record.operation.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.headline)
                                Spacer()
                                Text(record.outcome?.rawValue.replacingOccurrences(of: "_", with: " ") ?? "In progress")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(outcomeColor(record.outcome))
                            }
                            Text("Trace \(record.traceID)")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            if let failure = record.failure {
                                Text("Failure: \(failure.rawValue.replacingOccurrences(of: "_", with: " "))")
                                    .font(.caption)
                                    .foregroundColor(OpenKeyboardTheme.Semantic.error)
                            }
                            Text("\(record.events.count) stages · updated \(record.updatedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        }
                        .accessibilityIdentifier("ai_diagnostics_trace")
                    }
                }
            }
            .navigationTitle("AI Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") { reload() }
                }
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        records = AIOperationDiagnostics.shared.records()
    }

    private func outcomeColor(_ outcome: AIOperationDiagnosticOutcome?) -> Color {
        switch outcome {
        case .succeeded:
            return OpenKeyboardTheme.Semantic.success
        case .failed, .cancelled, .staleResultSuppressed:
            return OpenKeyboardTheme.Semantic.error
        case nil:
            return OpenKeyboardTheme.Semantic.warning
        }
    }
}

struct StatusCard: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var config: AppConfig { viewModel.config }

    private var isReady: Bool { viewModel.showsValidatedGatewayDetails && viewModel.connectionStatus == .success }
    private var isLimited: Bool { viewModel.showsValidatedGatewayDetails && viewModel.connectionStatus == .limited }
    private var isChecking: Bool { viewModel.isGatewayValidationInProgress }
    private var isFailure: Bool { viewModel.connectionStatus == .failure }

    private var statusTitle: String {
        if isReady { return "Gateway Ready" }
        if isLimited { return "Gateway Connected" }
        if isChecking { return "Checking gateway…" }
        if isFailure { return "Gateway needs attention" }
        return "Setup Required"
    }

    private var statusMessage: String {
        if isReady { return "Connection verified within the last hour." }
        if isLimited { return "Connected, but this model did not verify plain-text grammar correction." }
        if isChecking { return "Testing your saved gateway before enabling AI features." }
        if isFailure { return viewModel.errorMessage ?? "Connection failed. Open Settings to retry." }
        return "Add your API key to unlock AI features."
    }

    private var statusImage: String {
        if isReady { return "checkmark.circle.fill" }
        if isLimited { return "exclamationmark.triangle.fill" }
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
                Group {
                    if isChecking {
                        GatewayCheckingIcon()
                            .accessibilityIdentifier("gateway_status_progress")
                    } else {
                        Image(systemName: statusImage)
                            .accessibilityIdentifier("gateway_status_icon")
                    }
                }
                .foregroundColor(statusColor)
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(isChecking ? Color.clear : statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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

            if (isFailure || isLimited), viewModel.hasSavedGatewayConfig {
                Button(isLimited ? "Retry model check" : "Retry gateway check") {
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

private struct GatewayCheckingIcon: View {
    @State private var rotation = 0.0

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .rotationEffect(.degrees(rotation))
            .onAppear {
                rotation = 0
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
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
