import AppKit
import SonaryUI
import SwiftUI

func cleanTargetSymbol(_ id: String) -> String {
    switch id {
    case "caches": "shippingbox"
    case "logs": "doc.text"
    case "derivedData": "hammer"
    default: "folder"
    }
}

func cleanTargetTitle(_ id: String) -> LocalizedStringKey {
    switch id {
    case "caches": "App caches"
    case "logs": "Logs"
    case "derivedData": "Xcode build data"
    default: "Other"
    }
}

struct AppsPopoverView: View {
    let model: AppsModel
    /// The section that is open; one at a time, so the panel stays short and never scrolls.
    @AppStorage("panel.apps.open") private var open = "clean"
    @State private var processQuery = ""
    @State private var allApps = false
    @State private var allProcesses = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let installer = model.installer {
                row {
                    Image(systemName: "externaldrive.badge.plus").foregroundStyle(Color.sonaryAccent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(installer.name).lineLimit(1)
                        Text("Found on a mounted disk image", bundle: .module)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button { Task { await model.install(installer) } } label: {
                        Text("Install", bundle: .module)
                    }
                    Button { model.dismissInstaller() } label: { Text("Ignore", bundle: .module) }
                }
                .panelCard(padded: false)
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
            PanelDisclosure(symbol: "sparkles", title: Text("Clean", bundle: .module),
                            isExpanded: $open.opens("clean")) {
                let total = model.cleanTargets.compactMap(\.size).reduce(0, +)
                if total > 0 { Text(verbatim: formatBytes(total)) }
            } content: {
                cleanView.task { await model.scan() }
            }
            PanelDisclosure(symbol: "app.badge", title: Text("Apps", bundle: .module),
                            isExpanded: $open.opens("apps")) {
                Text(verbatim: "\(model.runningApps.count)")
            } content: {
                appsView
            }
            PanelDisclosure(symbol: "cpu", title: Text("Processes", bundle: .module),
                            isExpanded: $open.opens("processes")) {
                processesView.task {
                    // Refreshed while the section is open, and not otherwise.
                    while !Task.isCancelled {
                        await model.refreshProcesses()
                        try? await Task.sleep(for: .seconds(3))
                    }
                }
            }
            PanelDisclosure(symbol: "network", title: Text("Ports", bundle: .module),
                            isExpanded: $open.opens("ports")) {
                if !model.ports.isEmpty { Text(verbatim: "\(model.ports.count)") }
            } content: {
                portsView.task { await model.refreshPorts() }
            }
            PanelDisclosure(symbol: "arrow.down.app", title: Text("Updates", bundle: .module),
                            isExpanded: $open.opens("updates")) {
                let count = model.outdated.count + model.appStoreUpdates.count + model.appUpdates.count
                if count > 0 {
                    Text(verbatim: "\(count)").foregroundStyle(Color.sonaryAccent)
                }
            } content: {
                updatesView.task {
                    await model.refreshOutdated()
                    await model.refreshAppStore()
                    await model.checkAppUpdates()
                }
            }
        }
    }

    /// Show all / show less under a list cut to its first rows.
    private func more(_ count: Int, _ showsAll: Binding<Bool>) -> some View {
        PanelMoreButton(showsAll: showsAll, more: Text("Show all (\(count))", bundle: .module),
                        less: Text("Show less", bundle: .module))
    }

    /// A small icon button for a row, so a row's actions never push its name off the panel.
    private func iconButton(_ symbol: String, _ label: Text, destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(destructive ? AnyShapeStyle(Color.red.opacity(0.85)) : AnyShapeStyle(.secondary))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var cleanView: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelGroup {
                ForEach(model.cleanTargets) { target in
                    row {
                        IconBadge(symbol: cleanTargetSymbol(target.id), size: PanelMetrics.rowIconWidth)
                        Text(cleanTargetTitle(target.id), bundle: .module).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(target.size.map(formatBytes) ?? "…").foregroundStyle(.secondary).monospacedDigit()
                        Button { Task { await model.clean(target) } } label: { Text("Clean", bundle: .module) }
                            .disabled(model.isScanning || (target.size ?? 0) == 0)
                    }
                }
            }
            Text("Cleaning moves the files to the Trash. Apps rebuild their caches when needed.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }

    private var appsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { model.quitAll(keepFront: true) } label: {
                    Text("Quit all but the front app", bundle: .module).lineLimit(1).minimumScaleFactor(0.8)
                }
                Button(role: .destructive) { model.quitAll(keepFront: false) } label: {
                    Text("Quit all", bundle: .module).lineLimit(1)
                }
            }
            .controlSize(.small)
            let apps = model.runningApps
            PanelGroup {
                ForEach(PanelListLimit.visible(apps, showsAll: allApps), id: \.processIdentifier) { app in
                    row {
                        if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                        Text(app.localizedName ?? "?").lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        iconButton("xmark.circle", Text("Quit", bundle: .module)) { model.quit(app, force: false) }
                        iconButton("xmark.octagon", Text("Force Quit", bundle: .module), destructive: true) {
                            model.quit(app, force: true)
                        }
                    }
                }
            }
            if PanelListLimit.isLong(apps.count) { more(apps.count, $allApps) }
            if !model.settings.keepRunningOnQuitAll.isEmpty {
                Text("Apps you keep running are left alone by Quit all.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var portsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.ports.isEmpty {
                PanelEmptyState(symbol: "network", text: Text("No app is listening on a TCP port.", bundle: .module))
            } else {
                PanelGroup {
                    ForEach(model.ports) { port in
                        row {
                            Text(verbatim: ":\(port.port)").monospacedDigit().frame(width: 52, alignment: .leading)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(port.command).lineLimit(1)
                                Text(verbatim: "PID \(port.pid)").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            iconButton("stop.circle", Text("Stop", bundle: .module), destructive: true) {
                                Task { await model.stopProcess(pid: port.pid) }
                            }
                        }
                    }
                }
            }
            Button { Task { await model.refreshPorts() } } label: { Text("Refresh", bundle: .module) }
                .buttonStyle(.borderless)
        }
    }

    private var processesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(text: $processQuery) { Text("Find a process", bundle: .module) }
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            let processes = filteredProcesses(model.processes, query: processQuery, limit: 40)
            PanelGroup {
                ForEach(PanelListLimit.visible(processes, showsAll: allProcesses)) { process in
                    row {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: process.name).lineLimit(1).truncationMode(.tail)
                            Text(verbatim: "\(String(format: "%.0f %%", process.cpu)) · \(formatBytes(process.memory))")
                                .font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        iconButton("xmark.circle", Text("Quit", bundle: .module)) {
                            Task { await model.end(process, force: false) }
                        }
                        iconButton("xmark.octagon", Text("Force Quit", bundle: .module), destructive: true) {
                            Task { await model.end(process, force: true) }
                        }
                    }
                }
            }
            if PanelListLimit.isLong(processes.count) { more(processes.count, $allProcesses) }
            Text("Sorted by CPU. Quit asks a process to end; Force Quit ends it at once and loses unsaved work.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }

    private var updatesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.outdated.isEmpty || !model.appStoreUpdates.isEmpty {
                HStack {
                    Spacer()
                    Button { Task { await model.updateAll() } } label: { Text("Update all", bundle: .module) }
                        .controlSize(.small)
                        .disabled(model.isBrewBusy)
                }
            }
            if !model.brewAvailable {
                Text("Install Homebrew (brew.sh) to see and install updates for your apps and tools.", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary)
            } else if model.isBrewBusy && model.outdated.isEmpty {
                ProgressView().controlSize(.small)
            } else if model.outdated.isEmpty {
                PanelEmptyState(symbol: "checkmark.seal",
                                text: Text("Everything installed with Homebrew is up to date.", bundle: .module))
            }
            if !model.outdated.isEmpty {
                PanelGroup {
                    ForEach(model.outdated) { package in
                        row {
                            Image(systemName: package.isCask ? "app" : "terminal").foregroundStyle(Color.sonaryAccent)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(package.name)
                                Text(verbatim: "\(package.installed) → \(package.current)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { Task { await model.upgrade(package) } } label: { Text("Update", bundle: .module) }
                                .disabled(model.isBrewBusy)
                        }
                    }
                }
            }
            if !model.appStoreUpdates.isEmpty {
                PanelGroup {
                    ForEach(model.appStoreUpdates) { update in
                        row {
                            Image(systemName: "bag").foregroundStyle(Color.sonaryAccent)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: update.name)
                                Text(verbatim: "\(update.installed) → \(update.current)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { Task { await model.upgrade(update) } } label: { Text("Update", bundle: .module) }
                                .disabled(model.isBrewBusy)
                        }
                    }
                }
            } else if !model.masAvailable {
                HStack {
                    Text("App Store updates show here with the mas tool (brew install mas).", bundle: .module)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.openAppStoreUpdates() } label: { Text("App Store", bundle: .module) }
                        .controlSize(.small)
                }
            }
            if model.isCheckingApps {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking your apps…", bundle: .module).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !model.appUpdates.isEmpty {
                PanelGroup {
                    ForEach(model.appUpdates) { update in
                        row {
                            Image(systemName: "arrow.down.app").foregroundStyle(Color.sonaryAccent)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(update.app.name)
                                Text(verbatim: "\(update.app.shortVersion) → \(update.latestVersion)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { model.openApp(update) } label: { Text("Open", bundle: .module) }
                        }
                    }
                }
            }
        }
    }

    /// One line of a list; lists sit in a `PanelGroup`, which draws the card and the hairlines.
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .font(.system(size: 12))
            .controlSize(.small)
            .panelRowInsets()
    }
}

struct AppsSettingsView: View {
    let model: AppsModel
    @State private var brewQuery = ""

    var body: some View {
        SettingsCard(Text("Quit all", bundle: .module)) {
            Text("“Quit all” in the menu panel's Apps tab leaves these running.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            AppListEditor(bundleIDs: Binding(get: { model.settings.keepRunningOnQuitAll },
                                             set: { value in model.update { $0.keepRunningOnQuitAll = value } }),
                          addTitle: Text("Add app…", bundle: .module), removeLabel: Text("Remove", bundle: .module))
        }
        SettingsCard(Text("Uninstaller", bundle: .module)) {
            SettingsRow(symbol: "trash", title: Text("Remove an app completely", bundle: .module),
                        caption: Text("Moves the app and its settings, caches and data from your Library to the Trash.",
                                      bundle: .module)) {
                Button { model.chooseAppToUninstall() } label: { Text("Choose app…", bundle: .module) }
            }
            if let plan = model.uninstallPlan {
                Divider()
                Text("\(plan.name): \(plan.leftovers.count) extra items, \(formatBytes(plan.totalSize)) in total", bundle: .module)
                    .font(.callout)
                ForEach(plan.leftovers, id: \.self) { url in
                    Text(verbatim: url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Button(role: .destructive) { model.confirmUninstall() } label: { Text("Move to Trash", bundle: .module) }
                    Button { model.cancelUninstall() } label: { Text("Cancel", bundle: .module) }
                }
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        SettingsCard(Text("Disk images", bundle: .module)) {
            SettingsToggleRow(symbol: "externaldrive.badge.minus",
                              title: Text("Move the disk image to the Trash after installing", bundle: .module),
                              caption: Text("When a mounted image offers one app, the panel installs it into Applications and ejects the image. With this on, the downloaded file goes too.",
                                            bundle: .module),
                              isOn: Binding(get: { model.settings.trashDiskImageAfterInstall },
                                            set: { value in model.update { $0.trashDiskImageAfterInstall = value } }))
        }
        SettingsCard(Text("Scheduled cleaning", bundle: .module)) {
            SettingsRow(symbol: "calendar.badge.clock", title: Text("Clean caches and logs", bundle: .module),
                        caption: Text("Runs in the background and moves everything to the Trash.", bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.cleanSchedule },
                                          set: { value in model.setCleanSchedule(value) })) {
                    ForEach(CleanSchedule.allCases, id: \.self) { Text(scheduleTitle($0), bundle: .module).tag($0) }
                } label: { EmptyView() }
                    .labelsHidden().frame(width: 150)
            }
            if let last = model.settings.lastCleaned {
                Text("Last cleaned \(last.formatted(date: .abbreviated, time: .shortened))", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        SettingsCard(Text("Tidy up folders", bundle: .module)) {
            Text("Sonary moves files out of these folders to the Trash once they are old enough. Good for a messenger's downloads.",
                 bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.settings.watchedFolders) { folder in
                SettingsRow(symbol: "folder.badge.gearshape",
                            title: Text(verbatim: (folder.path as NSString).abbreviatingWithTildeInPath),
                            caption: Text("Delete after \(folder.retentionDays) days", bundle: .module)) {
                    Stepper(value: Binding(
                        get: { folder.retentionDays },
                        set: { value in
                            model.update { settings in
                                if let index = settings.watchedFolders.firstIndex(where: { $0.path == folder.path }) {
                                    settings.watchedFolders[index].retentionDays = value
                                }
                            }
                        }), in: 0...365, step: 7) { EmptyView() }
                        .labelsHidden()
                    Button(role: .destructive) {
                        model.update { $0.watchedFolders.removeAll { $0.path == folder.path } }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Remove folder", bundle: .module))
                }
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(get: { folder.removeRepeats ?? false },
                                         set: { value in changeFolder(folder) { $0.removeRepeats = value } })) {
                        Text("Remove repeated downloads", bundle: .module)
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    if let target = folder.moveFinishedTo {
                        Text("Finished ones go to \((target as NSString).abbreviatingWithTildeInPath)", bundle: .module)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button { changeFolder(folder) { $0.moveFinishedTo = nil } } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Stop sorting", bundle: .module))
                    } else {
                        Button { chooseSortFolder(for: folder) } label: { Text("Sort finished ones into…", bundle: .module) }
                    }
                }
                .controlSize(.small)
                .padding(.leading, 30)
            }
            Button { addWatchedFolder() } label: {
                Label { Text("Add folder…", bundle: .module) } icon: { Image(systemName: "plus") }
            }
        }
        if model.brewAvailable {
            SettingsCard(Text("Homebrew", bundle: .module)) {
                HStack {
                    TextField(text: $brewQuery) { Text("Search formulae and casks", bundle: .module) }
                        .onSubmit { Task { await model.searchBrew(brewQuery) } }
                    Button { Task { await model.searchBrew(brewQuery) } } label: { Text("Search", bundle: .module) }
                        .disabled(brewQuery.trimmingCharacters(in: .whitespaces).count < 2 || model.isBrewBusy)
                    if model.isBrewBusy { ProgressView().controlSize(.small) }
                }
                ForEach(model.brewResults) { package in
                    brewRow(package, installed: model.brewInstalled.contains(package))
                }
                if !model.brewInstalled.isEmpty {
                    Divider()
                    Text("Installed", bundle: .module).font(.callout.weight(.medium))
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(model.brewInstalled) { package in brewRow(package, installed: true) }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
            .task { await model.refreshBrewInstalled() }
        }
        SettingsCard(Text("In the menu panel", bundle: .module)) {
            Text("Clean caches and logs, quit or force quit apps and processes, stop processes that block a port and update Homebrew and App Store apps from the menu panel's apps tab.",
                 bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func brewRow(_ package: BrewPackage, installed: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: package.isCask ? "app" : "terminal").foregroundStyle(.secondary).frame(width: 18)
            Text(verbatim: package.name).lineLimit(1)
            Spacer()
            if installed {
                Button(role: .destructive) { Task { await model.uninstall(package) } } label: {
                    Text("Remove", bundle: .module)
                }
            } else {
                Button { Task { await model.install(package) } } label: { Text("Install", bundle: .module) }
            }
        }
        .controlSize(.small)
        .disabled(model.isBrewBusy)
    }

    private func changeFolder(_ folder: WatchedFolder, _ change: @escaping (inout WatchedFolder) -> Void) {
        model.update { settings in
            if let index = settings.watchedFolders.firstIndex(where: { $0.path == folder.path }) {
                change(&settings.watchedFolders[index])
            }
        }
    }

    private func chooseSortFolder(for folder: WatchedFolder) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Sort into this folder", bundle: .module)
        guard panel.runModal() == .OK, let url = panel.url, url.path != folder.path else { return }
        changeFolder(folder) { $0.moveFinishedTo = url.path }
    }
}

func scheduleTitle(_ schedule: CleanSchedule) -> LocalizedStringKey {
    switch schedule {
    case .off: "Never"
    case .weekly: "Every week"
    case .monthly: "Every month"
    }
}

extension AppsSettingsView {
    fileprivate func addWatchedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.update { settings in
            if !settings.watchedFolders.contains(where: { $0.path == url.path }) {
                settings.watchedFolders.append(WatchedFolder(path: url.path, retentionDays: 30))
            }
        }
    }
}
