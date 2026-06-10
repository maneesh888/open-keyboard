//
//  KeyboardDebugStatePolicy.swift
//  OpenKeyboardExtension
//
//  Production gate for keyboard debug-state persistence.
//

import Foundation

enum KeyboardDebugStatePolicy {
    static var isPersistenceAvailable: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }
}
