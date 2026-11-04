import SwiftUI

/// A card on a floating surface. Follows the user's appearance choice, and always falls back to a
/// plain material when Reduce Transparency is on.
public struct GlassCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.sonaryAppearance) private var appearance
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        if reduceTransparency || appearance != .glass {
            content
                .padding(Spacing.m)
                .background(appearance == .solid ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial), in: shape)
        } else {
            content
                .padding(Spacing.m)
                .glassEffect(.regular, in: shape)
        }
    }
}
