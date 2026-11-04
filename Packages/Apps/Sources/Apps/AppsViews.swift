import AppKit
import SonaryUI
import SwiftUI

private enum AppsSection: String, CaseIterable, Identifiable {
    case clean, apps, ports, updates
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .clean: "Clean"
        case .apps: "Apps"
        case .ports: "Ports"
        case .updates: "Updates"
        }
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
    @State private var section: AppsSection = .clean

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Picker(selection: $section) {
                ForEach(AppsSection.allCases) { Text($0.title, bundle: .module).tag($0) }
            } label: { EmptyView() }
                .pickerStyle(.segmented)
                .labelsHidden()
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            switch section {
            case .clean: cleanView.task { await model.scan() }
            case .apps: appsView
            case .ports: portsView.task { await model.refreshPorts() }
            case .updates: updatesView.task {
                await model.refreshOutdated()
                await model.checkAppUpdates()
            }
            }
        }
    }

    private var cleanView: some View {
        VStack(spacing: 6) {
            ForEach(model.cleanTargets) { target in
                row {
                    Text(cleanTargetTitle(target.id), bundle: .module)
                    Spacer()
                    Text(target.size.map(formatBytes) ?? "…").foregroundStyle(.secondary).monospacedDigit()
                    Button { Task { await model.clean(target) } } label: { Text("Clean", bundle: .module) }
                        .disabled(model.isScanning || (target.size ?? 0) == 0)
                }
            }
            Text("Cleaning moves the files to the Trash. Apps rebuild their caches when needed.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appsView: some View {
        VStack(spacing: 6) {
            ForEach(model.runningApps, id: \.processIdentifier) { app in
                row {
                    if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                    Text(app.localizedName ?? "?").lineLimit(1)
                    Spacer()
                    Button { model.quit(app, force: false) } label: { Text("Quit", bundle: .module) }
                    Button(role: .destructive) { model.quit(app, force: true) } label: { Text("Force Quit", bundle: .module) }
                }
            }
        }
    }

    private var portsView: some View {
        VStack(spacing: 6) {
            if model.ports.isEmpty {
                Text("No app is listening on a TCP port.", bundle: .module).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.ports) { port in
                row {
                    Text(verbatim: ":\(port.port)").font(.body.monospacedDigit()).frame(width: 64, alignment: .leading)
                    Text(port.command).lineLimit(1)
                    Text(verbatim: "PID \(port.pid)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) { Task { await model.stopProcess(pid: port.pid) } } label: {
                        Text("Stop", bundle: .module)
                    }
                }
            }
            Button { Task { await model.refreshPorts() } } label: { Text("Refresh", bundle: .module) }
                .buttonStyle(.borderless)
        }
    }

    private var updatesView: some View {
        VStack(spacing: 6) {
            if !model.brewAvailable {
                Text("Install Homebrew (brew.sh) to see and install updates for your apps and tools.", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary)
            } else if model.isBrewBusy && model.outdated.isEmpty {
                ProgressView().controlSize(.small)
            } else if model.outdated.isEmpty {
                Text("Everything installed with Homebrew is up to date.", bundle: .module).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.outdated) { package in
                row {
                    Image(systemName: package.isCask ? "app" : "terminal").foregroundStyle(Color.sonaryAccent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(package.name)
                        Text(verbatim: "\(package.installed) → \(package.current)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await model.upgrade(package) } } label: { Text("Update", bundle: .module) }
                        .disabled(model.isBrewBusy)
                }
            }
            if model.isCheckingApps {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking your apps…", bundle: .module).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .controlSize(.small)
            .padding(8)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct AppsSettingsView: View {
    let model: AppsModel

    var body: some View {
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
        SettingsCard(Text("Scheduled cleaning", bundle: .module)) {
            SettingsRow(symbol: "calendar.badge.clock", title: Text("Clean caches and logs", bundle: .module),
                        caption: Text("Runs in the background and moves everything to the Trash.", bundle: .module)) {
                Picker(selection: Binding(get: { model.settings.cleanSchedule },
                                          set: { value in model.update { $0.cleanSchedule = value } })) {
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
            }
            Button { addWatchedFolder() } label: {
                Label { Text("Add folder…", bundle: .module) } icon: { Image(systemName: "plus") }
            }
        }
        SettingsCard(Text("In the menu panel", bundle: .module)) {
            Text("Clean caches and logs, quit or force quit apps, stop processes that block a port and update Homebrew apps from the menu panel's apps tab.",
                 bundle: .module)
                .font(.callout).foregroundStyle(.secondary)
        }
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
