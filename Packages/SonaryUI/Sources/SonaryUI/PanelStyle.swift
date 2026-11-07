import Foundation
import SwiftUI

/// Where a shared component is shown. The menu bar panel is narrow and read at a glance, so the
/// same card or row is drawn smaller and calmer there than in the settings window.
public enum SonarySurface: Sendable {
    case settings
    case panel
}

private struct SonarySurfaceKey: EnvironmentKey {
    static let defaultValue = SonarySurface.settings
}

public extension EnvironmentValues {
    var sonarySurface: SonarySurface {
        get { self[SonarySurfaceKey.self] }
        set { self[SonarySurfaceKey.self] = newValue }
    }
}

/// Sizes of the menu bar panel.
public enum PanelMetrics {
    public static let width: CGFloat = 332
    public static let padding: CGFloat = 12
    public static let contentWidth: CGFloat = width - 2 * padding
    /// Space between the blocks of the panel: header, tabs, sections, footer.
    public static let spacing: CGFloat = 12
    public static let cardRadius: CGFloat = 10
    public static let cardPadding: CGFloat = 10
    public static let rowIconWidth: CGFloat = 22
    public static let rowIconSpacing: CGFloat = 9
    public static let rowHorizontalInset: CGFloat = 10
    public static let rowVerticalInset: CGFloat = 8
    /// Hairlines between rows start under the titles, not under the icons.
    public static let separatorInset: CGFloat = rowHorizontalInset + rowIconWidth + rowIconSpacing
    /// The tallest the scrolling part of the panel gets before it scrolls.
    public static let maxContentHeight: CGFloat = 480
}

/// The layers of the panel: cards a shade lighter than the surface they sit on, split by
/// hairlines rather than shadows. Increased contrast gets outlines that can actually be seen.
public enum PanelColors {
    public static func base(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.68) : Color.black.opacity(0.42)
    }

    public static func card(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.38) : Color.white.opacity(0.075)
    }

    public static func control(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.055) : Color.white.opacity(0.085)
    }

    public static func border(_ scheme: ColorScheme, increasedContrast: Bool = false) -> Color {
        scheme == .light
            ? Color.black.opacity(increasedContrast ? 0.24 : 0.09)
            : Color.white.opacity(increasedContrast ? 0.28 : 0.11)
    }
}

private struct PanelCardModifier: ViewModifier {
    let padded: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous)
        content
            .padding(padded ? PanelMetrics.cardPadding : 0)
            .background(shape.fill(PanelColors.card(colorScheme)))
            .overlay(shape.strokeBorder(PanelColors.border(colorScheme, increasedContrast: contrast == .increased),
                                        lineWidth: 0.7))
    }
}

public extension View {
    /// The rounded card every block of the panel sits in. A card that holds a list of rows is
    /// not padded: each row brings its own insets, so separators reach the card's edges.
    func panelCard(padded: Bool = true) -> some View {
        modifier(PanelCardModifier(padded: padded))
    }
}

/// The small capitals above a block of the panel ("SYSTEM", "WINDOWS"), with room on the right
/// for a count or a button.
public struct PanelSectionTitle<Accessory: View>: View {
    private let title: Text
    private let accessory: Accessory

    public init(_ title: Text, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: 6) {
            title
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            accessory
        }
        .frame(maxWidth: .infinity)
    }
}

public extension PanelSectionTitle where Accessory == EmptyView {
    init(_ title: Text) {
        self.init(title) { EmptyView() }
    }
}

/// One card for a list of rows, split by hairlines: a long list reads as one block instead of a
/// stack of boxes, and every row stays its own target. Rows bring their insets with
/// `panelRowInsets()`; `PanelRow` already has them.
public struct PanelGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                    if index > 0 {
                        Divider()
                            .padding(.leading, PanelMetrics.separatorInset)
                            .padding(.trailing, PanelMetrics.rowHorizontalInset)
                            .accessibilityHidden(true)
                    }
                    subview
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard(padded: false)
    }
}

public extension View {
    /// The padding of a row inside a `PanelGroup`.
    func panelRowInsets() -> some View {
        padding(.horizontal, PanelMetrics.rowHorizontalInset)
            .padding(.vertical, PanelMetrics.rowVerticalInset)
    }
}

/// A row of the panel: an icon badge, a title, an optional second line, and a control on the
/// right. The badge is filled with the accent colour while the thing it stands for is on.
public struct PanelRow<Accessory: View>: View {
    private let symbol: String
    private let title: Text
    private let caption: Text?
    private let isActive: Bool
    private let needsAttention: Bool
    private let accessory: Accessory

    public init(symbol: String, title: Text, caption: Text? = nil, isActive: Bool = true,
                needsAttention: Bool = false, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.caption = caption
        self.isActive = isActive
        self.needsAttention = needsAttention
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: PanelMetrics.rowIconSpacing) {
            IconBadge(symbol: symbol, isActive: isActive || needsAttention,
                      tint: needsAttention ? .orange : .sonaryAccent, size: PanelMetrics.rowIconWidth)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    caption
                        .font(.system(size: 10))
                        .foregroundStyle(needsAttention ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            accessory
        }
        .panelRowInsets()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

public extension PanelRow where Accessory == EmptyView {
    init(symbol: String, title: Text, caption: Text? = nil, isActive: Bool = true, needsAttention: Bool = false) {
        self.init(symbol: symbol, title: title, caption: caption, isActive: isActive,
                  needsAttention: needsAttention) { EmptyView() }
    }
}

/// A wide, quiet button for the bottom of the panel, such as Settings and Quit.
public struct PanelFooterButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(shape.fill(configuration.isPressed ? PanelColors.control(colorScheme) : PanelColors.card(colorScheme)))
            .overlay(shape.strokeBorder(PanelColors.border(colorScheme), lineWidth: 0.8))
            .contentShape(shape)
    }
}

/// Sonary's mark, the sweep from the menu bar icon, drawn as shapes so it stays sharp at any size
/// and takes any colour.
public struct SonaryMark: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let scale = side / 18
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
            }
            let center = point(9, 9)

            let ring = Path(ellipseIn: CGRect(x: center.x - 7.6 * scale, y: center.y - 7.6 * scale,
                                              width: 15.2 * scale, height: 15.2 * scale))
            context.opacity = 0.5
            context.stroke(ring, with: .foreground, style: StrokeStyle(lineWidth: 1.2 * scale))
            context.opacity = 1

            // The sweep: the slice from just past twelve to about two o'clock, as in the menu bar icon.
            var sweep = Path()
            sweep.move(to: center)
            let start = -75.04 * Double.pi / 180
            let end = -19.98 * Double.pi / 180
            let steps = 16
            for step in 0...steps {
                let angle = start + (end - start) * Double(step) / Double(steps)
                sweep.addLine(to: point(9 + 6 * cos(angle), 9 + 6 * sin(angle)))
            }
            sweep.closeSubpath()
            context.fill(sweep, with: .foreground)

            let dot = Path(ellipseIn: CGRect(x: center.x - 1.6 * scale, y: center.y - 1.6 * scale,
                                             width: 3.2 * scale, height: 3.2 * scale))
            context.fill(dot, with: .foreground)
        }
        .accessibilityHidden(true)
    }
}
