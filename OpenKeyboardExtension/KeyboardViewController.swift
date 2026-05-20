//
//  KeyboardViewController.swift
//  OpenKeyboardExtension
//

import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        installKeyboardView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hostingController?.rootView.viewModel.reloadConfig()
    }

    private func installKeyboardView() {
        let viewModel = KeyboardViewModel(
            textDocumentProxy: textDocumentProxy,
            advanceToNextInputMode: { [weak self] in
                self?.advanceToNextInputMode()
            }
        )
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
    }
}
