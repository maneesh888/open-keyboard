import Foundation

public enum NumberPadVariant: String, CaseIterable, Sendable {
    case digits, decimal
}

public enum NumberPadIntent: Equatable, Sendable {
    case insertText(String)
    case deleteBackward
}

public struct NumberPadConfiguration: Equatable, Sendable {
    public var variant: NumberPadVariant
    public var decimalSeparator: String

    public init(
        variant: NumberPadVariant = .decimal,
        decimalSeparator: String
    ) {
        self.variant = variant
        self.decimalSeparator = decimalSeparator
    }

    /// Exactly twelve stable positions. Nil is a noninteractive blank cell.
    public var cells: [NumberPadIntent?] {
        let auxiliary: NumberPadIntent?
        switch variant {
        case .digits: auxiliary = nil
        case .decimal: auxiliary = decimalSeparator.isEmpty ? nil : .insertText(decimalSeparator)
        }
        return (1...9).map { .insertText(String($0)) } + [auxiliary, .insertText("0"), .deleteBackward]
    }
}

/// Bounded geometry independent of device names. Four rows match the native number-pad arrangement.
public struct NumberPadGeometry: Equatable {
    public let contentWidth: CGFloat
    public let cellWidth: CGFloat
    public let rowHeight: CGFloat
    public let gap: CGFloat
    public let height: CGFloat

    public init(availableWidth: CGFloat, gap: CGFloat = 6, rowHeight: CGFloat = 54) {
        self.gap = max(0, gap)
        contentWidth = min(max(0, availableWidth), 480)
        cellWidth = max(0, (contentWidth - self.gap * 2) / 3)
        self.rowHeight = max(44, rowHeight)
        height = self.rowHeight * 4 + self.gap * 3
    }
}

/// One immediate delete, then bounded cadence without catching up missed ticks in a burst.
public struct DeleteRepeatState {
    public let delay: TimeInterval
    public let interval: TimeInterval
    private var nextDeadline: TimeInterval?

    public init(delay: TimeInterval = 0.4, interval: TimeInterval = 0.08) {
        self.delay = max(0.1, delay)
        self.interval = max(0.03, interval)
    }

    public mutating func begin(at time: TimeInterval) { nextDeadline = time + delay }
    public mutating func cancel() { nextDeadline = nil }
    public mutating func shouldRepeat(at time: TimeInterval) -> Bool {
        guard let deadline = nextDeadline, time >= deadline else { return false }
        nextDeadline = time + interval
        return true
    }
}
