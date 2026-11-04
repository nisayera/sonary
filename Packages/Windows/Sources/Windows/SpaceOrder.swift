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
