import Foundation

public struct DownloadEntry: Equatable, Sendable, Identifiable {
    public var url: URL
    public var modified: Date
    public var id: URL { url }

    public init(url: URL, modified: Date) {
        self.url = url
        self.modified = modified
    }
}

private let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial"]

/// Newest first, without hidden files and downloads still in progress.
public func recentDownloads(_ entries: [DownloadEntry], limit: Int) -> [DownloadEntry] {
    entries
        .filter { entry in
            let name = entry.url.lastPathComponent
            return !name.hasPrefix(".") && !partialExtensions.contains(entry.url.pathExtension.lowercased())
        }
        .sorted { $0.modified > $1.modified }
        .prefix(max(0, limit))
        .map { $0 }
}
