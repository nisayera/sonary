import Foundation

public enum CleanSchedule: String, CaseIterable, Codable, Sendable {
    case off, weekly, monthly

    var days: Int? {
        switch self {
        case .off: nil
        case .weekly: 7
        case .monthly: 30
        }
    }
}

/// True when the cleaner is due again. A clean that has never run is due at once.
public func shouldClean(schedule: CleanSchedule, lastCleaned: Date?, now: Date) -> Bool {
    guard let days = schedule.days else { return false }
    guard let lastCleaned else { return true }
    return now.timeIntervalSince(lastCleaned) >= Double(days) * 86_400
}

/// What `lastCleaned` becomes when the schedule is changed.
///
/// Switching the schedule on starts the interval from now. Without this a fresh
/// schedule has no last-cleaned date, `shouldClean` reads that as overdue, and the
/// first check — seconds later — moves caches to the Trash the moment the user picks
/// "weekly". Switching off, or changing between weekly and monthly, leaves the date
/// alone so the interval already served still counts.
public func lastCleanedAfterScheduleChange(from previousSchedule: CleanSchedule,
                                           to newSchedule: CleanSchedule,
                                           lastCleaned: Date?, now: Date) -> Date? {
    guard previousSchedule == .off, newSchedule != .off else { return lastCleaned }
    return now
}

public struct AgedFile: Equatable, Sendable {
    public var url: URL
    public var modified: Date

    public init(url: URL, modified: Date) {
        self.url = url
        self.modified = modified
    }
}

/// Files a retention rule has outlived. Zero days keeps everything, so a misconfigured
/// rule can never wipe a folder.
public func filesPastRetention(_ files: [AgedFile], days: Int, now: Date) -> [AgedFile] {
    guard days > 0 else { return [] }
    let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
    return files.filter { $0.modified < cutoff }
}

public struct WatchedFolder: Codable, Equatable, Sendable, Identifiable {
    public var path: String
    public var retentionDays: Int
    /// Finished downloads are moved here, out of the messenger's own folder. Optional, like
    /// the next one, so folders saved before these existed still read.
    public var moveFinishedTo: String?
    /// Copies of the same download ("photo (1).jpg" next to "photo.jpg", same size) go to the Trash.
    public var removeRepeats: Bool?
    public var id: String { path }

    public init(path: String, retentionDays: Int, moveFinishedTo: String? = nil, removeRepeats: Bool = false) {
        self.path = path
        self.retentionDays = retentionDays
        self.moveFinishedTo = moveFinishedTo
        self.removeRepeats = removeRepeats
    }
}

/// A file a download is still writing: a browser's or messenger's partial file, or one
/// that changed in the last couple of minutes.
public func isFinishedDownload(name: String, modified: Date, now: Date, settle: TimeInterval = 120) -> Bool {
    let partial = ["download", "crdownload", "part", "partial", "tmp", "opdownload"]
    let ext = (name as NSString).pathExtension.lowercased()
    guard !partial.contains(ext), !name.hasPrefix(".") else { return false }
    return now.timeIntervalSince(modified) >= settle
}

/// A file in a folder, by name and size, for spotting repeated downloads.
public struct FolderFile: Equatable, Sendable {
    public var name: String
    public var size: Int64

    public init(name: String, size: Int64) {
        self.name = name
        self.size = size
    }
}

/// The names that are a second copy of another file in the same folder: "photo (1).jpg" or
/// "photo-2.jpg" next to "photo.jpg" of the same size. The original stays.
public func repeatedDownloads(in files: [FolderFile]) -> [String] {
    let sizes = Dictionary(files.map { ($0.name, $0.size) }, uniquingKeysWith: { first, _ in first })
    return files.compactMap { file in
        let ext = (file.name as NSString).pathExtension
        let stem = (file.name as NSString).deletingPathExtension
        guard let match = stem.firstMatch(of: #/^(.+?)(?: \((\d+)\)|-(\d+))$/#) else { return nil }
        let original = ext.isEmpty ? String(match.1) : "\(match.1).\(ext)"
        guard original != file.name, sizes[original] == file.size else { return nil }
        return file.name
    }
}

public struct AppsSettings: Codable, Equatable, Sendable {
    public var cleanSchedule: CleanSchedule = .off
    public var lastCleaned: Date?
    /// Folders whose downloads are tidied up after a while, e.g. a messenger's download folder.
    public var watchedFolders: [WatchedFolder] = []
    /// After installing from a disk image, the image file goes to the Trash too.
    public var trashDiskImageAfterInstall = false
    /// Apps "Quit all" leaves running, by bundle ID.
    public var keepRunningOnQuitAll: [String] = []

    public init() {}
}

/// The apps "Quit all" ends: every running app except the ones kept running, and the one in
/// front when `keepFront` is set. Apps are given as process ID and bundle ID.
public func appsToQuit(running: [(pid: Int32, bundleID: String?)], front: Int32?, keepFront: Bool,
                       keepRunning: [String]) -> [Int32] {
    running.compactMap { app in
        if keepFront, app.pid == front { return nil }
        if let id = app.bundleID, keepRunning.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
            return nil
        }
        return app.pid
    }
}

/// A file name that is not taken yet: the name itself, or "name 2.ext", "name 3.ext" and so on.
public func uniqueFileName(_ name: String, exists: (String) -> Bool) -> String {
    guard exists(name) else { return name }
    let ext = (name as NSString).pathExtension
    let stem = (name as NSString).deletingPathExtension
    var number = 2
    while true {
        let candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
        if !exists(candidate) { return candidate }
        number += 1
    }
}
