//
//  KeyboardPreviewLabState.swift
//  OpenKeyboard
//
//  Deterministic preview states for hidden debug-reference-only previews. Acceptance screenshots must come from named XCUITests, not direct preview routes.
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
        case .correctionOnly: return .correctionOnly
        case .predictionOnly: return .predictionOnly
        case .correctionDetail: return .correctionDetail
        case .actions: return .actions
        case .correctionComplete: return .correctionComplete
        }
    }

    var compactSuggestion: KeyboardPreviewSuggestion? {
        switch self {
        case .correctionCard:
            return KeyboardPreviewSuggestion(
                label: "Subject-verb agreement:",
                replacement: "have",
                original: "has",
                remainingCount: 1,
                prediction: nil
            )
        case .correctionCardNext:
            return KeyboardPreviewSuggestion(
                label: "Correctness:",
                replacement: "There have been no apples",
                original: "There has been no apples",
                remainingCount: 1,
                prediction: nil
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
