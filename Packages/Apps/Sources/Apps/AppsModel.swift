import AppKit
import Observation
import SonaryCore

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
    public private(set) var appUpdates: [AppUpdate] = []
    public private(set) var isCheckingApps = false
    /// A mounted disk image that is offering exactly one app to install.
    public private(set) var installer: MountedInstaller?
    public private(set) var brewAvailable = brewExecutable() != nil
    public private(set) var isBrewBusy = false
    /// App Store apps with an update, read through the mas tool when it is installed.
    public private(set) var appStoreUpdates: [AppStoreUpdate] = []
    public private(set) var masAvailable = masExecutable() != nil
    public private(set) var brewResults: [BrewPackage] = []
    public private(set) var brewInstalled: [BrewPackage] = []
    public private(set) var processes: [RunningProcess] = []
    public private(set) var uninstallPlan: UninstallPlan?
    public private(set) var message: String?
    public private(set) var settings = AppsSettings()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var mountObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var unmountObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    /// The last app in front other than Sonary: the "front app" while Sonary's panel is open.
    @ObservationIgnored private var lastFrontApp: Int32?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = StoredSettings.load(AppsSettings.self, key: "apps.settings", from: defaults,
                                       fallback: AppsSettings())
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        cleanTargets = [
            CleanTarget(id: "caches", folder: library.appendingPathComponent("Caches")),
            CleanTarget(id: "logs", folder: library.appendingPathComponent("Logs")),
            CleanTarget(id: "derivedData", folder: library.appendingPathComponent("Developer/Xcode/DerivedData")),
        ]
    }

    func start() {
        guard scheduleTask == nil else { return }
        observeMounts()
        observeActivation()
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runScheduledWork()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func stop() {
        scheduleTask?.cancel()
        scheduleTask = nil
        let center = NSWorkspace.shared.notificationCenter
        if let mountObserver { center.removeObserver(mountObserver) }
        if let unmountObserver { center.removeObserver(unmountObserver) }
        if let activationObserver { center.removeObserver(activationObserver) }
        mountObserver = nil
        unmountObserver = nil
        activationObserver = nil
        installer = nil
    }

    // MARK: Disk images

    /// Watches for a mounted disk image so the panel can offer to install the app in it.
    private func observeMounts() {
        guard mountObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        mountObserver = center.addObserver(forName: NSWorkspace.didMountNotification,
                                           object: nil, queue: .main) { [weak self] note in
            let volume = note.userInfo?["NSDevicePath"] as? String
            MainActor.assumeIsolated { self?.volumeMounted(volume) }
        }
        unmountObserver = center.addObserver(forName: NSWorkspace.didUnmountNotification,
                                             object: nil, queue: .main) { [weak self] note in
            let volume = note.userInfo?["NSDevicePath"] as? String
            MainActor.assumeIsolated { self?.volumeUnmounted(volume) }
        }
    }

    private func volumeMounted(_ path: String?) {
        guard let path else { return }
        let volume = URL(fileURLWithPath: path, isDirectory: true)
        guard isInstallerVolume(volume) else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: volume, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        installer = installerApp(volume: volume, contents: contents)
    }

    private func volumeUnmounted(_ path: String?) {
        guard let path, installer?.volume.path == path else { return }
        installer = nil
    }

    public func dismissInstaller() { installer = nil }

    /// Copies the app into /Applications, then ejects the image.
    public func install(_ installer: MountedInstaller) async {
        let destination = installDestination(for: installer)
        let source = installer.app
        let moved = await Task.detached { () -> Bool in
            let manager = FileManager.default
            if manager.fileExists(atPath: destination.path) {
                guard (try? manager.trashItem(at: destination, resultingItemURL: nil)) != nil else { return false }
            }
            return (try? manager.copyItem(at: source, to: destination)) != nil
        }.value
        guard moved else {
            message = String(localized: "\(installer.name) could not be copied to the Applications folder.",
                             bundle: .module)
            return
        }
        // Ask where the image file is before ejecting: afterwards hdiutil no longer knows.
        var imagePath: String?
        if settings.trashDiskImageAfterInstall {
            let info = await runProcess("/usr/bin/hdiutil", ["info", "-plist"])
            if info.status == 0 { imagePath = diskImagePath(mountedAt: installer.volume.path, hdiutilInfo: info.output) }
        }
        let ejected = (try? NSWorkspace.shared.unmountAndEjectDevice(at: installer.volume)) != nil
        self.installer = nil
        message = String(localized: "\(installer.name) is in your Applications folder.", bundle: .module)
        if ejected, let imagePath, isTrashableDiskImage(imagePath) {
            let image = URL(fileURLWithPath: imagePath)
            if (try? FileManager.default.trashItem(at: image, resultingItemURL: nil)) != nil {
                message = String(localized: "\(installer.name) is in your Applications folder, and the disk image is in the Trash.",
                                 bundle: .module)
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    /// Changes the cleaning schedule. Switching it on also starts the interval from
    /// now, so picking "weekly" does not clean within seconds.
    public func setCleanSchedule(_ schedule: CleanSchedule, now: Date = Date()) {
        update { settings in
            let previous = settings.cleanSchedule
            settings.cleanSchedule = schedule
            settings.lastCleaned = lastCleanedAfterScheduleChange(
                from: previous, to: schedule, lastCleaned: settings.lastCleaned, now: now)
        }
    }

    public func update(_ change: (inout AppsSettings) -> Void) {
        change(&settings)
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "apps.settings") }
    }

    // MARK: App updates

    /// Asks every app in /Applications that ships a Sparkle feed whether it is current.
    public func checkAppUpdates() async {
        guard !isCheckingApps else { return }
        isCheckingApps = true
        defer { isCheckingApps = false }
        let apps = await Task.detached { Self.sparkleApps() }.value
        var found: [AppUpdate] = []
        await withTaskGroup(of: AppUpdate?.self) { group in
            for app in apps {
                group.addTask {
                    var request = URLRequest(url: app.feed)
                    request.timeoutInterval = 15
                    guard let (data, _) = try? await URLSession.shared.data(for: request),
                          let xml = String(data: data, encoding: .utf8) else { return nil }
                    return appUpdate(for: app, latest: latestAppcastVersion(xml))
                }
            }
            for await update in group { if let update { found.append(update) } }
        }
        appUpdates = found.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
    }

    /// Opens the app, so its own updater takes it from here.
    public func openApp(_ update: AppUpdate) {
        NSWorkspace.shared.open(update.app.url)
    }

    nonisolated private static func sparkleApps() -> [InstalledApp] {
        let folders = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                       FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var result: [InstalledApp] = []
        for folder in folders {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for bundle in contents where bundle.pathExtension == "app" {
                let plistURL = bundle.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plistURL),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let app = installedApp(at: bundle, plist: plist) else { continue }
                result.append(app)
            }
        }
        return result
    }

    /// The scheduled clean and the retention rules, checked once an hour.
    private func runScheduledWork() async {
        await tidyWatchedFolders()
        guard shouldClean(schedule: settings.cleanSchedule, lastCleaned: settings.lastCleaned, now: Date()) else { return }
        await scan()
        for target in cleanTargets where (target.size ?? 0) > 0 {
            await clean(target)
        }
        update { $0.lastCleaned = Date() }
    }

    /// Moves files that outlived their folder's retention rule to the Trash.
    public func tidyWatchedFolders() async {
        let folders = settings.watchedFolders
        guard !folders.isEmpty else { return }
        let (removed, moved) = await Task.detached { () -> (Int, Int) in
            var removed = 0
            var moved = 0
            for folder in folders {
                let url = URL(fileURLWithPath: folder.path, isDirectory: true)
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
                let files = contents.map { item in
                    AgedFile(url: item,
                             modified: (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?
                                 .contentModificationDate ?? Date())
                }
                var trashed = Set<URL>()
                for file in filesPastRetention(files, days: folder.retentionDays, now: Date()) {
                    if (try? FileManager.default.trashItem(at: file.url, resultingItemURL: nil)) != nil {
                        removed += 1
                        trashed.insert(file.url)
                    }
                }
                if folder.removeRepeats == true {
                    let sized = contents.filter { !trashed.contains($0) }.map { item in
                        FolderFile(name: item.lastPathComponent,
                                   size: Int64((try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1))
                    }
                    for name in repeatedDownloads(in: sized.filter { $0.size >= 0 }) {
                        let copy = url.appendingPathComponent(name)
                        if (try? FileManager.default.trashItem(at: copy, resultingItemURL: nil)) != nil {
                            removed += 1
                            trashed.insert(copy)
                        }
                    }
                }
                if let target = folder.moveFinishedTo, !target.isEmpty {
                    let destination = URL(fileURLWithPath: target, isDirectory: true)
                    try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                    for file in files where !trashed.contains(file.url)
                        && isFinishedDownload(name: file.url.lastPathComponent, modified: file.modified, now: Date()) {
                        let free = uniqueFileName(file.url.lastPathComponent) {
                            FileManager.default.fileExists(atPath: destination.appendingPathComponent($0).path)
                        }
                        if (try? FileManager.default.moveItem(at: file.url, to: destination.appendingPathComponent(free))) != nil {
                            moved += 1
                        }
                    }
                }
            }
            return (removed, moved)
        }.value
        if removed > 0 {
            message = String(localized: "Moved \(removed) old files to the Trash.", bundle: .module)
        }
        if moved > 0 {
            message = String(localized: "Sorted \(moved) finished downloads.", bundle: .module)
        }
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

    /// Asks every running app to quit, or all but the one in front, leaving the apps that are
    /// kept running alone. Apps with unsaved work still ask about it themselves.
    public func quitAll(keepFront: Bool) {
        let running = runningApps
        let pids = appsToQuit(running: running.map { ($0.processIdentifier, $0.bundleIdentifier) },
                              front: frontApp, keepFront: keepFront, keepRunning: settings.keepRunningOnQuitAll)
        for app in running where pids.contains(app.processIdentifier) { app.terminate() }
    }

    /// The app that was in front before Sonary's panel opened.
    private var frontApp: Int32? {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.bundleIdentifier != Bundle.main.bundleIdentifier { return front.processIdentifier }
        return lastFrontApp
    }

    private func observeActivation() {
        guard activationObserver == nil else { return }
        lastFrontApp = NSWorkspace.shared.frontmostApplication.flatMap {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0.processIdentifier
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.lastFrontApp = pid }
        }
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

    /// Everything Sonary can update by itself at once: Homebrew's formulae and casks, and the
    /// App Store apps when mas is there. Apps with their own updater still need opening.
    public func updateAll() async {
        isBrewBusy = true
        var failed = false
        if let brew = brewExecutable(), !outdated.isEmpty {
            failed = await runProcess(brew, ["upgrade"]).status != 0 || failed
        }
        if let mas = masExecutable(), !appStoreUpdates.isEmpty {
            failed = await runProcess(mas, ["upgrade"]).status != 0 || failed
        }
        isBrewBusy = false
        message = failed ? String(localized: "Some updates did not go through.", bundle: .module)
            : String(localized: "Everything Sonary manages is up to date.", bundle: .module)
        await refreshOutdated()
        await refreshAppStore()
    }

    // MARK: App Store

    public func refreshAppStore() async {
        guard let mas = masExecutable() else {
            masAvailable = false
            appStoreUpdates = []
            return
        }
        masAvailable = true
        let result = await runProcess(mas, ["outdated"])
        appStoreUpdates = parseMasOutdated(String(decoding: result.output, as: UTF8.self))
    }

    public func upgrade(_ update: AppStoreUpdate) async {
        guard let mas = masExecutable() else { return }
        isBrewBusy = true
        let result = await runProcess(mas, ["upgrade", update.id])
        if result.status != 0 {
            message = String(localized: "The App Store could not update \(update.name).", bundle: .module)
        }
        isBrewBusy = false
        await refreshAppStore()
    }

    /// The App Store's own updates page, for when mas is not installed.
    public func openAppStoreUpdates() {
        if let url = URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(url) }
    }

    // MARK: Homebrew installs

    public func searchBrew(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let brew = brewExecutable(), q.count >= 2 else {
            brewResults = []
            return
        }
        isBrewBusy = true
        async let formulae = runProcess(brew, ["search", "--formula", q])
        async let casks = runProcess(brew, ["search", "--cask", q])
        let found = parseBrewNames(String(decoding: await formulae.output, as: UTF8.self), isCask: false)
            + parseBrewNames(String(decoding: await casks.output, as: UTF8.self), isCask: true)
        brewResults = Array(found.prefix(40))
        isBrewBusy = false
    }

    public func refreshBrewInstalled() async {
        guard let brew = brewExecutable() else { return }
        async let formulae = runProcess(brew, ["list", "--formula", "-1"])
        async let casks = runProcess(brew, ["list", "--cask", "-1"])
        brewInstalled = parseBrewNames(String(decoding: await formulae.output, as: UTF8.self), isCask: false)
            + parseBrewNames(String(decoding: await casks.output, as: UTF8.self), isCask: true)
    }

    public func install(_ package: BrewPackage) async {
        await runBrew("install", package,
                      failure: String(localized: "Homebrew could not install \(package.name).", bundle: .module))
    }

    public func uninstall(_ package: BrewPackage) async {
        await runBrew("uninstall", package,
                      failure: String(localized: "Homebrew could not remove \(package.name).", bundle: .module))
    }

    private func runBrew(_ verb: String, _ package: BrewPackage, failure: String) async {
        guard let brew = brewExecutable() else { return }
        isBrewBusy = true
        let result = await runProcess(brew, brewArguments(verb, package))
        message = result.status == 0 ? nil : failure
        isBrewBusy = false
        await refreshBrewInstalled()
    }

    // MARK: Processes

    public func refreshProcesses() async {
        let result = await runProcess("/bin/ps", ["-axo", "pid=,pcpu=,rss=,user=,comm="])
        processes = parseProcessList(String(decoding: result.output, as: UTF8.self))
    }

    /// Asks a process to end, or ends it at once when `force` is set.
    public func end(_ process: RunningProcess, force: Bool) async {
        if kill(process.pid, force ? SIGKILL : SIGTERM) != 0 {
            message = String(localized: "\(process.name) could not be stopped. It may belong to the system.", bundle: .module)
        }
        try? await Task.sleep(for: .milliseconds(400))
        await refreshProcesses()
    }
}
