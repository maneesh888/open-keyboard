//
//  KeyboardViewController.swift
//  OpenKeyboardExtension
//

import Combine
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardView>?
    private var viewModel: KeyboardViewModel?
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
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
            textDocumentProxy: textDocumentProxy
        )
        self.viewModel = viewModel

        let keyboardView = KeyboardView(viewModel: viewModel)
        let controller = UIHostingController(rootView: keyboardView)

        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.backgroundColor = .clear
        let keyboardHeightConstraint = view.heightAnchor.constraint(equalToConstant: KeyboardPanelLayout.preferredKeyboardHeight)
        self.keyboardHeightConstraint = keyboardHeightConstraint

        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keyboardHeightConstraint
        ])

        controller.didMove(toParent: self)
        hostingController = controller
        bindKeyboardHeight(to: viewModel)
        refreshRuntimeState()
    }

    private func bindKeyboardHeight(to viewModel: KeyboardViewModel) {
        Publishers.CombineLatest(viewModel.$panelMode, viewModel.$actionPanelState)
            .map { panelMode, actionPanelState in
                KeyboardPanelLayout.keyboardHeight(
                    for: panelMode,
                    actionPanelState: actionPanelState
                )
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] height in
                guard let self else { return }
                self.keyboardHeightConstraint?.constant = height
                self.view.setNeedsUpdateConstraints()
                self.view.invalidateIntrinsicContentSize()
                self.view.layoutIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func refreshRuntimeState() {
        viewModel?.updateFullAccess(hasFullAccess)
    }
}
