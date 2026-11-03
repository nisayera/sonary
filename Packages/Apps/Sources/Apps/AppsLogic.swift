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
