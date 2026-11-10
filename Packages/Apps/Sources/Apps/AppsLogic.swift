import Foundation

// MARK: - Leftovers (uninstaller)

/// Places in the user's Library where apps leave settings, caches and data, for a bundle ID and app name.
public func leftoverCandidates(bundleID: String, appName: String, home: URL) -> [URL] {
    let library = home.appendingPathComponent("Library")
    let byID = [
        "Application Support/\(bundleID)", "Caches/\(bundleID)", "Preferences/\(bundleID).plist",
        "Containers/\(bundleID)", "Saved Application State/\(bundleID).savedState", "Logs/\(bundleID)",
        "HTTPStorages/\(bundleID)", "HTTPStorages/\(bundleID).binarycookies", "WebKit/\(bundleID)",
        "Cookies/\(bundleID).binarycookies", "Application Scripts/\(bundleID)", "LaunchAgents/\(bundleID).plist",
    ]
    var paths = byID.map { library.appendingPathComponent($0) }
    let name = appName.trimmingCharacters(in: .whitespaces)
    if !name.isEmpty, !name.contains("/") {
        paths += ["Application Support/\(name)", "Caches/\(name)", "Logs/\(name)"].map { library.appendingPathComponent($0) }
    }
    return paths
}

// MARK: - Sizes

public func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// Total size of a file or folder, counting allocated sizes. Unreadable items count as zero.
public func allocatedSize(of url: URL) -> Int64 {
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
    guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
    if values.isDirectory != true { return Int64(values.totalFileAllocatedSize ?? 0) }
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
    var total: Int64 = 0
    for case let file as URL in enumerator {
        total += Int64((try? file.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
    }
    return total
}

/// What the cleaner may move to the Trash: everything in the folder except Sonary's own
/// folders, which hold the clipboard history's images and the pending update.
public func cleanableItems(_ items: [URL], ownBundleID: String?) -> [URL] {
    guard let ownBundleID, !ownBundleID.isEmpty else { return items }
    return items.filter { !$0.lastPathComponent.hasPrefix(ownBundleID) }
}

// MARK: - Ports

public struct ListeningPort: Equatable, Sendable, Identifiable {
    public var pid: Int32
    public var command: String
    public var port: Int
    public var address: String
    public var id: String { "\(pid):\(address):\(port)" }
}

/// Parses `lsof -nP -iTCP -sTCP:LISTEN -F pcn` output (p = pid, c = command, n = address:port).
public func parseLsofListening(_ output: String) -> [ListeningPort] {
    var result: [ListeningPort] = []
    var pid: Int32?
    var command = ""
    for line in output.split(separator: "\n") {
        guard let tag = line.first else { continue }
        let value = String(line.dropFirst())
        switch tag {
        case "p": pid = Int32(value); command = ""
        case "c": command = value
        case "n":
            guard let pid, let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) else { continue }
            let address = String(value[..<colon])
            let item = ListeningPort(pid: pid, command: command, port: port, address: address)
            if !result.contains(where: { $0.pid == pid && $0.port == port }) { result.append(item) }
        default: continue
        }
    }
    return result.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
}

// MARK: - Homebrew

public struct OutdatedPackage: Equatable, Sendable, Identifiable {
    public var name: String
    public var installed: String
    public var current: String
    public var isCask: Bool
    public var id: String { (isCask ? "cask:" : "formula:") + name }
}

/// Parses `brew outdated --json=v2`.
public func parseBrewOutdated(_ data: Data) -> [OutdatedPackage] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
    func items(_ key: String, cask: Bool) -> [OutdatedPackage] {
        (json[key] as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            let installed = (item["installed_versions"] as? [String])?.last ?? (item["installed_versions"] as? String) ?? ""
            let current = item["current_version"] as? String ?? ""
            return OutdatedPackage(name: name, installed: installed, current: current, isCask: cask)
        }
    }
    return (items("formulae", cask: false) + items("casks", cask: true)).sorted { $0.name < $1.name }
}

/// The brew binary on Apple silicon, or the Intel location as a fallback.
public func brewExecutable(fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
    ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: fileExists)
}

// MARK: - App Store, through the mas tool

/// An App Store app with a newer version waiting.
public struct AppStoreUpdate: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var installed: String
    public var current: String
}

/// Parses `mas outdated`: "497799835  Xcode  (15.0 -> 15.1)" per line.
public func parseMasOutdated(_ text: String) -> [AppStoreUpdate] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
        guard let match = String(line).firstMatch(of: #/^\s*(\d+)\s+(.+?)\s+\((.+?)\s*->\s*(.+?)\)\s*$/#) else { return nil }
        return AppStoreUpdate(id: String(match.1), name: String(match.2), installed: String(match.3),
                              current: String(match.4))
    }
}

/// The mas binary, installed with Homebrew; nil when it is not there.
public func masExecutable(fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
    ["/opt/homebrew/bin/mas", "/usr/local/bin/mas"].first(where: fileExists)
}

// MARK: - Homebrew search and installs

/// A formula or cask found by a search or installed already.
public struct BrewPackage: Equatable, Hashable, Sendable, Identifiable {
    public var name: String
    public var isCask: Bool
    public var id: String { (isCask ? "cask:" : "formula:") + name }

    public init(name: String, isCask: Bool) {
        self.name = name
        self.isCask = isCask
    }
}

/// Names from `brew search` or `brew list -1`, one per line, without headings or notes.
public func parseBrewNames(_ text: String, isCask: Bool) -> [BrewPackage] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
        let name = line.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.hasPrefix("==>"), !name.contains(" ") else { return nil }
        return BrewPackage(name: name, isCask: isCask)
    }
}

/// The Homebrew command for installing or removing a package.
public func brewArguments(_ verb: String, _ package: BrewPackage) -> [String] {
    package.isCask ? [verb, "--cask", package.name] : [verb, package.name]
}

// MARK: - Processes

/// One process, as `ps` lists it.
public struct RunningProcess: Equatable, Sendable, Identifiable {
    public var pid: Int32
    /// Share of one core, in percent.
    public var cpu: Double
    /// Resident memory, in bytes.
    public var memory: Int64
    public var user: String
    public var name: String
    public var id: Int32 { pid }
}

/// Parses `ps -axo pid=,pcpu=,rss=,user=,comm=`. The command is a path; its last part is
/// the name shown.
public func parseProcessList(_ text: String) -> [RunningProcess] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
        let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard fields.count == 5, let pid = Int32(fields[0]), let cpu = Double(fields[1]),
              let rss = Int64(fields[2]) else { return nil }
        let command = String(fields[4]).trimmingCharacters(in: .whitespaces)
        let name = (command as NSString).lastPathComponent
        return RunningProcess(pid: pid, cpu: cpu, memory: rss * 1024, user: String(fields[3]),
                              name: name.isEmpty ? command : name)
    }
}

/// The busiest processes first, narrowed to those whose name or number contains the query.
public func filteredProcesses(_ list: [RunningProcess], query: String, limit: Int = 60) -> [RunningProcess] {
    let q = query.trimmingCharacters(in: .whitespaces)
    let matching = q.isEmpty ? list : list.filter {
        $0.name.localizedCaseInsensitiveContains(q) || String($0.pid) == q
    }
    return Array(matching.sorted { ($0.cpu, $0.memory) > ($1.cpu, $1.memory) }.prefix(limit))
}
