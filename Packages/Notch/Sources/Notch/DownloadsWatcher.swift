import Foundation
import Observation

/// Watches the Downloads folder and keeps the newest finished files.
@MainActor
@Observable
public final class DownloadsWatcher {
    public private(set) var entries: [DownloadEntry] = []
    @ObservationIgnored private var source: (any DispatchSourceFileSystemObject)?

    public init() {}

    public var folder: URL? { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first }

    public func start() {
        guard source == nil, let folder else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        reload()
    }

    public func stop() {
        source?.cancel()
        source = nil
        entries = []
    }

    private func reload() {
        guard let folder,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { entries = []; return }
        let all = urls.map { url in
            DownloadEntry(url: url, modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast)
        }
        entries = recentDownloads(all, limit: 6)
    }
}
