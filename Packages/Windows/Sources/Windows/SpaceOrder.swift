import Foundation

/// macOS reorders Spaces by how recently they were used, which moves them under you.
/// The Dock reads this from its own preferences, so Sonary sets it there rather than
/// reaching into private APIs.
enum SpaceOrder {
    static let domain = "com.apple.dock"
    static let key = "workspaces-auto-swoosh"

    /// True when macOS is still rearranging Spaces by most recent use.
    static var rearrangesAutomatically: Bool {
        guard let dock = UserDefaults(suiteName: domain),
              dock.object(forKey: key) != nil else { return true }  // Apple's default is on
        return dock.bool(forKey: key)
    }

    /// The preference as it is stored: true, false, or nil when it was never set.
    static var storedValue: Bool? {
        guard let dock = UserDefaults(suiteName: domain), dock.object(forKey: key) != nil else { return nil }
        return dock.bool(forKey: key)
    }

    /// Puts back a value read with `storedValue`: nil removes the preference again, so
    /// macOS is left exactly as it was before Sonary touched it.
    @discardableResult
    static func restore(_ value: Bool?) -> Bool {
        guard let value else {
            guard let dock = UserDefaults(suiteName: domain) else { return false }
            dock.removeObject(forKey: key)
            dock.synchronize()
            return restartDock()
        }
        return setRearrangesAutomatically(value)
    }

    /// Writes the preference and restarts the Dock, which is the only way it notices.
    @discardableResult
    static func setRearrangesAutomatically(_ value: Bool) -> Bool {
        guard let dock = UserDefaults(suiteName: domain) else { return false }
        dock.set(value, forKey: key)
        dock.synchronize()
        return restartDock()
    }

    private static func restartDock() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

/// What the setting row says about the Spaces order, from the Dock's own preference.
public func spaceOrderIsFixed(rearrangesAutomatically: Bool) -> Bool {
    !rearrangesAutomatically
}

/// How the Spaces preference that was there before is kept in Sonary's own defaults:
/// 1 on, 0 off, -1 never set.
public func encodeSpaceOrderPreference(_ value: Bool?) -> Int {
    switch value {
    case .some(true): 1
    case .some(false): 0
    case .none: -1
    }
}

/// The value to put back. Nothing saved (Sonary never fixed the order) means "rearrange",
/// which is what releasing the order asks for.
public func decodeSpaceOrderPreference(_ raw: Int?) -> Bool? {
    switch raw {
    case .some(1): true
    case .some(0): false
    case .some(-1): nil
    default: true
    }
}
