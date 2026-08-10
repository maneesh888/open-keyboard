#if DEBUG
//
//  KeyboardPreviewLabState.swift
//  OpenKeyboard
//
//  Deterministic preview states for app lab and screenshot harness.
//

import CoreGraphics
import Foundation

enum KeyboardVisualPreviewLayout {
    static let toolbarHeight: CGFloat = 38
    static let toolbarControlSize: CGFloat = 34
    static let toolbarSpacing: CGFloat = 10
    static let outerHorizontalPadding: CGFloat = 6
    static let outerTopPadding: CGFloat = 2
    static let outerBottomPadding: CGFloat = 1
    static let letterKeyHeight: CGFloat = 54
    static let controlKeyHeight: CGFloat = 54
    static let keyCapHeight: CGFloat = 43
    static let keyRowSpacing: CGFloat = 0
    static let keyShadowAllowance: CGFloat = 0
    static let keyGridHeight: CGFloat = (letterKeyHeight * 3) + controlKeyHeight + (keyRowSpacing * 3) + keyShadowAllowance
    static let expandedPanelHeight: CGFloat = outerTopPadding + toolbarHeight + toolbarSpacing + keyGridHeight + outerBottomPadding
    static let actionPanelHeight: CGFloat = 351
    static let actionPanelScrollableResultHeight: CGFloat = 160
    static let actionCarouselButtonHeight: CGFloat = 44
    static let actionContextSelectorHeight: CGFloat = 44
    static let actionContextSelectorSpacing: CGFloat = 8
    static let actionPanelContextualResultHeight: CGFloat = 108
    static let actionControlButtonHeight: CGFloat = 44
    static let actionGroupedButtonWidth: CGFloat = 48
    static let correctionDetailMinHeight: CGFloat = 232
    static let correctionCompleteMinHeight: CGFloat = 226
}

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
