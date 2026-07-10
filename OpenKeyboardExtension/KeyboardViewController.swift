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
        applyKeyboardHeight(currentKeyboardHeight, forcingLayout: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshRuntimeState()
    }

    override func updateViewConstraints() {
        ensureKeyboardHeightConstraint()
        keyboardHeightConstraint?.constant = currentKeyboardHeight
        super.updateViewConstraints()
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
        ensureKeyboardHeightConstraint()

        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        controller.didMove(toParent: self)
        hostingController = controller
        bindKeyboardHeight(to: viewModel)
        refreshRuntimeState()
        applyKeyboardHeight(currentKeyboardHeight, forcingLayout: true)
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
                self.applyKeyboardHeight(height, forcingLayout: true)
            }
            .store(in: &cancellables)
    }

    private func refreshRuntimeState() {
        viewModel?.updateFullAccess(hasFullAccess)
    }

    private var currentKeyboardHeight: CGFloat {
        guard let viewModel else { return KeyboardPanelLayout.preferredKeyboardHeight }
        return KeyboardPanelLayout.keyboardHeight(
            for: viewModel.panelMode,
            actionPanelState: viewModel.actionPanelState
        )
    }

    private func ensureKeyboardHeightConstraint() {
        guard keyboardHeightConstraint == nil else { return }
        let constraint = view.heightAnchor.constraint(equalToConstant: KeyboardPanelLayout.preferredKeyboardHeight)
        constraint.priority = .required
        constraint.isActive = true
        keyboardHeightConstraint = constraint
    }

    private func applyKeyboardHeight(_ height: CGFloat, forcingLayout: Bool) {
        ensureKeyboardHeightConstraint()
        keyboardHeightConstraint?.constant = height
        view.setNeedsUpdateConstraints()
        view.invalidateIntrinsicContentSize()
        view.superview?.setNeedsLayout()
        if forcingLayout {
            view.layoutIfNeeded()
            view.superview?.layoutIfNeeded()
        }
    }
}
