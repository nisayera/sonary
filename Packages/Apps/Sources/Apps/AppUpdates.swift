import Foundation

/// An app in /Applications that ships a Sparkle feed, so Sonary can ask the feed
/// whether a newer build exists.
public struct InstalledApp: Equatable, Sendable, Identifiable {
    public var name: String
    public var bundleID: String
    public var shortVersion: String
    public var build: String
    public var feed: URL
    public var url: URL
    public var id: String { bundleID }

    public init(name: String, bundleID: String, shortVersion: String, build: String, feed: URL, url: URL) {
        self.name = name
        self.bundleID = bundleID
        self.shortVersion = shortVersion
        self.build = build
        self.feed = feed
        self.url = url
    }
}

public struct AppUpdate: Equatable, Sendable, Identifiable {
    public var app: InstalledApp
    public var latestVersion: String
    public var id: String { app.bundleID }

    public init(app: InstalledApp, latestVersion: String) {
        self.app = app
        self.latestVersion = latestVersion
    }
}

/// Compares dotted version numbers part by part, so 1.10 beats 1.9 and 1.2 beats 1.2-beta.
public func isNewerVersion(_ candidate: String, than current: String) -> Bool {
    func parts(_ value: String) -> [Int] {
        value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }
    let left = parts(candidate), right = parts(current)
    guard !left.isEmpty, !right.isEmpty else { return false }
    for index in 0..<max(left.count, right.count) {
        let a = index < left.count ? left[index] : 0
        let b = index < right.count ? right[index] : 0
        if a != b { return a > b }
    }
    return false
}

/// The highest `sparkle:shortVersionString` (or `sparkle:version`) an appcast offers.
public func latestAppcastVersion(_ xml: String) -> String? {
    var best: String?
    for attribute in ["sparkle:shortVersionString", "sparkle:version"] {
        var search = xml[...]
        while let range = search.range(of: "\(attribute)=\"") {
            let rest = search[range.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { break }
            let value = String(rest[..<end])
            if best == nil || isNewerVersion(value, than: best!) { best = value }
            search = rest[end...]
        }
        if best != nil { break }
    }
    return best
}

/// The update to show, or nil when the installed copy is already current.
public func appUpdate(for app: InstalledApp, latest: String?) -> AppUpdate? {
    guard let latest else { return nil }
    let installed = app.shortVersion.isEmpty ? app.build : app.shortVersion
    guard isNewerVersion(latest, than: installed) else { return nil }
    return AppUpdate(app: app, latestVersion: latest)
}

/// Reads an app bundle's Info.plist; nil when it has no Sparkle feed to ask.
public func installedApp(at url: URL, plist: [String: Any]) -> InstalledApp? {
    guard let feedString = plist["SUFeedURL"] as? String, let feed = URL(string: feedString),
          feed.scheme == "https", let bundleID = plist["CFBundleIdentifier"] as? String
    else { return nil }
    let name = plist["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
    return InstalledApp(name: name, bundleID: bundleID,
                        shortVersion: plist["CFBundleShortVersionString"] as? String ?? "",
                        build: plist["CFBundleVersion"] as? String ?? "", feed: feed, url: url)
}
