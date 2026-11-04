import AppKit
import Observation

/// Files parked in the notch: drop them in, drag them out again. They are not copied,
/// so the shelf only remembers where they are.
@MainActor
@Observable
public final class FileShelf {
    public private(set) var files: [URL] = []

    public init() {}

    /// Adds what was dropped, keeping the newest first and ignoring files already there.
    public func add(_ urls: [URL]) {
        for url in urls.reversed() where !files.contains(url) {
            files.insert(url, at: 0)
        }
        files = Array(files.prefix(shelfLimit))
    }

    public func remove(_ url: URL) { files.removeAll { $0 == url } }
    public func clear() { files.removeAll() }

    /// Drops the files that have since been moved or deleted, so the shelf never
    /// offers something that is no longer there.
    public func prune() {
        files = files.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// How many files the shelf holds before the oldest fall off.
public let shelfLimit = 12

/// The label under a shelf item: the file's name, shortened in the middle so both the
/// beginning and the extension stay readable.
public func shelfLabel(_ name: String, limit: Int = 18) -> String {
    guard name.count > limit, limit > 4 else { return name }
    let head = name.prefix((limit - 1) / 2)
    let tail = name.suffix(limit / 2)
    return "\(head)…\(tail)"
}
