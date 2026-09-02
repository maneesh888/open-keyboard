import CoreGraphics

struct KeyboardVisualKey: Equatable {
    let id: String
    let minX: CGFloat
    let width: CGFloat
}

struct KeyboardTouchKey: Equatable, Identifiable {
    let id: String
    let visualFrame: CGRect
    let touchFrame: CGRect

    var leadingTouchInset: CGFloat {
        visualFrame.minX - touchFrame.minX
    }

    var trailingTouchInset: CGFloat {
        touchFrame.maxX - visualFrame.maxX
    }
}

struct KeyboardTouchRow: Equatable {
    let availableWidth: CGFloat
    let keyHeight: CGFloat
    let keys: [KeyboardTouchKey]

    init(availableWidth: CGFloat, keyHeight: CGFloat, visualKeys: [KeyboardVisualKey]) {
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

    func keyID(at point: CGPoint) -> String? {
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

struct KeyboardKeyPositions {
    static let horizontalSpacing: CGFloat = 5.5

    let availableWidth: CGFloat
    let letterWidth: CGFloat
    let homeRowInset: CGFloat
    let modifierWidth: CGFloat
    let bottomLetterSideGap: CGFloat
    let bottomControlWidth: CGFloat
    let spaceWidth: CGFloat
    let returnWidth: CGFloat

    init(availableWidth: CGFloat) {
        let letterWidth = (availableWidth - (Self.horizontalSpacing * 9)) / 10
        let bottomControlWidth = letterWidth * (142 / 111)
        let returnWidth = letterWidth * (302 / 111)
        self.availableWidth = availableWidth
        self.letterWidth = letterWidth
        homeRowInset = (letterWidth + Self.horizontalSpacing) / 2
        modifierWidth = letterWidth * (149 / 111)
        bottomLetterSideGap = letterWidth * (43 / 111)
        self.bottomControlWidth = bottomControlWidth
        self.returnWidth = returnWidth
        spaceWidth = availableWidth
            - (bottomControlWidth * 2)
            - returnWidth
            - (Self.horizontalSpacing * 3)
    }

    func topRow(keyIDs: [String], keyHeight: CGFloat) -> KeyboardTouchRow {
        evenlySpacedRow(
            keyIDs: keyIDs,
            keyWidth: letterWidth,
            leadingInset: 0,
            keyHeight: keyHeight
        )
    }

    func homeRow(keyIDs: [String], keyHeight: CGFloat) -> KeyboardTouchRow {
        evenlySpacedRow(
            keyIDs: keyIDs,
            keyWidth: letterWidth,
            leadingInset: homeRowInset,
            keyHeight: keyHeight
        )
    }

    func bottomLetterRow(
        leadingKeyID: String,
        letterKeyIDs: [String],
        trailingKeyID: String,
        keyHeight: CGFloat
    ) -> KeyboardTouchRow {
        let keyIDs = [leadingKeyID] + letterKeyIDs + [trailingKeyID]
        let widths = [modifierWidth]
            + Array(repeating: letterWidth, count: letterKeyIDs.count)
            + [modifierWidth]
        let gaps = [bottomLetterSideGap]
            + Array(repeating: Self.horizontalSpacing, count: max(0, letterKeyIDs.count - 1))
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

    func controlRow(keyIDs: [String], keyHeight: CGFloat) -> KeyboardTouchRow {
        precondition(keyIDs.count == 4, "The control row requires four keys.")
        return row(
            keyIDs: keyIDs,
            widths: [bottomControlWidth, bottomControlWidth, spaceWidth, returnWidth],
            gaps: Array(repeating: Self.horizontalSpacing, count: 3),
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
            gaps: Array(repeating: Self.horizontalSpacing, count: max(0, keyIDs.count - 1)),
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

        var minX = leadingInset
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
