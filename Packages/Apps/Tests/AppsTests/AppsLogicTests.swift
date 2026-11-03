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
