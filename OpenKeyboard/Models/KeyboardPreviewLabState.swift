//
//  KeyboardPreviewLabState.swift
//  OpenKeyboard
//
//  Deterministic preview states for app lab and screenshot harness.
//

import Foundation

enum KeyboardVisualPreviewPanel: String {
    case keyboard
    case issue
    case correctionCard
    case correctionCardNext
    case correctionDetail
    case actions
    case correctionComplete
}

struct KeyboardPreviewSuggestion: Equatable {
    let label: String
    let replacement: String
    let original: String
    let remainingCount: Int

    var nextState: KeyboardPreviewLabState {
        remainingCount > 1 ? .correctionCardNext : .correctionComplete
    }
}

enum KeyboardPreviewLabState: String, CaseIterable, Identifiable {
    case ready
    case issue
    case correctionCard
    case correctionCardNext
    case correctionDetail
    case actions
    case correctionComplete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ready: return "Zero issues"
        case .issue: return "Issue count"
        case .correctionCard: return "First suggestion"
        case .correctionCardNext: return "Next suggestion"
        case .correctionDetail: return "Correction detail"
        case .actions: return "AI actions"
        case .correctionComplete: return "All clear"
        }
    }

    var previewPanel: KeyboardVisualPreviewPanel {
        switch self {
        case .ready: return .keyboard
        case .issue: return .issue
        case .correctionCard: return .correctionCard
        case .correctionCardNext: return .correctionCardNext
        case .correctionDetail: return .correctionDetail
        case .actions: return .actions
        case .correctionComplete: return .correctionComplete
        }
    }

    var compactSuggestion: KeyboardPreviewSuggestion? {
        switch self {
        case .correctionCard:
            return KeyboardPreviewSuggestion(
                label: "Correct capitalization:",
                replacement: "I",
                original: "i",
                remainingCount: 3
            )
        case .correctionCardNext:
            return KeyboardPreviewSuggestion(
                label: "Correct verb:",
                replacement: "have",
                original: "has",
                remainingCount: 2
            )
        default:
            return nil
        }
    }

    func advancedAfterApplyingCompactSuggestion() -> KeyboardPreviewLabState {
        compactSuggestion?.nextState ?? self
    }
}
