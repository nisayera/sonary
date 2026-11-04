import Foundation

public struct MountedInstaller: Equatable, Sendable, Identifiable {
    /// The mounted volume, e.g. /Volumes/Something.
    public var volume: URL
    /// The app bundle inside it.
    public var app: URL
    public var name: String
    public var id: String { app.path }

    public init(volume: URL, app: URL, name: String) {
        self.volume = volume
        self.app = app
        self.name = name
    }
}

/// The app a mounted disk image is offering, if it offers exactly one. A volume with
/// several apps, or none, is left alone: guessing which one the user wants is worse
/// than letting them drag it themselves.
public func installerApp(volume: URL, contents: [URL]) -> MountedInstaller? {
    let apps = contents.filter { $0.pathExtension == "app" }
    guard apps.count == 1, let app = apps.first else { return nil }
    return MountedInstaller(volume: volume, app: app,
                            name: app.deletingPathExtension().lastPathComponent)
}

/// Where an installer's app would land, and whether something is already there.
public func installDestination(for installer: MountedInstaller,
                               applications: URL = URL(fileURLWithPath: "/Applications", isDirectory: true))
-> URL {
    applications.appendingPathComponent(installer.app.lastPathComponent)
}

/// A volume Sonary should not treat as an installer: the startup disk and the
/// read-only system volumes macOS keeps mounted.
public func isInstallerVolume(_ volume: URL) -> Bool {
    let path = volume.path
    guard path.hasPrefix("/Volumes/") else { return false }
    let skipped = ["/Volumes/Macintosh HD", "/Volumes/Preboot", "/Volumes/Recovery", "/Volumes/VM",
                   "/Volumes/Update", "/Volumes/xarts", "/Volumes/iSCPreboot", "/Volumes/Data"]
    return !skipped.contains { path == $0 || path.hasPrefix($0 + "/") }
}
