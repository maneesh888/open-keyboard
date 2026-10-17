import SwiftUI

/// Device-independent sizing. Values describe content inside the host's safe area.
public struct KeyboardMetrics: Equatable {
    public let letterKeyHeight: CGFloat
    public var controlKeyHeight: CGFloat { letterKeyHeight }
    public let keyCapHeight: CGFloat
    public let horizontalSpacing: CGFloat
    public let keyRowSpacing: CGFloat
    public let keyShadowAllowance: CGFloat
    public var keyGridHeight: CGFloat { letterKeyHeight * 4 + keyRowSpacing * 3 + keyShadowAllowance }
    public init(rowHeight: CGFloat = 54, keyCapHeight: CGFloat = 43,
                rowSpacing: CGFloat = 0, shadowAllowance: CGFloat = 0, horizontalSpacing: CGFloat = 5.5) {
        letterKeyHeight = rowHeight.isFinite ? max(44, rowHeight) : 54
        self.keyCapHeight = keyCapHeight.isFinite ? min(letterKeyHeight, max(1, keyCapHeight)) : 43
        self.horizontalSpacing = horizontalSpacing.isFinite ? max(0, horizontalSpacing) : 5.5
        keyRowSpacing = rowSpacing.isFinite ? max(0, rowSpacing) : 0
        keyShadowAllowance = shadowAllowance.isFinite ? max(0, shadowAllowance) : 0
    }
}

public struct KeyboardStyle {
    public var key: Color
    public var control: Color
    public var foreground: Color
    public var accent: Color
    public var shadow: Color
    public var background: Color
    public var border: Color
    public var borderWidth: CGFloat
    public var cornerRadius: CGFloat
    public var letterFont: Font
    public var controlFont: Font
    public init(key: Color = .primary.opacity(0.08), control: Color = .gray.opacity(0.25),
                foreground: Color = .primary, accent: Color = .accentColor.opacity(0.32),
                shadow: Color = .black.opacity(0.25), background: Color = .clear,
                border: Color = .clear, borderWidth: CGFloat = 0, cornerRadius: CGFloat = 8,
                letterFont: Font = .system(size: 25), controlFont: Font = .system(size: 16)) {
        self.key = key; self.control = control; self.foreground = foreground
        self.accent = accent; self.shadow = shadow; self.background = background
        self.border = border; self.borderWidth = max(0, borderWidth); self.cornerRadius = max(0, cornerRadius)
        self.letterFont = letterFont; self.controlFont = controlFont
    }
}

/// Explicit slot extents avoid asynchronous measurement/extension-height feedback loops.
/// Zero-height slots are absent, including their spacing. Replacement uses the content extent.
public struct KeyboardSurfaceLayout: Equatable {
    public let contentHeight: CGFloat
    public let accessoryHeight: CGFloat
    public let toolbarHeight: CGFloat
    public let spacing: CGFloat
    public let horizontalPadding: CGFloat
    public let topPadding: CGFloat
    public let bottomPadding: CGFloat
    public var preferredHeight: CGFloat {
        contentHeight + accessoryHeight + toolbarHeight + topPadding + bottomPadding
            + (accessoryHeight > 0 ? spacing : 0) + (toolbarHeight > 0 ? spacing : 0)
    }
    public init(contentHeight: CGFloat = KeyboardMetrics().keyGridHeight,
                accessoryHeight: CGFloat = 0, toolbarHeight: CGFloat = 0, spacing: CGFloat = 0,
                horizontalPadding: CGFloat = 0, topPadding: CGFloat = 0, bottomPadding: CGFloat = 0) {
        func bounded(_ value: CGFloat) -> CGFloat { value.isFinite ? max(0, value) : 0 }
        self.contentHeight = bounded(contentHeight); self.accessoryHeight = bounded(accessoryHeight)
        self.toolbarHeight = bounded(toolbarHeight); self.spacing = bounded(spacing)
        self.horizontalPadding = bounded(horizontalPadding); self.topPadding = bounded(topPadding)
        self.bottomPadding = bounded(bottomPadding)
    }
}

/// A consumer-supplied container with accessory, toolbar, and replacement slots.
/// It does not read screen bounds, change system windows, or own the host's document.
public struct KeyboardSurface<Content: View, Accessory: View, Toolbar: View, Replacement: View>: View {
    public let layout: KeyboardSurfaceLayout
    public let style: KeyboardStyle
    public let showsReplacement: Bool
    private let content: Content
    private let accessory: Accessory
    private let toolbar: Toolbar
    private let replacement: Replacement
    public init(layout: KeyboardSurfaceLayout = .init(), style: KeyboardStyle = .init(),
                showsReplacement: Bool = false,
                @ViewBuilder content: () -> Content,
                @ViewBuilder accessory: () -> Accessory = { EmptyView() },
                @ViewBuilder toolbar: () -> Toolbar = { EmptyView() },
                @ViewBuilder replacement: () -> Replacement = { EmptyView() }) {
        self.layout = layout; self.style = style; self.showsReplacement = showsReplacement
        self.content = content(); self.accessory = accessory(); self.toolbar = toolbar()
        self.replacement = replacement()
    }
    public var body: some View {
        VStack(spacing: 0) {
            if layout.accessoryHeight > 0 {
                accessory.frame(height: layout.accessoryHeight).clipped()
                Spacer().frame(height: layout.spacing)
            }
            if layout.toolbarHeight > 0 {
                toolbar.frame(height: layout.toolbarHeight).clipped()
                Spacer().frame(height: layout.spacing)
            }
            Group {
                if showsReplacement { replacement }
                else { content }
            }
            .frame(maxWidth: .infinity)
            .frame(height: layout.contentHeight, alignment: .top)
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, layout.topPadding)
        .padding(.bottom, layout.bottomPadding)
        .frame(maxWidth: .infinity)
        .frame(height: layout.preferredHeight, alignment: .top)
        .background(style.background)
        .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .strokeBorder(style.border, lineWidth: style.borderWidth)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
