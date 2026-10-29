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
        refreshKeyboardLayout()
        refreshRuntimeState()
        applyKeyboardHeight(currentKeyboardHeight, forcingLayout: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshKeyboardLayout()
        refreshRuntimeState()
        refreshNumberPadHostContext()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshKeyboardLayout()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        viewModel?.cancelNumberPadInteraction()
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
            showsSystemKeyboardSwitch: needsInputModeSwitchKey,
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
        Publishers.CombineLatest(
            Publishers.CombineLatest4(viewModel.$panelMode, viewModel.$actionPanelState,
                                      viewModel.$isShowingSmileys, viewModel.$smileyState),
            Publishers.CombineLatest4(viewModel.$isNumberPadVisible, viewModel.$needsSystemKeyboardSwitch,
                                      viewModel.$isPhoneLandscape, viewModel.$actionError)
        )
            .map { presentation, context in
                let (panelMode, actionPanelState, showing, smileys) = presentation
                let (isNumberPadVisible, needsSystemSwitch, isPhoneLandscape, actionError) = context
                return isNumberPadVisible
                    ? NumberPadGeometry(availableWidth: 0).height + 12 + (needsSystemSwitch ? 44 : 0)
                    : KeyboardViewModel.presentationHeight(panelMode: panelMode, actionPanelState: actionPanelState,
                                                           searchingSmileys: showing && smileys.isSearching,
                                                           isPhoneLandscape: isPhoneLandscape,
                                                           hasActionError: actionError != nil)
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] height in
                guard let self else { return }
                self.applyKeyboardHeight(height, forcingLayout: true)
            }
            .store(in: &cancellables)
    }

    private func refreshKeyboardLayout() {
        let isPhoneLandscape = traitCollection.userInterfaceIdiom == .phone
            && (view.window?.windowScene?.interfaceOrientation.isLandscape == true
                || traitCollection.verticalSizeClass == .compact)
        viewModel?.updatePhoneLandscape(isPhoneLandscape)
    }

    private func refreshNumberPadHostContext() {
        viewModel?.updateSystemKeyboardSwitchRequirement(needsInputModeSwitchKey)
        viewModel?.refreshNumberPadContext(using: textDocumentProxy)
    }

    private func refreshRuntimeState() {
        hostingController?.rootView.showsSystemKeyboardSwitch = needsInputModeSwitchKey
        // Host document traits are unavailable during viewDidLoad. Read them only
        // after appearance or a host text/selection callback.
        viewModel?.updateSystemKeyboardSwitchRequirement(needsInputModeSwitchKey)
        let fullAccess = hasFullAccess
        viewModel?.updateFullAccess(fullAccess)
        AppConfig.updateKeyboardFullAccess(fullAccess)
    }

    private var currentKeyboardHeight: CGFloat {
        guard let viewModel else { return KeyboardPanelLayout.preferredKeyboardHeight }
        return viewModel.keyboardPresentationHeight
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
