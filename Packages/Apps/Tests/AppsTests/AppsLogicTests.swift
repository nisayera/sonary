import Foundation
import Testing
@testable import Apps

struct LeftoverTests {
    private let home = URL(fileURLWithPath: "/Users/test")

    @Test func includesPreferencesAndContainers() {
        let paths = leftoverCandidates(bundleID: "com.example.App", appName: "Example", home: home).map(\.path)
        #expect(paths.contains("/Users/test/Library/Preferences/com.example.App.plist"))
        #expect(paths.contains("/Users/test/Library/Containers/com.example.App"))
        #expect(paths.contains("/Users/test/Library/Application Support/Example"))
    }

    @Test func unsafeNameAddsNoNamePaths() {
        let paths = leftoverCandidates(bundleID: "com.x", appName: "../evil", home: home).map(\.path)
        #expect(!paths.contains { $0.contains("evil") })
    }

    @Test func emptyNameAddsNoNamePaths() {
        let paths = leftoverCandidates(bundleID: "com.x", appName: " ", home: home)
        #expect(paths.allSatisfy { $0.path.contains("com.x") })
    }
}

struct LsofTests {
    @Test func parsesListeningPorts() {
        let output = "p123\ncnode\nn*:3000\nn127.0.0.1:9229\np456\ncpostgres\nn[::1]:5432\n"
        let ports = parseLsofListening(output)
        #expect(ports.map(\.port) == [3000, 5432, 9229])
        #expect(ports.first?.command == "node")
        #expect(ports.first(where: { $0.port == 5432 })?.address == "[::1]")
    }

    @Test func deduplicatesSamePortPerProcess() {
        let ports = parseLsofListening("p1\ncx\nn*:80\nn[::]:80\n")
        #expect(ports.count == 1)
    }

    @Test func emptyOutputIsEmpty() {
        #expect(parseLsofListening("").isEmpty)
    }
}

struct BrewTests {
    @Test func parsesFormulaeAndCasks() {
        let json = """
        {"formulae":[{"name":"wget","installed_versions":["1.21"],"current_version":"1.24"}],
         "casks":[{"name":"firefox","installed_versions":["120.0"],"current_version":"121.0"}]}
        """
        let result = parseBrewOutdated(Data(json.utf8))
        #expect(result == [
            OutdatedPackage(name: "firefox", installed: "120.0", current: "121.0", isCask: true),
            OutdatedPackage(name: "wget", installed: "1.21", current: "1.24", isCask: false),
        ])
    }

    @Test func invalidJSONIsEmpty() {
        #expect(parseBrewOutdated(Data("nope".utf8)).isEmpty)
    }

    @Test func prefersAppleSiliconBrew() {
        #expect(brewExecutable { _ in true } == "/opt/homebrew/bin/brew")
        #expect(brewExecutable { $0 == "/usr/local/bin/brew" } == "/usr/local/bin/brew")
        #expect(brewExecutable { _ in false } == nil)
    }
}

struct SizeTests {
    @Test func sumsFolderContents() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sonary-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(count: 10_000).write(to: dir.appendingPathComponent("a"))
        try Data(count: 5_000).write(to: dir.appendingPathComponent("b"))
        #expect(allocatedSize(of: dir) >= 15_000)
    }

    @Test func missingIsZero() {
        #expect(allocatedSize(of: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")) == 0)
    }
}

struct HousekeepingTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func offNeverRuns() {
        #expect(!shouldClean(schedule: .off, lastCleaned: nil, now: now))
    }

    @Test func neverCleanedIsDueAtOnce() {
        #expect(shouldClean(schedule: .weekly, lastCleaned: nil, now: now))
    }

    @Test func weeklyWaitsSevenDays() {
        #expect(!shouldClean(schedule: .weekly, lastCleaned: now.addingTimeInterval(-6 * 86_400), now: now))
        #expect(shouldClean(schedule: .weekly, lastCleaned: now.addingTimeInterval(-8 * 86_400), now: now))
    }

    @Test func monthlyWaitsLonger() {
        #expect(!shouldClean(schedule: .monthly, lastCleaned: now.addingTimeInterval(-20 * 86_400), now: now))
        #expect(shouldClean(schedule: .monthly, lastCleaned: now.addingTimeInterval(-31 * 86_400), now: now))
    }

    @Test func retentionDropsOnlyOldFiles() {
        let files = [AgedFile(url: URL(fileURLWithPath: "/tmp/old"), modified: now.addingTimeInterval(-40 * 86_400)),
                     AgedFile(url: URL(fileURLWithPath: "/tmp/new"), modified: now.addingTimeInterval(-1 * 86_400))]
        #expect(filesPastRetention(files, days: 30, now: now).map(\.url.lastPathComponent) == ["old"])
    }

    @Test func zeroDaysKeepsEverything() {
        let files = [AgedFile(url: URL(fileURLWithPath: "/tmp/ancient"), modified: Date(timeIntervalSince1970: 0))]
        #expect(filesPastRetention(files, days: 0, now: now).isEmpty)
    }

    @Test func defaultsDoNothingUntilAsked() {
        let settings = AppsSettings()
        #expect(settings.cleanSchedule == .off)
        #expect(settings.watchedFolders.isEmpty)
    }
}

@Suite struct AppUpdateTests {
    private func app(_ version: String) -> InstalledApp {
        InstalledApp(name: "Demo", bundleID: "app.demo", shortVersion: version, build: "100",
                     feed: URL(string: "https://example.com/appcast.xml")!,
                     url: URL(fileURLWithPath: "/Applications/Demo.app"))
    }

    @Test func comparesVersionsPartByPart() {
        #expect(isNewerVersion("1.10.0", than: "1.9.3"))
        #expect(isNewerVersion("2.0", than: "1.99.99"))
        #expect(!isNewerVersion("1.2", than: "1.2.0"))
        #expect(!isNewerVersion("1.2", than: "1.3"))
        #expect(!isNewerVersion("", than: "1.0"))
        #expect(!isNewerVersion("beta", than: "1.0"))
    }

    @Test func readsTheHighestVersionFromAnAppcast() {
        let xml = """
        <rss><channel>
        <item><enclosure sparkle:shortVersionString="1.2.0" sparkle:version="120"/></item>
        <item><enclosure sparkle:shortVersionString="1.10.0" sparkle:version="1100"/></item>
        </channel></rss>
        """
        #expect(latestAppcastVersion(xml) == "1.10.0")
        #expect(latestAppcastVersion("<rss></rss>") == nil)
    }

    @Test func onlyReportsRealUpdates() {
        #expect(appUpdate(for: app("1.0"), latest: "1.1")?.latestVersion == "1.1")
        #expect(appUpdate(for: app("1.1"), latest: "1.1") == nil)
        #expect(appUpdate(for: app("1.2"), latest: "1.1") == nil)
        #expect(appUpdate(for: app("1.0"), latest: nil) == nil)
    }

    @Test func skipsAppsWithoutAnHTTPSFeed() {
        let url = URL(fileURLWithPath: "/Applications/Demo.app")
        #expect(installedApp(at: url, plist: ["CFBundleIdentifier": "app.demo"]) == nil)
        #expect(installedApp(at: url, plist: ["CFBundleIdentifier": "app.demo",
                                              "SUFeedURL": "http://example.com/a.xml"]) == nil)
        let good = installedApp(at: url, plist: ["CFBundleIdentifier": "app.demo",
                                                 "SUFeedURL": "https://example.com/a.xml",
                                                 "CFBundleShortVersionString": "1.0"])
        #expect(good?.shortVersion == "1.0")
        #expect(good?.name == "Demo")
    }
}

@Suite struct DMGInstallerTests {
    private let volume = URL(fileURLWithPath: "/Volumes/Demo", isDirectory: true)

    @Test func offersAnImageThatHoldsExactlyOneApp() {
        let one = installerApp(volume: volume, contents: [
            volume.appendingPathComponent("Demo.app"),
            volume.appendingPathComponent("Readme.txt"),
        ])
        #expect(one?.name == "Demo")
        #expect(one?.app.lastPathComponent == "Demo.app")
    }

    @Test func leavesAmbiguousImagesAlone() {
        #expect(installerApp(volume: volume, contents: []) == nil)
        #expect(installerApp(volume: volume, contents: [volume.appendingPathComponent("Readme.txt")]) == nil)
        #expect(installerApp(volume: volume, contents: [
            volume.appendingPathComponent("A.app"), volume.appendingPathComponent("B.app"),
        ]) == nil)
    }

    @Test func installsIntoApplicationsUnderTheSameName() {
        let installer = MountedInstaller(volume: volume, app: volume.appendingPathComponent("Demo.app"), name: "Demo")
        #expect(installDestination(for: installer).path == "/Applications/Demo.app")
    }

    @Test func ignoresSystemVolumes() {
        #expect(isInstallerVolume(volume))
        #expect(!isInstallerVolume(URL(fileURLWithPath: "/", isDirectory: true)))
        #expect(!isInstallerVolume(URL(fileURLWithPath: "/Volumes/Recovery", isDirectory: true)))
        #expect(!isInstallerVolume(URL(fileURLWithPath: "/Volumes/Macintosh HD", isDirectory: true)))
    }
}
