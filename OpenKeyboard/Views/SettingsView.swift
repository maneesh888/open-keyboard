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
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Gateway Configuration")) {
                    TextField("Gateway URL", text: $viewModel.config.gatewayURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    SecureField("API Key", text: $viewModel.config.apiKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    HStack(alignment: .firstTextBaseline) {
                        Text("Model")
                        Spacer(minLength: 12)
                        Text(viewModel.config.selectedModel.isEmpty ? "Loaded from gateway" : viewModel.config.selectedModel)
                            .foregroundColor(viewModel.config.selectedModel.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Text("Model is read-only and is loaded from the configured gateway after testing the connection.")
                        .font(.footnote)
                        .foregroundColor(OpenKeyboardTheme.Text.secondaryStrong)
                }
                
                Section(header: Text("Connection Test")) {
                    Button(action: {
                        Task {
                            await viewModel.testConnection()
                        }
                    }) {
                        HStack {
                            if viewModel.isTestingConnection {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            
                            Text(viewModel.isTestingConnection ? "Testing..." : "Test Connection & Load Models")
                        }
                    }
                    .disabled(viewModel.config.gatewayURL.isEmpty || viewModel.config.apiKey.isEmpty || viewModel.isTestingConnection)
                    
                    if viewModel.connectionStatus == .success {
                        Label("Connected successfully", systemImage: "checkmark.circle.fill")
                            .foregroundColor(OpenKeyboardTheme.Semantic.success)
                    }
                    
                    if viewModel.connectionStatus == .failure {
                        Label(viewModel.errorMessage ?? "Connection failed", systemImage: "xmark.circle.fill")
                            .foregroundColor(OpenKeyboardTheme.Semantic.error)
                    }
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
                    
                    Link("Documentation", destination: URL(string: "https://github.com/maneesh/open-keyboard")!)

                    if let adminURL = gatewayAdminURL {
                        Link("Gateway Admin", destination: adminURL)
                    }
                }
                
                Section {
                    Button("Reset Onboarding") {
                        UserDefaults(suiteName: "group.com.maneesh.openkeyboard")?
                            .set(false, forKey: "hasCompletedOnboarding")
                    }
                    .foregroundColor(OpenKeyboardTheme.Semantic.error)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        viewModel.saveSettings()
                        dismiss()
                    }
                }
            }
        }
        .tint(OpenKeyboardTheme.Brand.cyan)
    }

    private var gatewayAdminURL: URL? {
        guard var components = URLComponents(string: viewModel.config.gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }
        components.path = "/ui"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(SettingsViewModel())
    }
}
