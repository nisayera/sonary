import SwiftUI

/// How much of the desktop shows through Sonary's floating surfaces.
public enum SonaryAppearance: String, CaseIterable, Codable, Sendable {
    case glass, frosted, solid

    public static let defaultsKey = "appearance.surface"

    public static func stored(in defaults: UserDefaults) -> SonaryAppearance {
        defaults.string(forKey: defaultsKey).flatMap(SonaryAppearance.init(rawValue:)) ?? .glass
    }

    public func store(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

private struct SonaryAppearanceKey: EnvironmentKey {
    static let defaultValue = SonaryAppearance.glass
}

public extension EnvironmentValues {
    var sonaryAppearance: SonaryAppearance {
        get { self[SonaryAppearanceKey.self] }
        set { self[SonaryAppearanceKey.self] = newValue }
    }
}

/// The background of a floating panel, in the chosen appearance. Reduce Transparency always wins,
/// because that setting is an accessibility need rather than a preference.
public struct PanelBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.sonaryAppearance) private var appearance
    private let shape: AnyShape

    public init(shape: some Shape) {
        self.shape = AnyShape(shape)
    }

    public func body(content: Content) -> some View {
        if reduceTransparency || appearance == .solid {
            content.background(.background, in: shape)
        } else if appearance == .frosted {
            content.background(.thickMaterial, in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

public extension View {
    /// Gives a floating surface its background, following the user's appearance choice.
    func panelBackground(in shape: some Shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)) -> some View {
        modifier(PanelBackground(shape: shape))
    }
}

/// The surface behind the whole menu bar panel, edge to edge. The menu bar window already brings
/// the system's glass; Glass only darkens it a little so text stays readable, Frosted lays a
/// thicker material over it, and Solid (or Reduce Transparency) covers it.
public struct PanelSurfaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.sonaryAppearance) private var appearance

    public init() {}

    public var body: some View {
        surface.ignoresSafeArea()
    }

    @ViewBuilder
    private var surface: some View {
        if reduceTransparency || appearance == .solid {
            Rectangle().fill(.background)
        } else if appearance == .frosted {
            Rectangle().fill(.regularMaterial)
                .overlay(Rectangle().fill(PanelColors.base(colorScheme)))
        } else {
            Rectangle().fill(PanelColors.base(colorScheme).opacity(colorScheme == .light ? 0.35 : 0.45))
        }
    }
}
