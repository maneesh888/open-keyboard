//
//  KeyboardViewController.swift
//  OpenKeyboardExtension
//

import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
#if targetEnvironment(simulator)
    private static let configProbeBuildMarker = "OK_CONFIG_PROBE_BINARY_MARKER_20260619T1600"
#endif
    private var hostingController: UIHostingController<KeyboardView>?
    private var viewModel: KeyboardViewModel?

    override func viewDidLoad() {
        super.viewDidLoad()
#if targetEnvironment(simulator)
        emitBuildMarker(context: "controller.viewDidLoad")
#endif
        installKeyboardView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshRuntimeState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshRuntimeState()
    }

    private func installKeyboardView() {
        let viewModel = KeyboardViewModel(
            textDocumentProxy: textDocumentProxy,
            advanceToNextInputMode: { [weak self] in
                self?.advanceToNextInputMode()
            }
        )
        self.viewModel = viewModel

        let keyboardView = KeyboardView(viewModel: viewModel)
        let controller = UIHostingController(rootView: keyboardView)

        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.backgroundColor = .clear

        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controller.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])

        controller.didMove(toParent: self)
        hostingController = controller
        refreshRuntimeState()
    }

    private func refreshRuntimeState() {
#if targetEnvironment(simulator)
        emitEntrypointConfigProbe(context: "controller.refreshRuntimeState", hasFullAccess: hasFullAccess)
#endif
        viewModel?.updateFullAccess(hasFullAccess)
    }

#if targetEnvironment(simulator)
    private func emitBuildMarker(context: String) {
        let marker = Self.configProbeBuildMarker
        NSLog("\(marker) runtime context=\(context)")
        fputs("\(marker) stdout context=\(context)\n", stderr)
    }

    private func emitEntrypointConfigProbe(context: String, hasFullAccess: Bool) {
        emitBuildMarker(context: context)
        let defaults = AppConfig.sharedDefaults()
        let config = AppConfig.load()
        let legacyAPIKeyPresent = !(defaults?.string(forKey: AppConfig.apiKeyKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let keychainAPIKeyPresent = !(AppConfig.secretStore.loadAPIKey() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let loadedAPIKeyPresent = !config.apiKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let toolbarReason: String
        let toolbarTitle: String
        if !hasFullAccess {
            toolbarReason = "fullAccessRequired"
            toolbarTitle = "Full Access required"
        } else if !config.isConfigured {
            toolbarReason = "notConfigured"
            toolbarTitle = "Gateway not configured"
        } else {
            toolbarReason = "actions"
            toolbarTitle = "Open Keyboard AI"
        }

        let fields = [
            "context=\(context)",
            "debugFlag=true",
            "appGroupSuite=\(AppConfig.appGroupIdentifier)",
            "sharedDefaultsAvailable=\(defaults != nil)",
            "gatewayURL=\(sanitizedGatewayURL(config.gatewayURL))",
            "selectedModel=\(config.selectedModel.isEmpty ? "<empty>" : config.selectedModel)",
            "appConfigIsConfigured=\(config.isConfigured)",
            "legacyDefaultsAPIKeyPresent=\(legacyAPIKeyPresent)",
            "keychainAPIKeyPresent=\(keychainAPIKeyPresent)",
            "loadedAPIKeyPresent=\(loadedAPIKeyPresent)",
            "hasFullAccess=\(hasFullAccess)",
            "toolbarReason=\(toolbarReason)",
            "toolbarTitle=\(toolbarTitle)"
        ]
        NSLog("Keyboard config probe: \(fields.joined(separator: "; "))")
    }

    private func sanitizedGatewayURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "<empty>" }
        guard var components = URLComponents(string: trimmed) else { return "<invalid-or-non-url-present>" }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "<url-present>"
    }
#endif
}
