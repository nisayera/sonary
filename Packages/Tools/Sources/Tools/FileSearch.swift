import Foundation

/// A file Spotlight found, for the command bar.
public struct FoundFile: Equatable, Sendable, Identifiable {
    public var url: URL
    public var name: String
    public var id: String { url.path }

    public init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
}

/// A query short enough to match half the disk is not worth asking Spotlight about.
public func isWorthSearching(_ query: String, minimum: Int = 3) -> Bool {
    query.trimmingCharacters(in: .whitespaces).count >= minimum
}

/// The Spotlight predicate for a name search. Quotes in the query are dropped rather
/// than escaped, so a stray one cannot change what is asked.
public func fileSearchPredicate(_ query: String) -> String {
    let cleaned = query.replacingOccurrences(of: "\"", with: "")
        .replacingOccurrences(of: "\\", with: "")
    return "kMDItemDisplayName CONTAINS[cd] \"\(cleaned)\""
}

/// Asks Spotlight for files whose name contains the query. Empty when the query is
/// too short or nothing matched.
@MainActor
final class FileSearcher {
    private var query: NSMetadataQuery?
    private var observer: (any NSObjectProtocol)?
    /// Held here rather than captured, so the notification closure only has to carry
    /// a reference to this object, which the main actor already protects.
    private var completion: (([FoundFile]) -> Void)?
    private var limit = 5

    func search(_ text: String, limit: Int = 5, completion: @escaping ([FoundFile]) -> Void) {
        cancel()
        guard isWorthSearching(text) else { return completion([]) }
        self.completion = completion
        self.limit = limit
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(fromMetadataQueryString: fileSearchPredicate(text))
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        self.query = query
        query.start()
    }

    private func finish() {
        guard let query else { return }
        query.disableUpdates()
        let results = (0..<min(query.resultCount, limit)).compactMap { index -> FoundFile? in
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String
                ?? URL(fileURLWithPath: path).lastPathComponent
            return FoundFile(url: URL(fileURLWithPath: path), name: name)
        }
        let completion = self.completion
        cancel()
        completion?(results)
    }

    func cancel() {
        query?.stop()
        query = nil
        completion = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
