//
//  KeyboardToolbarState.swift
//  OpenKeyboardExtension
//

import Foundation

enum KeyboardPanelMode: Equatable {
    case keyboard
    case actions
    case analyzing
    case allGood
    case analysisFailed
    case correctionDetail
    case correctionComplete
}

struct KeyboardToolbarState: Equatable {
    enum Kind: Equatable {
        case fullAccessRequired
        case notConfigured
        case actions(status: String)
        case loading(title: String)
        case correctionPreview(count: Int, explanation: String, replacement: String, original: String, prediction: String?)
        case error(message: String)
    }

    let kind: Kind

    var isActionEnabled: Bool {
        switch kind {
        case .actions:
            return true
        default:
            return false
        }
    }

    var issueCount: Int {
        if case .correctionPreview(let count, _, _, _, _) = kind { return count }
        return 0
    }

    var showsBrandMark: Bool {
        switch kind {
        case .actions, .loading:
            return true
        default:
            return false
        }
    }

    var isZeroIssueLogoState: Bool {
        showsBrandMark && !showsIssueCount
    }

    var showsIssueCount: Bool {
        issueCount > 0
    }

    var leadingSystemImage: String {
        switch kind {
        case .fullAccessRequired, .notConfigured, .error:
            return "exclamationmark.triangle.fill"
        case .actions, .loading:
            return "keyboard"
        case .correctionPreview:
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
        case .correctionPreview(let count, _, _, _, _):
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
        case .correctionPreview(_, let explanation, let replacement, let original, _):
            if !explanation.isEmpty { return explanation }
            if !replacement.isEmpty, !original.isEmpty { return "\(original) → \(replacement)" }
            return "Tap to apply"
        case .error(let message):
            return message
        }
    }

    var compactCorrection: (label: String, value: String)? {
        guard case .correctionPreview(_, let explanation, let replacement, let original, _) = kind, !replacement.isEmpty else { return nil }
        let label = explanation.isEmpty ? "Correctness" : explanation.replacingOccurrences(of: ":", with: "")
        let value = original.isEmpty ? replacement : "\(original) → \(replacement)"
        return (label, value)
    }

    var compactPrediction: String? {
        guard case .correctionPreview(_, _, _, _, let prediction) = kind else { return nil }
        return prediction
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

        if aiStatus == "No issues found" || aiStatus == "No more suggestions" {
            return KeyboardToolbarState(kind: .actions(status: "No issues found"))
        }

        let idleStatus = aiStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        return KeyboardToolbarState(kind: .actions(status: idleStatus.isEmpty ? "Ready" : idleStatus))
    }
}
