//
//  ContentView.swift
//  OpenKeyboard
//
//  Main app view
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var keyboardAccessViewModel = KeyboardAccessViewModel()
    @State private var showingSettings = false
    @State private var showingPlayground = false
    @State private var showingKeyboardAccessCheck = false
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
                            if !keyboardAccessViewModel.hasFullAccess {
                                Button {
                                    if keyboardAccessViewModel.needsConfirmation {
                                        showingKeyboardAccessCheck = true
                                    } else {
                                        keyboardAccessViewModel.didOpenKeyboardSettings()
                                        settingsViewModel.openKeyboardSettings()
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: keyboardAccessViewModel.needsConfirmation ? "checkmark.shield" : "keyboard")
                                            .font(.title3.weight(.semibold))
                                            .foregroundColor(OpenKeyboardTheme.Brand.cyan)
                                            .frame(width: 36, height: 36)
                                            .background(OpenKeyboardTheme.Brand.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(keyboardAccessViewModel.needsConfirmation ? "Check Keyboard Access" : "Open Keyboard Settings")
                                                .font(.headline)
                                            Text(keyboardAccessViewModel.needsConfirmation
                                                 ? "Select Open Keyboard in a text field to confirm Allow Full Access."
                                                 : "Allow Full Access is needed for AI actions. Open the keyboard once afterward to confirm access.")
                                                .font(.caption)
                                                .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .accessibilityIdentifier(keyboardAccessViewModel.needsConfirmation ? "keyboard_access_check_note" : "keyboard_full_access_note")
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
                                            .stroke(OpenKeyboardTheme.Semantic.warning.opacity(0.42), lineWidth: 1.2)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(keyboardAccessViewModel.needsConfirmation ? "check_keyboard_access_button" : "open_keyboard_settings_button")
                                .accessibilityHint(keyboardAccessViewModel.needsConfirmation
                                                   ? "Opens a text field where Open Keyboard can confirm its access"
                                                   : "Opens Keyboard Settings to enable Full Access for AI actions")
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
                                        Text("Review recent AI operations and diagnostic captures")
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
            .sheet(isPresented: $showingKeyboardAccessCheck, onDismiss: {
                keyboardAccessViewModel.refresh()
            }) {
                KeyboardAccessCheckView()
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
        .onAppear {
            keyboardAccessViewModel.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            keyboardAccessViewModel.refresh()
        }
    }
}

private final class KeyboardAccessViewModel: ObservableObject {
    @Published private(set) var hasFullAccess = false
    @Published private(set) var needsConfirmation = false

    func refresh() {
        hasFullAccess = AppConfig.keyboardHasFullAccess()
        needsConfirmation = !hasFullAccess && AppConfig.keyboardAccessNeedsConfirmation()
        if hasFullAccess {
            AppConfig.updateKeyboardAccessNeedsConfirmation(false)
        }
    }

    func didOpenKeyboardSettings() {
        AppConfig.updateKeyboardAccessNeedsConfirmation(true)
        needsConfirmation = true
    }
}

private struct KeyboardAccessCheckView: View {
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationView {
            ZStack {
                AppBackground()

                VStack(alignment: .leading, spacing: 18) {
                    Text("Tap the field and select Open Keyboard using the globe key. Then return to Home to see whether Allow Full Access was confirmed.")
                        .font(.subheadline)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $text)
                        .frame(minHeight: 150)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .background(OpenKeyboardTheme.Surface.panelBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(OpenKeyboardTheme.Stroke.subtle, lineWidth: 1)
                        )
                        .accessibilityIdentifier("keyboard_access_check_input")

                    Button("Open Keyboard Settings") {
                        settingsViewModel.openKeyboardSettings()
                    }
                    .accessibilityIdentifier("keyboard_access_check_settings_button")

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle("Check Keyboard Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct AIOperationDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AIOperationDiagnosticsViewModel()
    @State private var showingShareConfirmation = false
    @State private var showingShareSheet = false
    @Environment(\.scenePhase) private var scenePhase

    private var records: [AIOperationDiagnosticRecord] { viewModel.visibleRecords }

    var body: some View {
        NavigationStack {
            List {
                Section("Diagnostics export") {
                    Text("Includes provider, model, request settings, failure details, timing, and app/OS versions. Credentials from Settings and gateway addresses are never collected. Captured phrases and responses are included only after you confirm sharing.")
                        .font(.footnote)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    Button {
                        viewModel.prepareTextPreview()
                        showingShareConfirmation = !viewModel.textPreview.isEmpty
                    } label: {
                        Label("Share Diagnostics", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("ai_diagnostics_export")
                    .disabled(viewModel.exportTraceIDs.isEmpty)
                }

                Section {
                    Toggle("Capture Text", isOn: Binding(
                        get: { viewModel.captureExpiresAt != nil },
                        set: { viewModel.setTextCaptureEnabled($0) }
                    ))
                    .accessibilityIdentifier("ai_diagnostics_capture_toggle")
                } footer: {
                    Text("Records AI phrases and available responses for 10 minutes, including automatic checks and text from other apps. Stored on this device for up to 24 hours. Turning this off deletes captured text.")
                }
                Section {
                    Button("Delete All Diagnostics", role: .destructive) { viewModel.clear() }
                        .accessibilityIdentifier("ai_diagnostics_delete_all")
                }
                Section("Recent operations") {
                    Picker("Reports", selection: Binding(get: { viewModel.filter }, set: { viewModel.selectFilter($0) })) {
                        ForEach(AIOperationDiagnosticFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("ai_diagnostics_filter")
                    if viewModel.filter == .warnings {
                        Text("Cancelled or ignored operations, and operations with a recorded failure that did not end in an error.")
                            .font(.caption)
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    }
                    if records.isEmpty {
                        Text(viewModel.records.isEmpty ? "No recent AI operations. The ledger keeps at most 48 traces for seven days." : "No operations in this category.")
                            .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                    }

                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button { viewModel.toggleSelection(record.traceID) } label: {
                                    Image(systemName: viewModel.selectedTraceIDs.contains(record.traceID) ? "checkmark.square.fill" : "square")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Select report \(record.traceID)")
                                .accessibilityValue(viewModel.selectedTraceIDs.contains(record.traceID) ? "Selected" : "Not selected")
                                .accessibilityIdentifier("ai_diagnostics_select_\(record.traceID)")
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
                            if let subreason = record.events.reversed().compactMap(\.subreason).first {
                                Text("Detail: \(subreason.rawValue.replacingOccurrences(of: "_", with: " "))")
                                    .font(.caption)
                                    .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                                    .accessibilityIdentifier("ai_diagnostics_subreason")
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
                    Button("Refresh") { viewModel.refresh() }
                }
            }
            .onAppear { viewModel.refresh() }
            .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in viewModel.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.refresh() }
                if phase == .background && !showingShareSheet {
                    showingShareConfirmation = false
                    viewModel.dismissTextPreview()
                }
            }
            .alert("Share diagnostics?", isPresented: $showingShareConfirmation) {
                Button("Cancel", role: .cancel) { viewModel.dismissTextPreview() }
                Button("OK") { showingShareSheet = viewModel.confirmShare() }
            } message: {
                Text("The selected reports may include captured phrases and AI responses, which can contain sensitive information. Continue to choose where to share them?")
            }
            .sheet(isPresented: $showingShareSheet, onDismiss: { viewModel.dismissTextPreview() }) {
                DiagnosticShareSheet(text: viewModel.textPreview)
            }
            .onChange(of: viewModel.textPreview) { _, text in
                if text.isEmpty { showingShareConfirmation = false; showingShareSheet = false }
            }
        }
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

private struct DiagnosticShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
