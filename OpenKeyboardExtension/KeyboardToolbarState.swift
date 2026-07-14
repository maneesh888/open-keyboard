//
//  KeyboardToolbarState.swift
//  OpenKeyboardExtension
//

import CoreGraphics
import Foundation

enum KeyboardPanelMode: Equatable {
    case keyboard
    case actions
    case rewriteOptions
    case correctionDetail
    case correctionComplete
}

enum KeyboardPanelLayout {
    static let toolbarHeight: CGFloat = 38
    static let toolbarControlSize: CGFloat = 34
    static let toolbarRenderedHeight: CGFloat = toolbarHeight
    static let toolbarSpacing: CGFloat = 6
    static let outerHorizontalPadding: CGFloat = 4
    static let outerTopPadding: CGFloat = 6
    static let outerBottomPadding: CGFloat = 0
    static let letterKeyHeight: CGFloat = 45
    static let controlKeyHeight: CGFloat = 45
    static let keyHorizontalSpacing: CGFloat = 5.5
    static let keyRowSpacing: CGFloat = 11
    static let keyShadowAllowance: CGFloat = 2
    static let keyGridHeight: CGFloat = (letterKeyHeight * 3) + controlKeyHeight + (keyRowSpacing * 3) + keyShadowAllowance
    static let preferredKeyboardHeight: CGFloat = 280
    static let expandedPanelHeight: CGFloat = preferredKeyboardHeight
    static let improvePanelHeight: CGFloat = preferredKeyboardHeight + 104

    struct KeyGridMetrics {
        let contentWidth: CGFloat
        let letterWidth: CGFloat
        let homeRowInset: CGFloat
        let modifierWidth: CGFloat
        let bottomLetterSideGap: CGFloat
        let bottomControlWidth: CGFloat
        let returnWidth: CGFloat
        let spaceWidth: CGFloat
    }

    static func keyGridMetrics(for contentWidth: CGFloat) -> KeyGridMetrics {
        let safeWidth = max(contentWidth, 1)
        let letterWidth = max((safeWidth - (keyHorizontalSpacing * 9)) / 10, 1)
        let homeRowInset = (letterWidth + keyHorizontalSpacing) / 2
        let modifierWidth = letterWidth * (149 / 111)
        let bottomLetterSideGap = letterWidth * (43 / 111)
        let bottomControlWidth = letterWidth * (142 / 111)
        let returnWidth = letterWidth * (302 / 111)
        let spaceWidth = max(
            safeWidth - (bottomControlWidth * 2) - returnWidth - (keyHorizontalSpacing * 3),
            letterWidth
        )

        return KeyGridMetrics(
            contentWidth: safeWidth,
            letterWidth: letterWidth,
            homeRowInset: homeRowInset,
            modifierWidth: modifierWidth,
            bottomLetterSideGap: bottomLetterSideGap,
            bottomControlWidth: bottomControlWidth,
            returnWidth: returnWidth,
            spaceWidth: spaceWidth
        )
    }

    static func keyboardHeight(
        for panelMode: KeyboardPanelMode,
        actionPanelState: KeyboardActionPanelState?
    ) -> CGFloat {
        if panelMode == .actions, actionPanelState?.usesExpandedImprovePanel == true {
            return improvePanelHeight
        }
        return preferredKeyboardHeight
    }
}

struct KeyboardCompletionPanelState: Equatable {
    let title: String
    let message: String

    static let allDone = KeyboardCompletionPanelState(
        title: "All Done",
        message: "There are no more suggestions."
    )

    static let noIssues = KeyboardCompletionPanelState(
        title: "No issues found",
        message: "There are no grammar or spelling suggestions."
    )

    static let rewriteApplied = KeyboardCompletionPanelState(
        title: "Rewrite applied",
        message: "The selected rewrite replaced the original text."
    )

    static let improvementApplied = KeyboardCompletionPanelState(
        title: "Improvement applied",
        message: "The selected improvement replaced the original text."
    )
}

struct KeyboardToolbarState: Equatable {
    enum Kind: Equatable {
        case fullAccessRequired
        case notConfigured
        case actions(status: String)
        case loading(title: String)
        case correctionPreview(count: Int, explanation: String, replacement: String, original: String)
        case error(message: String)
    }

    let kind: Kind

    var isActionEnabled: Bool {
        if case .actions = kind { return true }
        return false
    }

    var issueCount: Int {
        if case .correctionPreview(let count, _, _, _) = kind { return count }
        return 0
    }

    var showsBrandMark: Bool {
        if case .actions = kind { return true }
        return false
    }

    var showsIssueCount: Bool {
        issueCount > 0
    }

    var leadingSystemImage: String {
        switch kind {
        case .fullAccessRequired, .notConfigured, .error:
            return "exclamationmark.triangle.fill"
        case .actions:
            return "keyboard"
        case .loading, .correctionPreview:
            return "sparkles"
        }
    }

    var title: String {
        switch kind {
        case .fullAccessRequired:
            return "Full Access required"
        case .notConfigured:
            return "Gateway not configured"
        case .actions:
            return "Open Keyboard AI"
        case .loading(let title):
            return title
        case .correctionPreview(let count, _, _, _):
            return count == 1 ? "1 writing suggestion" : "\(count) writing suggestions"
        case .error:
            return "AI unavailable"
        }
    }

    var subtitle: String {
        switch kind {
        case .fullAccessRequired:
            return "Basic typing is local. Full Access lets AI send bounded text to your gateway."
        case .notConfigured:
            return "Pair your gateway in the app before using AI actions."
        case .actions(let status):
            return status
        case .loading:
            return "Checking…"
        case .correctionPreview(_, let explanation, let replacement, let original):
            if !explanation.isEmpty { return explanation }
            if !replacement.isEmpty, !original.isEmpty { return "\(original) → \(replacement)" }
            return "Tap to apply"
        case .error(let message):
            return message
        }
    }

    static func current(
        hasFullAccess: Bool,
        isConfigured: Bool,
        selectedModel: String,
        isPerformingAIAction: Bool,
        aiStatus: String
    ) -> KeyboardToolbarState {
        guard hasFullAccess else { return KeyboardToolbarState(kind: .fullAccessRequired) }
        guard isConfigured else { return KeyboardToolbarState(kind: .notConfigured) }
        if isPerformingAIAction { return KeyboardToolbarState(kind: .loading(title: aiStatus)) }

        let trimmedStatus = aiStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayStatus: String
        if trimmedStatus.isEmpty || trimmedStatus.hasPrefix("AI ready") {
            displayStatus = "Ready"
        } else {
            displayStatus = trimmedStatus
        }
        return KeyboardToolbarState(kind: .actions(status: displayStatus))
    }
}
