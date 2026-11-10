import SwiftUI

// The rows every tab of the menu panel is built from. A tab is a list of `PanelDisclosure`
// sections; a section holds one `PanelGroup` of these rows and, where something needs saying,
// a `PanelNote` under it. Nothing in a tab lays out its own card, so every tab reads the same.

/// A switch as a row of the panel.
public struct PanelToggleRow: View {
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
        PanelRow(symbol: symbol, title: title, caption: caption, isActive: isOn) {
            Toggle(isOn: $isOn) { title }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// A slider as a row of the panel: the badge, an optional name with a short remark beside it,
/// the slider, and its value as text.
public struct PanelSliderRow: View {
    private let symbol: String
    private let title: Text?
    private let remark: Text?
    @Binding private var value: Double
    private let valueText: String?

    public init(symbol: String, title: Text? = nil, remark: Text? = nil, value: Binding<Double>,
                valueText: String? = nil) {
        self.symbol = symbol
        self.title = title
        self.remark = remark
        self._value = value
        self.valueText = valueText
    }

    public var body: some View {
        HStack(spacing: PanelMetrics.rowIconSpacing) {
            IconBadge(symbol: symbol, size: PanelMetrics.rowIconWidth)
            VStack(alignment: .leading, spacing: 2) {
                if title != nil || remark != nil {
                    HStack(spacing: 6) {
                        if let title {
                            title
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if let remark {
                            remark
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Slider(value: $value, in: 0...1)
                    .controlSize(.small)
            }
            if let valueText {
                Text(verbatim: valueText)
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .panelRowInsets()
    }
}

/// A row of the panel that is one button: the whole row takes the click.
public struct PanelButtonRow<Accessory: View>: View {
    private let symbol: String
    private let title: Text
    private let caption: Text?
    private let action: () -> Void
    private let accessory: Accessory

    public init(symbol: String, title: Text, caption: Text? = nil, action: @escaping () -> Void,
                @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.caption = caption
        self.action = action
        self.accessory = accessory()
    }

    public var body: some View {
        Button(action: action) {
            PanelRow(symbol: symbol, title: title, caption: caption) { accessory }
        }
        .buttonStyle(.plain)
    }
}

public extension PanelButtonRow where Accessory == EmptyView {
    init(symbol: String, title: Text, caption: Text? = nil, action: @escaping () -> Void) {
        self.init(symbol: symbol, title: title, caption: caption, action: action) { EmptyView() }
    }
}

/// A line of explanation under a block of the panel.
public struct PanelNote: View {
    private let text: Text

    public init(_ text: Text) {
        self.text = text
    }

    public var body: some View {
        text
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }
}

/// The value on the right of a panel row, such as a shortcut or a count.
public struct PanelValue: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }
}
