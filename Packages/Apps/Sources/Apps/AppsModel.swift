import AppKit
import Observation

public struct CleanTarget: Identifiable, Equatable, Sendable {
    public var id: String
    public var folder: URL
    public var size: Int64?
}

public struct UninstallPlan: Equatable, Sendable {
    public var app: URL
    public var name: String
    public var leftovers: [URL]
    public var totalSize: Int64
}

struct ProcessResult: Sendable {
    var status: Int32
    var output: Data
}

func runProcess(_ path: String, _ arguments: [String]) async -> ProcessResult {
    await Task.detached {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return ProcessResult(status: -1, output: Data()) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessResult(status: process.terminationStatus, output: data)
    }.value
}

/// Cleaner, uninstaller, port manager, quitting apps and Homebrew updates.
@MainActor
@Observable
public final class AppsModel {
    public private(set) var cleanTargets: [CleanTarget]
    public private(set) var isScanning = false
    public private(set) var ports: [ListeningPort] = []
    public private(set) var outdated: [OutdatedPackage] = []
    public private(set) var brewAvailable = brewExecutable() != nil
    public private(set) var isBrewBusy = false
    public private(set) var uninstallPlan: UninstallPlan?
    public private(set) var message: String?

    public init() {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        cleanTargets = [
            CleanTarget(id: "caches", folder: library.appendingPathComponent("Caches")),
            CleanTarget(id: "logs", folder: library.appendingPathComponent("Logs")),
            CleanTarget(id: "derivedData", folder: library.appendingPathComponent("Developer/Xcode/DerivedData")),
        ]
    }

    // MARK: Cleaner

    public func scan() async {
        guard !isScanning else { return }
        isScanning = true
        for index in cleanTargets.indices {
            let folder = cleanTargets[index].folder
            cleanTargets[index].size = await Task.detached { allocatedSize(of: folder) }.value
        }
        isScanning = false
    }

    /// Moves the folder's contents to the Trash, so nothing is lost for good.
    public func clean(_ target: CleanTarget) async {
        let folder = target.folder
        let failed = await Task.detached { () -> Int in
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            var failed = 0
            for item in items {
                do { try FileManager.default.trashItem(at: item, resultingItemURL: nil) } catch { failed += 1 }
            }
            return failed
        }.value
        message = failed == 0 ? nil : String(localized: "Some items are in use and were skipped.", bundle: .module)
        await scan()
    }

    // MARK: Uninstaller

    public func chooseAppToUninstall() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let app = panel.url else { return }
        prepareUninstall(app)
    }

    public func prepareUninstall(_ app: URL) {
        guard let bundle = Bundle(url: app), let bundleID = bundle.bundleIdentifier else {
            message = String(localized: "This is not an app Sonary can read.", bundle: .module)
            return
        }
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        let name = app.deletingPathExtension().lastPathComponent
        let home = FileManager.default.homeDirectoryForCurrentUser
        let leftovers = leftoverCandidates(bundleID: bundleID, appName: name, home: home)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let total = ([app] + leftovers).reduce(Int64(0)) { $0 + allocatedSize(of: $1) }
        uninstallPlan = UninstallPlan(app: app, name: name, leftovers: leftovers, totalSize: total)
    }

    public func cancelUninstall() { uninstallPlan = nil }

    public func confirmUninstall() {
        guard let plan = uninstallPlan else { return }
        let bundleID = Bundle(url: plan.app)?.bundleIdentifier
        if let bundleID {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) { app.terminate() }
        }
        var failed: [String] = []
        for url in [plan.app] + plan.leftovers {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { failed.append(url.lastPathComponent) }
        }
        uninstallPlan = nil
        message = failed.isEmpty
            ? String(localized: "\(plan.name) was moved to the Trash.", bundle: .module)
            : String(localized: "Could not move \(failed.joined(separator: ", ")) to the Trash.", bundle: .module)
    }

    // MARK: Ports

    public func refreshPorts() async {
        let result = await runProcess("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"])
        ports = parseLsofListening(String(decoding: result.output, as: UTF8.self))
    }

    public func stopProcess(pid: Int32) async {
        kill(pid, SIGTERM)
        try? await Task.sleep(for: .milliseconds(500))
        await refreshPorts()
    }

    // MARK: Running apps

    public var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    public func quit(_ app: NSRunningApplication, force: Bool) {
        _ = force ? app.forceTerminate() : app.terminate()
    }

    // MARK: Homebrew

    public func refreshOutdated() async {
        guard let brew = brewExecutable() else { brewAvailable = false; return }
        brewAvailable = true
        isBrewBusy = true
        let result = await runProcess(brew, ["outdated", "--json=v2"])
        outdated = parseBrewOutdated(result.output)
        isBrewBusy = false
    }

    public func upgrade(_ package: OutdatedPackage) async {
        guard let brew = brewExecutable() else { return }
        isBrewBusy = true
        let args = package.isCask ? ["upgrade", "--cask", package.name] : ["upgrade", package.name]
        let result = await runProcess(brew, args)
        if result.status != 0 {
            message = String(localized: "Homebrew could not upgrade \(package.name).", bundle: .module)
        }
        isBrewBusy = false
        await refreshOutdated()
    }
}
