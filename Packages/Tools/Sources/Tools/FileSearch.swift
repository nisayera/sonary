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

    func search(_ text: String, limit: Int = 5, completion: @escaping ([FoundFile]) -> Void) {
        cancel()
        guard isWorthSearching(text) else { return completion([]) }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(fromMetadataQueryString: fileSearchPredicate(text))
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { [weak self] _ in
            query.disableUpdates()
            let results = (0..<min(query.resultCount, limit)).compactMap { index -> FoundFile? in
                guard let item = query.result(at: index) as? NSMetadataItem,
                      let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
                let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String
                    ?? URL(fileURLWithPath: path).lastPathComponent
                return FoundFile(url: URL(fileURLWithPath: path), name: name)
            }
            completion(results)
            self?.cancel()
        }
        self.query = query
        query.start()
    }

    func cancel() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
