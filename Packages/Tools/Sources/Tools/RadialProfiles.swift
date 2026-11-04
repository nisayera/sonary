import Foundation

/// A named ring of actions. The first profile is what ⌃⌥R opens; the others appear in
/// it as wedges that open their own ring, which is what a submenu is here.
public struct RadialProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var actions: [QuickAction]

    public init(id: UUID = UUID(), name: String, symbol: String = "square.grid.2x2",
                actions: [QuickAction] = []) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.actions = actions
    }
}

/// What one wedge of the ring is: an action to run, or a profile to open.
public enum RadialItem: Equatable, Sendable, Identifiable {
    case action(QuickAction)
    case profile(RadialProfile)
    case back

    public var id: String {
        switch self {
        case .action(let action): "action-\(action.rawValue)"
        case .profile(let profile): "profile-\(profile.id.uuidString)"
        case .back: "back"
        }
    }

    public var symbol: String {
        switch self {
        case .action(let action): action.symbol
        case .profile(let profile): profile.symbol
        case .back: "chevron.backward"
        }
    }
}

/// A ring never holds more than this; beyond it the wedges are too thin to hit.
public let radialRingLimit = 8

/// The first ring: the chosen actions, with one wedge per extra profile. Profiles come
/// last, so adding one never moves the actions a hand already knows.
public func radialRootItems(actions: [QuickAction], profiles: [RadialProfile]) -> [RadialItem] {
    let chosen = actions.isEmpty ? QuickAction.allCases : actions
    let wedges = chosen.map(RadialItem.action) + profiles.map(RadialItem.profile)
    return Array(wedges.prefix(radialRingLimit))
}

/// A profile's own ring, with a way back to the first one.
public func radialProfileItems(_ profile: RadialProfile) -> [RadialItem] {
    Array(profile.actions.prefix(radialRingLimit - 1).map(RadialItem.action)) + [.back]
}
