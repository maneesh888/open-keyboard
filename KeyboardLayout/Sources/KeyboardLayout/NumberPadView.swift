import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct NumberPadStyle {
    public var key: Color
    public var control: Color
    public var foreground: Color
    public init(key: Color = .primary.opacity(0.08), control: Color = .gray.opacity(0.25), foreground: Color = .primary) {
        self.key = key
        self.control = control
        self.foreground = foreground
    }
}

public struct NumberPadView: View {
    public let configuration: NumberPadConfiguration
    public let style: NumberPadStyle
    /// Change on field/session changes to invalidate a held delete without resetting on every edit.
    public let interactionID: UUID
    public let onIntent: (NumberPadIntent) -> Void
    @Environment(\.scenePhase) private var scenePhase

    public init(configuration: NumberPadConfiguration, style: NumberPadStyle = .init(),
                interactionID: UUID, onIntent: @escaping (NumberPadIntent) -> Void) {
        self.configuration = configuration
        self.style = style
        self.interactionID = interactionID
        self.onIntent = onIntent
    }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = NumberPadGeometry(availableWidth: proxy.size.width)
            VStack(spacing: metrics.gap) {
                ForEach(0..<4) { row in
                    HStack(spacing: metrics.gap) {
                        ForEach(0..<3) { column in
                            cell(configuration.cells[row * 3 + column])
                                .frame(width: metrics.cellWidth, height: metrics.rowHeight)
                        }
                    }
                }
                HStack(spacing: metrics.gap) {
                    key("Back", label: "Back to typing", id: "number_pad_back", intent: .back)
                    if configuration.needsSystemKeyboardSwitch {
                        Button { onIntent(.advanceToNextInputMode) } label: {
                            Image(systemName: "globe").frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .accessibilityLabel("Next keyboard")
                        .accessibilityIdentifier("number_pad_next_keyboard")
                    }
                    Menu {
                        variant("Digits", .digits)
                        variant("Decimal", .decimal)
                        variant("Phone", .phone)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .accessibilityLabel("Number pad type")
                    .accessibilityValue(configuration.variant.rawValue.capitalized)
                    .accessibilityIdentifier("number_pad_type")
                    ForEach(configuration.phoneControls, id: \.self) { symbol in
                        key(symbol, label: symbol == "*" ? "Asterisk" : "Number sign",
                            id: "number_pad_\(symbol)", intent: .insertText(symbol))
                    }
                    if configuration.showsSubmit {
                        key(configuration.submitLabel, label: configuration.submitLabel,
                            id: "number_pad_submit", intent: .submit)
                            .disabled(!configuration.submitEnabled)
                    }
                }
                .frame(height: metrics.rowHeight)
                .background(style.control, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .font(.system(size: 16))
            .foregroundStyle(style.foreground)
            .frame(width: metrics.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .frame(height: NumberPadGeometry(availableWidth: 0).height)
        .accessibilityIdentifier("keyboard_number_pad")
    }

    private func variant(_ label: String, _ variant: NumberPadVariant) -> some View {
        Button(label) { onIntent(.selectVariant(variant)) }
    }

    @ViewBuilder private func cell(_ intent: NumberPadIntent?) -> some View {
        switch intent {
        case .insertText(let text):
            key(text, label: text, id: "number_pad_\(text)", intent: .insertText(text))
                .font(.system(size: 25))
                .background(style.key, in: RoundedRectangle(cornerRadius: 8))
        case .deleteBackward:
            #if canImport(UIKit)
            RepeatingNumberPadDeleteButton(foreground: style.foreground) { onIntent(.deleteBackward) }
                .id(DeleteIdentity(session: interactionID, variant: configuration.variant, sceneActive: scenePhase == .active))
                .background(style.control, in: RoundedRectangle(cornerRadius: 8))
            #else
            key("⌫", label: "Delete", id: "number_pad_delete", intent: .deleteBackward)
                .background(style.control, in: RoundedRectangle(cornerRadius: 8))
            #endif
        default:
            Color.clear.accessibilityHidden(true)
        }
    }

    private func key(_ title: String, label: String, id: String, intent: NumberPadIntent) -> some View {
        Button { onIntent(intent) } label: {
            Text(title).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

private struct DeleteIdentity: Hashable {
    let session: UUID
    let variant: NumberPadVariant
    let sceneActive: Bool
}

#if canImport(UIKit)
struct RepeatingNumberPadDeleteButton: UIViewRepresentable {
    let foreground: Color
    let action: () -> Void

    func makeUIView(context: Context) -> NumberPadDeleteButton {
        NumberPadDeleteButton(frame: .zero)
    }
    func updateUIView(_ button: NumberPadDeleteButton, context: Context) {
        button.action = action
        button.tintColor = UIColor(foreground)
    }
    static func dismantleUIView(_ button: NumberPadDeleteButton, coordinator: ()) { button.endDelete() }
}

final class NumberPadDeleteButton: UIButton {
    var action: () -> Void = {}
    private var repeatState = DeleteRepeatState()
    private var timer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    private func configure() {
        setImage(UIImage(systemName: "delete.left"), for: .normal)
        accessibilityLabel = "Delete"
        accessibilityIdentifier = "number_pad_delete"
        addTarget(self, action: #selector(beginDelete), for: .touchDown)
        addTarget(self, action: #selector(endDelete),
                  for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    @objc func beginDelete() {
        endDelete()
        repeatState.begin(at: ProcessInfo.processInfo.systemUptime)
        action()
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self, self.repeatState.shouldRepeat(at: ProcessInfo.processInfo.systemUptime) else { return }
            self.action()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    @objc func endDelete() {
        timer?.invalidate()
        timer = nil
        repeatState.cancel()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { endDelete() }
    }
    override func accessibilityActivate() -> Bool {
        endDelete()
        action()
        return true
    }
    deinit { timer?.invalidate() }
}
#endif
