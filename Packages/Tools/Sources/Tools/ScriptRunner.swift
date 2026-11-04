import Foundation

/// A script the user put in Sonary's scripts folder, offered in the command bar.
public struct UserScript: Equatable, Sendable, Identifiable {
    public var url: URL
    public var name: String
    public var id: String { url.path }

    public init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
}

/// The scripts Sonary will run: executable files in the folder, nothing nested, and
/// nothing hidden. A file that is not marked executable is left alone rather than run
/// behind the user's back.
public func usableScripts(_ files: [(url: URL, isExecutable: Bool, isDirectory: Bool)]) -> [UserScript] {
    files.filter { $0.isExecutable && !$0.isDirectory && !$0.url.lastPathComponent.hasPrefix(".") }
        .map { UserScript(url: $0.url, name: $0.url.deletingPathExtension().lastPathComponent) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

/// Where the scripts live: a folder the user can open from the settings.
public func scriptsFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
    home.appendingPathComponent("Library/Application Support/app.sonary.Sonary/Scripts", isDirectory: true)
}

/// Reads the folder and keeps the files that may be run.
@MainActor
func loadScripts() -> [UserScript] {
    let folder = scriptsFolder()
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let keys: [URLResourceKey] = [.isExecutableKey, .isDirectoryKey]
    let contents = (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
    return usableScripts(contents.map { url in
        let values = try? url.resourceValues(forKeys: Set(keys))
        return (url: url, isExecutable: values?.isExecutable ?? false, isDirectory: values?.isDirectory ?? false)
    })
}

/// Runs a script without waiting for it. Its output is not shown; a script that wants
/// to say something can use the notification centre or write a file.
@MainActor
func runScript(_ script: UserScript) {
    let process = Process()
    process.executableURL = script.url
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try? process.run()
}
