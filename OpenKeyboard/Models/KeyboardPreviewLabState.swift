#if DEBUG
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
    case correctionOnly
    case predictionOnly
    case correctionDetail
    case actions
    case rewriteOptions
    case correctionComplete
}

struct KeyboardPreviewSuggestion: Equatable {
    let label: String
    let replacement: String
    let original: String
    let remainingCount: Int
    let prediction: String?

    var nextState: KeyboardPreviewLabState {
        remainingCount > 1 ? .correctionCardNext : .correctionComplete
    }
}

enum KeyboardPreviewLabState: String, CaseIterable, Identifiable {
    case ready
    case issue
    case correctionCard
    case correctionCardNext
    case correctionOnly
    case predictionOnly
    case correctionDetail
    case actions
    case rewriteOptions
    case correctionComplete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ready: return "Zero issues"
        case .issue: return "Issue count"
        case .correctionCard: return "First suggestion"
        case .correctionCardNext: return "Next suggestion"
        case .correctionOnly: return "Correction only"
        case .predictionOnly: return "Prediction only"
        case .correctionDetail: return "Correction detail"
        case .actions: return "Improve text"
        case .rewriteOptions: return "Rephrase result"
        case .correctionComplete: return "All clear"
        }
    }

    var previewPanel: KeyboardVisualPreviewPanel {
        switch self {
        case .ready: return .keyboard
        case .issue: return .issue
        case .correctionCard: return .correctionCard
        case .correctionCardNext: return .correctionCardNext
        case .correctionOnly: return .correctionOnly
        case .predictionOnly: return .predictionOnly
        case .correctionDetail: return .correctionDetail
        case .actions: return .actions
        case .rewriteOptions: return .rewriteOptions
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
                remainingCount: 3,
                prediction: "apple"
            )
        case .correctionCardNext:
            return KeyboardPreviewSuggestion(
                label: "Correct verb:",
                replacement: "have",
                original: "has",
                remainingCount: 2,
                prediction: "an"
            )
        case .correctionOnly:
            return KeyboardPreviewSuggestion(
                label: "Correct article:",
                replacement: "an",
                original: "a",
                remainingCount: 1,
                prediction: nil
            )
        case .predictionOnly:
            return KeyboardPreviewSuggestion(
                label: "Suggestion:",
                replacement: "apple",
                original: "",
                remainingCount: 0,
                prediction: "apple"
            )
        default:
            return nil
        }
    }

    func advancedAfterApplyingCompactSuggestion() -> KeyboardPreviewLabState {
        compactSuggestion?.nextState ?? self
    }
}
#endif
