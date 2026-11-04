import AppKit
import ApplicationServices

/// What a click on a running app's Dock icon should do instead of the system's own
/// behaviour. `.system` leaves the click alone.
public enum DockClickAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case system, cycleWindows, minimizeAll, showAllWindows

    public var id: String { rawValue }
}

/// One window of an app, as the window server lists it.
public struct DockWindow: Equatable, Sendable, Identifiable {
    public var id: UInt32
    public var title: String
    public var frame: CGRect

    public init(id: UInt32, title: String, frame: CGRect) {
        self.id = id
        self.title = title
        self.frame = frame
    }
}

/// The windows of one app, from a `CGWindowListCopyWindowInfo` dump: on-screen layers
/// only, big enough to be a real window, and across every Space.
public func dockWindows(ofPID pid: Int32, in info: [[String: Any]]) -> [DockWindow] {
    info.compactMap { entry in
        guard let owner = entry[kCGWindowOwnerPID as String] as? Int32, owner == pid,
              let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
              let number = entry[kCGWindowNumber as String] as? UInt32,
              let bounds = entry[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
              width >= 80, height >= 60
        else { return nil }
        let x = bounds["X"] as? Double ?? 0
        let y = bounds["Y"] as? Double ?? 0
        let title = entry[kCGWindowName as String] as? String ?? ""
        return DockWindow(id: number, title: title,
                          frame: CGRect(x: x, y: y, width: width, height: height))
    }
}

/// The window to raise when the icon is clicked again: the one after the frontmost,
/// wrapping around. Nil when there is nothing to cycle.
public func nextWindowToRaise(after current: UInt32?, in windows: [DockWindow]) -> DockWindow? {
    guard windows.count > 1 else { return windows.first }
    guard let current, let index = windows.firstIndex(where: { $0.id == current }) else { return windows.first }
    return windows[(index + 1) % windows.count]
}

/// Whether the pointer has rested on the same Dock icon long enough to show previews.
public struct DockHoverState: Sendable {
    public var delay: Double
    private var candidate: Int32?
    private var since: Double?

    public init(delay: Double = 0.45) {
        self.delay = delay
    }

    /// Returns the app whose previews should open now, or nil while waiting.
    public mutating func pointer(over pid: Int32?, at time: Double) -> Int32? {
        guard let pid else {
            candidate = nil
            since = nil
            return nil
        }
        if candidate != pid {
            candidate = pid
            since = time
            return nil
        }
        guard let since, time - since >= delay else { return nil }
        self.since = nil
        return pid
    }
}
