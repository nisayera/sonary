import SwiftUI

public struct IconTab<ID: Hashable>: Identifiable {
    public let id: ID
    public let symbol: String
    public let title: Text

    public init(id: ID, symbol: String, title: Text) {
        self.id = id
        self.symbol = symbol
        self.title = title
    }
}

/// A row of icon-only tabs in a rounded bar; the active one sits on the accent colour.
/// VoiceOver reads each tab's title.
public struct IconTabBar<ID: Hashable>: View {
    private let tabs: [IconTab<ID>]
    private let minimumItemWidth: CGFloat?
    @Binding private var selection: ID
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `minimumItemWidth` keeps every tab readable when there are many of them; the row is meant
    /// to sit in a horizontal scroll view then, rather than squeezing the icons together.
    public init(tabs: [IconTab<ID>], selection: Binding<ID>, minimumItemWidth: CGFloat? = nil) {
        self.tabs = tabs
        self.minimumItemWidth = minimumItemWidth
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                let isActive = tab.id == selection
                Button {
                    withAnimation(sonaryAnimation(reduceMotion)) { selection = tab.id }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 13.5, weight: .semibold))
                        .frame(minWidth: minimumItemWidth, maxWidth: minimumItemWidth == nil ? .infinity : nil)
                        .frame(height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? Color.white : Color.secondary.opacity(0.86))
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.sonaryAccent.gradient)
                            .shadow(color: Color.sonaryAccent.opacity(0.35), radius: 4, y: 1)
                    }
                }
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(4)
        .background(PanelColors.card(colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PanelColors.border(colorScheme, increasedContrast: contrast == .increased), lineWidth: 0.7)
        )
    }
}
