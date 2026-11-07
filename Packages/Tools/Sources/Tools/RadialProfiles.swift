import Foundation
import SonaryCore

/// An app, a file or a keyboard shortcut on a wedge of its own.
public enum RadialLaunch: Codable, Equatable, Hashable, Sendable, Identifiable {
    case app(path: String)
    case file(path: String)
    case shortcut(KeyCombo)

    public var id: String {
        switch self {
        case .app(let path): "app-" + path
        case .file(let path): "file-" + path
        case .shortcut(let combo): "shortcut-\(combo.keyCode)-\(combo.modifiers)"
        }
    }

    /// The name the wedge and the settings show: the app or file name, or the keys.
    public var title: String {
        switch self {
        case .app(let path): URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        case .file(let path): URL(fileURLWithPath: path).lastPathComponent
        case .shortcut(let combo): shortcutDisplay(combo)
        }
    }
}

/// A named ring of actions. The first profile is what ⌃⌥R opens; the others appear in
/// it as wedges that open their own ring, which is what a submenu is here.
public struct RadialProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var actions: [QuickAction]
    /// Apps, files and shortcuts after the actions. Optional, so rings saved before these
    /// existed still read.
    public var launches: [RadialLaunch]?

    public init(id: UUID = UUID(), name: String, symbol: String = "square.grid.2x2",
                actions: [QuickAction] = [], launches: [RadialLaunch] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.actions = actions
        self.launches = launches
    }
}

/// What one wedge of the ring is: an action to run, or a profile to open.
public enum RadialItem: Equatable, Sendable, Identifiable {
    case action(QuickAction)
    case launch(RadialLaunch)
    case profile(RadialProfile)
    case back

    public var id: String {
        switch self {
        case .action(let action): "action-\(action.rawValue)"
        case .launch(let launch): "launch-\(launch.id)"
        case .profile(let profile): "profile-\(profile.id.uuidString)"
        case .back: "back"
        }
    }

    public var symbol: String {
        switch self {
        case .action(let action): action.symbol
        case .launch(.app): "app"
        case .launch(.file): "doc"
        case .launch(.shortcut): "command"
        case .profile(let profile): profile.symbol
        case .back: "chevron.backward"
        }
    }
}

/// A ring never holds more than this; beyond it the wedges are too thin to hit.
public let radialRingLimit = 8

/// The first ring: the chosen actions, then apps, files and shortcuts, with one wedge per
/// extra profile. Profiles come last, so adding one never moves the wedges a hand already
/// knows.
public func radialRootItems(actions: [QuickAction], launches: [RadialLaunch] = [],
                            profiles: [RadialProfile]) -> [RadialItem] {
    let chosen = actions.isEmpty && launches.isEmpty ? QuickAction.allCases : actions
    let wedges = chosen.map(RadialItem.action) + launches.map(RadialItem.launch) + profiles.map(RadialItem.profile)
    return Array(wedges.prefix(radialRingLimit))
}

/// A profile's own ring, with a way back to the first one.
public func radialProfileItems(_ profile: RadialProfile) -> [RadialItem] {
    let wedges = profile.actions.map(RadialItem.action) + (profile.launches ?? []).map(RadialItem.launch)
    return Array(wedges.prefix(radialRingLimit - 1)) + [.back]
}
