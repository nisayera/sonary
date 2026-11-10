import SwiftUI

/// Top of a settings page: icon tile, title, one line of explanation and an optional control (e.g. on/off).
public struct SettingsPageHeader<Accessory: View>: View {
    private let symbol: String
    private let title: Text
    private let subtitle: Text?
    private let accessory: Accessory

    public init(symbol: String, title: Text, subtitle: Text? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconBadge(symbol: symbol, size: 46)
                .shadow(color: Color.sonaryAccent.opacity(0.3), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.title2.weight(.semibold))
                if let subtitle {
                    subtitle.font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}

public extension SettingsPageHeader where Accessory == EmptyView {
    init(symbol: String, title: Text, subtitle: Text? = nil) {
        self.init(symbol: symbol, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The sizes every settings page shares.
public enum SettingsMetrics {
    public static let cardRadius: CGFloat = 12
    public static let rowHorizontalInset: CGFloat = 14
    public static let rowVerticalInset: CGFloat = 10
    /// How wide a picker, slider or text field on the right of a row is, so the controls of a
    /// page line up in one column.
    public static let controlWidth: CGFloat = 190
}

public extension View {
    /// A picker or field on the right of a settings row: no label of its own, the standard width.
    func settingsControl() -> some View {
        labelsHidden().frame(width: SettingsMetrics.controlWidth)
    }
}

/// One rounded group of related controls, with an optional heading. In the menu bar panel the
/// heading moves above the card in small capitals and the card gets the panel's tighter look.
public struct SettingsCard<Content: View>: View {
    private let title: Text?
    private let content: Content
    @Environment(\.sonarySurface) private var surface

    public init(_ title: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        switch surface {
        case .settings:
            // The heading stands above the card and the card is one list: every child is a
            // row with the same insets, and hairlines come between rows by themselves. No
            // page lays out its own card, which is what keeps them all alike.
            let shape = RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius, style: .continuous)
            VStack(alignment: .leading, spacing: 7) {
                if let title {
                    title
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Group(subviews: content) { subviews in
                        ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                            if index > 0 {
                                Divider()
                                    .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
                                    .accessibilityHidden(true)
                            }
                            subview
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, SettingsMetrics.rowHorizontalInset)
                                .padding(.vertical, SettingsMetrics.rowVerticalInset)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
            }
        case .panel:
            VStack(alignment: .leading, spacing: 6) {
                if let title {
                    PanelSectionTitle(title)
                        .padding(.horizontal, 2)
                }
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelCard()
            }
        }
    }
}

/// Icon tile, title, an optional line of explanation, and the control on the right.
public struct SettingsRow<Accessory: View>: View {
    private let symbol: String
    private let title: Text
    private let caption: Text?
    private let accessory: Accessory

    public init(symbol: String, title: Text, caption: Text? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.caption = caption
        self.accessory = accessory()
    }

    @Environment(\.sonarySurface) private var surface

    public var body: some View {
        switch surface {
        case .settings:
            HStack(spacing: 12) {
                IconBadge(symbol: symbol, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    title
                    if let caption {
                        caption.font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                accessory
            }
            .accessibilityElement(children: .combine)
        case .panel:
            HStack(spacing: PanelMetrics.rowIconSpacing) {
                IconBadge(symbol: symbol, size: PanelMetrics.rowIconWidth)
                VStack(alignment: .leading, spacing: 1) {
                    title
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                    if let caption {
                        caption.font(.system(size: 10)).foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                accessory
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// A settings row whose control is an on/off switch.
public struct SettingsToggleRow: View {
    private let symbol: String
    private let title: Text
    private let caption: Text?
    @Binding private var isOn: Bool

    public init(symbol: String, title: Text, caption: Text? = nil, isOn: Binding<Bool>) {
        self.symbol = symbol
        self.title = title
        self.caption = caption
        self._isOn = isOn
    }

    public var body: some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            Toggle(isOn: $isOn) { title }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// A scrollable settings page: header on top, cards below.
public struct SettingsPage<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content

    public init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header.padding(.bottom, Spacing.xs)
                content
            }
            .padding(Spacing.l)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

/// A line inside a settings card for something that cannot work right now, such as a missing
/// permission.
public struct SettingsWarning: View {
    private let text: Text

    public init(_ text: Text) {
        self.text = text
    }

    public var body: some View {
        Label {
            text.font(.callout).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
