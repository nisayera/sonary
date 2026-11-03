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
    public var id: String { path }

    public init(path: String, retentionDays: Int) {
        self.path = path
        self.retentionDays = retentionDays
    }
}

public struct AppsSettings: Codable, Equatable, Sendable {
    public var cleanSchedule: CleanSchedule = .off
    public var lastCleaned: Date?
    /// Folders whose downloads are tidied up after a while, e.g. a messenger's download folder.
    public var watchedFolders: [WatchedFolder] = []

    public init() {}
}
