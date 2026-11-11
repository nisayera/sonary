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

/// One release offered by a Sparkle appcast. Sparkle accepts both forms for the version numbers:
/// child elements of `<item>` (`<sparkle:version>`, the current form) and attributes of
/// `<enclosure>` (the older form). `version` is the build number Sparkle compares with
/// `CFBundleVersion`; `shortVersion` is the marketing version shown to people.
public struct AppcastEntry: Equatable, Sendable {
    public var version: String?
    public var shortVersion: String?

    public init(version: String? = nil, shortVersion: String? = nil) {
        self.version = version
        self.shortVersion = shortVersion
    }

    /// What to show: the marketing version, or the build number when the feed has none.
    public var displayVersion: String? { shortVersion ?? version }
}

/// Every release in an appcast on the default channel (items with a `<sparkle:channel>`, such as
/// betas, are skipped, as Sparkle itself does unless the app opts in). Empty for anything that
/// is not a readable feed.
public func appcastEntries(_ data: Data) -> [AppcastEntry] {
    let reader = AppcastReader()
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = false
    parser.shouldResolveExternalEntities = false
    parser.delegate = reader
    _ = parser.parse()
    return reader.entries
}

public func appcastEntries(_ xml: String) -> [AppcastEntry] {
    appcastEntries(Data(xml.utf8))
}

private final class AppcastReader: NSObject, XMLParserDelegate {
    private struct Item {
        var elementVersion: String?
        var elementShort: String?
        var attributeVersion: String?
        var attributeShort: String?
        var channel: String?
    }

    private static let versionName = "sparkle:version"
    private static let shortName = "sparkle:shortVersionString"
    private static let channelName = "sparkle:channel"

    var entries: [AppcastEntry] = []
    private var item: Item?
    private var text = ""
    private var collecting = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = qName ?? elementName
        if name == "item" {
            item = Item()
            return
        }
        guard item != nil else { return }
        switch name {
        case "enclosure":
            if item?.attributeVersion == nil { item?.attributeVersion = Self.clean(attributeDict[Self.versionName]) }
            if item?.attributeShort == nil { item?.attributeShort = Self.clean(attributeDict[Self.shortName]) }
        case Self.versionName, Self.shortName, Self.channelName:
            text = ""
            collecting = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting { text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if collecting, let string = String(data: CDATABlock, encoding: .utf8) { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = qName ?? elementName
        guard let current = item else { return }
        switch name {
        case Self.versionName:
            item?.elementVersion = Self.clean(text)
            collecting = false
        case Self.shortName:
            item?.elementShort = Self.clean(text)
            collecting = false
        case Self.channelName:
            item?.channel = Self.clean(text)
            collecting = false
        case "item":
            item = nil
            guard current.channel == nil else { return }
            let entry = AppcastEntry(version: current.elementVersion ?? current.attributeVersion,
                                     shortVersion: current.elementShort ?? current.attributeShort)
            if entry.version != nil || entry.shortVersion != nil { entries.append(entry) }
        default:
            break
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

/// The update to show, or nil when the installed copy is already current.
///
/// Like is compared with like: the feed's build number (`sparkle:version`) with the installed
/// `CFBundleVersion`, which is what Sparkle itself does. Only when either side has no build
/// number are the marketing versions compared.
public func appUpdate(for app: InstalledApp, entries: [AppcastEntry]) -> AppUpdate? {
    func key(_ entry: AppcastEntry) -> (feed: String, installed: String)? {
        if let version = entry.version, !app.build.isEmpty { return (version, app.build) }
        if let short = entry.shortVersion, !app.shortVersion.isEmpty { return (short, app.shortVersion) }
        return nil
    }
    var best: (entry: AppcastEntry, feed: String)?
    for entry in entries {
        guard let pair = key(entry), isNewerVersion(pair.feed, than: pair.installed) else { continue }
        if let current = best, !isNewerVersion(pair.feed, than: current.feed) { continue }
        best = (entry, pair.feed)
    }
    guard let best, let shown = best.entry.displayVersion else { return nil }
    return AppUpdate(app: app, latestVersion: shown)
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
