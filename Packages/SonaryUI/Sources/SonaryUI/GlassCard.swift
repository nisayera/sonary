import SwiftUI

public struct GlassCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        if reduceTransparency {
            content
                .padding(Spacing.m)
                .background(.regularMaterial, in: shape)
        } else {
            content
                .padding(Spacing.m)
                .glassEffect(.regular, in: shape)
        }
    }
}
