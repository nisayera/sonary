import SwiftUI

/// A section of the menu panel that opens in place: a row with an icon, a title, a short summary
/// on the right and a chevron. The panel does not scroll, so anything long folds away behind one
/// of these instead of running past the bottom of the screen.
public struct PanelDisclosure<Summary: View, Content: View>: View {
    private let symbol: String
    private let title: Text
    @Binding private var isExpanded: Bool
    private let summary: Summary
    private let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(symbol: String, title: Text, isExpanded: Binding<Bool>,
                @ViewBuilder summary: () -> Summary, @ViewBuilder content: () -> Content) {
        self.symbol = symbol
        self.title = title
        self._isExpanded = isExpanded
        self.summary = summary()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(sonaryAnimation(reduceMotion)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: PanelMetrics.rowIconSpacing) {
                    IconBadge(symbol: symbol, size: PanelMetrics.rowIconWidth)
                    title
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    summary
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .panelRowInsets()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .panelCard(padded: false)
            .accessibilityAddTraits(isExpanded ? [.isButton, .isSelected] : .isButton)
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
    }
}

public extension PanelDisclosure where Summary == EmptyView {
    init(symbol: String, title: Text, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.init(symbol: symbol, title: title, isExpanded: isExpanded, summary: { EmptyView() }, content: content)
    }
}

public extension Binding where Value == String {
    /// For a set of `PanelDisclosure`s that behave as one accordion: true while `id` is the open
    /// section, and opening one closes the one that was open, so the panel never grows past one
    /// section's worth of content.
    func opens(_ id: String) -> Binding<Bool> {
        let source = self
        return Binding<Bool>(get: { source.wrappedValue == id },
                             set: { source.wrappedValue = $0 ? id : "" })
    }
}

/// How many rows of a long list the panel shows before "Show all" (`PanelMoreButton`).
public enum PanelListLimit {
    public static let rows = 6

    /// The first rows of a list, or all of them.
    public static func visible<Element>(_ items: [Element], showsAll: Bool) -> [Element] {
        showsAll ? items : Array(items.prefix(rows))
    }

    /// Whether the list is long enough to need the button.
    public static func isLong(_ count: Int) -> Bool { count > rows }
}

/// The quiet link under a shortened list that shows the rest of it, or folds it again.
public struct PanelMoreButton: View {
    @Binding private var showsAll: Bool
    private let more: Text
    private let less: Text
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(showsAll: Binding<Bool>, more: Text, less: Text) {
        self._showsAll = showsAll
        self.more = more
        self.less = less
    }

    public var body: some View {
        Button {
            withAnimation(sonaryAnimation(reduceMotion)) { showsAll.toggle() }
        } label: {
            HStack(spacing: 4) {
                showsAll ? less : more
                Image(systemName: showsAll ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Color.sonaryAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
