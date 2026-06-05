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

                    TextField("Model", text: $viewModel.config.selectedModel)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    if !viewModel.availableModels.isEmpty {
                        Picker("Available Models", selection: $viewModel.config.selectedModel) {
                            ForEach(viewModel.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    }
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
                            
                            Text(viewModel.isTestingConnection ? "Testing..." : "Test Connection")
                        }
                    }
                    .disabled(viewModel.config.apiKey.isEmpty || viewModel.isTestingConnection)
                    
                    if viewModel.connectionStatus == .success {
                        Label("Connected successfully", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                    
                    if viewModel.connectionStatus == .failure {
                        Label(viewModel.errorMessage ?? "Connection failed", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundColor(.secondary)
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
                    .foregroundColor(.red)
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
