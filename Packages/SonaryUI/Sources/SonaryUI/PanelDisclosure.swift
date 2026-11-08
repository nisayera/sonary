import SwiftUI

/// A section of the menu panel that opens in place: a row with an icon, a title, a short summary
/// on the right and a chevron. Anything long folds away behind one of these instead of running
/// past the bottom of the screen.
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
    /// For a group of `PanelDisclosure`s whose open sections are kept in one stored string, as
    /// a comma-separated list of ids. Each section opens and closes on its own; opening one
    /// leaves the others as they are.
    func opens(_ id: String) -> Binding<Bool> {
        let source = self
        return Binding<Bool>(get: { panelOpenSections(source.wrappedValue).contains(id) },
                             set: { source.wrappedValue = panelTogglingSection(id, open: $0, in: source.wrappedValue) })
    }
}

/// The ids in a stored list of open sections.
public func panelOpenSections(_ stored: String) -> [String] {
    stored.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

/// The stored list with one section opened or closed, the others kept as they were.
public func panelTogglingSection(_ id: String, open: Bool, in stored: String) -> String {
    var sections = panelOpenSections(stored).filter { $0 != id }
    if open { sections.append(id) }
    return sections.joined(separator: ",")
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
