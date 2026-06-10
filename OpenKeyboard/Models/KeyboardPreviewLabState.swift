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
    case correctionDetail
    case actions
    case correctionComplete
}

enum KeyboardPreviewLabState: String, CaseIterable, Identifiable {
    case ready
    case issue
    case correctionCard
    case correctionDetail
    case actions
    case correctionComplete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ready: return "Zero issues"
        case .issue: return "Issue count"
        case .correctionCard: return "Correction card"
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
        case .correctionDetail: return .correctionDetail
        case .actions: return .actions
        case .correctionComplete: return .correctionComplete
        }
    }
}
