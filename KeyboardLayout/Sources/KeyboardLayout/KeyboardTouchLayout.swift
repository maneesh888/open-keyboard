import CoreGraphics

public struct KeyboardVisualKey: Equatable {
    public let id: String
    public let minX: CGFloat
    public let width: CGFloat
    public init(id: String, minX: CGFloat, width: CGFloat) {
        self.id = id; self.minX = minX; self.width = width
    }
}

public struct KeyboardTouchKey: Equatable, Identifiable {
    public let id: String
    public let visualFrame: CGRect
    public let touchFrame: CGRect

    public var leadingTouchInset: CGFloat {
        visualFrame.minX - touchFrame.minX
    }

    public var trailingTouchInset: CGFloat {
        touchFrame.maxX - visualFrame.maxX
    }
}

public struct KeyboardTouchRow: Equatable {
    public let availableWidth: CGFloat
    public let keyHeight: CGFloat
    public let keys: [KeyboardTouchKey]

    public init(availableWidth: CGFloat, keyHeight: CGFloat, visualKeys: [KeyboardVisualKey]) {
        self.availableWidth = availableWidth
        self.keyHeight = keyHeight

        let orderedKeys = visualKeys.sorted { lhs, rhs in
            if lhs.minX == rhs.minX {
                return lhs.id < rhs.id
            }
            return lhs.minX < rhs.minX
        }

        keys = orderedKeys.enumerated().map { index, key in
            let visualFrame = CGRect(x: key.minX, y: 0, width: key.width, height: keyHeight)
            let touchMinX: CGFloat
            if index == orderedKeys.startIndex {
                touchMinX = 0
            } else {
                let previousKey = orderedKeys[index - 1]
                touchMinX = (previousKey.minX + previousKey.width + key.minX) / 2
            }

            let touchMaxX: CGFloat
            if index == orderedKeys.index(before: orderedKeys.endIndex) {
                touchMaxX = availableWidth
            } else {
                let nextKey = orderedKeys[index + 1]
                touchMaxX = (key.minX + key.width + nextKey.minX) / 2
            }

            return KeyboardTouchKey(
                id: key.id,
                visualFrame: visualFrame,
                touchFrame: CGRect(
                    x: touchMinX,
                    y: 0,
                    width: max(0, touchMaxX - touchMinX),
                    height: keyHeight
                )
            )
        }
    }

    public func keyID(at point: CGPoint) -> String? {
        guard !keys.isEmpty,
              point.x >= 0,
              point.x <= availableWidth,
              point.y >= 0,
              point.y <= keyHeight else {
            return nil
        }

        return keys.first(where: { point.x < $0.touchFrame.maxX })?.id ?? keys.last?.id
    }
}

public struct KeyboardKeyPositions {
    public static let horizontalSpacing: CGFloat = 5.5

    public let spacing: CGFloat
    public let availableWidth: CGFloat
    public let letterWidth: CGFloat
    public let homeRowInset: CGFloat
    public let modifierWidth: CGFloat
    public let bottomLetterSideGap: CGFloat
    public let bottomControlWidth: CGFloat
    public let spaceWidth: CGFloat
    public let returnWidth: CGFloat
    public let symbolBottomKeyWidth: CGFloat

    public init(availableWidth: CGFloat, spacing: CGFloat = KeyboardKeyPositions.horizontalSpacing) {
        let spacing = spacing.isFinite ? max(0, spacing) : Self.horizontalSpacing
        self.spacing = spacing
        let availableWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
        let letterWidth = max(0, (availableWidth - (spacing * 9)) / 10)
        let bottomControlWidth = letterWidth * (142 / 111)
        let returnWidth = letterWidth * (302 / 111)
        self.availableWidth = availableWidth
        self.letterWidth = letterWidth
        homeRowInset = (letterWidth + spacing) / 2
        modifierWidth = letterWidth * (149 / 111)
        bottomLetterSideGap = letterWidth * (43 / 111)
        self.bottomControlWidth = bottomControlWidth
        self.returnWidth = returnWidth
        symbolBottomKeyWidth = (
            availableWidth
                - (modifierWidth * 2)
                - (bottomLetterSideGap * 2)
                - (spacing * 4)
        ) / 5
        spaceWidth = availableWidth
            - (bottomControlWidth * 2)
            - returnWidth
            - (spacing * 3)
    }

    public func topRow(keyIDs: [String], keyHeight: CGFloat) -> KeyboardTouchRow {
        evenlySpacedRow(
            keyIDs: keyIDs,
            keyWidth: letterWidth,
            leadingInset: 0,
            keyHeight: keyHeight
        )
    }

    public func homeRow(keyIDs: [String], keyHeight: CGFloat) -> KeyboardTouchRow {
        middleRow(keyIDs: keyIDs, usesInset: true, keyHeight: keyHeight)
    }

    public func middleRow(
        keyIDs: [String],
        usesInset: Bool,
        keyHeight: CGFloat
    ) -> KeyboardTouchRow {
        evenlySpacedRow(
            keyIDs: keyIDs,
            keyWidth: letterWidth,
            leadingInset: usesInset ? homeRowInset : 0,
            keyHeight: keyHeight
        )
    }

    public func bottomLetterRow(
        leadingKeyID: String,
        letterKeyIDs: [String],
        trailingKeyID: String,
        keyWidth: CGFloat? = nil,
        keyHeight: CGFloat
    ) -> KeyboardTouchRow {
        let resolvedKeyWidth = keyWidth ?? letterWidth
        let keyIDs = [leadingKeyID] + letterKeyIDs + [trailingKeyID]
        let widths = [modifierWidth]
            + Array(repeating: resolvedKeyWidth, count: letterKeyIDs.count)
            + [modifierWidth]
        let gaps = [bottomLetterSideGap]
            + Array(repeating: spacing, count: max(0, letterKeyIDs.count - 1))
            + [bottomLetterSideGap]
        let contentWidth = widths.reduce(0, +) + gaps.reduce(0, +)

        return row(
            keyIDs: keyIDs,
            widths: widths,
            gaps: gaps,
            leadingInset: max(0, (availableWidth - contentWidth) / 2),
            keyHeight: keyHeight
        )
    }

    public func controlRow(keyIDs: [String], keyHeight: CGFloat) -> KeyboardTouchRow {
        precondition(keyIDs.count == 4 || keyIDs.count == 5, "The control row requires four or five keys.")
        if keyIDs.count == 5 {
            // Keep mode/switch targets usable at compact widths and bounded on iPad.
            let modifier = min(56, max(44, availableWidth * 0.13))
            let returnKey = min(88, max(54, availableWidth * 0.2))
            let space = max(0, availableWidth - modifier * 3 - returnKey - spacing * 4)
            return row(keyIDs: keyIDs, widths: [modifier, modifier, modifier, space, returnKey],
                       gaps: Array(repeating: spacing, count: 4),
                       leadingInset: 0, keyHeight: keyHeight)
        }
        return row(
            keyIDs: keyIDs,
            widths: [bottomControlWidth, bottomControlWidth, spaceWidth, returnWidth],
            gaps: Array(repeating: spacing, count: 3),
            leadingInset: 0,
            keyHeight: keyHeight
        )
    }

    private func evenlySpacedRow(
        keyIDs: [String],
        keyWidth: CGFloat,
        leadingInset: CGFloat,
        keyHeight: CGFloat
    ) -> KeyboardTouchRow {
        row(
            keyIDs: keyIDs,
            widths: Array(repeating: keyWidth, count: keyIDs.count),
            gaps: Array(repeating: spacing, count: max(0, keyIDs.count - 1)),
            leadingInset: leadingInset,
            keyHeight: keyHeight
        )
    }

    private func row(
        keyIDs: [String],
        widths: [CGFloat],
        gaps: [CGFloat],
        leadingInset: CGFloat,
        keyHeight: CGFloat
    ) -> KeyboardTouchRow {
        precondition(keyIDs.count == widths.count, "Every key requires a visual width.")
        precondition(gaps.count == max(0, keyIDs.count - 1), "Every adjacent key pair requires a gap.")

        let boundedWidths = widths.map { max(0, $0) }
        let boundedGaps = gaps.map { max(0, $0) }
        let contentWidth = boundedWidths.reduce(0, +) + boundedGaps.reduce(0, +)
        let scale = contentWidth > availableWidth && contentWidth > 0 ? availableWidth / contentWidth : 1
        let widths = boundedWidths.map { $0 * scale }
        let gaps = boundedGaps.map { $0 * scale }
        var minX = scale < 1 ? 0 : leadingInset
        let visualKeys = keyIDs.indices.map { index in
            let key = KeyboardVisualKey(id: keyIDs[index], minX: minX, width: widths[index])
            minX += widths[index]
            if index < gaps.count {
                minX += gaps[index]
            }
            return key
        }

        return KeyboardTouchRow(
            availableWidth: availableWidth,
            keyHeight: keyHeight,
            visualKeys: visualKeys
        )
    }
}
