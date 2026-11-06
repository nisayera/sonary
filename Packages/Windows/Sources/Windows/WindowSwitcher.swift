import CoreGraphics
import Foundation

public struct WindowEntry: Equatable, Sendable, Identifiable {
    public var id: UInt32
    public var pid: Int32
    public var appName: String
    public var title: String
    /// Where the window is, in window-server coordinates (origin top left of the main display).
    public var bounds: CGRect

    public init(id: UInt32, pid: Int32, appName: String, title: String, bounds: CGRect = .zero) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.bounds = bounds
    }

    /// What the list shows: the app, plus the window title when it says something extra.
    public var label: String {
        title.isEmpty || title == appName ? appName : "\(appName) — \(title)"
    }
}

/// Turns the window server's list into the switcher's entries: real windows of other apps,
/// newest (frontmost) first, without the desktop, menu bar items and tiny helper windows.
public func switcherEntries(from windows: [[String: Any]], excludingPID ownPID: Int32) -> [WindowEntry] {
    windows.compactMap { window -> WindowEntry? in
        guard (window["kCGWindowLayer"] as? Int) == 0,
              let id = (window["kCGWindowNumber"] as? NSNumber)?.uint32Value,
              let pid = (window["kCGWindowOwnerPID"] as? NSNumber)?.int32Value, pid != ownPID,
              let appName = window["kCGWindowOwnerName"] as? String, !appName.isEmpty,
              let bounds = window["kCGWindowBounds"] as? [String: Any],
              let width = (bounds["Width"] as? NSNumber)?.doubleValue,
              let height = (bounds["Height"] as? NSNumber)?.doubleValue,
              width >= 120, height >= 80 else { return nil }
        let x = (bounds["X"] as? NSNumber)?.doubleValue ?? 0
        let y = (bounds["Y"] as? NSNumber)?.doubleValue ?? 0
        return WindowEntry(id: id, pid: pid, appName: appName, title: window["kCGWindowName"] as? String ?? "",
                           bounds: CGRect(x: x, y: y, width: width, height: height))
    }
}

/// Moves the selection, wrapping at both ends.
public func nextIndex(from index: Int, count: Int, forward: Bool) -> Int {
    guard count > 0 else { return 0 }
    let next = forward ? index + 1 : index - 1
    return (next % count + count) % count
}

/// Filters the list by what the user typed; empty query keeps the order.
public func filteredEntries(_ entries: [WindowEntry], query: String) -> [WindowEntry] {
    filteredEntries(entries, query: query, app: nil)
}

/// The same, narrowed to one app as well. `app` is an app name from `appNames`.
public func filteredEntries(_ entries: [WindowEntry], query: String, app: String?) -> [WindowEntry] {
    var result = entries
    if let app, !app.isEmpty { result = result.filter { $0.appName == app } }
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return result }
    // A query with a space matches each word, so "saf dow" finds a Safari download.
    let words = q.split(separator: " ").map(String.init)
    return result.filter { entry in
        words.allSatisfy { entry.label.localizedCaseInsensitiveContains($0) }
    }
}

/// The same, narrowed to the windows whose middle is on one display, given by its bounds in
/// window-server coordinates (`CGDisplayBounds`).
public func filteredEntries(_ entries: [WindowEntry], query: String, app: String?, display: CGRect?) -> [WindowEntry] {
    let result = filteredEntries(entries, query: query, app: app)
    guard let display else { return result }
    return result.filter { display.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }
}

/// The apps that have windows open, for the filter row, in the order they appear.
public func appNames(in entries: [WindowEntry]) -> [String] {
    var seen: [String] = []
    for entry in entries where !seen.contains(entry.appName) { seen.append(entry.appName) }
    return seen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

/// How the switcher looks.
public enum SwitcherStyle: String, Codable, CaseIterable, Sendable {
    /// Every window in a list with search, filters and pictures.
    case list
    /// One large icon per app in a row, the way the macOS switcher looks.
    case icons
}

/// One entry per app, its frontmost window, in the order the apps come up.
public func oneWindowPerApp(_ entries: [WindowEntry]) -> [WindowEntry] {
    var seen = Set<Int32>()
    return entries.filter { seen.insert($0.pid).inserted }
}

/// Where the selection starts when ⌘Tab opens the switcher: on the window behind the front
/// one, so a quick ⌘Tab goes back and forth between two; ⌘⇧Tab starts at the far end.
public func heldSelection(count: Int, forward: Bool) -> Int {
    guard count > 1 else { return 0 }
    return forward ? 1 : count - 1
}

/// What a key does while Sonary's switcher has taken over ⌘Tab.
public enum CommandTabStep: Equatable, Sendable {
    /// Nothing for the switcher: the key goes on to the app.
    case pass
    /// ⌘Tab opened the switcher, going forward, or backward with ⇧.
    case open(forward: Bool)
    case move(forward: Bool)
    /// ⌘ was let go, or Return pressed: bring the selected window forward.
    case choose
    case cancel
    /// A key pressed while the switcher is open that does nothing there; the app never gets it.
    case swallow
}

/// Follows ⌘Tab: opens on Tab while ⌘ is held, moves on each further Tab and chooses when ⌘
/// is let go, the way the macOS switcher works.
public struct CommandTabTracker: Sendable {
    public private(set) var isOpen = false

    public init() {}

    public mutating func keyDown(keyCode: Int64, command: Bool, shift: Bool, option: Bool, control: Bool)
        -> CommandTabStep {
        if keyCode == 48, command, !option, !control {
            if isOpen { return .move(forward: !shift) }
            isOpen = true
            return .open(forward: !shift)
        }
        guard isOpen else { return .pass }
        switch keyCode {
        case 53:
            isOpen = false
            return .cancel
        case 36, 76:
            isOpen = false
            return .choose
        case 123, 126, 50:  // left, up, and the key above Tab
            return .move(forward: false)
        case 124, 125:
            return .move(forward: true)
        default:
            return .swallow
        }
    }

    /// The Tab let go while the switcher is open stays away from the app, like its key-down.
    public func keyUp(keyCode: Int64) -> CommandTabStep {
        isOpen && keyCode == 48 ? .swallow : .pass
    }

    public mutating func flagsChanged(command: Bool) -> CommandTabStep {
        guard isOpen, !command else { return .pass }
        isOpen = false
        return .choose
    }

    /// The switcher closed some other way: a click on a window, or nothing to show.
    public mutating func closed() {
        isOpen = false
    }
}
