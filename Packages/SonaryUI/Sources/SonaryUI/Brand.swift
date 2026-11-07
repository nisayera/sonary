import Foundation
import Observation
import SwiftUI

/// The colours Sonary can wear. Coral is the one from the app icon.
public enum SonaryAccent: String, CaseIterable, Codable, Sendable, Identifiable {
    case coral, pink, red, orange, yellow, green, mint, teal, blue, indigo, purple, graphite

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .coral: Color(red: 1.0, green: 0.42, blue: 0.45)
        case .pink: Color(red: 1.0, green: 0.30, blue: 0.62)
        case .red: Color(red: 0.96, green: 0.26, blue: 0.24)
        case .orange: Color(red: 1.0, green: 0.58, blue: 0.0)
        case .yellow: Color(red: 0.95, green: 0.75, blue: 0.0)
        case .green: Color(red: 0.20, green: 0.78, blue: 0.35)
        case .mint: Color(red: 0.0, green: 0.78, blue: 0.70)
        case .teal: Color(red: 0.19, green: 0.69, blue: 0.85)
        case .blue: Color(red: 0.0, green: 0.48, blue: 1.0)
        case .indigo: Color(red: 0.35, green: 0.34, blue: 0.84)
        case .purple: Color(red: 0.69, green: 0.32, blue: 0.87)
        case .graphite: Color(red: 0.56, green: 0.56, blue: 0.60)
        }
    }
}

/// The user's choice of accent, read wherever `Color.sonaryAccent` is, so every view that
/// uses it redraws when it changes.
@Observable
public final class SonaryTheme: @unchecked Sendable {
    public static let shared = SonaryTheme()
    public static let defaultsKey = "appearance.accent"

    public private(set) var accent: SonaryAccent

    private init() {
        accent = UserDefaults.standard.string(forKey: Self.defaultsKey).flatMap(SonaryAccent.init(rawValue:)) ?? .coral
    }

    public func setAccent(_ accent: SonaryAccent, in defaults: UserDefaults = .standard) {
        self.accent = accent
        defaults.set(accent.rawValue, forKey: Self.defaultsKey)
    }
}

public extension Color {
    /// Sonary's accent: coral from the app icon, or the colour the user picked.
    static var sonaryAccent: Color { SonaryTheme.shared.accent.color }
}

/// A row of round swatches for picking the accent.
public struct AccentPicker: View {
    private let selection: SonaryAccent
    private let choose: (SonaryAccent) -> Void

    public init(selection: SonaryAccent, choose: @escaping (SonaryAccent) -> Void) {
        self.selection = selection
        self.choose = choose
    }

    public var body: some View {
        HStack(spacing: 7) {
            ForEach(SonaryAccent.allCases) { accent in
                Button { choose(accent) } label: {
                    Circle()
                        .fill(accent.color.gradient)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                        .padding(2.5)
                        .overlay(Circle().strokeBorder(accent == selection ? accent.color : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: accent.rawValue.capitalized))
                .accessibilityLabel(Text(verbatim: accent.rawValue.capitalized))
                .accessibilityAddTraits(accent == selection ? .isSelected : [])
            }
        }
    }
}
