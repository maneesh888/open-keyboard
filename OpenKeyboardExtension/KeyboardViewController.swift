//
//  KeyboardViewController.swift
//  OpenKeyboardExtension
//

import Combine
import KeyboardLayout
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
        refreshNumberPadHostContext()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshNumberPadHostContext()
        viewModel?.documentDidChange()
    }

    override func viewWillDisappear(_ animated: Bool) {
        viewModel?.cancelNumberPadInteraction()
        super.viewWillDisappear(animated)
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        viewModel?.cancelNumberPadInteraction()
        refreshNumberPadHostContext()
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

        let keyboardView = KeyboardView(
            viewModel: viewModel,
            onNextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            },
            onInputModeList: { [weak self] sender, event in
                self?.viewModel?.cancelNumberPadInteraction()
                self?.handleInputModeList(from: sender, with: event)
            }
        )
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
        Publishers.CombineLatest4(viewModel.$panelMode, viewModel.$actionPanelState, viewModel.$isNumberPadVisible, viewModel.$needsSystemKeyboardSwitch)
            .map { panelMode, actionPanelState, isNumberPadVisible, needsSystemSwitch in
                isNumberPadVisible ? NumberPadGeometry(availableWidth: 0).height + 12 + (needsSystemSwitch ? 44 : 0) : KeyboardPanelLayout.keyboardHeight(
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

    private func refreshNumberPadHostContext() {
        viewModel?.updateSystemKeyboardSwitchRequirement(needsInputModeSwitchKey)
        viewModel?.refreshNumberPadContext()
    }

    private func refreshRuntimeState() {
        // Host document traits are unavailable during viewDidLoad. Read them only
        // after appearance or a host text/selection callback.
        viewModel?.updateSystemKeyboardSwitchRequirement(needsInputModeSwitchKey)
        let fullAccess = hasFullAccess
        viewModel?.updateFullAccess(fullAccess)
        AppConfig.updateKeyboardFullAccess(fullAccess)
    }

    private var currentKeyboardHeight: CGFloat {
        guard let viewModel else { return KeyboardPanelLayout.preferredKeyboardHeight }
        return viewModel.isNumberPadVisible ? viewModel.numberPadHeight : KeyboardPanelLayout.keyboardHeight(
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
