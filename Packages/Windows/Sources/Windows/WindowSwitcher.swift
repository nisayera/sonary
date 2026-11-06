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
